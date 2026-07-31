import AppKit
import ApplicationServices
import Carbon.HIToolbox
import FramegenticKit

enum DeliveryError: LocalizedError {
    case targetNotInstalled(String)
    case activationTimedOut(String)
    case accessibilityDenied
    case focusLost(String?)

    var errorDescription: String? {
        switch self {
        case .targetNotInstalled(let name):
            return "\(name) isn't installed. Install it, or switch delivery to Clipboard only in Settings."
        case .activationTimedOut(let name):
            return "\(name) didn't come to the front in time. Your capture is on the clipboard — paste it with ⌘V."
        case .accessibilityDenied:
            return "Accessibility permission is missing. Grant it in System Settings, then quit and relaunch Framegentic."
        case .focusLost(let bundleID):
            return "\(bundleID ?? "Another app") took focus, so nothing was pasted. Your capture is on the clipboard — paste it with ⌘V."
        }
    }
}

@MainActor
final class DeliveryService {
    private let settleDelay: Duration = .milliseconds(150)
    private let pasteToSendDelay: Duration = .milliseconds(600)
    private let warmActivationTimeout: TimeInterval = 3
    private let coldLaunchTimeout: TimeInterval = 10

    /// Delivers whatever is already on the clipboard to `target`.
    ///
    /// A target that does not auto-paste returns immediately: the clipboard *is*
    /// the delivery, so nothing may expire it before the user pastes. Accessibility
    /// is never requested on that path, which is why it is the default.
    func deliver(to target: DeliveryTarget,
                 autoSend: Bool,
                 clipboardChangeCount: Int) async throws {
        guard target.autoPaste, let bundleID = target.bundleID else {
            return
        }

        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            throw DeliveryError.accessibilityDenied
        }

        let runningApps = NSWorkspace.shared.runningApplications.map {
            RunningAppInfo(bundleID: $0.bundleIdentifier, localizedName: $0.localizedName)
        }
        let installedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)

        let timeout: TimeInterval
        switch AppLocator.resolve(bundleID: bundleID,
                                  runningApps: runningApps,
                                  installedAppURL: installedURL) {
        case .activateRunning:
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first?
                .activate()
            timeout = warmActivationTimeout
        case .launch(let url):
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            timeout = coldLaunchTimeout
        case .notFound:
            throw DeliveryError.targetNotInstalled(target.displayName)
        }

        guard await waitForFrontmost(bundleID: bundleID, timeout: timeout) else {
            throw DeliveryError.activationTimedOut(target.displayName)
        }
        try? await Task.sleep(for: settleDelay)

        try checkGuard(expecting: bundleID)
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        Log.paste.info("Pasted into \(target.displayName, privacy: .public)")

        if autoSend {
            try? await Task.sleep(for: pasteToSendDelay)
            // Re-checked rather than trusted: focus can change in the 600ms since
            // the paste, and a stray Return lands in whatever is frontmost now.
            try checkGuard(expecting: bundleID)
            postKey(CGKeyCode(kVK_Return))
            Log.paste.info("Sent")
        }

        clearClipboardLater(ifStillAt: clipboardChangeCount)
    }

    private func waitForFrontmost(bundleID: String, timeout: TimeInterval) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while clock.now < deadline {
            if isFrontmost(bundleID) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return isFrontmost(bundleID)
    }

    private func isFrontmost(_ bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private func checkGuard(expecting bundleID: String) throws {
        let decision = PasteGuard.evaluate(
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            expectedBundleID: bundleID,
            axTrusted: AXIsProcessTrusted()
        )
        switch decision {
        case .allowed:
            return
        case .blocked(.accessibilityDenied):
            throw DeliveryError.accessibilityDenied
        case .blocked(.wrongFrontmostApp(let actual)):
            throw DeliveryError.focusLost(actual)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func promptForAccessibility() {
        // Literal key: kAXTrustedCheckOptionPrompt imports as a mutable C global,
        // which Swift 6 strict concurrency rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Once pasted, the capture has been delivered, and it may contain anything
    /// visible on screen — so it shouldn't linger. Cleared only if nothing else
    /// has written since. Every `throw` above skips this, leaving a failed
    /// delivery on the clipboard for the user to paste themselves.
    private func clearClipboardLater(ifStillAt changeCount: Int) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                Log.paste.info("Cleared capture from clipboard")
            }
        }
    }
}
