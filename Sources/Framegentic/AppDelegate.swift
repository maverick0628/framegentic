import AppKit
import ApplicationServices
import FramegenticKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let captureService = CaptureService()
    private let delivery = DeliveryService()
    private let hotKey = HotKeyManager()
    private lazy var model = SettingsModel(store: HotKeyStore(), hotKey: hotKey)
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private weak var captureMenuItem: NSMenuItem?
    private var isCapturing = false
    private var confirmationTask: Task<Void, Never>?
    private var isShowingConfirmation = false
    private var bufferingTransition: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        hotKey.onHotKey = { [weak self] in self?.capture() }
        model.registerStoredHotKey()
        model.onRecordingStateChange = { [weak self] isRecording in
            self?.captureMenuItem?.keyEquivalent = isRecording
                ? ""
                : self?.model.hotKeyConfig.menuKeyEquivalent ?? ""
        }
        model.onBufferEnabledChange = { [weak self] enabled in
            self?.setBuffering(enabled)
        }
        captureService.prewarm()
        if model.bufferEnabled {
            setBuffering(true)
        }
        Log.app.info("Framegentic launched, hotkey registered: \(self.model.hotKeyRegistered)")
    }

    /// Best-effort: stopCapture() is async and the process may exit before it
    /// finishes, same as any other in-flight work at quit time in this app. The
    /// stream and its background queue are torn down by process exit regardless.
    func applicationWillTerminate(_ notification: Notification) {
        let previous = bufferingTransition
        bufferingTransition = Task { [weak self] in
            await previous?.value
            await self?.captureService.stopBuffering()
        }
    }

    /// Chained after whatever transition is already in flight, rather than fired
    /// independently — CaptureService.startBuffering only guards against a second
    /// start once `stream` is actually set, so two toggles in quick succession
    /// (settings bounced on/off before the first finishes resolving a display)
    /// could otherwise start two streams and leak one, or race a stop against a
    /// start still coming up. Chaining makes every transition run to completion
    /// in request order before the next one begins, so neither can happen.
    private func setBuffering(_ enabled: Bool) {
        let previous = bufferingTransition
        bufferingTransition = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if enabled {
                await self.captureService.startBuffering(
                    capacity: self.model.bufferCapacity,
                    frameInterval: self.model.frameIntervalSeconds
                )
            } else {
                await self.captureService.stopBuffering()
            }
            self.refreshStatusIcon()
        }
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "FramegenticStatusItem"
        item.button?.image = Self.menuBarIcon()

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private static func menuBarIcon() -> NSImage? {
        if let image = NSImage(named: "MenuBarIcon") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Framegentic")?
            .withSymbolConfiguration(config)
    }

    private static func confirmationIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "checkmark.circle.fill",
                            accessibilityDescription: "Capture copied to the clipboard")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// Distinct from the idle glyph on purpose — an app that can reproduce the
    /// last few minutes of the screen must say so visibly, not as a hidden
    /// preference. This is what Rewind being on looks like in the menu bar.
    private static func bufferingIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "record.circle",
                            accessibilityDescription: "Framegentic — Rewind is recording")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// What the status item shows whenever nothing is actively flashing. The one
    /// place that decides idle-vs-buffering, so the confirmation tick's revert and
    /// refreshStatusIcon can never disagree about which icon that is.
    private func currentIdleIcon() -> NSImage? {
        captureService.isBuffering ? Self.bufferingIcon() : Self.menuBarIcon()
    }

    /// Applies currentIdleIcon() unless a confirmation tick is currently showing —
    /// that tick's own revert reads the same helper a second later, so skipping
    /// here never leaves the icon stale, only briefly deferred.
    private func refreshStatusIcon() {
        guard !isShowingConfirmation else { return }
        statusItem?.button?.image = currentIdleIcon()
    }

    /// A clipboard-only capture activates nothing, so the menu bar icon is the only
    /// evidence the hotkey did anything. A newer capture takes the indicator over:
    /// the cancelled task bows out without reverting, leaving the revert to whoever
    /// owns it now. The revert target is resolved fresh, not captured at flash time,
    /// so a tick that overlaps a buffering start/stop still reverts to the correct
    /// icon a second later rather than the one true when it fired.
    private func flashCaptureConfirmation() {
        confirmationTask?.cancel()
        isShowingConfirmation = true
        statusItem?.button?.image = Self.confirmationIcon()
        confirmationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            self?.isShowingConfirmation = false
            self?.statusItem?.button?.image = self?.currentIdleIcon()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        model.refreshStartAtLogin()

        let config = model.hotKeyConfig
        let capture = NSMenuItem(
            title: model.deliveryTarget.autoPaste
                ? "Capture → \(model.deliveryTarget.displayName)"
                : "Capture to Clipboard",
            action: #selector(captureFromMenu),
            keyEquivalent: model.isRecording ? "" : config.menuKeyEquivalent
        )
        if !model.isRecording {
            capture.keyEquivalentModifierMask = config.menuModifiers
        }
        capture.target = self
        menu.addItem(capture)
        captureMenuItem = capture

        if !model.hotKeyRegistered {
            let warning = NSMenuItem(
                title: "Hotkey unavailable — is \(config.displayString) taken?",
                action: #selector(openSettings),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
        }

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        if model.deliveryTarget.autoPaste {
            let send = NSMenuItem(
                title: "Send Automatically After Paste",
                action: #selector(toggleAutoSend),
                keyEquivalent: ""
            )
            send.target = self
            send.state = model.autoSend ? .on : .off
            menu.addItem(send)
        }

        let login = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        login.target = self
        login.state = model.startAtLogin ? .on : .off
        menu.addItem(login)

        var permissionItems: [NSMenuItem] = []
        if !CGPreflightScreenCaptureAccess() {
            let item = NSMenuItem(
                title: "Grant Screen Recording…",
                action: #selector(openScreenRecordingSettings),
                keyEquivalent: ""
            )
            item.target = self
            permissionItems.append(item)
        }
        if model.deliveryTarget.autoPaste, !AXIsProcessTrusted() {
            let item = NSMenuItem(
                title: "Grant Accessibility…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            item.target = self
            permissionItems.append(item)
        }
        if !permissionItems.isEmpty {
            menu.addItem(.separator())
            permissionItems.forEach { menu.addItem($0) }
        }

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Framegentic", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Framegentic", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Capture flow

    @objc private func captureFromMenu() {
        capture()
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let changeCount = try await captureService.captureToClipboard()
                let target = model.deliveryTarget
                try await delivery.deliver(to: target,
                                           autoSend: model.autoSend,
                                           clipboardChangeCount: changeCount)
                if !target.autoPaste { flashCaptureConfirmation() }
            } catch {
                report(error)
            }
        }
    }

    private func report(_ error: Error) {
        Log.app.error("\(error.localizedDescription, privacy: .public)")

        let settingsPane: String?
        switch error {
        case CaptureError.screenRecordingDenied:
            settingsPane = "Privacy_ScreenCapture"
        case DeliveryError.accessibilityDenied:
            settingsPane = "Privacy_Accessibility"
        default:
            settingsPane = nil
        }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Framegentic"
        alert.informativeText = error.localizedDescription
        if let settingsPane {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                openPrivacySettings(pane: settingsPane)
            }
        } else {
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Menu actions

    @objc private func toggleAutoSend() {
        model.autoSend.toggle()
    }

    @objc private func toggleLoginItem() {
        model.setStartAtLogin(!model.startAtLogin)
    }

    @objc private func openScreenRecordingSettings() {
        openPrivacySettings(pane: "Privacy_ScreenCapture")
    }

    @objc private func openAccessibilitySettings() {
        openPrivacySettings(pane: "Privacy_Accessibility")
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    private func openPrivacySettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
