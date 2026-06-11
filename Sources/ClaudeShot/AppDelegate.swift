import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let screenshot = ScreenshotService()
    private let hotKey = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("menu bar app")
        ProcessInfo.processInfo.disableSuddenTermination()
        setupStatusBar()
        hotKey.onHotKey = { [weak self] in self?.screenshotToClaude() }
        hotKey.register()
        if !AXIsProcessTrusted() {
            let _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            )
        }
        NSLog("ClaudeShot launched")
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "ClaudeShotStatusItem"
        guard let button = statusItem.button else { return }
        if let iconPath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
           let img = NSImage(contentsOfFile: iconPath) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            button.image = img
        } else if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ClaudeShot") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = img.withSymbolConfiguration(config)
        } else {
            button.title = "CS"
        }

        let menu = NSMenu()
        let item = NSMenuItem(title: "Screenshot → Claude", action: #selector(screenshotToClaude), keyEquivalent: "6")
        item.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(item)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ClaudeShot", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func screenshotToClaude() {
        screenshot.captureToClipboard { [weak self] ok in
            guard ok else {
                NSLog("ClaudeShot: capture failed")
                return
            }
            self?.activateClaudeAndPaste()
        }
    }

    private func activateClaudeAndPaste() {
        let claude = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == "Claude"
        })
        if let claude {
            claude.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.simulatePaste() }
        } else {
            let url = URL(fileURLWithPath: "/Applications/Claude.app")
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.simulatePaste() }
            }
        }
    }

    private func simulatePaste() {
        guard AXIsProcessTrusted() else {
            NSLog("ClaudeShot: paste blocked — Accessibility not granted")
            return
        }
        let src = CGEventSource(stateID: CGEventSourceStateID.combinedSessionState)
        let pasteDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        pasteDown?.flags = CGEventFlags.maskCommand
        let pasteUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        pasteUp?.flags = CGEventFlags.maskCommand
        pasteDown?.post(tap: CGEventTapLocation.cghidEventTap)
        pasteUp?.post(tap: CGEventTapLocation.cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let src2 = CGEventSource(stateID: CGEventSourceStateID.combinedSessionState)
            let returnDown = CGEvent(keyboardEventSource: src2, virtualKey: 0x24, keyDown: true)
            let returnUp = CGEvent(keyboardEventSource: src2, virtualKey: 0x24, keyDown: false)
            returnDown?.post(tap: CGEventTapLocation.cghidEventTap)
            returnUp?.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
