import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        model.windowWillShow()

        if let window {
            // LSUIElement apps do not get focus from ordering a window front alone,
            // and without focus the recorder never receives key events.
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let created = NSWindow(contentViewController: hosting)
        created.title = "ClaudeShot Settings"
        created.styleMask = [.titled, .closable]
        created.isReleasedWhenClosed = false
        created.center()
        window = created

        NSApp.activate()
        created.makeKeyAndOrderFront(nil)
    }
}
