import AppKit
import ApplicationServices
import Carbon.HIToolbox
import FramegenticKit

enum DeliveryError: LocalizedError {
    case targetNotInstalled(String)
    case activationTimedOut(String)
    case accessibilityDenied
    case focusLost(String?)
    case deliveryInProgress

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
        case .deliveryInProgress:
            return "Still copying the last clip. Wait for it to finish, then try again."
        }
    }
}

@MainActor
final class DeliveryService {
    private let settleDelay: Duration = .milliseconds(150)
    private let pasteToSendDelay: Duration = .milliseconds(600)
    private let frontmostPollInterval: Duration = .milliseconds(100)
    private let warmActivationTimeout: TimeInterval = 3
    private let coldLaunchTimeout: TimeInterval = 10
    private let postPasteClearDelay: Duration = .seconds(3)
    private let pipeline = OptimizationPipeline()

    /// Guards `deliverClip` only. `deliver` needs nothing equivalent: its
    /// caller writes the pasteboard before `deliver` is ever called, so by the
    /// time `deliver` runs there is nothing left inside this class for a
    /// second call to clobber. `deliverClip` writes the pasteboard itself, and
    /// RewindViewModel's `isDelivering` cannot be the thing that prevents two
    /// overlapping writes — it is deliberately reset the moment the popover
    /// closes, so a detached delivery's UI goes quiet (see
    /// RewindViewModel.releaseFrames), and that reset is exactly what lets a
    /// second confirmSelection() start a second deliverClip while the first is
    /// still mid-flight. A flag on the view model can always be reopened by
    /// the view model; this one lives one level down, where a second caller
    /// cannot bypass it no matter what UI state does.
    private var clipDeliveryInFlight = false

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
    /// A second call while one is already running is rejected, not queued:
    /// two clips have no sensible merged pasteboard outcome. Queueing would
    /// only delay the same collision — clip B's write would still land on top
    /// of clip A's URLs, just later, and clip A's already-scheduled clipboard
    /// clear would still fire on clip A's ttl and blow away clip B's entry
    /// early. Rejecting outright is the only option that leaves the pasteboard
    /// holding one clip's identity at a time.
    ///
    /// Unlike `deliver`, the clear is scheduled from the write, unconditionally
    /// and before anything is pasted: TempFileManager starts deleting the
    /// underlying files on `ttl` from that same instant whether the paste
    /// works, fails or never happens, so the pasteboard entry has to expire on
    /// the same clock or it outlives the files it points at — the dangling
    /// state that is worse than either clearing it or letting the files live
    /// longer.
    func deliverClip(_ frames: [CapturedFrame],
                      to target: DeliveryTarget,
                      autoSend: Bool,
                      ttl: TimeInterval) async throws -> Int {
        guard !clipDeliveryInFlight else {
            throw DeliveryError.deliveryInProgress
        }
        clipDeliveryInFlight = true
        defer { clipDeliveryInFlight = false }

        let written = await pipeline.processAndCopy(frames: frames, ttl: ttl)
        guard written.frames > 0 else { return 0 }

        // Started here rather than on the way out, because TempFileManager
        // started the files' own ttl at the moment of that write. Scheduling
        // this after the paste would run the two clocks ten seconds apart on a
        // cold launch, and the pasteboard would spend that gap pointing at
        // files already deleted.
        clearClipboardLater(ifStillAt: written.changeCount, after: .seconds(ttl))

        guard target.autoPaste, let bundleID = target.bundleID else {
            return written.frames
        }
        try await activateAndPaste(bundleID: bundleID, displayName: target.displayName, autoSend: autoSend)
        return written.frames
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
        await delay(settleDelay)

        try checkGuard(expecting: bundleID)
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        Log.paste.info("Pasted into \(displayName, privacy: .public)")

        if autoSend {
            await delay(pasteToSendDelay)
            // Re-checked rather than trusted: focus can change in the 600ms since
            // the paste, and a stray Return lands in whatever is frontmost now.
            try checkGuard(expecting: bundleID)
            postKey(CGKeyCode(kVK_Return))
            Log.paste.info("Sent")
        }
    }

    /// Waits `duration` in a way no caller can shorten.
    ///
    /// Every pause in the paste sequence is doing work: the settle gives a
    /// just-activated app time to accept input, the paste-to-send gap keeps
    /// Return from submitting before ⌘V has landed, and waitForFrontmost's poll
    /// is the only thing keeping a cold-launch wait from becoming a hot loop.
    /// `Task.sleep` returns the instant its task is cancelled, so a cancelled
    /// caller would collapse all three to zero and auto-send an empty message.
    /// A timer-backed continuation has no cancellation to observe, which makes
    /// these delays a property of the sequence rather than of whoever calls it.
    private func delay(_ duration: Duration) async {
        let components = duration.components
        let nanoseconds = components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(clamping: nanoseconds))) {
                continuation.resume()
            }
        }
    }

    private func waitForFrontmost(bundleID: String, timeout: TimeInterval) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while clock.now < deadline {
            if isFrontmost(bundleID) { return true }
            await delay(frontmostPollInterval)
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
            // A cancelled sleep returns immediately, which would clear the
            // clipboard the moment after it was written instead of at the end
            // of its life. Nothing holds this task's handle today; the guard
            // keeps that from being load-bearing.
            guard !Task.isCancelled else { return }
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                Log.paste.info("Cleared capture from clipboard")
            }
        }
    }
}
