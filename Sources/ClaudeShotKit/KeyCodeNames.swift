import Carbon.HIToolbox
import Foundation

public enum KeyCodeNames {
    /// UCKeyTranslate maps Space to " " and the function keys to unprintable
    /// control characters, both of which survive a length check and render as
    /// nothing. This table must be consulted before the keyboard layout.
    private static let nonPrinting: [UInt32: String] = [
        UInt32(kVK_Return): "↩",
        UInt32(kVK_ANSI_KeypadEnter): "⌤",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "␣",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13",
        UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17",
        UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19",
        UInt32(kVK_F20): "F20"
    ]

    private static let ansi: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\",
        UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'",
        UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`"
    ]

    private static let functionKeyUnicode: [UInt32: Int] = [
        UInt32(kVK_UpArrow): 0xF700,
        UInt32(kVK_DownArrow): 0xF701,
        UInt32(kVK_LeftArrow): 0xF702,
        UInt32(kVK_RightArrow): 0xF703,
        UInt32(kVK_F1): 0xF704, UInt32(kVK_F2): 0xF705, UInt32(kVK_F3): 0xF706,
        UInt32(kVK_F4): 0xF707, UInt32(kVK_F5): 0xF708, UInt32(kVK_F6): 0xF709,
        UInt32(kVK_F7): 0xF70A, UInt32(kVK_F8): 0xF70B, UInt32(kVK_F9): 0xF70C,
        UInt32(kVK_F10): 0xF70D, UInt32(kVK_F11): 0xF70E, UInt32(kVK_F12): 0xF70F,
        UInt32(kVK_F13): 0xF710, UInt32(kVK_F14): 0xF711, UInt32(kVK_F15): 0xF712,
        UInt32(kVK_F16): 0xF713, UInt32(kVK_F17): 0xF714, UInt32(kVK_F18): 0xF715,
        UInt32(kVK_F19): 0xF716, UInt32(kVK_F20): 0xF717,
        UInt32(kVK_ForwardDelete): 0xF728,
        UInt32(kVK_Home): 0xF729,
        UInt32(kVK_End): 0xF72B,
        UInt32(kVK_PageUp): 0xF72C,
        UInt32(kVK_PageDown): 0xF72D
    ]

    public static func nonPrintingSymbol(for keyCode: UInt32) -> String? {
        nonPrinting[keyCode]
    }

    public static func ansiSymbol(for keyCode: UInt32) -> String? {
        ansi[keyCode]
    }

    public static func displayString(for keyCode: UInt32) -> String {
        if let symbol = nonPrintingSymbol(for: keyCode) { return symbol }
        if let fromLayout = layoutCharacter(for: keyCode) { return fromLayout }
        if let fallback = ansiSymbol(for: keyCode) { return fallback }
        return "Key \(keyCode)"
    }

    public static func menuKeyEquivalent(for keyCode: UInt32) -> String {
        if let scalarValue = functionKeyUnicode[keyCode],
           let scalar = UnicodeScalar(scalarValue) {
            return String(scalar)
        }
        switch keyCode {
        case UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter): return "\r"
        case UInt32(kVK_Tab): return "\t"
        case UInt32(kVK_Space): return " "
        case UInt32(kVK_Delete): return "\u{8}"
        case UInt32(kVK_Escape): return "\u{1b}"
        default: break
        }
        if let fromLayout = layoutCharacter(for: keyCode) { return fromLayout.lowercased() }
        if let fallback = ansiSymbol(for: keyCode) { return fallback.lowercased() }
        return ""
    }

    /// Asks the live keyboard layout what the key produces, so a Dvorak or AZERTY
    /// board shows the letter actually engraved on it. Returns nil under a
    /// non-ASCII-capable input source, where the ANSI fallback takes over.
    private static func layoutCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(
                source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let capacity = chars.count

        // withMemoryRebound rather than unsafeBitCast: the latter warns about
        // changing pointee type, and this target builds warning-free.
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyLayout in
            UCKeyTranslate(
                keyLayout,
                UInt16(truncatingIfNeeded: keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                capacity,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else { return nil }
        let result = String(utf16CodeUnits: chars, count: length)
        guard !result.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }),
              !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return result.uppercased()
    }
}
