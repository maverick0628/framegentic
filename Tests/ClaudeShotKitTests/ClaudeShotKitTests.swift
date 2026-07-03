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
    func testMenuAndCarbonHotKeyDefinitionsAgree() {
        let c = HotKeyConfig.standard
        XCTAssertEqual(c.keyCode, UInt32(kVK_ANSI_6))
        XCTAssertEqual(c.carbonModifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(c.menuKeyEquivalent, "6")
        XCTAssertEqual(c.menuModifiers, [.command, .shift])
    }
}
