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
            return "Framegentic is still delivering the last capture. Wait for it to finish, then try again."
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

    /// One delivery at a time, whichever path asked for it.
    ///
    /// The state a second delivery corrupts is not inside this class — it is
    /// the system pasteboard and the target app's keystroke stream, both
    /// global. So a flag scoped to one path cannot help: a Snap fired during a
    /// clip's cold-launch wait calls `clearContents()` on the clip's file URLs
    /// and interleaves a second ⌘V and Return with the first. Both entry
    /// points claim this flag, and the whole app shares one `DeliveryService`
    /// so the flag is as global as the thing it protects.
    ///
    /// It also cannot live in the UI. `RewindViewModel.isDelivering` is reset
    /// the moment the popover closes so a detached delivery's UI goes quiet
    /// (see `RewindViewModel.releaseFrames`), and that reset is exactly what
    /// lets a reopened popover start a second clip mid-flight. A flag the view
    /// model owns can always be reopened by the view model.
    private var deliveryInFlight = false

    /// Runs `body` as the app's one in-flight delivery, or refuses. `defer`
    /// releases the claim on every exit, thrown or returned, so a failed
    /// delivery cannot wedge every later one shut.
    private func claimingDelivery<T>(_ body: () async throws -> T) async throws -> T {
        guard !deliveryInFlight else { throw DeliveryError.deliveryInProgress }
        deliveryInFlight = true
        defer { deliveryInFlight = false }
        return try await body()
    }

    /// A whole Snap — pasteboard write included — under one claim.
    ///
    /// `writeCapture` puts the capture on the pasteboard and reports the
    /// change count it left. It runs inside the claim rather than before it
    /// because the write is the destructive half: `clearContents()` takes a
    /// Rewind clip's file URLs with it. Guarding only the paste would still
    /// let a Snap wipe a clip mid-delivery and then refuse politely — the same
    /// collision, minus the second ⌘V.
    func deliverSnap(to target: DeliveryTarget,
                     autoSend: Bool,
                     writeCapture: () async throws -> Int) async throws {
        try await claimingDelivery {
            let changeCount = try await writeCapture()
            try await self.deliver(to: target,
                                   autoSend: autoSend,
                                   clipboardChangeCount: changeCount)
        }
    }

    /// Delivers whatever is already on the clipboard to `target`.
    ///
    /// A target that does not auto-paste returns immediately: the clipboard *is*
    /// the delivery, so nothing may expire it before the user pastes. Accessibility
    /// is never requested on that path, which is why it is the default.
    ///
    /// Private because the claim lives one level up, in `deliverSnap`: a
    /// caller that could reach this directly would be a caller able to paste
    /// without holding the claim, which is the shape of every collision on
    /// this branch so far.
    private func deliver(to target: DeliveryTarget,
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
        try await claimingDelivery {
            let written = await self.pipeline.processAndCopy(frames: frames, ttl: ttl)
            guard written.frames > 0 else { return 0 }

            // Started here rather than on the way out, because TempFileManager
            // started the files' own ttl at the moment of that write. Scheduling
            // this after the paste would run the two clocks ten seconds apart on a
            // cold launch, and the pasteboard would spend that gap pointing at
            // files already deleted.
            self.clearClipboardLater(ifStillAt: written.changeCount, after: .seconds(ttl))

            guard target.autoPaste, let bundleID = target.bundleID else {
                return written.frames
            }
            try await self.activateAndPaste(bundleID: bundleID,
                                            displayName: target.displayName,
                                            autoSend: autoSend)
            return written.frames
        }
    }

    /// Deletes every temp file a delivered clip has written, without an actor
    /// hop. Called at termination, where an `await` is not reliable — see
    /// `AppDelegate.applicationWillTerminate`.
    func removeDeliveredFiles() {
        pipeline.removeSessionDirectory()
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
