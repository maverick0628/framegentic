import AppKit
// @preconcurrency: older SDKs (CI runners) don't mark SCK types Sendable yet.
@preconcurrency import ScreenCaptureKit
import CoreMedia
import FramegenticKit

enum CaptureError: LocalizedError {
    case screenRecordingDenied
    case noDisplay
    case pngEncodingFailed
    case pasteboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            return "Screen Recording permission is missing. Grant it in System Settings, then quit and relaunch Framegentic."
        case .noDisplay:
            return "No display found to capture."
        case .pngEncodingFailed:
            return "Could not encode the screenshot."
        case .pasteboardWriteFailed:
            return "Could not copy the screenshot to the clipboard."
        }
    }
}

@MainActor
final class CaptureService: NSObject {
    // org.nspasteboard markers: clipboard managers skip Concealed/Transient content,
    // and Handoff won't sync Concealed items to other devices.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private var cachedDisplay: SCDisplay?
    private var screenObserver: NSObjectProtocol?

    override init() {
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cachedDisplay = nil }
        }
    }

    /// Resolves the display once at launch so the Screen Recording prompt fires here,
    /// not on the user's first hotkey press.
    func prewarm() {
        Task { _ = try? await self.resolveDisplay() }
    }

    /// Captures the main display at its native scale and writes it to the general
    /// pasteboard as concealed, transient PNG data. Returns the pasteboard change
    /// count after the write so callers can guard a later clear.
    func captureToClipboard() async throws -> Int {
        let display = try await resolveDisplay()
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let geometry = CaptureGeometry(
            pointWidth: display.width,
            pointHeight: display.height,
            scaleFactor: CGFloat(filter.pointPixelScale)
        )

        let config = SCStreamConfiguration()
        config.width = geometry.pixelWidth
        config.height = geometry.pixelHeight
        config.showsCursor = false

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )

        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = geometry.logicalSize
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.pngEncodingFailed
        }

        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(Data(), forType: Self.concealedType)
        item.setData(Data(), forType: Self.transientType)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw CaptureError.pasteboardWriteFailed
        }
        Log.capture.info("Captured \(geometry.pixelWidth)×\(geometry.pixelHeight) px, \(png.count) bytes PNG")
        return pasteboard.changeCount
    }

    private func resolveDisplay() async throws -> SCDisplay {
        if let cachedDisplay { return cachedDisplay }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw CaptureError.screenRecordingDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        )
        let displayInfos = content.displays.map {
            DisplayInfo(id: $0.displayID, pointWidth: $0.width, pointHeight: $0.height)
        }
        guard let selected = selectCaptureDisplay(from: displayInfos, mainDisplayID: CGMainDisplayID()),
              let display = content.displays.first(where: { $0.displayID == selected.id }) else {
            throw CaptureError.noDisplay
        }
        cachedDisplay = display
        return display
    }

    // MARK: - Continuous capture (Rewind)
    //
    // The ring buffer and every other mutable field below live exclusively on
    // MainActor — CaptureService's own isolation — and are never read or written
    // from anywhere else. That is a deliberate choice, not a default the compiler
    // picked: RingBuffer<CapturedFrame> has no Sendable conformance of its own
    // (Element is unconstrained), so the alternative would be forcing one into
    // existence for a type that never actually crosses a concurrency boundary.
    // The only thing that does cross is a raw CGImage, which this SDK genuinely
    // conforms to Sendable, handed from the stream's nonisolated output callback
    // into a `Task { @MainActor in }` hop. CapturedFrame itself is constructed
    // only on MainActor, at the moment a sampled frame is kept.

    private var stream: SCStream?
    private let activityMonitor = ActivityMonitor()
    private var samplingTask: Task<Void, Never>?
    private var latestFrame: CGImage?
    private var lastAppendedHash: UInt64?
    private(set) var ringBuffer: RingBuffer<CapturedFrame>?

    private static let sampleQueue = DispatchQueue(label: "com.duncansmith.framegentic.capture-stream")

    var isBuffering: Bool { stream != nil }

    /// Starts the rolling buffer, sized to `capacity` slots. `frameInterval` is the
    /// *active* sampling cadence — the same value `SettingsModel.bufferCapacity`
    /// used to size `capacity`, so a "2 minute" buffer actually spans 2 minutes
    /// while the user is working. Idle cadence backs off to a multiple of it,
    /// since a screen nobody is touching is also one DHash will mostly dedup
    /// away regardless of how often it's sampled.
    ///
    /// A no-op if already running. Permission denial is handled the same way the
    /// one-shot path handles it — resolveDisplay() throws, this logs and leaves
    /// buffering off, nothing crashes or retries in a loop.
    func startBuffering(capacity: Int, frameInterval: TimeInterval) async {
        guard stream == nil else { return }

        do {
            let display = try await resolveDisplay()
            let filter = SCContentFilter(display: display, excludingWindows: [])

            // Point (1x) dimensions, not the one-shot path's pixel-scaled
            // geometry: a rolling buffer of raw decoded CGImages is memory that
            // sits around for the whole buffer window, so it stays cheap here
            // and pays for quality only once, at delivery, when OptimizationPipeline
            // downsamples and compresses whatever gets kept.
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            // Caps the underlying stream's raw delivery rate, decoupled from
            // frameInterval on purpose — this just keeps latestFrame reasonably
            // fresh between samples; how often a sample is actually kept is the
            // sampling loop's job, below.
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false

            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: Self.sampleQueue)
            try await newStream.startCapture()
            stream = newStream
        } catch {
            Log.capture.error("Continuous capture failed to start: \(error.localizedDescription, privacy: .public)")
            return
        }

        ringBuffer = RingBuffer<CapturedFrame>(capacity: capacity)
        lastAppendedHash = nil
        latestFrame = nil
        activityMonitor.start()
        startSamplingLoop(activeInterval: frameInterval, idleInterval: frameInterval * 3)
    }

    /// Safe to call whether or not buffering is running. Clears the buffer along
    /// with the stream — Rewind's contents are a live recording, not a saved
    /// document, so there is nothing to preserve across a stop.
    func stopBuffering() async {
        samplingTask?.cancel()
        samplingTask = nil
        activityMonitor.stop()
        latestFrame = nil
        lastAppendedHash = nil
        ringBuffer = nil

        let stoppingStream = stream
        stream = nil
        try? await stoppingStream?.stopCapture()
    }

    private func startSamplingLoop(activeInterval: TimeInterval, idleInterval: TimeInterval) {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.sampleFrame()
                let interval = self.activityMonitor.currentState == .active ? activeInterval : idleInterval
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
            }
        }
    }

    /// Compares the newest decoded frame against the last one actually kept, not
    /// the last one merely sampled — the question worth asking is "has the screen
    /// changed since what's already in the buffer," not "since the previous tick."
    private func sampleFrame() {
        guard let image = latestFrame else { return }
        let hash = DHash.hash(image)
        if let lastAppendedHash, DHash.areSimilar(lastAppendedHash, hash) {
            return
        }
        lastAppendedHash = hash
        ringBuffer?.append(CapturedFrame(image: image))
    }
}

extension CaptureService: SCStreamDelegate, SCStreamOutput {
    // Fires on sampleQueue, not MainActor — ScreenCaptureKit delivers frames far
    // faster than anything here consumes them, so decoding happens off the main
    // actor and only the decoded, Sendable CGImage crosses into it.
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return }
        Task { @MainActor [weak self] in
            self?.latestFrame = cgImage
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.capture.error("Continuous capture stream stopped: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor [weak self] in
            await self?.stopBuffering()
        }
    }
}
