import Carbon
import FramegenticKit

// Carbon is deliberate here: RegisterEventHotKey is the only macOS API that both
// consumes a global hotkey and works without Accessibility trust. NSEvent global
// monitors can only observe — the keystroke would still reach the frontmost app.
@MainActor
final class HotKeyManager {
    typealias Shortcut = HotKeyStore.Shortcut

    var onHotKey: ((Shortcut) -> Void)?

    // nonisolated(unsafe): only written on the main actor; deinit needs to read
    // them and Swift 6 forbids MainActor state in a nonisolated deinit.
    private nonisolated(unsafe) var hotKeyRefs: [Shortcut: EventHotKeyRef] = [:]
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?

    // "CSHT". Each shortcut gets its own id under this one signature — two
    // registrations sharing an id would make the second silently replace the
    // first, with no error and no warning from Carbon.
    private static let signature = OSType(0x4353_4854)

    private static func carbonID(for shortcut: Shortcut) -> UInt32 {
        switch shortcut {
        case .capture: return 1
        case .rewind: return 2
        }
    }

    private static func shortcut(forCarbonID id: UInt32) -> Shortcut? {
        Shortcut.allCases.first { carbonID(for: $0) == id }
    }

    /// Registers `config` for `shortcut`, replacing whatever that shortcut
    /// previously held; the other shortcut, if registered, is untouched. Returns
    /// false when Carbon refuses it — for example ⌘⇧6 on a Touch Bar Mac, where
    /// the system screenshot shortcut already owns it.
    func register(_ config: HotKeyConfig, for shortcut: Shortcut) -> Bool {
        unregister(shortcut)
        guard installHandlerIfNeeded() else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.carbonID(for: shortcut))
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        guard status == noErr, let newRef else {
            Log.hotkey.error("RegisterEventHotKey failed for \(shortcut.rawValue, privacy: .public): \(status)")
            return false
        }
        hotKeyRefs[shortcut] = newRef
        return true
    }

    /// Tears down every registered shortcut. Recording either one suspends both:
    /// the recorder captures a raw keystroke, and Carbon consumes a registered
    /// combo before AppKit ever sees it, so leaving the other shortcut live while
    /// recording would let it fire mid-recording instead of being captured.
    func unregister() {
        for shortcut in Shortcut.allCases { unregister(shortcut) }
    }

    private func unregister(_ shortcut: Shortcut) {
        guard let ref = hotKeyRefs[shortcut] else { return }
        UnregisterEventHotKey(ref)
        hotKeyRefs[shortcut] = nil
    }

    /// Installed once and kept for the process lifetime — reinstalling per
    /// re-registration would leak a handler ref each time a shortcut changes.
    private func installHandlerIfNeeded() -> Bool {
        guard handlerRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }

                // Both shortcuts share this one handler, so the fired event is the
                // only way to tell — by its EventHotKeyID — which one it was.
                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard paramStatus == noErr else { return noErr }

                // Handlers on the application event target fire on the main run loop.
                MainActor.assumeIsolated {
                    guard let shortcut = HotKeyManager.shortcut(forCarbonID: hotKeyID.id) else { return }
                    Unmanaged<HotKeyManager>.fromOpaque(userData)
                        .takeUnretainedValue()
                        .onHotKey?(shortcut)
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        guard status == noErr else {
            Log.hotkey.error("InstallEventHandler failed: \(status)")
            handlerRef = nil
            return false
        }
        return true
    }

    deinit {
        for ref in hotKeyRefs.values { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
