import AppKit
import Carbon.HIToolbox
import SwiftUI
import ClaudeShotKit

@MainActor
final class ShortcutRecorderView: NSView {
    var onRecord: ((HotKeyConfig) -> Void)?
    var onBeginRecording: (() -> Void)?
    var onEndRecording: (() -> Void)?

    var idleTitle = "" {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet { needsDisplay = true }
    }
    private var previewGlyphs = "" {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 26) }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
            startRecording()
        }
    }

    // Required, not optional: AppKit sends ⌘-modified keys down the key-equivalent
    // chain, so a keyDown-only recorder never sees a combo containing ⌘.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        return capture(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, capture(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        previewGlyphs = HotKeyConfig.modifierGlyphs(
            HotKeyConfig.carbonModifiers(from: event.modifierFlags))
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return super.resignFirstResponder()
    }

    private var windowResignObserver: NSObjectProtocol?

    // resignFirstResponder only fires when first responder changes within this
    // window (e.g. clicking another control). Cmd-Tabbing away, clicking a
    // different app's window, or hiding this window resigns key status on the
    // whole window without ever touching first responder, so recording would
    // otherwise get stuck on with no way to exit it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
            self.windowResignObserver = nil
        }

        guard let window else { return }

        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // The queue: .main above guarantees this runs on the main thread,
            // but the compiler has no static way to know that, so it can't
            // verify this @Sendable closure's access to MainActor-isolated
            // self is safe. assumeIsolated documents and enforces that
            // guarantee rather than silencing a real race.
            MainActor.assumeIsolated {
                self?.stopRecording()
            }
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        previewGlyphs = ""
        isRecording = true
        onBeginRecording?()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        previewGlyphs = ""
        onEndRecording?()
    }

    private func capture(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        let carbon = HotKeyConfig.carbonModifiers(from: flags)

        if event.keyCode == UInt16(kVK_Escape) && carbon == 0 {
            stopRecording()
            return true
        }

        let config = HotKeyConfig(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
        stopRecording()
        onRecord?(config)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: inset, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                     : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        if isRecording {
            text = previewGlyphs.isEmpty ? "Type a shortcut…" : previewGlyphs
        } else {
            text = idleTitle
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                    y: bounds.midY - size.height / 2))
    }
}

struct ShortcutRecorderField: NSViewRepresentable {
    let idleTitle: String
    let onRecord: (HotKeyConfig) -> Void
    let onBeginRecording: () -> Void
    let onEndRecording: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.idleTitle = idleTitle
        view.onRecord = onRecord
        view.onBeginRecording = onBeginRecording
        view.onEndRecording = onEndRecording
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.idleTitle = idleTitle
        view.onRecord = onRecord
        view.onBeginRecording = onBeginRecording
        view.onEndRecording = onEndRecording
    }
}
