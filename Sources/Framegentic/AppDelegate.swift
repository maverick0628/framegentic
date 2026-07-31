import AppKit
import ApplicationServices
import FramegenticKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let screenshot = ScreenshotService()
    private let automator = ClaudeAutomator()
    private let hotKey = HotKeyManager()
    private lazy var model = SettingsModel(store: HotKeyStore(), hotKey: hotKey)
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private weak var captureMenuItem: NSMenuItem?
    private var isCapturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        hotKey.onHotKey = { [weak self] in self?.screenshotToClaude() }
        model.registerStoredHotKey()
        model.onRecordingStateChange = { [weak self] isRecording in
            self?.captureMenuItem?.keyEquivalent = isRecording
                ? ""
                : self?.model.hotKeyConfig.menuKeyEquivalent ?? ""
        }
        screenshot.prewarm()
        Log.app.info("Framegentic launched, hotkey registered: \(self.model.hotKeyRegistered)")
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        model.refreshStartAtLogin()

        let config = model.hotKeyConfig
        let capture = NSMenuItem(
            title: "Screenshot → Claude",
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

        let send = NSMenuItem(
            title: "Send Automatically After Paste",
            action: #selector(toggleAutoSend),
            keyEquivalent: ""
        )
        send.target = self
        send.state = model.autoSend ? .on : .off
        menu.addItem(send)

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
        if !AXIsProcessTrusted() {
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
        screenshotToClaude()
    }

    private func screenshotToClaude() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let changeCount = try await screenshot.captureToClipboard()
                try await automator.deliver(autoSend: model.autoSend,
                                           clipboardChangeCount: changeCount)
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
        case PasteError.accessibilityDenied:
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
