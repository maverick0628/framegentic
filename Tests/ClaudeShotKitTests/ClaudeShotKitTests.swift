import XCTest
import Carbon.HIToolbox
@testable import ClaudeShotKit

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
