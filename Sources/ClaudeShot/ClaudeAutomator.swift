import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClaudeShotKit

enum PasteError: LocalizedError {
    case claudeNotInstalled
    case activationTimedOut
    case accessibilityDenied
    case focusLost(String?)

    var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            return "Claude isn't installed. Install the Claude desktop app and try again."
        case .activationTimedOut:
            return "Claude didn't come to the front in time. Your screenshot is on the clipboard — paste it with ⌘V."
        case .accessibilityDenied:
            return "Accessibility permission is missing. Grant it in System Settings, then quit and relaunch ClaudeShot."
        case .focusLost(let bundleID):
            return "\(bundleID ?? "Another app") took focus, so nothing was pasted. Your screenshot is on the clipboard — paste it with ⌘V."
        }
    }
}

@MainActor
final class ClaudeAutomator {
    private let settleDelay: Duration = .milliseconds(150)
    private let pasteToSendDelay: Duration = .milliseconds(600)
    private let warmActivationTimeout: TimeInterval = 3
    private let coldLaunchTimeout: TimeInterval = 10

    /// Activates (or launches) Claude, waits until it is actually frontmost, then
    /// pastes. The Return keystroke only fires when `autoSend` is on, and every
    /// keystroke is re-guarded against the frontmost app immediately before posting.
    func deliver(autoSend: Bool, clipboardChangeCount: Int) async throws {
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            throw PasteError.accessibilityDenied
        }

        let runningApps = NSWorkspace.shared.runningApplications.map {
            RunningAppInfo(bundleID: $0.bundleIdentifier, localizedName: $0.localizedName)
        }
        let installedURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: ClaudeLocator.bundleID
        )

        let timeout: TimeInterval
        switch ClaudeLocator.resolve(runningApps: runningApps, installedAppURL: installedURL) {
        case .activateRunning:
            NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeLocator.bundleID)
                .first?
                .activate()
            timeout = warmActivationTimeout
        case .launch(let url):
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            timeout = coldLaunchTimeout
        case .notFound:
            throw PasteError.claudeNotInstalled
        }

        guard await waitForClaudeFrontmost(timeout: timeout) else {
            throw PasteError.activationTimedOut
        }
        try? await Task.sleep(for: settleDelay)

        try checkGuard()
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        Log.paste.info("Pasted screenshot into Claude")

        if autoSend {
            try? await Task.sleep(for: pasteToSendDelay)
            try checkGuard()
            postKey(CGKeyCode(kVK_Return))
            Log.paste.info("Sent")
        }

        clearClipboardLater(ifStillAt: clipboardChangeCount)
    }

    private func waitForClaudeFrontmost(timeout: TimeInterval) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while clock.now < deadline {
            if claudeIsFrontmost { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return claudeIsFrontmost
    }

    private var claudeIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == ClaudeLocator.bundleID
    }

    private func checkGuard() throws {
        let decision = PasteGuard.evaluate(
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            expectedBundleID: ClaudeLocator.bundleID,
            axTrusted: AXIsProcessTrusted()
        )
        switch decision {
        case .allowed:
            return
        case .blocked(.accessibilityDenied):
            throw PasteError.accessibilityDenied
        case .blocked(.wrongFrontmostApp(let actual)):
            throw PasteError.focusLost(actual)
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

    /// The screenshot may contain anything visible on screen, so it shouldn't sit on
    /// the clipboard after delivery. Cleared only if nothing else has written since.
    private func clearClipboardLater(ifStillAt changeCount: Int) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                Log.paste.info("Cleared screenshot from clipboard")
            }
        }
    }
}
