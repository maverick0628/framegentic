# Framegentic — merging FrameSnap and ClaudeShot

Date: 2026-07-31
Status: draft, pending approval

## Problem

Two macOS menu bar apps do adjacent halves of the same job.

**ClaudeShot** captures the current screen and pastes it into the Claude desktop
app with one keystroke. **FrameSnap** keeps a rolling two-minute buffer of screen
frames in memory and lets you scrub back, trim and copy. Both use
ScreenCaptureKit, both are `LSUIElement` menu bar apps, both split a pure kit from
an AppKit/SwiftUI app layer, both target macOS 14+.

Maintaining them separately costs twice the notarization, twice the release
pipeline, twice the permission-onboarding support, and leaves each with a weaker
version of a component the other does properly.

There is also a naming problem. ClaudeShot puts Anthropic's trademark in a product
name, which implies an affiliation that does not exist.

## Goal

One app — **Framegentic** — that shows an AI what is on your screen: right now, or
the last two minutes of it. Agent-agnostic by default, with Claude as one
delivery target among several.

## Non-goals

Region select, annotation, a screenshot history browser, OCR, video recording,
cloud sync, and a Windows port. Existing screenshot tools are better at all of
that. This captures a display and hands it to an agent.

## The product

Two capture modes over one pipeline:

- **Snap** — one keypress. Captures the current screen, delivers it, done.
- **Rewind** — a keypress opens the scrubber over the in-memory buffer. Trim to
  the frames that matter, then deliver.

Rewind is the differentiated feature. "I just hit a bug, show the agent what led
up to it" is something no screenshot tool does today.

### Delivery targets, not modes

The two apps disagree about the final step: FrameSnap copies to the clipboard and
stops, ClaudeShot activates Claude and pastes. Both are correct for different
users, so neither becomes a "mode". Delivery is a **target**, chosen in settings:

| Target | Behaviour | Permissions |
|---|---|---|
| **Clipboard only** *(default)* | Copy, notify, stop | Screen Recording |
| Claude | Copy → activate → verify frontmost → paste | + Accessibility |
| *(later)* Cursor, ChatGPT desktop… | Same, different bundle ID | + Accessibility |

A target is a small record: bundle ID, display name, and whether it auto-pastes.
Adding one later is a table entry, not a new mode or a new code path.

**Clipboard-only is the default deliberately.** The auto-paste path needs
Accessibility, simulates keystrokes and steals focus — it is the source of most of
ClaudeShot's support burden today. Making it opt-in means the majority of users
never grant Accessibility at all.

This also fixes the trademark posture. Claude becomes a target the tool
interoperates with rather than the product's identity, which is referential use
and defensible. The README says "works with Claude"; the app is not named after it.

## Architecture

Both apps already use the same shape, so the merge is mostly moving files.

```
FramegenticKit   (pure logic, unit tested — no AppKit dependency)
  ── from ClaudeShotKit ──
  CaptureGeometry      display point/pixel maths
  DisplaySelection     which display to capture
  HotKeyConfig         the shortcut value type
  HotKeyValidator      reserved-combo table + modifier rules
  HotKeyStore          UserDefaults persistence
  KeyCodeNames         keyCode → glyph
  PasteGuard           frontmost + trust check before a keystroke
  ── from FrameSnapKit ──
  RingBuffer           the rolling frame buffer
  CapturedFrame        frame value type
  DHash                perceptual hash, for dropping duplicate frames
  ImageProcessor       scaling and encoding
  OptimizationPipeline JPEG optimisation
  TempFileManager      temp files with TTL deletion
  ClipboardWriter      clipboard strategies
  ── new ──
  DeliveryTarget       bundle ID, name, autoPaste flag
  TargetRegistry       the known-targets table

Framegentic      (AppKit + SwiftUI glue, not unit tested)
  AppDelegate          menu bar, wiring
  CaptureService       ScreenCaptureKit — one-shot AND continuous
  ActivityMonitor      adaptive capture rate
  HotKeyManager        Carbon registration, register/unregister
  DeliveryService      clipboard write, then optional activate + paste
  SettingsModel        observable single source of truth
  SettingsView         SwiftUI settings incl. target picker
  ShortcutRecorderField NSView key recorder
  PopoverView          Rewind UI
  TimelineScrubber     buffer scrubbing
  FramePreview         frame thumbnails
  ToastView            confirmations
```

### Which implementation wins where

The two apps overlap asymmetrically — each has the better version of something.

| Component | Winner | Why |
|---|---|---|
| Hotkeys | **ClaudeShot** | Carbon registration, configurable, recorder UI, 20-combo reserved table, validation, 34 tests. FrameSnap's is a basic manager. |
| Capture | **FrameSnap** | Ring buffer, activity-adaptive rate, DHash dedup. ClaudeShot grabs one frame. |
| Delivery | **ClaudeShot** | Bundle-ID resolution, frontmost verification, paste guard, concealed clipboard. |
| Rewind UI | **FrameSnap** | Popover with a timeline scrubber is a real interface. |
| Build | **ClaudeShot** | SwiftPM, Swift 6, existing notarizing CI. FrameSnap is an `.xcodeproj`. |

FrameSnap's `HotkeyManager` is deleted rather than merged. ClaudeShot's
`ScreenshotService` is absorbed into the new `CaptureService` as its one-shot path.

### `PasteGuard` generalises

`PasteGuard.evaluate(frontmostBundleID:expectedBundleID:axTrusted:)` already takes
the expected bundle ID as a parameter — it is not hardcoded to Claude. Pointing it
at a `DeliveryTarget` is a call-site change, not a rewrite. `ClaudeLocator`
generalises the same way into a `TargetLocator` that resolves any target by bundle
ID with a launch fallback.

## Privacy

This is the hard part of the merge and it needs designing, not patching.

ClaudeShot's current claim is strong and simple: no network code, nothing written
to disk, clipboard cleared after delivery. FrameSnap continuously buffers the
screen in memory and writes temp files when you copy. Merged naively, the strong
claim becomes a qualified one.

Three rules keep it honest:

1. **The buffer is off by default.** Snap works with it off — it captures on
   demand. Rewind requires it, and turning Rewind on is what enables continuous
   capture. A user who only wants the screenshot key never pays the battery,
   memory or privacy cost of an always-on buffer.
2. **The buffer never touches disk.** Frames live in memory and are dropped as
   they age out. Temp files are written only at the moment of delivery, and
   `TempFileManager` already deletes them on a TTL.
3. **The menu bar shows when the buffer is running.** An app that can record the
   last two minutes of your screen must make that state visible, not bury it in
   settings.

The "no network code" claim survives the merge intact — neither app links anything
that opens a socket, and that stays true.

## Migration

**Target repo: `claudeshot`, renamed to `framegentic`.** It is current, already
SwiftPM and Swift 6, has the notarizing release workflow, the stronger test suite,
and today's README work. FrameSnap is an Xcode project untouched since June.

`framesnap` becomes an archived repo whose README points at the new one.

Order of work, each step leaving a building app:

1. Rename `claudeshot` → `framegentic`; rename the kit and app targets, bundle ID
   `com.duncansmith.framegentic`, update `build.sh` and the CI workflow.
2. Introduce `DeliveryTarget` and `TargetRegistry`; generalise `PasteGuard` and
   `ClaudeLocator`; add the target picker to settings. Clipboard-only becomes the
   default. **At this point the app is agent-agnostic and shippable.**
3. Port `FrameSnapKit` into `FramegenticKit` — pure logic, moves nearly as-is,
   with its 343 lines of tests.
4. Extend `CaptureService` with the continuous path, `ActivityMonitor` and the
   buffer toggle, off by default.
5. Port the popover, scrubber, preview and toast; wire Rewind to its own hotkey.
6. Reconcile the two clipboard strategies — PNG-concealed for single frames, file
   URLs with TTL for multi-frame clips.

Step 2 is the natural first release. Steps 3–6 add Rewind.

## Testing

The kit keeps its existing coverage from both sides — ClaudeShot's 34 tests plus
FrameSnap's ring-buffer, DHash, image-processor, pipeline and temp-file suites.

New pure-logic tests worth having:

- `TargetRegistry` — a known target resolves; an unknown bundle ID does not; the
  clipboard-only target reports `autoPaste == false`.
- `PasteGuard` with a non-Claude target — proves the generalisation, since every
  existing assertion uses Claude's bundle ID.
- Buffer-disabled path — Snap produces a frame with the ring buffer off.

The app layer stays unit-test-free by existing convention. GUI behaviour is
verified by a manual checklist, as with the shortcut-customization work.

## Open decisions

1. **Rewind's clipboard format.** Multi-frame clips as file URLs works for Claude
   and most chat UIs, but not all. Worth confirming against the actual targets
   before committing.
2. **One hotkey or two.** Snap and Rewind could share a key (tap versus hold) or
   take one each. Two is simpler to implement and explain; one is fewer bindings
   to find room for.
3. **Buffer duration.** FrameSnap's two minutes was chosen for FrameSnap. Whether
   it stays fixed or becomes a setting is a memory-footprint question.
4. **What happens to ClaudeShot's existing installs.** The bundle ID changes, so a
   rename is effectively a new app: TCC grants reset and the old one lingers in
   `/Applications`. Given the install base is one machine, a note in the release
   is enough — but it should be a deliberate note, not a surprise.
