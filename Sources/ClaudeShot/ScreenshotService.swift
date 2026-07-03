import AppKit
// @preconcurrency: older SDKs (CI runners) don't mark SCK types Sendable yet.
@preconcurrency import ScreenCaptureKit
import ClaudeShotKit

enum CaptureError: LocalizedError {
    case screenRecordingDenied
    case noDisplay
    case pngEncodingFailed
    case pasteboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            return "Screen Recording permission is missing. Grant it in System Settings, then quit and relaunch ClaudeShot."
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
final class ScreenshotService {
    // org.nspasteboard markers: clipboard managers skip Concealed/Transient content,
    // and Handoff won't sync Concealed items to other devices.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private var cachedDisplay: SCDisplay?
    private var screenObserver: NSObjectProtocol?

    init() {
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
}
