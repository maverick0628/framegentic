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
    private let postPasteClearDelay: Duration = .seconds(3)
    private let pipeline = OptimizationPipeline()

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
        try await activateAndPaste(bundleID: bundleID, displayName: target.displayName, autoSend: autoSend)
        clearClipboardLater(ifStillAt: clipboardChangeCount, after: postPasteClearDelay)
    }

    /// Delivers a trimmed Rewind clip: several frames become file URLs on the
    /// clipboard, since a pasteboard item can hold one image as data or many
    /// file references, never several images. OptimizationPipeline dedups
    /// before writing, so the count returned can be lower than `frames.count`
    /// — show the caller that number, not the pre-dedup selection size.
    ///
    /// Unlike `deliver`, the clear below is scheduled unconditionally, success
    /// or thrown error: TempFileManager deletes the underlying files on `ttl`
    /// either way, so the pasteboard entry has to expire on that same clock or
    /// it outlives the files it points at — the dangling state that is worse
    /// than either clearing it or letting the files live longer.
    func deliverClip(_ frames: [CapturedFrame],
                      to target: DeliveryTarget,
                      autoSend: Bool,
                      ttl: TimeInterval) async throws -> Int {
        let count = await pipeline.processAndCopy(frames: frames, ttl: ttl)
        guard count > 0 else { return 0 }

        let changeCount = NSPasteboard.general.changeCount
        defer { clearClipboardLater(ifStillAt: changeCount, after: .seconds(ttl)) }

        guard target.autoPaste, let bundleID = target.bundleID else {
            return count
        }
        try await activateAndPaste(bundleID: bundleID, displayName: target.displayName, autoSend: autoSend)
        return count
    }

    /// Activates `target`, waits for it to take focus, then pastes and
    /// optionally sends. The one activation-and-paste sequence, shared by
    /// every delivery path so a clip and a snap behave identically once
    /// something is already on the clipboard — only what got there differs.
    private func activateAndPaste(bundleID: String, displayName: String, autoSend: Bool) async throws {
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
            throw DeliveryError.targetNotInstalled(displayName)
        }

        guard await waitForFrontmost(bundleID: bundleID, timeout: timeout) else {
            throw DeliveryError.activationTimedOut(displayName)
        }
        try? await Task.sleep(for: settleDelay)

        try checkGuard(expecting: bundleID)
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        Log.paste.info("Pasted into \(displayName, privacy: .public)")

        if autoSend {
            try? await Task.sleep(for: pasteToSendDelay)
            // Re-checked rather than trusted: focus can change in the 600ms since
            // the paste, and a stray Return lands in whatever is frontmost now.
            try checkGuard(expecting: bundleID)
            postKey(CGKeyCode(kVK_Return))
            Log.paste.info("Sent")
        }
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

    /// Whatever got delivered may contain anything visible on screen, so it
    /// shouldn't linger — cleared only if nothing else has written since.
    /// `deliver` calls this with a few seconds' grace past a successful paste
    /// (skipped entirely on failure, leaving the capture for a manual paste);
    /// `deliverClip` calls it unconditionally with the files' own ttl, since a
    /// clip's entry is pointers rather than data and needs to expire whether
    /// or not the paste itself succeeded.
    private func clearClipboardLater(ifStillAt changeCount: Int, after delay: Duration) {
        Task {
            try? await Task.sleep(for: delay)
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                Log.paste.info("Cleared capture from clipboard")
            }
        }
    }
}
