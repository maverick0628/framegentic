# Framegentic — Rewind Mode

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Rewind — a rolling in-memory buffer of screen frames you can scrub back through, trim, and deliver — by porting FrameSnap into Framegentic. The buffer is off by default and never touches disk.

**Architecture:** FrameSnap's pure logic (ring buffer, perceptual hashing, image pipeline, temp-file lifecycle) moves into `FramegenticKit` largely as-is, along with its tests. Its `AppSettings` does **not** move — it is `ObservableObject`-era and collides with Framegentic's `@Observable SettingsModel`, so its four settings fold into that instead. The app layer gains a continuous capture path, a second hotkey, and a popover with a timeline scrubber.

**Tech Stack:** Swift 6, SwiftPM, AppKit + SwiftUI, ScreenCaptureKit, Carbon hotkeys, CoreGraphics/ImageIO, XCTest.

Design spec: [docs/superpowers/specs/2026-07-31-framegentic-merge-design.md](docs/superpowers/specs/2026-07-31-framegentic-merge-design.md)

This plan covers steps 3–6 of the six in that spec. Steps 1–2 shipped in `master` — the rename and delivery targets.

Source repo for the port: `/Users/duncansmith/repos/framesnap` (branch `main`, untouched since 2026-06-23). It is not a dependency; files are copied in and adapted.

## Global Constraints

- `swift-tools-version:6.0`, Swift 6 language mode, platform floor `.macOS(.v14)`.
- **Zero third-party dependencies.** Do not add anything to `Package.swift` dependencies.
- `FramegenticKit` holds decisions and is unit tested. `Framegentic` holds AppKit/SwiftUI glue and is **not** unit tested — do not add app-target tests, and do not move AppKit types into the kit.
- `@Observable` over `@ObservableObject`. FrameSnap predates this; ported code must be converted, not carried over.
- `async`/`await` over completion handlers.
- No force unwraps. `guard` over nested `if let`.
- The release build must be warning-free.
- Comments explain *why*, never *what*, and stay sparse.
- Run tests from the repo root with `swift test`. Build the bundle with `bash scripts/build.sh`.
- Baseline is **42 tests**. Expected after Task 1: **66**.
- Every task ends with a commit whose message ends:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`

### Three decisions this plan settles

The design spec left these open. They are resolved here, with reasons, so no task has to guess.

**1. Multi-frame clips go to the clipboard as file URLs.** FrameSnap's `ClipboardWriter.writeFileURLs` already does this and is in daily use, so it is a working answer rather than a guess. Single-frame Snap keeps its existing PNG-as-data path, marked concealed. The two strategies coexist because they solve different problems: one image can be pasteboard data, several cannot.

**2. Rewind gets its own hotkey.** Tap-versus-hold on a Carbon global hotkey needs timer gymnastics around `RegisterEventHotKey`, which delivers a press event and nothing else. Two bindings are simpler to implement, simpler to explain, and the shortcut recorder already exists — a second field is cheap.

**3. Buffer duration stays configurable, frame interval does not get a UI.** FrameSnap already persists both. Porting the storage costs nothing, but exposing two interacting knobs invites a settings screen nobody understands. Duration gets a control; interval keeps its stored default and stays out of the UI.

### The constraint that governs the whole plan

**The buffer is off by default, and enabling Rewind is what turns it on.** Snap works with the buffer off — it captures on demand. A user who only wants the screenshot key must never pay the battery, memory or privacy cost of an always-on recorder.

Frames live in memory only. Nothing is written to disk until the moment of delivery, and `TempFileManager` deletes those files on a TTL. When the buffer is running, the menu bar says so — an app that can reproduce the last two minutes of your screen must make that visible, not bury it in settings.

---

### Task 1: Port FrameSnap's pure logic into the kit

Seven files move with their tests. This is the largest task by file count and the least risky by nature — it is pure logic with no AppKit dependency, and it arrives with 343 lines of existing tests.

**Files:**
- Create in `Sources/FramegenticKit/`: `RingBuffer.swift`, `CapturedFrame.swift`, `DHash.swift`, `ImageProcessor.swift`, `OptimizationPipeline.swift`, `TempFileManager.swift`, `ClipboardWriter.swift`
- Test: `Tests/FramegenticKitTests/FramegenticKitTests.swift` (append the ported suites)

**Source:** `/Users/duncansmith/repos/framesnap/FrameSnapKit/` and `/Users/duncansmith/repos/framesnap/FrameSnapTests/`

**Interfaces produced** (unchanged from FrameSnap unless noted):
- `RingBuffer<Element>` — `init(capacity:)`, `capacity`, `count`, `append(_:)`, `allElements()`, `slice(from:to:)`
- `CapturedFrame` — `init(image:timestamp:)`, `image: CGImage`, `timestamp: Date`, `timeAgo(relativeTo:)`, `formattedTimeAgo(relativeTo:)`
- `DHash` — `hash(_:) -> UInt64`, `hammingDistance(_:_:) -> Int`, `areSimilar(_:_:threshold:) -> Bool`
- `ImageProcessor` — `downsample(_:maxWidth:) -> CGImage`, `encodeJPEG(_:quality:) -> Data?`
- `OptimizationPipeline` — `init()`, `process(...)`, `processAndCopy(...)`, `cleanup()`
- `TempFileManager` — `init()`, `write(_:filename:) throws -> URL`, `scheduleCleanup(after:)`, `cleanupAll()`, `currentSessionURLs()`
- `ClipboardWriter` — `writeFileURLs(_:)`

- [x] **Step 1: Copy the seven source files**

```bash
cd /Users/duncansmith/repos/claudeshot
FS=/Users/duncansmith/repos/framesnap/FrameSnapKit
cp "$FS/Capture/RingBuffer.swift" "$FS/Models/CapturedFrame.swift" Sources/FramegenticKit/
cp "$FS/Pipeline/DHash.swift" "$FS/Pipeline/ImageProcessor.swift" "$FS/Pipeline/OptimizationPipeline.swift" "$FS/Pipeline/TempFileManager.swift" "$FS/Pipeline/ClipboardWriter.swift" Sources/FramegenticKit/
```

**Do not copy `AppSettings.swift`.** It is `ObservableObject` with `@Published` properties, which conflicts with this project's `@Observable` rule. Task 2 folds its four settings into `SettingsModel` instead.

- [x] **Step 2: Make them build under Swift 6**

Compile and fix what the language mode rejects. Expect at minimum:

- `Sendable` conformance complaints on types crossing concurrency boundaries. `CapturedFrame` holds a `CGImage`, which is not `Sendable` — mark the type `@unchecked Sendable` **only** if you can state in a comment why it is safe (CGImage is immutable once created), or keep it off the boundary entirely.
- `OptimizationPipeline` and `TempFileManager` hold mutable state. If they are used from one actor, isolate them to it rather than reaching for locks.

Do not silence a real data race with `@unchecked`. If something genuinely needs synchronising, synchronise it and say why in a comment.

- [x] **Step 3: Port the tests**

Copy the five suites from `/Users/duncansmith/repos/framesnap/FrameSnapTests/` — `RingBufferTests`, `DHashTests`, `ImageProcessorTests`, `OptimizationPipelineTests`, `TempFileManagerTests` — into `Tests/FramegenticKitTests/FramegenticKitTests.swift`, appended as new classes.

The file already has `import XCTest`, `import Carbon.HIToolbox` and `@testable import FramegenticKit`. Add `import CoreGraphics` if the ported tests need it. Do not duplicate existing imports and do not modify existing suites.

If a ported test used a FrameSnap-only helper, port the helper too rather than weakening the test.

- [x] **Step 4: Verify**

Run: `swift test`
Expected: `Executed 66 tests, with 0 failures` (42 baseline + 24 ported)

If the count differs, reconcile it before continuing — report the actual number and which suite differs from expectation. Do not adjust the expectation to match reality without saying so.

Run: `swift build -c release 2>&1 | grep -ciE 'warning:|error:'`
Expected: `0`

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(kit): port FrameSnap's capture pipeline

Ring buffer, perceptual hashing, image processing, temp-file lifecycle and
the clipboard writer, with their existing tests. Pure logic, no AppKit.

AppSettings is deliberately not ported — it is ObservableObject-era and the
settings it holds belong in SettingsModel.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Buffer settings, off by default

FrameSnap's four settings fold into the existing `@Observable SettingsModel`. One of them — launch at login — already exists there and must not be duplicated.

**Files:**
- Modify: `Sources/Framegentic/SettingsModel.swift`
- Modify: `Sources/Framegentic/SettingsView.swift`

**Source for defaults:** `/Users/duncansmith/repos/framesnap/FrameSnapKit/Services/AppSettings.swift` — read its `defaults.register(defaults:)` block and carry the same values.

- [x] **Step 1: Add the settings**

Add to `SettingsModel`, following the existing `deliveryTarget` pattern of a `didSet` that writes through to `UserDefaults`. Read the four defaults out of FrameSnap's `AppSettings.swift` `defaults.register(defaults:)` block and carry the same values:

```swift
    private static let bufferEnabledKey = "BufferEnabled"
    private static let bufferWindowKey = "BufferWindowSeconds"
    private static let frameIntervalKey = "FrameIntervalSeconds"
    private static let autoDeleteTTLKey = "AutoDeleteTTLSeconds"

    /// Off by default: an always-on screen recorder is not something to opt a
    /// user out of. Snap works without it; enabling Rewind is what starts it.
    var bufferEnabled: Bool {
        didSet { UserDefaults.standard.set(bufferEnabled, forKey: Self.bufferEnabledKey) }
    }

    var bufferWindowSeconds: Int {
        didSet { UserDefaults.standard.set(bufferWindowSeconds, forKey: Self.bufferWindowKey) }
    }

    var frameIntervalSeconds: Double {
        didSet { UserDefaults.standard.set(frameIntervalSeconds, forKey: Self.frameIntervalKey) }
    }

    var autoDeleteTTLSeconds: Int {
        didSet { UserDefaults.standard.set(autoDeleteTTLSeconds, forKey: Self.autoDeleteTTLKey) }
    }

    var bufferCapacity: Int {
        max(1, Int(Double(bufferWindowSeconds) / max(frameIntervalSeconds, 0.1)))
    }
```

Initialise them in `init` the same way `deliveryTarget` is — read from `UserDefaults`, falling back to the registered default. `bufferEnabled` must read `false` when unset, which `UserDefaults.bool(forKey:)` gives you for free.

The `max(1, ...)` and `max(frameIntervalSeconds, 0.1)` guards matter: a zero or negative interval reaching `RingBuffer(capacity:)` would either divide by zero or ask for a zero-capacity buffer.

Do **not** add a `launchAtLogin` — `SettingsModel.startAtLogin` already covers it and is wired to `SMAppService`. Porting FrameSnap's would give you two settings writing different keys for one behaviour.

- [x] **Step 2: Add the Rewind section to settings**

A section with a toggle labelled for what it does, not what it is — the user is enabling Rewind, and continuous capture is the consequence. Beneath it, only when enabled, a control for buffer duration.

The copy must be honest about what turning it on means: the app begins continuously capturing the screen into memory. Say that plainly. Do not bury it, and do not soften it — an app that can reproduce the last two minutes of someone's screen earns trust by being direct about it.

Follow the conditional-copy pattern already in `SettingsView` for the delivery target, where explanatory text appears alongside the control it explains.

- [x] **Step 3: Verify**

Run: `swift test`
Expected: `Executed 66 tests, with 0 failures` — this task adds no tests; the app target is untested by design.

Run: `swift build -c release 2>&1 | grep -ciE 'warning:|error:'`
Expected: `0`

- [x] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: buffer settings, off by default

Enabling Rewind is what starts continuous capture, so the toggle says so
rather than describing a buffer. Frame interval and TTL keep their stored
defaults and stay out of the UI — two interacting knobs is a settings screen
nobody understands.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Continuous capture

The capture layer gains a second mode. `ScreenshotService` currently grabs one frame on demand; it now also drives a rolling buffer when enabled.

**Files:**
- Modify: `Sources/Framegentic/ScreenshotService.swift` (or rename to `CaptureService.swift` — see below)
- Create: `Sources/Framegentic/ActivityMonitor.swift`
- Modify: `Sources/Framegentic/AppDelegate.swift`

**Source:** `/Users/duncansmith/repos/framesnap/FrameSnap/Capture/ScreenCaptureManager.swift` (102 lines) and `ActivityMonitor.swift` (54 lines)

- [x] **Step 1: Port the activity monitor**

Copy `ActivityMonitor.swift` and adapt it. It varies capture rate by user activity — faster while working, slower while idle — which is what keeps an always-on buffer affordable.

- [x] **Step 2: Extend the capture service**

Rename `ScreenshotService` to `CaptureService` with `git mv` and give it a continuous path alongside the existing one-shot `captureToClipboard()`. It should:

- Start and stop buffering on demand, driven by `SettingsModel.bufferEnabled`
- Push `CapturedFrame`s into a `RingBuffer` sized by `bufferCapacity`
- Drop near-duplicate frames using `DHash.areSimilar` — a static screen should not fill the buffer with identical frames
- Keep the one-shot path working unchanged when the buffer is off

The single-frame path must not depend on the buffer. Snap works with Rewind disabled; that is the whole point of the default.

- [x] **Step 3: Wire the lifecycle in `AppDelegate`**

Start buffering at launch only if `model.bufferEnabled`. Start and stop it when the setting changes. Stop it on termination.

- [x] **Step 4: Show it in the menu bar**

When the buffer is running, the status item must reflect it — a distinct icon state, not a hidden preference. This is a spec requirement, not a nicety.

`AppDelegate` already flashes a one-second confirmation tick after a capture (`flashCaptureConfirmation`). The buffer indicator must compose with it: a tick during buffering must revert to the *buffering* icon, not the idle one.

- [x] **Step 5: Verify**

Run: `swift test` — 66 pass. Run a clean warning-free `swift build -c release`, then `bash scripts/build.sh`.

Do **not** drive the GUI, install to `/Applications`, or change system settings. Note in your report that the visual states need a human pass.

- [x] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: continuous capture behind the buffer toggle

Buffering only runs when Rewind is enabled, and the menu bar says so while it
does. Near-duplicate frames are dropped by perceptual hash so a static screen
does not fill the buffer with copies.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: A second hotkey for Rewind

**Files:**
- Modify: `Sources/FramegenticKit/HotKeyStore.swift`
- Modify: `Sources/Framegentic/HotKeyManager.swift`
- Modify: `Sources/Framegentic/SettingsModel.swift`, `SettingsView.swift`, `AppDelegate.swift`
- Test: `Tests/FramegenticKitTests/FramegenticKitTests.swift`

**Interfaces produced:**
- `HotKeyStore` gains a second stored shortcut, keyed separately
- `HotKeyManager` registers two hotkeys with distinct Carbon IDs

- [x] **Step 1: Write the failing test**

`HotKeyStore` currently persists one config under one key. Add a test proving two shortcuts persist independently: saving one must not disturb the other, each falls back to its own default when unset, and a corrupt blob for one does not affect the other.

Give Rewind a default that passes `HotKeyValidator` and is not `HotKeyConfig.default` (⇧⌘6). Assert it validates — the same self-consistency trap the capture default has a test for.

- [x] **Step 2: Run it and watch it fail**

Run: `swift test --filter HotKeyStore`
Expected: FAIL — the second shortcut's API does not exist.

- [x] **Step 3: Implement**

Extend `HotKeyStore` to hold two shortcuts. Prefer a parameterised API over duplicated members — the store already validates on load, and that logic should not be copied.

Extend `HotKeyManager` to register both. Each Carbon hotkey needs its **own `EventHotKeyID`** — the existing one uses signature `0x4353_4854` with id 1; the second must differ or one will silently replace the other. The handler must dispatch on which fired.

`unregister()` currently tears down one. Recording a shortcut suspends the global hotkey so the combo can be captured — with two hotkeys, recording either must suspend **both**, or recording Rewind's shortcut could fire Snap.

- [x] **Step 4: Wire settings and the menu**

A second recorder field, labelled for Rewind. It appears only when the buffer is enabled — a shortcut for a disabled feature is noise.

- [x] **Step 5: Verify**

Run: `swift test` — expect 66 plus your new tests; state the number. Clean warning-free release build.

- [x] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: a separate hotkey for Rewind

Two bindings rather than tap-versus-hold: RegisterEventHotKey delivers a press
and nothing else, so hold detection would mean timer gymnastics for a worse
result. Recording either shortcut suspends both, or recording one would fire
the other.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: The Rewind popover

The scrubber UI. This is the largest app-layer task and the only one with genuinely new interaction.

**Files:**
- Create: `Sources/Framegentic/RewindPopover.swift`, `TimelineScrubber.swift`, `FramePreview.swift`, `ToastView.swift`
- Modify: `Sources/Framegentic/AppDelegate.swift`

**Source:** `/Users/duncansmith/repos/framesnap/FrameSnap/UI/` — `PopoverView.swift` (55), `TimelineScrubber.swift` (108), `FramePreview.swift` (55), `ToastView.swift` (20), `CaptureViewModel.swift` (89)

**On the toast, which is not redundant with the existing tick.** Framegentic already flashes a one-second checkmark on the status item after a Snap, and it is tempting to reuse that here. Do not. `ToastView` reports *"N frames copied · deletes in M min"* — a frame count and a deletion deadline, neither of which a checkmark can express. A clip delivery needs both: the user has just trimmed a range and has to know how much was taken, and the files are on a TTL so they need to know it is finite. Port the toast for clips; leave the tick for single snaps.

- [x] **Step 1: Port the views**

Bring across the popover, scrubber and preview. `CaptureViewModel` is `ObservableObject`-era — convert it to `@Observable` rather than carrying the old pattern in, per the global constraints.

Preserve the interaction: scrub the buffer, trim to a range, see the selected frame, read how long ago it was.

`CapturedFrame.formattedTimeAgo` already renders the "−1m 20s" labels — use it rather than reimplementing.

- [x] **Step 2: Present it from the hotkey**

The Rewind hotkey opens the popover anchored to the status item. It needs keyboard focus for scrubbing, and this app is `LSUIElement` — `NSApp.activate()` is required or the popover never becomes key. `SettingsWindowController` already solves this exact problem; follow it.

Closing behaviour must be unambiguous: Escape closes without delivering, clicking away closes without delivering, and delivering closes.

- [x] **Step 3: Handle the empty and disabled cases**

Opening Rewind with the buffer disabled, or enabled but empty (just switched on, nothing captured yet), must explain itself rather than showing a blank popover. These are the two states a new user hits first.

- [x] **Step 4: Verify**

Run: `swift test` — count unchanged from Task 4. Clean warning-free release build, then `bash scripts/build.sh`.

Do not drive the GUI. List what needs a human pass.

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: the Rewind popover

Scrub the buffer, trim, preview. CaptureViewModel converted from
ObservableObject to @Observable rather than carried over.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Deliver a clip

Reconciling the two clipboard strategies, and routing a trimmed clip through the existing delivery path.

**Files:**
- Modify: `Sources/Framegentic/DeliveryService.swift`
- Modify: `Sources/Framegentic/RewindPopover.swift`

- [x] **Step 1: Deliver frames as file URLs**

Add a path to `DeliveryService` that takes the trimmed frames, runs them through `OptimizationPipeline`, writes them via `TempFileManager`, and puts the file URLs on the clipboard with `ClipboardWriter.writeFileURLs`.

The existing single-image path is unchanged. Both coexist: one image can be pasteboard data, several cannot.

- [x] **Step 2: Reuse the target logic, do not fork it**

A clip delivers to the same `DeliveryTarget` as a snap. Clipboard-only stops after the write; an auto-pasting target activates, guards and pastes exactly as it does today.

**The `autoPaste` guard must stay the first thing that runs**, and the Accessibility check must stay behind it. That property is compiler-enforced today — a clipboard-only user is never prompted for Accessibility — and this task must not weaken it.

- [x] **Step 3: Get the clipboard hygiene right, and it differs from Snap**

Snap's single image is cleared from the clipboard a few seconds after a successful paste. A clip is different: it is file URLs pointing at real files, and `TempFileManager` owns their deletion on a TTL.

Decide what happens to the pasteboard entry when those files are deleted, and write the reasoning in the commit. A pasteboard holding URLs to deleted files is a worse state than either clearing it or leaving the files longer.

Whatever you choose, the README's clipboard-hygiene section must describe it accurately — that section was corrected once already for overclaiming.

- [x] **Step 4: Verify**

Run: `swift test`, clean release build, `bash scripts/build.sh`. Report which delivery paths you could and could not verify without a GUI.

- [x] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: deliver a trimmed clip

Clips go to the clipboard as file URLs; a single snap stays pasteboard data.
Both route through the same delivery target, so clipboard-only still never
touches Accessibility.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Documentation and verification

**Files:**
- Modify: `README.md`, `DECISIONS.md`, `Resources/Info.plist`

- [x] **Step 1: Document Rewind in the README**

Add it as a mode alongside Snap. Cover: what it does, that it is **off by default**, that enabling it starts continuous in-memory capture, that frames never touch disk until delivery, and how to turn it off.

Update the privacy section. The "no network code" claim survives untouched and stays — but the honest description of what the app holds in memory changes materially, and that section is the one readers trust most. It has been corrected once for overclaiming; do not let it overclaim in the other direction either.

Update the badge test count and the comparison table — Rewind is the row where nothing else competes.

- [x] **Step 2: Update the capture usage string**

`NSScreenCaptureUsageDescription` currently describes one-shot capture. It now also covers continuous buffering when Rewind is enabled. Keep it accurate and short.

- [x] **Step 3: Record the decisions**

Add entries to `DECISIONS.md`, newest first, for the three this plan settled — file URLs for clips, two hotkeys, configurable duration without a frame-interval UI — plus anything the implementation forced a call on.

- [x] **Step 4: Full verification**

```bash
rm -rf .build/release .build/arm64-apple-macosx/release
swift build -c release 2>&1 | grep -ciE 'warning:|error:'
swift test 2>&1 | grep -E 'Executed [0-9]+ tests'
bash scripts/build.sh 2>&1 | tail -3
```

Expected: 0 warnings, all tests pass, bundle signs and verifies.

- [x] **Step 5: Commit and open a PR**

Open a PR against `master`. List the manual GUI checks below with their status — none of them can be run without a human.

**Do not rename the GitHub repo**, and do not install to `/Applications`.

---

## Outstanding — manual GUI checks

Nothing here has been verified. The app target has no unit tests by design, so these are the only
checks that can confirm the built app behaves.

Rewind is disabled (`SettingsModel.isRewindAvailable = false`), so the checks below are what
"off" should look like — its feature checklist is archived with the completed plan.

- [ ] Settings shows no Rewind section at all — no toggle, no duration control, no second recorder
- [ ] The menu bar shows no "Rewind hotkey unavailable" warning
- [ ] ⇧⌘7 does nothing in Framegentic and is free for another app to claim
- [ ] The menu bar icon never enters the buffering state
- [ ] Snap captures and delivers to Clipboard only, with no Accessibility prompt
- [ ] Snap captures, activates and pastes with Claude selected; auto-send submits
- [ ] Recording a new Snap shortcut works, takes effect immediately and survives relaunch
- [ ] **Reset to Default** returns to ⇧⌘6
- [ ] Start at login toggles and reports its real state

One known-correct behaviour, so it is not mistaken for a bug: a stored `BufferEnabled = true` from
an older build reads as off and stays stored — flipping `isRewindAvailable` back restores it.

---

## Completed

**2026-07-31 — Rewind mode.** Seven tasks via subagent-driven development. Ported
FrameSnap's buffer, perceptual hashing, image pipeline and temp-file lifecycle into
the kit; added buffer settings off by default, the continuous capture loop, a second
hotkey, the scrubber popover, and clip delivery. 74 kit tests.

Four of seven tasks needed fix rounds, and the same failure shape recurred three
times: a guard placed where it could not see a second caller. Task 3's serialisation
sat in `AppDelegate` while `didStopWithError` bypassed it; Task 6's in-flight flag
sat in the view model while the delivery detached; and the final review found the
flag was per-instance while the contended state — the system pasteboard — is global,
letting a Snap destroy an in-flight clip's URLs and submit two messages. Spec:
`docs/superpowers/specs/2026-07-31-framegentic-merge-design.md`.


**2026-07-31 — Framegentic rename and delivery targets.** Seven tasks executed via
subagent-driven development, merged as PR #4. The app is renamed, delivery is a
chosen target, and clipboard-only is the default — so Accessibility is now opt-in.
A final whole-branch review caught a critical bug no per-task review could see: the
clipboard-only path inherited a 3-second clipboard wipe from the auto-paste path,
destroying the capture before the user could paste it. Fixed, with six lesser
findings. 42 kit tests. Spec:
`docs/superpowers/specs/2026-07-31-framegentic-merge-design.md`.

**2026-07-29 — Shortcut customization.** Nine tasks. Shipped `KeyCodeNames`,
`HotKeyConfig` as a value type, `HotKeyValidator` (20 reserved combos),
`HotKeyStore`, a configurable `HotKeyManager`, `SettingsModel`,
`ShortcutRecorderField` and the settings window. Spec:
`docs/superpowers/specs/2026-07-29-shortcut-customization-design.md`.
