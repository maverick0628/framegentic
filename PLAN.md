# Framegentic — Rename and Delivery Targets

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename ClaudeShot to Framegentic and make delivery a chosen target, with clipboard-only as the default — producing an agent-agnostic app that is shippable before any FrameSnap code moves.

**Architecture:** The Claude coupling lives in two places: `ClaudeLocator` in the kit and `ClaudeAutomator` in the app. Both generalise into target-parameterised equivalents driven by a `TargetRegistry`. Everything upstream of delivery — capture, clipboard write — is already target-agnostic and does not change.

**Tech Stack:** Swift 6, SwiftPM, AppKit + SwiftUI, ScreenCaptureKit, Carbon hotkeys, XCTest.

Design spec: [docs/superpowers/specs/2026-07-31-framegentic-merge-design.md](docs/superpowers/specs/2026-07-31-framegentic-merge-design.md)

This plan covers steps 1–2 of the six in that spec. Steps 3–6 (the FrameSnap port: ring buffer, Rewind, scrubber) get their own plan once this ships.

## Global Constraints

- `swift-tools-version:6.0`, Swift 6 language mode, platform floor `.macOS(.v14)`.
- **Zero third-party dependencies.** Do not add anything to `Package.swift` dependencies.
- `FramegenticKit` holds decisions and is unit tested. `Framegentic` holds AppKit/SwiftUI glue and is **not** unit tested. Do not add app-target tests; do not move AppKit code into the kit.
- `@Observable` over `@ObservableObject`. SwiftUI for window content; AppKit only where SwiftUI cannot express the behaviour.
- No force unwraps. `guard` over nested `if let`.
- The release build must be warning-free.
- Comments explain *why*, never *what*, and stay sparse.
- New bundle identifier: `com.duncansmith.framegentic`.
- Run tests from the repo root with `swift test`. Build the bundle with `bash scripts/build.sh`.
- Every task ends with a commit whose message ends:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

### The rename rule — read before touching any file

The repo contains **189 occurrences of "ClaudeShot" and 270 of "Claude"**. These are not the same thing and a blanket find/replace will break the product.

- **"ClaudeShot" → "Framegentic"** everywhere. This is the product name.
- **"Claude" stays** wherever it refers to *Anthropic's desktop app* — the delivery target, the bundle identifier `com.anthropic.claudefordesktop`, README prose describing what the app interoperates with, and user-facing strings naming where a screenshot went.

Keeping those references is deliberate. Describing what your tool works with is referential use and is exactly why the rename is worth doing: Claude stops being the product's identity and becomes one target it supports.

---

### Task 1: Rename the package, targets and bundle

Mechanical but wide. Nothing behavioural changes; the app builds and passes its 34 tests at the end.

**Files:**
- Rename: `Sources/ClaudeShot/` → `Sources/Framegentic/`
- Rename: `Sources/ClaudeShotKit/` → `Sources/FramegenticKit/`
- Rename: `Tests/ClaudeShotKitTests/` → `Tests/FramegenticKitTests/`
- Modify: `Package.swift`, `Resources/Info.plist`, `scripts/build.sh`, `.github/workflows/ci.yml`, `docs/RELEASING.md`

- [x] **Step 1: Move the directories with git**

```bash
git mv Sources/ClaudeShot Sources/Framegentic
git mv Sources/ClaudeShotKit Sources/FramegenticKit
git mv Tests/ClaudeShotKitTests Tests/FramegenticKitTests
git mv Tests/FramegenticKitTests/ClaudeShotKitTests.swift Tests/FramegenticKitTests/FramegenticKitTests.swift
```

- [x] **Step 2: Update `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Framegentic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "FramegenticKit",
            path: "Sources/FramegenticKit"
        ),
        .executableTarget(
            name: "Framegentic",
            dependencies: ["FramegenticKit"],
            path: "Sources/Framegentic"
        ),
        .testTarget(
            name: "FramegenticKitTests",
            dependencies: ["FramegenticKit"],
            path: "Tests/FramegenticKitTests"
        )
    ]
)
```

- [x] **Step 3: Replace the product name in source, scripts and CI**

Replace `ClaudeShot` → `Framegentic` and `claudeshot` → `framegentic` across Swift sources, `scripts/build.sh`, `.github/workflows/ci.yml`, `Resources/Info.plist` and `docs/RELEASING.md`. This includes `import ClaudeShotKit` → `import FramegenticKit` and `@testable import ClaudeShotKit` → `@testable import FramegenticKit`.

Do **not** touch `README.md` or `DECISIONS.md` in this task — Task 6 rewrites the README wholesale, and DECISIONS is a historical record whose old entries correctly say ClaudeShot.

Do **not** rename `ClaudeLocator`, `ClaudeTarget` or `ClaudeAutomator` here — Tasks 3 and 4 own those, and doing it now would collide.

In `Resources/Info.plist` set:

```xml
    <key>CFBundleIdentifier</key>
    <string>com.duncansmith.framegentic</string>
    <key>CFBundleName</key>
    <string>Framegentic</string>
    <key>CFBundleDisplayName</key>
    <string>Framegentic</string>
    <key>CFBundleExecutable</key>
    <string>Framegentic</string>
```

Leave `NSScreenCaptureUsageDescription` wording alone for now; Task 6 revises copy.

- [x] **Step 4: Verify nothing behavioural changed**

Run: `swift build -c release 2>&1 | grep -ciE 'warning:|error:'`
Expected: `0`

Run: `swift test`
Expected: `Executed 34 tests, with 0 failures`

Run: `bash scripts/build.sh`
Expected: bundles and signs `.build/Framegentic.app`, codesign verify passes.

Confirm no stale references remain:

```bash
grep -rIn 'ClaudeShot\|claudeshot' --include='*.swift' --include='*.sh' --include='*.yml' --include='*.plist' Sources Tests scripts .github Resources
```

Expected: no output.

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "Rename the app to Framegentic

Renames the package, both targets, the test target and the bundle identifier.
References to Claude the delivery target are untouched — only the product name
changes.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `DeliveryTarget` and `TargetRegistry`

The value type describing where a capture goes, and the table of known destinations. Pure logic, unit tested.

**Files:**
- Create: `Sources/FramegenticKit/DeliveryTarget.swift`
- Test: `Tests/FramegenticKitTests/FramegenticKitTests.swift` (append a suite)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct DeliveryTarget: Identifiable, Equatable, Sendable, Codable` with `id: String`, `displayName: String`, `bundleID: String?`, `autoPaste: Bool`
  - `DeliveryTarget.clipboardOnly`
  - `enum TargetRegistry` with `all: [DeliveryTarget]`, `target(id:) -> DeliveryTarget?`, `defaultTarget: DeliveryTarget`

- [ ] **Step 1: Write the failing test**

Append to `Tests/FramegenticKitTests/FramegenticKitTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DeliveryTargetTests`
Expected: FAIL — compile error, `cannot find 'TargetRegistry' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/FramegenticKit/DeliveryTarget.swift`:

```swift
import Foundation

/// Where a capture goes after it reaches the clipboard.
public struct DeliveryTarget: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let displayName: String
    /// nil for clipboard-only, which activates nothing.
    public let bundleID: String?
    /// Whether delivery activates the app and simulates ⌘V. Requires Accessibility.
    public let autoPaste: Bool

    public init(id: String, displayName: String, bundleID: String?, autoPaste: Bool) {
        self.id = id
        self.displayName = displayName
        self.bundleID = bundleID
        self.autoPaste = autoPaste
    }

    public static let clipboardOnly = DeliveryTarget(
        id: "clipboard",
        displayName: "Clipboard only",
        bundleID: nil,
        autoPaste: false
    )
}

public enum TargetRegistry {
    /// Clipboard-only is first and default: the auto-paste path needs Accessibility,
    /// simulates keystrokes and steals focus, so it is opted into rather than out of.
    public static let all: [DeliveryTarget] = [
        .clipboardOnly,
        DeliveryTarget(
            id: "claude",
            displayName: "Claude",
            bundleID: "com.anthropic.claudefordesktop",
            autoPaste: true
        )
    ]

    public static var defaultTarget: DeliveryTarget { .clipboardOnly }

    public static func target(id: String) -> DeliveryTarget? {
        all.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DeliveryTargetTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/FramegenticKit/DeliveryTarget.swift Tests/FramegenticKitTests/FramegenticKitTests.swift
git commit -m "feat(kit): describe delivery destinations as data

Clipboard-only is the default and never auto-pastes, so the Accessibility
path is opt-in. Adding another destination later is a table entry.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Generalise the locator

`ClaudeLocator` already takes the running-app list as a parameter; only the bundle ID is hardcoded. Generalising it is small.

**Naming trap:** the existing result enum is called `ClaudeTarget`, which is a *plan for activating an app* — a different concept from `DeliveryTarget`, which is *a destination*. Two types called "target" meaning different things will cause mistakes. `ClaudeTarget` becomes `ActivationPlan`.

**Files:**
- Rename: `Sources/FramegenticKit/ClaudeLocator.swift` → `Sources/FramegenticKit/AppLocator.swift`
- Modify: `Sources/Framegentic/ClaudeAutomator.swift` (call sites only; Task 4 rewrites it)
- Test: replace the `ClaudeLocatorTests` suite

**Interfaces:**
- Consumes: `RunningAppInfo` (unchanged).
- Produces:
  - `enum ActivationPlan: Equatable, Sendable { case activateRunning, launch(URL), notFound }`
  - `AppLocator.resolve(bundleID:runningApps:installedAppURL:) -> ActivationPlan`

- [ ] **Step 1: Replace the test suite**

Replace the whole `ClaudeLocatorTests` class in `Tests/FramegenticKitTests/FramegenticKitTests.swift` with:

```swift
final class AppLocatorTests: XCTestCase {
    private let claude = "com.anthropic.claudefordesktop"

    func testResolvesByBundleIDNotName() {
        let apps = [
            RunningAppInfo(bundleID: "com.evil.claude", localizedName: "Claude"),
            RunningAppInfo(bundleID: claude, localizedName: "Claude Beta")
        ]
        XCTAssertEqual(
            AppLocator.resolve(bundleID: claude, runningApps: apps, installedAppURL: nil),
            .activateRunning)

        let impostorOnly = [RunningAppInfo(bundleID: "com.evil.claude", localizedName: "Claude")]
        XCTAssertEqual(
            AppLocator.resolve(bundleID: claude, runningApps: impostorOnly, installedAppURL: nil),
            .notFound)
    }

    func testFallsBackToInstalledURLThenNotFound() {
        let url = URL(fileURLWithPath: "/Applications/Claude.app")
        XCTAssertEqual(
            AppLocator.resolve(bundleID: claude, runningApps: [], installedAppURL: url),
            .launch(url))
        XCTAssertEqual(
            AppLocator.resolve(bundleID: claude, runningApps: [], installedAppURL: nil),
            .notFound)
    }

    // The generalisation is the point of this type: it must work for a target
    // that is not Claude, which every assertion above happens to use.
    func testResolvesANonClaudeTarget() {
        let cursor = "com.todesktop.230313mzl4w4u92"
        let apps = [RunningAppInfo(bundleID: cursor, localizedName: "Cursor")]
        XCTAssertEqual(
            AppLocator.resolve(bundleID: cursor, runningApps: apps, installedAppURL: nil),
            .activateRunning)
        XCTAssertEqual(
            AppLocator.resolve(bundleID: claude, runningApps: apps, installedAppURL: nil),
            .notFound)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppLocatorTests`
Expected: FAIL — `cannot find 'AppLocator' in scope`.

- [ ] **Step 3: Write the implementation**

`git mv Sources/FramegenticKit/ClaudeLocator.swift Sources/FramegenticKit/AppLocator.swift`, then replace its contents:

```swift
import Foundation

public struct RunningAppInfo: Equatable, Sendable {
    public let bundleID: String?
    public let localizedName: String?

    public init(bundleID: String?, localizedName: String?) {
        self.bundleID = bundleID
        self.localizedName = localizedName
    }
}

/// How to bring a delivery target to the front. Distinct from `DeliveryTarget`,
/// which is the destination itself rather than the plan for reaching it.
public enum ActivationPlan: Equatable, Sendable {
    case activateRunning
    case launch(URL)
    case notFound
}

public enum AppLocator {
    /// Matches on bundle identifier only. An app is trivially able to claim
    /// another's display name, so the name is never used to decide.
    public static func resolve(bundleID: String,
                               runningApps: [RunningAppInfo],
                               installedAppURL: URL?) -> ActivationPlan {
        if runningApps.contains(where: { $0.bundleID == bundleID }) {
            return .activateRunning
        }
        if let installedAppURL {
            return .launch(installedAppURL)
        }
        return .notFound
    }
}
```

- [ ] **Step 4: Fix `PasteGuardTests`, which this task breaks**

`PasteGuardTests` opens with `private let claude = ClaudeLocator.bundleID`. That static no longer exists once the bundle ID becomes a parameter, so the test target stops compiling. Replace that line with a literal:

```swift
    private let claude = "com.anthropic.claudefordesktop"
```

While there, add the test the design spec calls for — every existing assertion in this suite happens to use Claude's bundle ID, so nothing yet proves the guard is not Claude-specific:

```swift
    func testGuardsAnyExpectedBundleIDNotJustClaude() {
        let cursor = "com.todesktop.230313mzl4w4u92"
        XCTAssertEqual(
            PasteGuard.evaluate(frontmostBundleID: cursor, expectedBundleID: cursor, axTrusted: true),
            .allowed)
        XCTAssertEqual(
            PasteGuard.evaluate(frontmostBundleID: claude, expectedBundleID: cursor, axTrusted: true),
            .blocked(.wrongFrontmostApp(actual: claude)))
    }
```

- [ ] **Step 5: Fix the remaining call sites so the build passes**

`Sources/Framegentic/ClaudeAutomator.swift` references `ClaudeLocator.bundleID`, `ClaudeLocator.resolve` and `ClaudeTarget`. Make the minimal edits to compile: hold a `private let target = TargetRegistry.target(id: "claude") ?? .clipboardOnly` for now and read `target.bundleID ?? ""` where the static was used. Task 4 replaces this file properly — do not redesign it here.

- [ ] **Step 6: Verify**

Run: `swift test`
Expected: `Executed 43 tests, with 0 failures`

The arithmetic: 34 at the start of this plan, +7 from Task 2's `DeliveryTargetTests`, +1 from replacing the 2-test `ClaudeLocatorTests` with the 3-test `AppLocatorTests`, +1 from the PasteGuard test above.

Run: `swift build -c release 2>&1 | grep -ciE 'warning:|error:'`
Expected: `0`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(kit): generalise the locator to any bundle ID

ClaudeLocator becomes AppLocator with the bundle ID as a parameter, and its
result enum is renamed ActivationPlan — 'target' now means a destination, and
one word meaning two things in the same module invites mistakes.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `DeliveryService` replaces `ClaudeAutomator`

The app-layer delivery path, parameterised by target. When the target does not auto-paste, delivery ends at the clipboard and never asks for Accessibility.

**Files:**
- Rename: `Sources/Framegentic/ClaudeAutomator.swift` → `Sources/Framegentic/DeliveryService.swift`
- Modify: `Sources/Framegentic/AppDelegate.swift` (call site)

**Interfaces:**
- Consumes: `DeliveryTarget`, `TargetRegistry` (Task 2); `AppLocator`, `ActivationPlan`, `PasteGuard` (Task 3 and existing kit).
- Produces: `DeliveryService.deliver(to:autoSend:clipboardChangeCount:) async throws`

- [x] **Step 1: Write the implementation**

`git mv Sources/Framegentic/ClaudeAutomator.swift Sources/Framegentic/DeliveryService.swift`, then replace its contents:

```swift
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import FramegenticKit

enum DeliveryError: LocalizedError {
    case targetNotInstalled(String)
    case activationTimedOut(String)
    case accessibilityDenied
    case focusLost(String?)

    var errorDescription: String? {
        switch self {
        case .targetNotInstalled(let name):
            return "\(name) isn't installed. Install it, or switch delivery to Clipboard only in Settings."
        case .activationTimedOut(let name):
            return "\(name) didn't come to the front in time. Your capture is on the clipboard — paste it with ⌘V."
        case .accessibilityDenied:
            return "Accessibility permission is missing. Grant it in System Settings, then quit and relaunch Framegentic."
        case .focusLost(let bundleID):
            return "\(bundleID ?? "Another app") took focus, so nothing was pasted. Your capture is on the clipboard — paste it with ⌘V."
        }
    }
}

@MainActor
final class DeliveryService {
    private let settleDelay: Duration = .milliseconds(150)
    private let pasteToSendDelay: Duration = .milliseconds(600)
    private let warmActivationTimeout: TimeInterval = 3
    private let coldLaunchTimeout: TimeInterval = 10

    /// Delivers whatever is already on the clipboard to `target`.
    ///
    /// A target that does not auto-paste returns immediately: the capture is on
    /// the clipboard and that is the whole contract. Accessibility is never
    /// requested on that path, which is why it is the default.
    func deliver(to target: DeliveryTarget,
                 autoSend: Bool,
                 clipboardChangeCount: Int) async throws {
        guard target.autoPaste, let bundleID = target.bundleID else {
            clearClipboardLater(ifStillAt: clipboardChangeCount)
            return
        }

        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            throw DeliveryError.accessibilityDenied
        }

        let runningApps = NSWorkspace.shared.runningApplications.map {
            RunningAppInfo(bundleID: $0.bundleIdentifier, localizedName: $0.localizedName)
        }
        let installedURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)

        let timeout: TimeInterval
        switch AppLocator.resolve(bundleID: bundleID,
                                  runningApps: runningApps,
                                  installedAppURL: installedURL) {
        case .activateRunning:
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first?
                .activate()
            timeout = warmActivationTimeout
        case .launch(let url):
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            timeout = coldLaunchTimeout
        case .notFound:
            throw DeliveryError.targetNotInstalled(target.displayName)
        }

        guard await waitForFrontmost(bundleID: bundleID, timeout: timeout) else {
            throw DeliveryError.activationTimedOut(target.displayName)
        }
        try? await Task.sleep(for: settleDelay)

        try checkGuard(expecting: bundleID)
        postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        Log.paste.info("Pasted into \(target.displayName, privacy: .public)")

        if autoSend {
            try? await Task.sleep(for: pasteToSendDelay)
            try checkGuard(expecting: bundleID)
            postKey(CGKeyCode(kVK_Return))
            Log.paste.info("Sent")
        }

        clearClipboardLater(ifStillAt: clipboardChangeCount)
    }

    private func waitForFrontmost(bundleID: String, timeout: TimeInterval) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while clock.now < deadline {
            if isFrontmost(bundleID) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return isFrontmost(bundleID)
    }

    private func isFrontmost(_ bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private func checkGuard(expecting bundleID: String) throws {
        let decision = PasteGuard.evaluate(
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            expectedBundleID: bundleID,
            axTrusted: AXIsProcessTrusted()
        )
        switch decision {
        case .allowed:
            return
        case .blocked(.accessibilityDenied):
            throw DeliveryError.accessibilityDenied
        case .blocked(.wrongFrontmostApp(let actual)):
            throw DeliveryError.focusLost(actual)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func promptForAccessibility() {
        // Literal key: kAXTrustedCheckOptionPrompt imports as a mutable C global,
        // which Swift 6 strict concurrency rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// The capture may contain anything visible on screen, so it shouldn't sit on
    /// the clipboard indefinitely. Cleared only if nothing else has written since.
    private func clearClipboardLater(ifStillAt changeCount: Int) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                Log.paste.info("Cleared capture from clipboard")
            }
        }
    }
}
```

- [x] **Step 2: Update the call site in `AppDelegate`**

Rename the stored property `automator` to `delivery` and its type to `DeliveryService`, then change the call inside `screenshotToClaude()` — rename that method to `capture()` — to pass the target:

```swift
                let changeCount = try await screenshot.captureToClipboard()
                try await delivery.deliver(to: model.deliveryTarget,
                                           autoSend: model.autoSend,
                                           clipboardChangeCount: changeCount)
```

`model.deliveryTarget` does not exist until Task 5. Until then, use `TargetRegistry.defaultTarget` so this task builds standalone, and Task 5 swaps it.

Also update `report(_:)`, which switches on `PasteError` — the cases are now `DeliveryError.accessibilityDenied` and `CaptureError.screenRecordingDenied`.

- [x] **Step 3: Verify**

Run: `swift test`
Expected: `Executed 43 tests, with 0 failures`

Run: `swift build -c release 2>&1 | grep -ciE 'warning:|error:'`
Expected: `0`

Run: `bash scripts/build.sh` — bundle builds and signs.

- [x] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: deliver to a chosen target rather than always to Claude

A target that does not auto-paste returns as soon as the capture is on the
clipboard and never asks for Accessibility, which is what makes clipboard-only
a safe default rather than a degraded one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Target picker in settings

Persist the chosen target and expose it in the settings window. Auto-send becomes conditional — it is meaningless without auto-paste.

**Files:**
- Modify: `Sources/Framegentic/SettingsModel.swift`
- Modify: `Sources/Framegentic/SettingsView.swift`
- Modify: `Sources/Framegentic/AppDelegate.swift`

**Interfaces:**
- Consumes: `DeliveryTarget`, `TargetRegistry`.
- Produces: `SettingsModel.deliveryTarget: DeliveryTarget` (settable, persisted).

- [x] **Step 1: Add the setting to `SettingsModel`**

Add alongside the existing `autoSendKey`:

```swift
    private static let deliveryTargetKey = "DeliveryTargetID"

    var deliveryTarget: DeliveryTarget {
        didSet { UserDefaults.standard.set(deliveryTarget.id, forKey: Self.deliveryTargetKey) }
    }
```

In `init`, resolve the stored id, falling back to the default when it is absent or names a target that no longer exists:

```swift
        let storedID = UserDefaults.standard.string(forKey: Self.deliveryTargetKey)
        self.deliveryTarget = storedID.flatMap(TargetRegistry.target(id:)) ?? TargetRegistry.defaultTarget
```

- [x] **Step 2: Add the picker to `SettingsView`**

Replace the toggles `VStack` with:

```swift
            VStack(alignment: .leading, spacing: 8) {
                Picker("Deliver to", selection: Binding(
                    get: { model.deliveryTarget.id },
                    set: { id in
                        if let target = TargetRegistry.target(id: id) { model.deliveryTarget = target }
                    }
                )) {
                    ForEach(TargetRegistry.all) { target in
                        Text(target.displayName).tag(target.id)
                    }
                }
                .pickerStyle(.menu)

                if model.deliveryTarget.autoPaste {
                    Toggle("Send automatically after paste", isOn: $model.autoSend)
                    Text("Pasting into \(model.deliveryTarget.displayName) needs Accessibility permission.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Captures go to the clipboard. Paste them wherever you like with ⌘V — no extra permission needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Start at login", isOn: Binding(
                    get: { model.startAtLogin },
                    set: { model.setStartAtLogin($0) }
                ))
            }
```

- [x] **Step 3: Update `AppDelegate`**

Swap the placeholder from Task 4 for the real setting:

```swift
                try await delivery.deliver(to: model.deliveryTarget,
                                           autoSend: model.autoSend,
                                           clipboardChangeCount: changeCount)
```

In `menuNeedsUpdate`, show the auto-send item only when the target auto-pastes, and retitle the capture item so it names the destination:

```swift
        let capture = NSMenuItem(
            title: model.deliveryTarget.autoPaste
                ? "Capture → \(model.deliveryTarget.displayName)"
                : "Capture to Clipboard",
            action: #selector(captureFromMenu),
            keyEquivalent: model.isRecording ? "" : config.menuKeyEquivalent
        )
```

Also gate the Accessibility grant item — with clipboard-only selected there is nothing to grant it for:

```swift
        if model.deliveryTarget.autoPaste, !AXIsProcessTrusted() {
```

- [ ] **Step 4: Verify by hand**

Run `swift test` (43 pass), a clean warning-free `swift build -c release`, then `bash scripts/build.sh` and launch `.build/Framegentic.app`.

Check each and report the result:

1. Fresh launch defaults to Clipboard only.
2. Capture with Clipboard only selected: image lands on the clipboard, **no Accessibility prompt appears**, and the menu reads "Capture to Clipboard".
3. The Accessibility grant item is absent from the menu while Clipboard only is selected.
4. Switching to Claude changes the menu item to "Capture → Claude" and reveals the auto-send toggle.
5. Capture with Claude selected still activates Claude and pastes.
6. Selecting Claude without granting Accessibility surfaces the permission error rather than failing silently.
7. The chosen target survives quit and relaunch.
8. Recording a new shortcut still works and the menu key equivalent follows it.

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: choose a delivery target in settings

Auto-send and the Accessibility grant item only appear when the selected target
actually pastes; with clipboard-only there is nothing to send and no permission
to ask for.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Rewrite the README, marketing and copy

The current README sells a Claude-specific screenshot tool. The product is now an agent-agnostic capture tool that integrates with Claude.

**Files:**
- Modify: `README.md` (substantial rewrite)
- Modify: `Resources/Info.plist` (`NSScreenCaptureUsageDescription`)
- Modify: `docs/RELEASING.md` (product name)

- [ ] **Step 1: Rewrite `README.md`**

Keep the existing structure — How it works, Changing the shortcut, Privacy, How it compares, Requirements, Build, Troubleshooting, Uninstall, Structure, Notes — and rewrite the content around these points:

- **Title:** `# Framegentic — screenshots straight into your AI`
- **Opening:** a free, open-source macOS menu bar app that captures your screen and gets it to an AI in one keypress. Copies to the clipboard by default; can paste directly into Claude if you want it to.
- **Keep the before/after framing** — it is the clearest thing in the current README. Adjust the "after" to "press one key, paste anywhere".
- **Keep the "no network code" badge and the `otool` check** verbatim. Still true, still the strongest trust signal.
- **Delivery targets get their own short section** explaining clipboard-only as the default and why: no Accessibility permission, works with every chat UI, nothing can steal focus. Claude as the auto-paste option, with the note that more targets are a table entry.
- **Requirements:** split into always-required (macOS 14+, Screen Recording) and only-for-auto-paste (Accessibility, the target app installed). The current README presents both as mandatory, which they no longer are.
- **Comparison table:** keep it, and change the first row from "Screenshot to Claude" to "Screenshot to an AI chat".
- **Non-affiliation notice:** keep it. It is more accurate now, not less.
- **Retire "ClaudeShot"** from all prose. Keep every reference to Claude as a delivery target.

Badges to update: the tests badge from 34 to the current count.

- [ ] **Step 2: Update the capture usage string**

`Resources/Info.plist`:

```xml
    <key>NSScreenCaptureUsageDescription</key>
    <string>Framegentic captures your screen so you can send it to an AI assistant.</string>
```

- [ ] **Step 3: Verify**

```bash
grep -rIn 'ClaudeShot' README.md docs/RELEASING.md Resources/Info.plist
```

Expected: no output.

```bash
plutil -lint Resources/Info.plist
```

Expected: `OK`.

Confirm the README still contains "Claude" — deleting those would be the failure mode this task exists to avoid:

```bash
grep -c 'Claude' README.md
```

Expected: a non-zero count.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: pitch an agent-agnostic capture tool

The README sold a Claude-specific screenshot app. The product now copies to
the clipboard by default and treats Claude as one delivery target, so the
pitch, the requirements and the comparison all move with it.

References to Claude as a destination stay — that is the point of the change.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Repo rename and release readiness

**Files:**
- Modify: `DECISIONS.md`

- [ ] **Step 1: Log the outcome in `DECISIONS.md`**

Add at the top, above the existing 2026-07-31 entries:

```markdown
## 2026-07-31 — Shipped the rename and delivery targets

Steps 1–2 of the merge design landed: the app is Framegentic, delivery is a
chosen target, and clipboard-only is the default. The app no longer requires
Accessibility unless the user opts into auto-paste. FrameSnap's ring buffer and
the Rewind mode follow in a separate plan.
```

- [ ] **Step 2: Full verification**

```bash
swift build -c release 2>&1 | grep -ciE 'warning:|error:'
swift test 2>&1 | grep -E 'Executed [0-9]+ tests'
bash scripts/build.sh 2>&1 | tail -3
```

Expected: `0` warnings, all tests pass, bundle signs and verifies.

- [ ] **Step 3: Commit and open a PR**

```bash
git add -A
git commit -m "docs: record the rename and target work

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push -u origin <branch>
```

Open a PR against `master` describing the rename, the target registry and the new default, and listing the Task 5 manual checks with their results.

**Do not rename the GitHub repo in this task.** That is a separate deliberate step with its own consequences — the bundle identifier change means TCC grants reset and the old `/Applications/ClaudeShot.app` lingers. Surface both to Duncan when the PR is ready rather than doing it silently.

---

## Outstanding — carried from the design doc

Not blocking this plan, but unresolved:

- [ ] Rewind's clipboard format for multi-frame clips
- [ ] One hotkey or two, once Rewind exists
- [ ] Buffer duration — fixed at two minutes or configurable
- [ ] Migration note for the existing install: new bundle ID means new TCC grants

---

## Completed

**2026-07-29 — Shortcut customization.** Nine tasks, executed via subagent-driven
development. Shipped `KeyCodeNames`, `HotKeyConfig` as a value type,
`HotKeyValidator` (20 reserved combos), `HotKeyStore`, a configurable
`HotKeyManager`, `SettingsModel`, `ShortcutRecorderField` and the settings window.
34 kit tests. Spec:
`docs/superpowers/specs/2026-07-29-shortcut-customization-design.md`. Full step
history is in the git log for that branch.
