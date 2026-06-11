import Carbon
import Cocoa

final class HotKeyManager {
    var onHotKey: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?

    static var shared: HotKeyManager?

    func register() {
        HotKeyManager.shared = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async { HotKeyManager.shared?.onHotKey?() }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
        if installStatus != noErr {
            NSLog("ClaudeShot: InstallEventHandler failed: %d", installStatus)
        }

        var hotKeyID = EventHotKeyID(signature: OSType(0x43534854), id: 1)
        let regStatus = RegisterEventHotKey(
            22,
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if regStatus != noErr {
            NSLog("ClaudeShot: RegisterEventHotKey failed: %d", regStatus)
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    }
}
