import Carbon
import ClaudeShotKit

// Carbon is deliberate here: RegisterEventHotKey is the only macOS API that both
// consumes a global hotkey and works without Accessibility trust. NSEvent global
// monitors can only observe — the keystroke would still reach the frontmost app.
@MainActor
final class HotKeyManager {
    var onHotKey: (() -> Void)?

    // nonisolated(unsafe): only written from register() on the main actor; deinit
    // needs to read them and Swift 6 forbids MainActor state in a nonisolated deinit.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?

    /// Returns false when the hotkey could not be registered (for example when
    /// ⌘⇧6 is already taken by the system's Touch Bar screenshot shortcut).
    func register() -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
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
        guard installStatus == noErr else {
            Log.hotkey.error("InstallEventHandler failed: \(installStatus)")
            return false
        }

        let config = HotKeyConfig.standard
        let hotKeyID = EventHotKeyID(signature: OSType(0x4353_4854), id: 1) // "CSHT"
        let registerStatus = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            Log.hotkey.error("RegisterEventHotKey failed: \(registerStatus)")
            return false
        }
        return true
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
