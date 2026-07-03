import AppKit
import Carbon.HIToolbox

public struct HotKeyConfig: Sendable {
    public static let standard = HotKeyConfig()

    public let keyCode = UInt32(kVK_ANSI_6)
    public let carbonModifiers = UInt32(cmdKey | shiftKey)
    public let menuKeyEquivalent = "6"
    public let menuModifiers: NSEvent.ModifierFlags = [.command, .shift]
}
