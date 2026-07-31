import XCTest
import Carbon.HIToolbox
@testable import FramegenticKit

final class CaptureGeometryTests: XCTestCase {
    func testCaptureDimensionsFollowDisplayScale() {
        let retina = CaptureGeometry(pointWidth: 1512, pointHeight: 982, scaleFactor: 2.0)
        XCTAssertEqual(retina.pixelWidth, 3024)
        XCTAssertEqual(retina.pixelHeight, 1964)

        let external1x = CaptureGeometry(pointWidth: 3440, pointHeight: 1440, scaleFactor: 1.0)
        XCTAssertEqual(external1x.pixelWidth, 3440)
        XCTAssertEqual(external1x.pixelHeight, 1440)

        let dense3x = CaptureGeometry(pointWidth: 1290, pointHeight: 800, scaleFactor: 3.0)
        XCTAssertEqual(dense3x.pixelWidth, 3870)
        XCTAssertEqual(dense3x.pixelHeight, 2400)
    }

    func testLogicalSizePreservesPointDimensions() {
        let g = CaptureGeometry(pointWidth: 1920, pointHeight: 1080, scaleFactor: 2.0)
        XCTAssertEqual(g.logicalSize, CGSize(width: 1920, height: 1080))
    }
}

final class DisplaySelectionTests: XCTestCase {
    func testSelectsMainDisplayNotFirstInList() {
        let secondary = DisplayInfo(id: 2, pointWidth: 1920, pointHeight: 1080)
        let main = DisplayInfo(id: 1, pointWidth: 3440, pointHeight: 1440)
        XCTAssertEqual(selectCaptureDisplay(from: [secondary, main], mainDisplayID: 1), main)
    }

    func testFallsBackToFirstDisplayWhenMainNotListed() {
        let only = DisplayInfo(id: 7, pointWidth: 800, pointHeight: 600)
        XCTAssertEqual(selectCaptureDisplay(from: [only], mainDisplayID: 1), only)
        XCTAssertNil(selectCaptureDisplay(from: [], mainDisplayID: 1))
    }
}

final class ClaudeLocatorTests: XCTestCase {
    func testResolvesClaudeByBundleIDNotName() {
        let apps = [
            RunningAppInfo(bundleID: "com.evil.claude", localizedName: "Claude"),
            RunningAppInfo(bundleID: ClaudeLocator.bundleID, localizedName: "Claude Beta")
        ]
        XCTAssertEqual(ClaudeLocator.resolve(runningApps: apps, installedAppURL: nil),
                       .activateRunning)

        let impostorOnly = [RunningAppInfo(bundleID: "com.evil.claude", localizedName: "Claude")]
        XCTAssertEqual(ClaudeLocator.resolve(runningApps: impostorOnly, installedAppURL: nil),
                       .notFound)
    }

    func testFallsBackToInstalledURLThenNotFound() {
        let url = URL(fileURLWithPath: "/Users/me/Applications/Claude.app")
        XCTAssertEqual(ClaudeLocator.resolve(runningApps: [], installedAppURL: url), .launch(url))
        XCTAssertEqual(ClaudeLocator.resolve(runningApps: [], installedAppURL: nil), .notFound)
    }
}

final class PasteGuardTests: XCTestCase {
    private let claude = ClaudeLocator.bundleID

    func testPasteAllowedOnlyWhenClaudeFrontmostAndTrusted() {
        XCTAssertEqual(
            PasteGuard.evaluate(frontmostBundleID: claude, expectedBundleID: claude, axTrusted: true),
            .allowed)
    }

    func testPasteBlockedWhenWrongAppFrontmost() {
        XCTAssertEqual(
            PasteGuard.evaluate(frontmostBundleID: "com.apple.Terminal", expectedBundleID: claude, axTrusted: true),
            .blocked(.wrongFrontmostApp(actual: "com.apple.Terminal")))
        XCTAssertEqual(
            PasteGuard.evaluate(frontmostBundleID: nil, expectedBundleID: claude, axTrusted: true),
            .blocked(.wrongFrontmostApp(actual: nil)))
    }

    func testPasteBlockedWhenAccessibilityDenied() {
        XCTAssertEqual(
            PasteGuard.evaluate(frontmostBundleID: claude, expectedBundleID: claude, axTrusted: false),
            .blocked(.accessibilityDenied))
    }
}

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

    // Whether the glyph table or the layout is consulted first is unobservable:
    // layoutCharacter's whitespace/control guard returns nil for every key in the
    // glyph table, so the two can never disagree. The observable guarantee is that
    // these keys render as a glyph rather than a blank under any live layout.
    func testNonPrintingKeysRenderAsGlyphsNotBlanks() {
        let expected: [(keyCode: Int, glyph: String)] = [
            (kVK_Space, "␣"), (kVK_Return, "↩"), (kVK_Tab, "⇥"), (kVK_Delete, "⌫"),
            (kVK_Escape, "⎋"), (kVK_LeftArrow, "←"), (kVK_UpArrow, "↑"),
            (kVK_F5, "F5"), (kVK_F12, "F12")
        ]
        for key in expected {
            XCTAssertEqual(KeyCodeNames.displayString(for: UInt32(key.keyCode)), key.glyph)
        }
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

    // Pins the whole table, not a sample of it: four rows were once deleted with
    // every test still green. Removing, retyping or re-owning any row fails here.
    func testEveryReservedComboIsRejectedWithItsOwner() {
        let expected: [(keyCode: Int, modifiers: Int, owner: String)] = [
            (kVK_Space, cmdKey, "Spotlight"),
            (kVK_Space, optionKey | cmdKey, "Finder search"),
            (kVK_Space, controlKey | cmdKey, "Emoji & Symbols"),
            (kVK_Space, controlKey, "input source switching"),
            (kVK_Tab, cmdKey, "the app switcher"),
            (kVK_Tab, cmdKey | shiftKey, "the app switcher"),
            (kVK_ANSI_Q, cmdKey, "Quit"),
            (kVK_ANSI_W, cmdKey, "Close Window"),
            (kVK_ANSI_H, cmdKey, "Hide"),
            (kVK_ANSI_M, cmdKey, "Minimise"),
            (kVK_ANSI_Comma, cmdKey, "Settings"),
            (kVK_ANSI_3, cmdKey | shiftKey, "Screenshot"),
            (kVK_ANSI_4, cmdKey | shiftKey, "Screenshot"),
            (kVK_ANSI_5, cmdKey | shiftKey, "Screenshot"),
            (kVK_UpArrow, controlKey, "Mission Control"),
            (kVK_DownArrow, controlKey, "Mission Control"),
            (kVK_LeftArrow, controlKey, "Spaces"),
            (kVK_RightArrow, controlKey, "Spaces"),
            (kVK_Escape, optionKey | cmdKey, "Force Quit"),
            (kVK_ANSI_Q, controlKey | cmdKey, "Lock Screen")
        ]

        for row in expected {
            let candidate = config(row.keyCode, row.modifiers)
            XCTAssertEqual(HotKeyValidator.validate(candidate),
                           .rejected(.reserved(owner: row.owner)),
                           "\(candidate.displayString) should be reserved for \(row.owner)")
        }

        XCTAssertEqual(HotKeyValidator.reserved.count, expected.count,
                       "a reserved row was added without being pinned here")
    }

    // ⌘, is this app's own Settings… equivalent. RegisterEventHotKey would take it
    // globally, so Preferences would stop opening in every other app on the Mac.
    func testRejectsTheSettingsMenuEquivalent() {
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_ANSI_Comma, cmdKey)),
                       .rejected(.reserved(owner: "Settings")))
    }

    // Reserved entries match on the exact modifier set, so a near miss is fine.
    func testReservedMatchIsExact() {
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_Space, cmdKey | shiftKey)), .valid)
        XCTAssertEqual(HotKeyValidator.validate(config(kVK_ANSI_Q, optionKey)), .valid)
    }

    // Not an ordering test, though it used to claim to be: no reserved row carries
    // fewer than one of ⌘/⌃/⌥, so no single input can trip both rules and the order
    // validate() runs them in is unobservable from outside. What is worth pinning is
    // the precondition that makes it unobservable — a row that failed the baseline
    // rule could never be reached, and its owner string would be dead text.
    func testEveryReservedRowClearsTheBaselineModifierRule() {
        let required = UInt32(cmdKey | controlKey | optionKey)
        for row in HotKeyValidator.reserved {
            XCTAssertNotEqual(row.carbonModifiers & required, 0,
                              "the \(row.owner) row is unreachable behind the modifier rule")
        }

        XCTAssertEqual(HotKeyValidator.validate(config(kVK_Space, 0)),
                       .rejected(.missingRequiredModifier))
    }
}

final class HotKeyStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suiteName = "com.duncansmith.framegentic.tests.\(UUID().uuidString)"
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

    // A hostile `defaults write` is well-formed JSON that the app's own UI would
    // never produce. Without a validation pass, a bare key registers globally and
    // every "a" typed anywhere fires a capture.
    func testLoadReturnsDefaultWhenStoredShortcutHasNoRequiredModifier() throws {
        try store(HotKeyConfig(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: 0))
        XCTAssertEqual(HotKeyStore(defaults: defaults).load(), .default)
    }

    func testLoadReturnsDefaultWhenStoredShortcutIsReserved() throws {
        try store(HotKeyConfig(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey)))
        XCTAssertEqual(HotKeyStore(defaults: defaults).load(), .default)
    }

    func testLoadStillReturnsAValidStoredShortcut() throws {
        let valid = HotKeyConfig(keyCode: UInt32(kVK_ANSI_C),
                                 carbonModifiers: UInt32(optionKey | shiftKey))
        try store(valid)
        XCTAssertEqual(HotKeyStore(defaults: defaults).load(), valid)
    }

    /// Writes past `save()` on purpose: the threat is a blob the app never wrote.
    private func store(_ config: HotKeyConfig) throws {
        defaults.set(try JSONEncoder().encode(config), forKey: HotKeyStore.defaultsKey)
    }
}

final class DeliveryTargetTests: XCTestCase {
    func testClipboardOnlyIsTheDefaultAndNeverPastes() {
        let target = TargetRegistry.defaultTarget
        XCTAssertEqual(target, DeliveryTarget.clipboardOnly)
        XCTAssertFalse(target.autoPaste)
        XCTAssertNil(target.bundleID)
    }

    func testRegistryContainsClipboardOnlyFirst() {
        XCTAssertEqual(TargetRegistry.all.first, DeliveryTarget.clipboardOnly)
        XCTAssertGreaterThan(TargetRegistry.all.count, 1)
    }

    func testClaudeIsAKnownTargetThatPastes() {
        guard let claude = TargetRegistry.target(id: "claude") else {
            return XCTFail("claude should be a known target")
        }
        XCTAssertEqual(claude.bundleID, "com.anthropic.claudefordesktop")
        XCTAssertTrue(claude.autoPaste)
        XCTAssertEqual(claude.displayName, "Claude")
    }

    func testUnknownTargetResolvesToNil() {
        XCTAssertNil(TargetRegistry.target(id: "definitely-not-a-target"))
    }

    // Every auto-pasting target needs a bundle ID to activate and to guard
    // against; one without would paste into whatever happened to be frontmost.
    func testEveryAutoPasteTargetHasABundleID() {
        for target in TargetRegistry.all where target.autoPaste {
            XCTAssertNotNil(target.bundleID, "\(target.id) auto-pastes without a bundle ID")
        }
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(TargetRegistry.all.map(\.id)).count, TargetRegistry.all.count)
    }

    func testRoundTripsThroughCodable() throws {
        let decoded = try JSONDecoder().decode(
            DeliveryTarget.self,
            from: JSONEncoder().encode(DeliveryTarget.clipboardOnly))
        XCTAssertEqual(decoded, DeliveryTarget.clipboardOnly)
    }
}
