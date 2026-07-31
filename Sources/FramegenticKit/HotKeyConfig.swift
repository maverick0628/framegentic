import AppKit
import Carbon.HIToolbox

public struct HotKeyConfig: Sendable, Equatable, Codable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public static let `default` = HotKeyConfig(
        keyCode: UInt32(kVK_ANSI_6),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    /// Sequential with Snap's ⇧⌘6. Unlike ⇧⌘3/4/5, ⇧⌘7 is not one of the system's
    /// reserved screenshot combos, so it needs no Touch-Bar-only exception from
    /// HotKeyValidator the way Snap's own default does.
    public static let rewindDefault = HotKeyConfig(
        keyCode: UInt32(kVK_ANSI_7),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    public var menuModifiers: NSEvent.ModifierFlags {
        Self.modifierFlags(fromCarbon: carbonModifiers)
    }

    public var menuKeyEquivalent: String {
        KeyCodeNames.menuKeyEquivalent(for: keyCode)
    }

    public var displayString: String {
        Self.modifierGlyphs(carbonModifiers) + KeyCodeNames.displayString(for: keyCode)
    }

    public static func modifierFlags(fromCarbon carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    public static func modifierGlyphs(_ carbon: UInt32) -> String {
        var glyphs = ""
        if carbon & UInt32(controlKey) != 0 { glyphs += "⌃" }
        if carbon & UInt32(optionKey) != 0 { glyphs += "⌥" }
        if carbon & UInt32(shiftKey) != 0 { glyphs += "⇧" }
        if carbon & UInt32(cmdKey) != 0 { glyphs += "⌘" }
        return glyphs
    }
}
