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

    /// A start takes real time — a display has to be resolved and a stream has to
    /// come up — so "is it buffering" has three answers, not two, and anything
    /// reading it mid-transition (the menu bar, chiefly) has to be told the
    /// honest one rather than an optimistic guess a failed start would leave
    /// permanently wrong.
    private enum BufferingState {
        case idle, starting, running, stopping

        var isBuffering: Bool { self == .running }
    }

    private var state: BufferingState = .idle {
        didSet {
            guard oldValue.isBuffering != state.isBuffering else { return }
            onBufferingStateChange?(state.isBuffering)
        }
    }
    private var transition: Task<Void, Never>?

    private var stream: SCStream?
    private let activityMonitor = ActivityMonitor()
    private var samplingTask: Task<Void, Never>?
    private var latestFrame: CGImage?
    private var lastAppendedHash: UInt64?
    private(set) var ringBuffer: RingBuffer<CapturedFrame>?

    private static let sampleQueue = DispatchQueue(label: "com.duncansmith.framegentic.capture-stream")

    // Building a CIContext allocates a GPU render pipeline; one per delivered
    // frame is pure overhead. Shared rather than per-callback — it is documented
    // thread-safe, and the only reader is the stream's own serial queue anyway.
    // nonisolated because that reader is the stream callback, off MainActor.
    private nonisolated static let renderContext = CIContext()

    /// Fires whenever buffering genuinely starts or stops — including when the
    /// stream dies underneath us. A caller that only refreshed its indicator
    /// after its own start/stop returned would keep claiming to record after a
    /// display unplug, a revoked permission or a fast user switch killed the
    /// stream, which is precisely the lie the indicator exists to prevent.
    var onBufferingStateChange: ((Bool) -> Void)?

    var isBuffering: Bool { state.isBuffering }

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
        await serialised { await self.performStart(capacity: capacity, frameInterval: frameInterval) }
    }

    /// Safe to call whether or not buffering is running. Clears the buffer along
    /// with the stream — Rewind's contents are a live recording, not a saved
    /// document, so there is nothing to preserve across a stop.
    func stopBuffering() async {
        await serialised { await self.performStop() }
    }

    /// Every start and stop runs through here, one at a time, in the order it was
    /// asked for. The service owns this rather than trusting its caller to: a
    /// start suspends twice before it has a `stream` to guard against, and the
    /// stream's own failure callback is a caller too. Without this, a stop
    /// arriving during those suspensions is a no-op that the resuming start then
    /// overwrites with a live stream nobody asked for — `isBuffering` true
    /// forever, every later start refused.
    ///
    /// Ordering holds because `transition` is read and reassigned with no await
    /// in between, so the chain is fixed at call time rather than at whatever
    /// order the executor happens to schedule the tasks in.
    private func serialised(_ work: @escaping @MainActor () async -> Void) async {
        let previous = transition
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        transition = task
        await task.value
    }

    private func performStart(capacity: Int, frameInterval: TimeInterval) async {
        guard state == .idle else { return }
        state = .starting

        let newStream: SCStream
        do {
            let display = try await resolveDisplay()
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let candidate = SCStream(
                filter: filter,
                configuration: Self.bufferConfiguration(display: display, frameInterval: frameInterval),
                delegate: self
            )
            try candidate.addStreamOutput(self, type: .screen, sampleHandlerQueue: Self.sampleQueue)
            try await candidate.startCapture()
            newStream = candidate
        } catch {
            Log.capture.error("Continuous capture failed to start: \(error.localizedDescription, privacy: .public)")
            state = .idle
            return
        }

        stream = newStream
        ringBuffer = RingBuffer<CapturedFrame>(capacity: capacity)
        lastAppendedHash = nil
        latestFrame = nil
        activityMonitor.start()
        state = .running
        startSamplingLoop(activeInterval: frameInterval, idleInterval: frameInterval * 3)
    }

    private func performStop() async {
        guard state != .idle else { return }
        state = .stopping

        samplingTask?.cancel()
        samplingTask = nil
        activityMonitor.stop()
        latestFrame = nil
        lastAppendedHash = nil
        ringBuffer = nil

        let stoppingStream = stream
        stream = nil
        try? await stoppingStream?.stopCapture()
        state = .idle
    }

    /// Point (1x) dimensions, not the one-shot path's pixel-scaled geometry: a
    /// rolling buffer of raw decoded CGImages is memory that sits around for the
    /// whole buffer window, so it stays cheap here and pays for quality only
    /// once, at delivery, when OptimizationPipeline downsamples and compresses
    /// whatever gets kept.
    ///
    /// `minimumFrameInterval` is the sampling cadence rather than a fixed 1 fps.
    /// The sampling loop keeps one frame per interval and nothing reads the rest,
    /// so every frame delivered faster than that is a full-screen decode and
    /// colour conversion computed only to be dropped — on the one feature whose
    /// whole case is being cheap enough to leave running.
    private static func bufferConfiguration(display: SCDisplay, frameInterval: TimeInterval) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(seconds: frameInterval, preferredTimescale: 600)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        return config
    }

    /// The idle backoff has to reach the stream, not just the sampling loop.
    /// Leaving delivery pinned at the active rate while sampling drops to a third
    /// of it means two of every three frames are decoded overnight for nothing.
    private func applyDeliveryRate(_ interval: TimeInterval) async {
        guard let stream, let display = cachedDisplay else { return }
        do {
            try await stream.updateConfiguration(
                Self.bufferConfiguration(display: display, frameInterval: interval)
            )
        } catch {
            Log.capture.error("Could not retune stream delivery rate: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startSamplingLoop(activeInterval: TimeInterval, idleInterval: TimeInterval) {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            var deliveredInterval = activeInterval
            while !Task.isCancelled {
                guard let self else { return }
                self.sampleFrame()
                let interval = self.activityMonitor.currentState == .active ? activeInterval : idleInterval
                if interval != deliveredInterval {
                    deliveredInterval = interval
                    await self.applyDeliveryRate(interval)
                }
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
        guard type == .screen,
              Self.carriesNewPixels(sampleBuffer),
              let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = Self.renderContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        Task { @MainActor [weak self] in
            self?.latestFrame = cgImage
        }
    }

    /// ScreenCaptureKit tags every delivered frame: `.complete` carries new
    /// pixels, while `.idle`, `.blank` and `.suspended` carry a stale or empty
    /// buffer that exists only to keep the stream alive. Dedup would drop most of
    /// those, but storing a blank frame once is still storing a blank frame.
    ///
    /// A frame the SDK declines to describe at all is let through — this gate is
    /// here to drop what SCK explicitly marks unusable, not to make delivery
    /// depend on metadata a future SDK might stop attaching.
    private nonisolated static func carriesNewPixels(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return true }
        return status == .complete
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.capture.error("Continuous capture stream stopped: \(error.localizedDescription, privacy: .public)")
        // Goes through the same serialised transition as every other stop, so it
        // cannot interleave with a start still coming up, and it moves the state
        // machine — which is what drives the menu bar back to the truth.
        Task { @MainActor [weak self] in
            await self?.stopBuffering()
        }
    }
}
