import Carbon
import ClaudeShotKit

// Carbon is deliberate here: RegisterEventHotKey is the only macOS API that both
// consumes a global hotkey and works without Accessibility trust. NSEvent global
// monitors can only observe — the keystroke would still reach the frontmost app.
@MainActor
final class HotKeyManager {
    var onHotKey: (() -> Void)?

    // nonisolated(unsafe): only written on the main actor; deinit needs to read
    // them and Swift 6 forbids MainActor state in a nonisolated deinit.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?

    /// Registers `config`, replacing any previously registered shortcut. Returns
    /// false when Carbon refuses it — for example ⌘⇧6 on a Touch Bar Mac, where
    /// the system screenshot shortcut already owns it.
    func register(_ config: HotKeyConfig) -> Bool {
        unregister()
        guard installHandlerIfNeeded() else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4353_4854), id: 1) // "CSHT"
        let status = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            Log.hotkey.error("RegisterEventHotKey failed: \(status)")
            hotKeyRef = nil
            return false
        }
        return true
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    /// Installed once and kept for the process lifetime — reinstalling per
    /// re-registration would leak a handler ref each time the shortcut changes.
    private func installHandlerIfNeeded() -> Bool {
        guard handlerRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                // Handlers on the application event target fire on the main run loop.
                MainActor.assumeIsolated {
                    Unmanaged<HotKeyManager>.fromOpaque(userData)
                        .takeUnretainedValue()
                        .onHotKey?()
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
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
