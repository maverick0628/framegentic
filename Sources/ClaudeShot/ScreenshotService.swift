import Cocoa
import ScreenCaptureKit

final class ScreenshotService {
    func captureToClipboard(completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                guard let display = content.displays.first else {
                    NSLog("ClaudeShot: no display found")
                    await MainActor.run { completion(false) }
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width * 2
                config.height = display.height * 2
                config.showsCursor = false

                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config
                )

                await MainActor.run {
                    let size = NSSize(width: cgImage.width / 2, height: cgImage.height / 2)
                    let nsImage = NSImage(cgImage: cgImage, size: size)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    let ok = pb.writeObjects([nsImage])
                    NSLog("ClaudeShot: captured via SCK, pasteboard write=\(ok)")
                    completion(ok)
                }
            } catch {
                NSLog("ClaudeShot: SCK capture error: \(error.localizedDescription)")
                await MainActor.run { completion(false) }
            }
        }
    }
}
