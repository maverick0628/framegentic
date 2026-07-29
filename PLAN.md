# Shortcut Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user record, validate and persist the capture hotkey from a settings window, instead of it being hardcoded at ⌘⇧6.

**Architecture:** The shortcut becomes a `Codable` value type. `ClaudeShotKit` owns the value, its display derivation, a validator and `UserDefaults` persistence — all pure and unit tested, following the existing `PasteGuard` pattern. The app target owns an `NSView` recorder, a SwiftUI settings window, and Carbon registration. An `@Observable SettingsModel` is the single source of truth shared by the menu bar and the window so the two surfaces cannot drift.

**Tech Stack:** Swift 6, SwiftPM, AppKit + SwiftUI (`NSHostingController`), Carbon `RegisterEventHotKey`, `UCKeyTranslate`, XCTest. No third-party dependencies.

Design spec: [docs/superpowers/specs/2026-07-29-shortcut-customization-design.md](docs/superpowers/specs/2026-07-29-shortcut-customization-design.md)

## Global Constraints

- `swift-tools-version:6.0`, Swift 6 language mode. Platform floor `.macOS(.v14)`.
- **Zero third-party dependencies.** Do not add anything to `Package.swift` dependencies.
- `ClaudeShotKit` holds decisions and is unit tested. `ClaudeShot` holds AppKit/SwiftUI glue and is not. Do not put testable decision logic in the app target.
- No force unwraps. `guard` over nested `if let`.
- `@Observable` over `@ObservableObject`. SwiftUI for the window content; AppKit only where SwiftUI cannot express the behaviour (the recorder).
- `HotKeyConfig.default` must remain ⌘⇧6 — `keyCode` `UInt32(kVK_ANSI_6)`, `carbonModifiers` `UInt32(cmdKey | shiftKey)`.
- Carbon modifier raw values, verified on this machine: `cmdKey` 256, `shiftKey` 512, `optionKey` 2048, `controlKey` 4096. `kVK_ANSI_6` is 22.
- Modifier display order is always ⌃⌥⇧⌘, regardless of the order pressed.
- Comments in source explain *why*, never *what* — match the existing style in `HotKeyManager.swift`. Keep them sparse.
- Run `swift test` from the repo root. Run `bash scripts/build.sh` to produce a signed bundle.
- Every task ends with a commit. Trailer on every commit message:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

---

### Task 1: `KeyCodeNames` — keyCode to glyph

Resolves a Carbon virtual keycode to something displayable. Three lookups in a fixed order, because the keyboard layout lies about two whole classes of key: `UCKeyTranslate` maps Space to a literal `" "` (invisible in a UI) and the function keys to unprintable control characters, and both pass a naive `length > 0` check. The non-printing table therefore has to win before the layout is ever consulted — verified empirically before writing this plan.

**Files:**
- Create: `Sources/ClaudeShotKit/KeyCodeNames.swift`
- Test: `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift` (append a new `final class`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `KeyCodeNames.nonPrintingSymbol(for keyCode: UInt32) -> String?`
  - `KeyCodeNames.ansiSymbol(for keyCode: UInt32) -> String?`
  - `KeyCodeNames.displayString(for keyCode: UInt32) -> String`
  - `KeyCodeNames.menuKeyEquivalent(for keyCode: UInt32) -> String`

- [ ] **Step 1: Write the failing test**

Append to `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift`:

```swift
final class KeyCodeNamesTests: XCTestCase {
    func testNonPrintingKeysUseGlyphsNotLayoutCharacters() {
        XCTAssertEqual(KeyCodeNames.nonPrintingSymbol(for: UInt32(kVK_Space)), "␣")
        XCTAssertEqual(KeyCodeNames.nonPrintingSymbol(for: UInt32(kVK_Return)), "↩")
        XCTAssertEqual(KeyCodeNames.nonPrintingSymbol(for: UInt32(kVK_Escape)), "⎋")
        XCTAssertEqual(KeyCodeNames.nonPrintingSymbol(for: UInt32(kVK_LeftArrow)), "←")
        XCTAssertEqual(KeyCodeNames.nonPrintingSymbol(for: UInt32(kVK_F1)), "F1")
        XCTAssertEqual(KeyCodeNames.nonPrintingSymbol(for: UInt32(kVK_F12)), "F12")
        XCTAssertNil(KeyCodeNames.nonPrintingSymbol(for: UInt32(kVK_ANSI_6)))
    }

    func testAnsiFallbackCoversLettersDigitsAndPunctuation() {
        XCTAssertEqual(KeyCodeNames.ansiSymbol(for: UInt32(kVK_ANSI_6)), "6")
        XCTAssertEqual(KeyCodeNames.ansiSymbol(for: UInt32(kVK_ANSI_C)), "C")
        XCTAssertEqual(KeyCodeNames.ansiSymbol(for: UInt32(kVK_ANSI_Slash)), "/")
        XCTAssertEqual(KeyCodeNames.ansiSymbol(for: UInt32(kVK_ANSI_Grave)), "`")
        XCTAssertNil(KeyCodeNames.ansiSymbol(for: UInt32(kVK_Space)))
    }

    // Deterministic because the non-printing table is consulted before the
    // keyboard layout — a layout-dependent assertion would fail on Dvorak.
    func testDisplayStringPrefersGlyphTableOverLayout() {
        XCTAssertEqual(KeyCodeNames.displayString(for: UInt32(kVK_Space)), "␣")
        XCTAssertEqual(KeyCodeNames.displayString(for: UInt32(kVK_F5)), "F5")
    }

    func testDisplayStringDegradesLegiblyForUnknownKeyCodes() {
        XCTAssertEqual(KeyCodeNames.displayString(for: 9999), "Key 9999")
    }

    func testMenuKeyEquivalentIsLowercaseBaseCharacter() {
        XCTAssertEqual(KeyCodeNames.menuKeyEquivalent(for: UInt32(kVK_ANSI_6)), "6")
        XCTAssertEqual(KeyCodeNames.menuKeyEquivalent(for: UInt32(kVK_ANSI_C)), "c")
        XCTAssertEqual(KeyCodeNames.menuKeyEquivalent(for: UInt32(kVK_Return)), "\r")
        XCTAssertEqual(KeyCodeNames.menuKeyEquivalent(for: UInt32(kVK_Tab)), "\t")
        XCTAssertEqual(KeyCodeNames.menuKeyEquivalent(for: UInt32(kVK_Space)), " ")
    }

    func testMenuKeyEquivalentUsesFunctionKeyUnicodeConstants() {
        XCTAssertEqual(KeyCodeNames.menuKeyEquivalent(for: UInt32(kVK_F1)), "\u{F704}")
        XCTAssertEqual(KeyCodeNames.menuKeyEquivalent(for: UInt32(kVK_UpArrow)), "\u{F700}")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter KeyCodeNamesTests`
Expected: FAIL — compile error, `cannot find 'KeyCodeNames' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeShotKit/KeyCodeNames.swift`:

```swift
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
```

This exact file was compiled under `-swift-version 6` and run against the assertions above before this plan was written: all pass, no warnings.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter KeyCodeNamesTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeShotKit/KeyCodeNames.swift Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift
git commit -m "feat(kit): resolve key codes to display glyphs and menu key equivalents

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `HotKeyConfig` becomes a value type

Turns the hardcoded singleton into an initialisable, `Codable` value with derived display and menu representations. `standard` is renamed `default`, which breaks two call sites — both are fixed in this task so the build stays green.

**Files:**
- Modify: `Sources/ClaudeShotKit/HotKeyConfig.swift` (whole file rewritten)
- Modify: `Sources/ClaudeShot/HotKeyManager.swift:47` (`HotKeyConfig.standard` → `.default`)
- Modify: `Sources/ClaudeShot/AppDelegate.swift:57` (`HotKeyConfig.standard` → `.default`)
- Test: `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift` (replace the existing `HotKeyConfigTests` class)

**Interfaces:**
- Consumes: `KeyCodeNames.displayString(for:)`, `KeyCodeNames.menuKeyEquivalent(for:)` from Task 1.
- Produces:
  - `HotKeyConfig(keyCode: UInt32, carbonModifiers: UInt32)`
  - `HotKeyConfig.default`
  - instance `keyCode`, `carbonModifiers`, `menuModifiers`, `menuKeyEquivalent`, `displayString`
  - `HotKeyConfig.modifierFlags(fromCarbon: UInt32) -> NSEvent.ModifierFlags`
  - `HotKeyConfig.carbonModifiers(from: NSEvent.ModifierFlags) -> UInt32`
  - `HotKeyConfig.modifierGlyphs(_ carbon: UInt32) -> String` (public — the recorder's
    live modifier preview in Task 7 needs it)
  - conformances: `Sendable`, `Equatable`, `Codable`

- [ ] **Step 1: Write the failing test**

Replace the existing `HotKeyConfigTests` class in `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift` with:

```swift
final class HotKeyConfigTests: XCTestCase {
    // Preserves the original guarantee: the shipped default must stay ⌘⇧6.
    func testMenuAndCarbonHotKeyDefinitionsAgree() {
        let c = HotKeyConfig.default
        XCTAssertEqual(c.keyCode, UInt32(kVK_ANSI_6))
        XCTAssertEqual(c.carbonModifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(c.menuKeyEquivalent, "6")
        XCTAssertEqual(c.menuModifiers, [.command, .shift])
    }

    func testRoundTripsThroughCodable() throws {
        let original = HotKeyConfig(keyCode: UInt32(kVK_ANSI_C),
                                    carbonModifiers: UInt32(optionKey | shiftKey))
        let decoded = try JSONDecoder().decode(
            HotKeyConfig.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testCarbonAndNSModifierMappingRoundTrips() {
        let all = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        XCTAssertEqual(
            HotKeyConfig.carbonModifiers(from: HotKeyConfig.modifierFlags(fromCarbon: all)),
            all)
        XCTAssertEqual(
            HotKeyConfig.carbonModifiers(from: HotKeyConfig.modifierFlags(fromCarbon: 0)), 0)
        XCTAssertEqual(HotKeyConfig.modifierFlags(fromCarbon: UInt32(controlKey)), [.control])
        XCTAssertEqual(HotKeyConfig.carbonModifiers(from: [.option]), UInt32(optionKey))
    }

    // Arrow keys and function keys arrive carrying .function and .numericPad;
    // only the four real modifiers may survive the mapping.
    func testMappingIgnoresIncidentalEventFlags() {
        XCTAssertEqual(
            HotKeyConfig.carbonModifiers(from: [.command, .function, .numericPad, .capsLock]),
            UInt32(cmdKey))
    }

    func testDisplayStringUsesCanonicalModifierOrder() {
        let scrambled = HotKeyConfig(
            keyCode: UInt32(kVK_ANSI_C),
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
        XCTAssertEqual(scrambled.displayString, "⌃⌥⇧⌘C")
        XCTAssertEqual(HotKeyConfig.default.displayString, "⇧⌘6")
        XCTAssertEqual(
            HotKeyConfig(keyCode: UInt32(kVK_Space),
                         carbonModifiers: UInt32(optionKey)).displayString, "⌥␣")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HotKeyConfigTests`
Expected: FAIL — compile error, no `init(keyCode:carbonModifiers:)` and no member `default`.

- [ ] **Step 3: Write minimal implementation**

Replace the entire contents of `Sources/ClaudeShotKit/HotKeyConfig.swift`:

```swift
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
```

- [ ] **Step 4: Fix the two broken call sites**

In `Sources/ClaudeShot/HotKeyManager.swift`, change:

```swift
        let config = HotKeyConfig.standard
```

to:

```swift
        let config = HotKeyConfig.default
```

In `Sources/ClaudeShot/AppDelegate.swift`, inside `menuNeedsUpdate`, change:

```swift
        let config = HotKeyConfig.standard
```

to:

```swift
        let config = HotKeyConfig.default
```

- [ ] **Step 5: Run the full suite and build**

Run: `swift test && swift build -c release`
Expected: PASS, all tests green, release build succeeds with no warnings.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeShotKit/HotKeyConfig.swift Sources/ClaudeShot/HotKeyManager.swift Sources/ClaudeShot/AppDelegate.swift Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift
git commit -m "refactor(kit): make HotKeyConfig an initialisable Codable value

Derives menu and display representations from keyCode instead of storing
them, so a recorded shortcut can be rendered anywhere. Renames standard
to default.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: `HotKeyValidator`

Rejects combos before they reach Carbon. Two rules: a baseline modifier requirement, then a curated table of system-owned combos carrying the name of the owner, so the error can say "⌘Space belongs to Spotlight" instead of "already taken".

`RegisterEventHotKey` remains the authoritative gate — this table is a courtesy in front of it. It cannot know about third-party bindings and will drift with macOS releases.

**Files:**
- Create: `Sources/ClaudeShotKit/HotKeyValidator.swift`
- Test: `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift` (append a new `final class`)

**Interfaces:**
- Consumes: `HotKeyConfig` from Task 2.
- Produces:
  - `enum HotKeyRejection: Equatable, Sendable { case missingRequiredModifier, reserved(owner: String) }`
  - `enum HotKeyValidation: Equatable, Sendable { case valid, rejected(HotKeyRejection) }`
  - `HotKeyValidator.validate(_ config: HotKeyConfig) -> HotKeyValidation`

- [ ] **Step 1: Write the failing test**

Append to `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift`:

```swift
final class HotKeyValidatorTests: XCTestCase {
    private func config(_ keyCode: Int, _ modifiers: Int) -> HotKeyConfig {
        HotKeyConfig(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers))
    }

    // The trap this test exists for: if anyone ever adds ⌘⇧6 to the reserved
    // table, the app rejects its own default and Reset to Default can never work.
    func testAcceptsItsOwnDefault() {
        XCTAssertEqual(HotKeyValidator.validate(.default), .valid)
    }

    func testAcceptsOrdinaryCombos() {
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_ANSI_C, optionKey | shiftKey)),
                       .valid)
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_ANSI_7, cmdKey | shiftKey)),
                       .valid)
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_F13, controlKey)), .valid)
    }

    func testRejectsShiftOnlyAndBareKeys() {
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_ANSI_C, 0)),
                       .rejected(.missingRequiredModifier))
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_ANSI_C, shiftKey)),
                       .rejected(.missingRequiredModifier))
    }

    func testRejectsReservedCombosWithTheirOwner() {
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_Space, cmdKey)),
                       .rejected(.reserved(owner: "Spotlight")))
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_Tab, cmdKey)),
                       .rejected(.reserved(owner: "the app switcher")))
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_ANSI_Q, cmdKey)),
                       .rejected(.reserved(owner: "Quit")))
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_ANSI_4, cmdKey | shiftKey)),
                       .rejected(.reserved(owner: "Screenshot")))
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_UpArrow, controlKey)),
                       .rejected(.reserved(owner: "Mission Control")))
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_Escape, optionKey | cmdKey)),
                       .rejected(.reserved(owner: "Force Quit")))
    }

    // Reserved entries match on the exact modifier set, so a near miss is fine.
    func testReservedMatchIsExact() {
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_Space, cmdKey | shiftKey)), .valid)
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_ANSI_Q, optionKey)), .valid)
    }

    func testModifierRuleIsCheckedBeforeTheReservedTable() {
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_Space, 0)),
                       .rejected(.missingRequiredModifier))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HotKeyValidatorTests`
Expected: FAIL — compile error, `cannot find 'HotKeyValidator' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeShotKit/HotKeyValidator.swift`:

```swift
import Carbon.HIToolbox

public enum HotKeyRejection: Equatable, Sendable {
    case missingRequiredModifier
    case reserved(owner: String)
}

public enum HotKeyValidation: Equatable, Sendable {
    case valid
    case rejected(HotKeyRejection)
}

public enum HotKeyValidator {
    private struct Reserved {
        let keyCode: UInt32
        let carbonModifiers: UInt32
        let owner: String
    }

    private static let cmd = UInt32(cmdKey)
    private static let shift = UInt32(shiftKey)
    private static let opt = UInt32(optionKey)
    private static let ctrl = UInt32(controlKey)

    /// A courtesy in front of RegisterEventHotKey, which reports failure without
    /// a reason. Deliberately does not list ⌘⇧6: it is only taken on Touch Bar
    /// Macs, and it is this app's own default — registration reports it there.
    private static let reserved: [Reserved] = [
        Reserved(keyCode: UInt32(kVK_Space), carbonModifiers: cmd, owner: "Spotlight"),
        Reserved(keyCode: UInt32(kVK_Space), carbonModifiers: opt | cmd, owner: "Finder search"),
        Reserved(keyCode: UInt32(kVK_Space), carbonModifiers: ctrl | cmd, owner: "Emoji & Symbols"),
        Reserved(keyCode: UInt32(kVK_Space), carbonModifiers: ctrl, owner: "input source switching"),
        Reserved(keyCode: UInt32(kVK_Tab), carbonModifiers: cmd, owner: "the app switcher"),
        Reserved(keyCode: UInt32(kVK_Tab), carbonModifiers: cmd | shift, owner: "the app switcher"),
        Reserved(keyCode: UInt32(kVK_ANSI_Q), carbonModifiers: cmd, owner: "Quit"),
        Reserved(keyCode: UInt32(kVK_ANSI_W), carbonModifiers: cmd, owner: "Close Window"),
        Reserved(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: cmd, owner: "Hide"),
        Reserved(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: cmd, owner: "Minimise"),
        Reserved(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: cmd | shift, owner: "Screenshot"),
        Reserved(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: cmd | shift, owner: "Screenshot"),
        Reserved(keyCode: UInt32(kVK_ANSI_5), carbonModifiers: cmd | shift, owner: "Screenshot"),
        Reserved(keyCode: UInt32(kVK_UpArrow), carbonModifiers: ctrl, owner: "Mission Control"),
        Reserved(keyCode: UInt32(kVK_DownArrow), carbonModifiers: ctrl, owner: "Mission Control"),
        Reserved(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: ctrl, owner: "Spaces"),
        Reserved(keyCode: UInt32(kVK_RightArrow), carbonModifiers: ctrl, owner: "Spaces"),
        Reserved(keyCode: UInt32(kVK_Escape), carbonModifiers: opt | cmd, owner: "Force Quit"),
        Reserved(keyCode: UInt32(kVK_ANSI_Q), carbonModifiers: ctrl | cmd, owner: "Lock Screen")
    ]

    public static func validate(_ config: HotKeyConfig) -> HotKeyValidation {
        let required = cmd | ctrl | opt
        guard config.carbonModifiers & required != 0 else {
            return .rejected(.missingRequiredModifier)
        }
        if let hit = reserved.first(where: {
            $0.keyCode == config.keyCode && $0.carbonModifiers == config.carbonModifiers
        }) {
            return .rejected(.reserved(owner: hit.owner))
        }
        return .valid
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HotKeyValidatorTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeShotKit/HotKeyValidator.swift Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift
git commit -m "feat(kit): validate shortcuts against a reserved-combo table

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `HotKeyStore`

Persists the shortcut as a JSON blob under one `UserDefaults` key. Falls back to `HotKeyConfig.default` when the key is unset or the blob does not decode, so a corrupt value degrades to a working app rather than a dead hotkey. `UserDefaults` is injected so tests use a scratch suite instead of the real domain.

**Files:**
- Create: `Sources/ClaudeShotKit/HotKeyStore.swift`
- Test: `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift` (append a new `final class`)

**Interfaces:**
- Consumes: `HotKeyConfig` from Task 2.
- Produces:
  - `HotKeyStore(defaults: UserDefaults = .standard)`
  - `HotKeyStore.defaultsKey: String`
  - `load() -> HotKeyConfig`
  - `save(_ config: HotKeyConfig)`

- [ ] **Step 1: Write the failing test**

Append to `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift`:

```swift
final class HotKeyStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "com.duncansmith.claudeshot.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadReturnsDefaultWhenNothingStored() {
        XCTAssertEqual(HotKeyStore(defaults: defaults).load(), .default)
    }

    func testSaveThenLoadRoundTrips() {
        let store = HotKeyStore(defaults: defaults)
        let config = HotKeyConfig(keyCode: UInt32(kVK_ANSI_C),
                                  carbonModifiers: UInt32(optionKey | shiftKey))
        store.save(config)
        XCTAssertEqual(store.load(), config)
        XCTAssertEqual(HotKeyStore(defaults: defaults).load(), config)
    }

    func testLoadReturnsDefaultWhenStoredBlobIsCorrupt() {
        defaults.set(Data("not json".utf8), forKey: HotKeyStore.defaultsKey)
        XCTAssertEqual(HotKeyStore(defaults: defaults).load(), .default)
    }

    func testLoadReturnsDefaultWhenStoredValueIsWrongType() {
        defaults.set("⌘⇧6", forKey: HotKeyStore.defaultsKey)
        XCTAssertEqual(HotKeyStore(defaults: defaults).load(), .default)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HotKeyStoreTests`
Expected: FAIL — compile error, `cannot find 'HotKeyStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeShotKit/HotKeyStore.swift`:

```swift
import Foundation

public struct HotKeyStore {
    public static let defaultsKey = "CaptureHotKey"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Falls back to the default on absent or undecodable data: a corrupt blob
    /// should leave a working hotkey, not no hotkey.
    public func load() -> HotKeyConfig {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let config = try? JSONDecoder().decode(HotKeyConfig.self, from: data)
        else { return .default }
        return config
    }

    public func save(_ config: HotKeyConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HotKeyStoreTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeShotKit/HotKeyStore.swift Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift
git commit -m "feat(kit): persist the capture shortcut in UserDefaults

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: `HotKeyManager` registers an arbitrary config

Takes a config parameter instead of reading the global default, and gains `unregister()` so the shortcut can be swapped at runtime and suspended while recording. The Carbon event handler is installed once and kept across re-registrations — reinstalling it per change would leak handler refs.

After this task the stored shortcut is honoured at launch, which is manually testable with `defaults write` before any UI exists.

**Files:**
- Modify: `Sources/ClaudeShot/HotKeyManager.swift`
- Modify: `Sources/ClaudeShot/AppDelegate.swift`

**Interfaces:**
- Consumes: `HotKeyConfig`, `HotKeyStore` from Tasks 2 and 4.
- Produces:
  - `HotKeyManager.register(_ config: HotKeyConfig) -> Bool`
  - `HotKeyManager.unregister()`

- [ ] **Step 1: Rewrite `HotKeyManager`**

Replace the entire contents of `Sources/ClaudeShot/HotKeyManager.swift`:

```swift
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
```

- [ ] **Step 2: Load the stored shortcut in `AppDelegate`**

In `Sources/ClaudeShot/AppDelegate.swift`, add a stored property next to the existing ones:

```swift
    private let hotKeyStore = HotKeyStore()
    private var hotKeyConfig = HotKeyConfig.default
```

Replace the body of `applicationDidFinishLaunching` with:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        hotKey.onHotKey = { [weak self] in self?.screenshotToClaude() }
        hotKeyConfig = hotKeyStore.load()
        hotKeyRegistered = hotKey.register(hotKeyConfig)
        screenshot.prewarm()
        Log.app.info("ClaudeShot launched, hotkey registered: \(self.hotKeyRegistered)")
    }
```

In `menuNeedsUpdate`, replace `let config = HotKeyConfig.default` with:

```swift
        let config = hotKeyConfig
```

and replace the hardcoded warning title:

```swift
            let warning = NSMenuItem(
                title: "Hotkey unavailable — is ⌘⇧6 taken by macOS?",
                action: nil,
                keyEquivalent: ""
            )
```

with:

```swift
            let warning = NSMenuItem(
                title: "Hotkey unavailable — is \(config.displayString) taken?",
                action: nil,
                keyEquivalent: ""
            )
```

- [ ] **Step 3: Build and verify the stored shortcut is honoured**

```bash
swift test && bash scripts/build.sh
```

Expected: tests pass, bundle builds.

Then verify persistence is actually read, before any UI exists. ⌥⇧C is keyCode 8 with `optionKey | shiftKey` = 2048 | 512 = 2560, and the store writes JSON, so the defaults value is that JSON as raw data:

```bash
defaults write com.duncansmith.claudeshot CaptureHotKey -data "$(printf '%s' '{"keyCode":8,"carbonModifiers":2560}' | xxd -p | tr -d '\n')"
```

Then `open .build/ClaudeShot.app`, open the menu bar item, and confirm the capture item shows ⌥⇧C and that pressing ⌥⇧C triggers a capture. Reset afterwards:

```bash
defaults delete com.duncansmith.claudeshot CaptureHotKey
```

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeShot/HotKeyManager.swift Sources/ClaudeShot/AppDelegate.swift
git commit -m "feat: register the stored shortcut instead of a hardcoded one

HotKeyManager takes a config and gains unregister() so the shortcut can be
swapped at runtime and suspended while recording. The Carbon handler is
installed once rather than per registration.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: `SettingsModel` — one source of truth

Centralises the three settings so the menu bar and the settings window read and write the same state. The menu keeps its toggles, so without a shared model the two surfaces would drift.

`apply(_:)` is the heart of the feature: validate, then register, then persist — in that order, so a shortcut that does not work can never end up saved. On failure the previous shortcut is re-registered.

**Files:**
- Create: `Sources/ClaudeShot/SettingsModel.swift`
- Modify: `Sources/ClaudeShot/AppDelegate.swift`

**Interfaces:**
- Consumes: `HotKeyConfig`, `HotKeyValidator`, `HotKeyStore` (Tasks 2–4); `HotKeyManager.register(_:)` / `unregister()` (Task 5).
- Produces, all `@MainActor`:
  - `SettingsModel(store: HotKeyStore, hotKey: HotKeyManager)`
  - `var hotKeyConfig: HotKeyConfig` (read-only to consumers; changed via `apply`)
  - `var hotKeyRegistered: Bool`
  - `var isRecording: Bool`
  - `var shortcutError: String?`
  - `var autoSend: Bool`
  - `var startAtLogin: Bool`
  - `func registerStoredHotKey()`
  - `@discardableResult func apply(_ candidate: HotKeyConfig) -> Bool`
  - `func resetToDefault()`
  - `func beginRecording()` / `func endRecording()`
  - `func refreshStartAtLogin()`
  - `func setStartAtLogin(_ enabled: Bool)`

- [ ] **Step 1: Write the model**

Create `Sources/ClaudeShot/SettingsModel.swift`:

```swift
import AppKit
import Observation
import ServiceManagement
import ClaudeShotKit

@MainActor
@Observable
final class SettingsModel {
    private static let autoSendKey = "AutoSendAfterPaste"

    private let store: HotKeyStore
    private let hotKey: HotKeyManager

    private(set) var hotKeyConfig: HotKeyConfig
    private(set) var hotKeyRegistered = false
    private(set) var isRecording = false
    private(set) var shortcutError: String?
    private(set) var startAtLogin = false

    var autoSend: Bool {
        didSet { UserDefaults.standard.set(autoSend, forKey: Self.autoSendKey) }
    }

    init(store: HotKeyStore, hotKey: HotKeyManager) {
        self.store = store
        self.hotKey = hotKey
        self.hotKeyConfig = store.load()
        self.autoSend = UserDefaults.standard.bool(forKey: Self.autoSendKey)
    }

    var canResetToDefault: Bool { hotKeyConfig != .default }

    func registerStoredHotKey() {
        hotKeyRegistered = hotKey.register(hotKeyConfig)
        refreshStartAtLogin()
    }

    /// Validate, register, then persist — in that order, so a shortcut that
    /// Carbon refuses is never written to the store.
    @discardableResult
    func apply(_ candidate: HotKeyConfig) -> Bool {
        switch HotKeyValidator.validate(candidate) {
        case .rejected(.missingRequiredModifier):
            shortcutError = "Add ⌘, ⌃ or ⌥ — without one it would fire while you type."
            return false
        case .rejected(.reserved(let owner)):
            shortcutError = "\(candidate.displayString) belongs to \(owner)."
            return false
        case .valid:
            break
        }

        guard hotKey.register(candidate) else {
            hotKeyRegistered = hotKey.register(hotKeyConfig)
            shortcutError = "\(candidate.displayString) is already taken by another app."
            return false
        }

        hotKeyConfig = candidate
        store.save(candidate)
        hotKeyRegistered = true
        shortcutError = nil
        return true
    }

    func resetToDefault() {
        apply(.default)
    }

    /// Carbon consumes the registered combo before AppKit dispatch, so the
    /// hotkey must be suspended or the current shortcut can never be re-recorded.
    func beginRecording() {
        isRecording = true
        shortcutError = nil
        hotKey.unregister()
    }

    func endRecording() {
        isRecording = false
        hotKeyRegistered = hotKey.register(hotKeyConfig)
    }

    func refreshStartAtLogin() {
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Login item toggle failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshStartAtLogin()
    }
}
```

- [ ] **Step 2: Route `AppDelegate` through the model**

In `Sources/ClaudeShot/AppDelegate.swift`, delete these members entirely: the `autoSendKey` static, the `autoSend` computed property, `hotKeyRegistered`, `hotKeyConfig`, `hotKeyStore`, and the `toggleLoginItem` body's `SMAppService` calls.

Replace the stored properties block with:

```swift
    private var statusItem: NSStatusItem?
    private let screenshot = ScreenshotService()
    private let automator = ClaudeAutomator()
    private let hotKey = HotKeyManager()
    private lazy var model = SettingsModel(store: HotKeyStore(), hotKey: hotKey)
    private weak var captureMenuItem: NSMenuItem?
    private var isCapturing = false
```

Replace `applicationDidFinishLaunching`:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        hotKey.onHotKey = { [weak self] in self?.screenshotToClaude() }
        model.registerStoredHotKey()
        screenshot.prewarm()
        Log.app.info("ClaudeShot launched, hotkey registered: \(self.model.hotKeyRegistered)")
    }
```

In `menuNeedsUpdate`, replace the capture item and warning block with:

```swift
        let config = model.hotKeyConfig
        let capture = NSMenuItem(
            title: "Screenshot → Claude",
            action: #selector(captureFromMenu),
            keyEquivalent: model.isRecording ? "" : config.menuKeyEquivalent
        )
        if !model.isRecording {
            capture.keyEquivalentModifierMask = config.menuModifiers
        }
        capture.target = self
        menu.addItem(capture)
        captureMenuItem = capture

        if !model.hotKeyRegistered {
            let warning = NSMenuItem(
                title: "Hotkey unavailable — is \(config.displayString) taken?",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)
        }
```

Replace the `send.state` and `login.state` lines with model reads:

```swift
        send.state = model.autoSend ? .on : .off
```

```swift
        login.state = model.startAtLogin ? .on : .off
```

Replace the two toggle actions:

```swift
    @objc private func toggleAutoSend() {
        model.autoSend.toggle()
    }

    @objc private func toggleLoginItem() {
        model.setStartAtLogin(!model.startAtLogin)
    }
```

Replace the `autoSend` reference inside `screenshotToClaude`:

```swift
                try await automator.deliver(autoSend: model.autoSend,
                                           clipboardChangeCount: changeCount)
```

- [ ] **Step 3: Build and verify no behaviour changed**

```bash
swift test && bash scripts/build.sh
```

Expected: tests pass, bundle builds with no warnings.

Then `open .build/ClaudeShot.app` and confirm from the menu bar that Send Automatically After Paste and Start at Login still toggle and still persist across a quit and relaunch. Nothing user-visible should have changed in this task.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeShot/SettingsModel.swift Sources/ClaudeShot/AppDelegate.swift
git commit -m "refactor: centralise settings in an observable model

The menu bar and the coming settings window both need to read and write
these three settings; a shared model is what stops them drifting.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: `ShortcutRecorderField`

An `NSView`, not a SwiftUI view, for one reason: `performKeyEquivalent(with:)` has to be overridden. AppKit routes ⌘-modified keys down the key-equivalent chain, so a recorder implementing only `keyDown` never sees any combo containing ⌘ — which is most of them.

Recording commits on the first non-modifier key-down. Escape with no modifiers cancels rather than being recorded.

**Files:**
- Create: `Sources/ClaudeShot/ShortcutRecorderField.swift`

**Interfaces:**
- Consumes: `HotKeyConfig.carbonModifiers(from:)` from Task 2.
- Produces:
  - `final class ShortcutRecorderView: NSView` with `onRecord: ((HotKeyConfig) -> Void)?`, `onBeginRecording: (() -> Void)?`, `onEndRecording: (() -> Void)?`, `var idleTitle: String`
  - `struct ShortcutRecorderField: NSViewRepresentable` with `idleTitle: String`, `onRecord: (HotKeyConfig) -> Void`, `onBeginRecording: () -> Void`, `onEndRecording: () -> Void`

- [ ] **Step 1: Write the view**

Create `Sources/ClaudeShot/ShortcutRecorderField.swift`:

```swift
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
```

- [ ] **Step 2: Build**

Run: `swift build -c release`
Expected: succeeds with no warnings. The view has no call site yet, so there is nothing to run.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeShot/ShortcutRecorderField.swift
git commit -m "feat: add an NSView shortcut recorder

performKeyEquivalent has to be overridden or the recorder never sees any
combo containing Command, which AppKit routes down the key-equivalent chain.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Settings window, wired end to end

The feature becomes usable. A SwiftUI view in an `NSHostingController`, opened from a new menu item, plus the unavailable-hotkey item becoming a clickable route into it.

Two details that matter. The app is `LSUIElement`, so `NSApp.activate()` is required or the window never becomes key and the recorder never receives keys. And while recording, the capture menu item's key equivalent is cleared on the live item as well as on rebuild — belt and braces, so correctness does not rest on AppKit trying the window's `performKeyEquivalent` before the main menu's.

**Files:**
- Create: `Sources/ClaudeShot/SettingsView.swift`
- Create: `Sources/ClaudeShot/SettingsWindowController.swift`
- Modify: `Sources/ClaudeShot/AppDelegate.swift`
- Modify: `Sources/ClaudeShot/SettingsModel.swift`

**Interfaces:**
- Consumes: `SettingsModel` (Task 6), `ShortcutRecorderField` (Task 7).
- Produces:
  - `struct SettingsView: View` initialised as `SettingsView(model:)`
  - `final class SettingsWindowController` with `init(model: SettingsModel)` and `func show()`
  - `SettingsModel.onRecordingStateChange: ((Bool) -> Void)?`

- [ ] **Step 1: Let the model announce recording state**

In `Sources/ClaudeShot/SettingsModel.swift`, add the property:

```swift
    var onRecordingStateChange: ((Bool) -> Void)?
```

and set it from both recording transitions:

```swift
    func beginRecording() {
        isRecording = true
        shortcutError = nil
        hotKey.unregister()
        onRecordingStateChange?(true)
    }

    func endRecording() {
        isRecording = false
        hotKeyRegistered = hotKey.register(hotKeyConfig)
        onRecordingStateChange?(false)
    }
```

- [ ] **Step 2: Write the SwiftUI view**

Create `Sources/ClaudeShot/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Capture Shortcut")
                    .font(.headline)
                HStack(spacing: 10) {
                    ShortcutRecorderField(
                        idleTitle: model.hotKeyConfig.displayString,
                        onRecord: { model.apply($0) },
                        onBeginRecording: { model.beginRecording() },
                        onEndRecording: { model.endRecording() }
                    )
                    .frame(width: 200, height: 26)

                    Button("Reset to Default") { model.resetToDefault() }
                        .disabled(!model.canResetToDefault)
                }
                if let error = model.shortcutError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !model.hotKeyRegistered {
                    Text("\(model.hotKeyConfig.displayString) could not be registered. Pick another.")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Send automatically after paste", isOn: $model.autoSend)
                Toggle("Start at login", isOn: Binding(
                    get: { model.startAtLogin },
                    set: { model.setStartAtLogin($0) }
                ))
            }

            Text("Sending is manual by default. With auto-send on, the screenshot reaches Anthropic the moment Return fires.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { model.refreshStartAtLogin() }
    }
}
```

- [ ] **Step 3: Write the window controller**

Create `Sources/ClaudeShot/SettingsWindowController.swift`:

```swift
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
        model.refreshStartAtLogin()

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
```

- [ ] **Step 4: Wire it into `AppDelegate`**

Add the stored property:

```swift
    private lazy var settingsWindow = SettingsWindowController(model: model)
```

In `applicationDidFinishLaunching`, after `model.registerStoredHotKey()`, add:

```swift
        model.onRecordingStateChange = { [weak self] isRecording in
            self?.captureMenuItem?.keyEquivalent = isRecording
                ? ""
                : self?.model.hotKeyConfig.menuKeyEquivalent ?? ""
        }
```

In `menuNeedsUpdate`, add a Settings item immediately after the warning block and before the first `menu.addItem(.separator())`:

```swift
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)
```

Make the warning item clickable by replacing the warning block with:

```swift
        if !model.hotKeyRegistered {
            let warning = NSMenuItem(
                title: "Hotkey unavailable — is \(config.displayString) taken?",
                action: #selector(openSettings),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
        }
```

Add the action alongside the other `@objc` methods:

```swift
    @objc private func openSettings() {
        settingsWindow.show()
    }
```

Rename the existing private `openSettings(pane:)` helper to `openPrivacySettings(pane:)` to avoid colliding with the new selector, and update its three call sites in `report(_:)`, `openScreenRecordingSettings()` and `openAccessibilitySettings()`.

- [ ] **Step 5: Build and test end to end**

```bash
swift test && bash scripts/build.sh && rm -rf /Applications/ClaudeShot.app && cp -R .build/ClaudeShot.app /Applications/ && open /Applications/ClaudeShot.app
```

Verify by hand:

1. Menu bar → Settings… opens the window and it takes focus.
2. Click the recorder; it highlights and reads "Type a shortcut…". Hold ⌥⇧ and the preview shows ⌥⇧.
3. Press ⌥⇧C. The field reads ⌥⇧C, the menu item shows ⌥⇧C, and pressing ⌥⇧C captures to Claude.
4. Press ⌘Space in the recorder. It refuses with "⌘Space belongs to Spotlight" and ⌥⇧C still works.
5. Press ⌘⇧C with no modifiers removed, then try plain `C` — refused with the add-a-modifier message.
6. Record the current shortcut over itself (⌥⇧C again). It records rather than firing a capture — this is the Carbon-suspension path.
7. Escape while recording cancels and leaves the shortcut untouched.
8. Reset to Default returns to ⇧⌘6 and greys itself out.
9. Toggle Send automatically in the window, then open the menu bar — the checkmark matches. Toggle it in the menu, reopen the window — the switch matches.
10. Quit and relaunch. The recorded shortcut survives.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeShot/SettingsView.swift Sources/ClaudeShot/SettingsWindowController.swift Sources/ClaudeShot/SettingsModel.swift Sources/ClaudeShot/AppDelegate.swift
git commit -m "feat: add a settings window with shortcut recording

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Documentation and verification pass

**Files:**
- Modify: `README.md`
- Modify: `DECISIONS.md`

- [ ] **Step 1: Update the README**

In the "How it works" section, replace the opening sentence:

```markdown
Press `⌘⇧6` (or pick **Screenshot → Claude** from the menu bar). ClaudeShot:
```

with:

```markdown
Press `⇧⌘6` (or pick **Screenshot → Claude** from the menu bar). ClaudeShot:
```

After the paragraph ending "The clipboard is cleared a few seconds after delivery so the screenshot doesn't linger.", add:

```markdown
## Changing the shortcut

Open **Settings…** from the menu bar, click the shortcut field and press the combo you
want. It takes effect immediately and survives a relaunch.

A shortcut needs at least one of ⌘, ⌃ or ⌥ — Shift alone would fire while you type.
ClaudeShot also refuses a short list of combos macOS owns, naming the owner when it
does, and refuses anything the system will not hand over. Nothing is saved unless it
registers, so you cannot end up with a shortcut that silently does nothing.

**Reset to Default** goes back to ⇧⌘6. On a Touch Bar Mac that combo belongs to the
system screenshot shortcut, so the reset will be refused there — pick something else.
```

In "Troubleshooting", replace the first entry:

```markdown
**Hotkey does nothing** — Screen Recording isn't granted, or `⌘⇧6` is taken (on Touch Bar Macs it's the system's Touch Bar screenshot shortcut — the menu will say so). The menu item works regardless.
```

with:

```markdown
**Hotkey does nothing** — Screen Recording isn't granted, or the shortcut is taken by something else (on Touch Bar Macs the default `⇧⌘6` is the system's Touch Bar screenshot shortcut). The menu says so and the warning opens Settings, where you can pick another. The menu item works regardless.
```

In the "Structure" block, update the kit line:

```
Sources/ClaudeShotKit/    Pure decision logic (display selection, capture geometry,
                          Claude resolution, paste guard, hotkey config, validation
                          and persistence) — unit tested
```

- [ ] **Step 2: Log the shipped state in DECISIONS.md**

Add at the top of `DECISIONS.md`, above the existing 2026-07-29 entries:

```markdown
## 2026-07-29 — Shortcut customization shipped

Recorder, validator, `UserDefaults` persistence and a SwiftUI settings window, with the
menu bar keeping its own toggles. Implemented per
`docs/superpowers/specs/2026-07-29-shortcut-customization-design.md`.
```

- [ ] **Step 3: Full verification**

```bash
swift build -c release 2>&1 | tail -5 && swift test 2>&1 | tail -20 && bash scripts/build.sh 2>&1 | tail -5
```

Expected: release build clean, all tests pass with the new suites present, bundle signs and verifies.

Confirm the new test suites actually ran:

```bash
swift test 2>&1 | grep -cE "KeyCodeNamesTests|HotKeyValidatorTests|HotKeyStoreTests|HotKeyConfigTests"
```

Expected: a non-zero count.

- [ ] **Step 4: Commit and open a PR**

```bash
git add README.md DECISIONS.md
git commit -m "docs: document shortcut customization

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push -u origin feat/shortcut-customization
```

Then open a PR against `master`, ready for review, describing the feature and noting the manual verification list from Task 8 Step 5.

---

## Completed

_(Move finished task headings here as they land, per the project convention.)_
