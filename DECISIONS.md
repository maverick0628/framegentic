# Decisions

## 2026-07-31 — Rewind clips go to the clipboard as file URLs; a single Snap stays pasteboard data

A pasteboard item can hold one image as data, or several file references, but never
several images — so a multi-frame clip had no way to reuse Snap's PNG-`Data`-on-
`NSPasteboardItem` path. `OptimizationPipeline.processAndCopy` writes each kept frame
out as a temp JPEG and hands the resulting URLs to `ClipboardWriter.writeFileURLs`;
`CaptureService.captureToClipboard` is untouched and still writes a single Snap as PNG
data. Less a fresh decision than confirming one already made: FrameSnap's
`ClipboardWriter` wrote file URLs before this merge started, so the multi-frame case
arrived with a working answer to port rather than a gap to design. Both shapes route
through the same `DeliveryService.activateAndPaste` once something is on the
clipboard, so Clipboard only still writes and stops, and an auto-pasting target still
activates, guards and pastes, regardless of which one delivered it.

## 2026-07-31 — Rewind's permission-denied state reuses CGPreflightScreenCaptureAccess() directly, no new CaptureService state

Fix round 1 on Task 5 caught that `.empty` covered two different situations: a buffer
legitimately still filling in, and Screen Recording permission denied or revoked
(`CaptureService.performStart` reverts to `.idle` silently on a stream-start failure, while
`bufferEnabled` stays `true`) — the two are indistinguishable from "enabled, zero frames" alone,
so every future Rewind open told a permission-denied user to wait a few seconds, forever. Rather
than add an error-state property to `CaptureService`, `RewindViewModel.state` calls
`CGPreflightScreenCaptureAccess()` directly — the same check `AppDelegate`'s menu already uses
for the identical question — evaluated live each time `state` is read, so it can't go stale
between the check and the display. The `.permissionDenied` copy reuses
`CaptureError.screenRecordingDenied.localizedDescription` for the message and the exact "Grant
Screen Recording…" wording from the menu item, rather than inventing a third phrasing of the
same fact.

## 2026-07-31 — TimelineScrubber clamps indexForPosition to frameCount - 1, not just to `total`

Fix round 1 on Task 5: `totalFrames = max(frameCount - 1, 1)` pads to 1 for a single frame so
the x-position ratio math never divides by zero, but that padding is one larger than the last
real index. `indexForPosition` used `total` as its upper bound, so a one-frame buffer could hand
`clipEnd` an index outside `frames.indices`, and `selectedFrames` would then return `[]`
permanently — Copy to Clipboard disabled for the rest of the session, no crash, no explanation.
Clamped inside `indexForPosition` itself (`min(raw, max(frameCount - 1, 0))`) rather than at
each of the three drag-handle call sites, since it's the single choke point all three (start,
end, playhead) funnel through, and the fix is a no-op for any buffer with 2+ frames.

## 2026-07-31 — The popover reads a snapshot of the buffer, never a live reference

`CaptureService.currentFrames() -> [CapturedFrame]` is the only way anything outside that
file touches the buffer now — `ringBuffer` went from `private(set)` to fully `private`. It
returns `ringBuffer?.allElements() ?? []`, a plain array of `Sendable` `CapturedFrame`s, never
the `RingBuffer` itself, which matches the reasoning already documented above `isBuffering` in
that file (RingBuffer was never meant to cross a boundary; it has no Sendable conformance of
its own). `RewindViewModel.refreshFrames()` calls this once, when the popover opens, and holds
the result — not a live read re-queried on every drag. Two reasons, not one: re-querying on
every drag event is an O(n) copy per pixel of mouse movement, and the buffer keeps recording
underneath an open popover, so a live read would shift `clipStart`/`clipEnd`/`playhead` out
from under a drag already in progress. A snapshot makes the scrubbed range stable for as long
as the popover is open, by construction, not by careful timing. Matches what FrameSnap's own
`CaptureViewModel.refreshFrames()` already did.

## 2026-07-31 — RewindPopoverController follows SettingsWindowController's activation pattern, for a popover instead of a window

This app is `LSUIElement` — no Dock icon, no focus by default. `SettingsWindowController`
already solved "how does a window become key in an accessory app" with `NSApp.activate()`
before ordering front; `RewindPopoverController` calls `NSApp.activate()` before
`popover.show(...)`, then explicitly `.makeKey()`s the popover's window, since an accessory
app needs both steps for a freshly-shown popover to actually take keyboard focus. The popover
uses `NSPopover.behavior = .transient` so clicking away closes it with no extra code, and the
SwiftUI content uses `.onExitCommand` for Escape rather than an AppKit event monitor — NSPopover
doesn't dismiss on Escape by default, and `onExitCommand` is the SwiftUI-native hook for exactly
this, not something the popover route needs AppKit for. Delivering (`confirmSelection()`) closes
the popover itself, after a 1.5s pause so the toast's frame count and TTL are readable first.
`NSPopoverDelegate.popoverDidClose` releases the frame snapshot regardless of which of the three
paths (Escape, click-away, deliver) triggered the close, so there's one release point, not three.

## 2026-07-31 — CaptureViewModel became RewindViewModel while converting off ObservableObject

Renamed, not just converted — `CaptureViewModel` invited confusion next to `CaptureService`
(unrelated concerns: one is the screen-capture pipeline, the other is UI state for a clip
selection). `@Published`/`ObservableObject` became plain stored properties under `@Observable`,
`@MainActor` carried over unchanged. It no longer owns a capture manager (it never needs to
start or stop buffering — that's `SettingsModel.bufferEnabled` and `AppDelegate`'s job) or the
`OptimizationPipeline` — those are Task 6's concern once delivery is real.

## 2026-07-31 — confirmSelection() is a deliberate stub pending Task 6

Per this task's brief: delivering a range is the next task, so `confirmSelection()` sets the
copied count, shows the toast, and closes the popover — the full interaction — without writing
anything to the clipboard. Nothing downstream depends on it doing real work yet. Flagged for the
reviewer so a Rewind session that shows "3 frames copied" but leaves the clipboard untouched
isn't mistaken for a bug before Task 6 lands.

## 2026-07-31 — Rewind gets its own hotkey binding rather than a tap-versus-hold on Snap's

Carbon's `RegisterEventHotKey` delivers a single event on key-down and nothing else —
it has no notion of "held for N seconds," so distinguishing tap-Snap from hold-Rewind
on one binding would mean layering timer-based hold detection on top of an API that
was never built to report duration, for a worse result than just registering a second
combo. Rewind gets its own `HotKeyConfig` (`.rewindDefault`, ⇧⌘7) instead, sequential
with Snap's ⇧⌘6. The cost lands in `SettingsModel` and `HotKeyManager`: recording
either shortcut has to suspend both registrations, since Carbon consumes a combo
before AppKit's recorder ever sees the keystroke, and `apply(_:for:)` has to reject a
candidate that collides with the app's *other* current binding — problems a single
hold-modified shortcut would not have had, accepted in exchange for not building hold
detection from scratch.

## 2026-07-31 — Rewind's shortcut collision check lives in SettingsModel, not HotKeyValidator

HotKeyValidator only knows the reserved-system-shortcut table; it has no notion of the
app's own second binding, and shouldn't gain one — it stays a pure function of one combo.
SettingsModel is the only object holding both HotKeyConfigs at once, so `apply(_:for:)`
rejects a candidate that matches the *other* shortcut's current config before registering
it, with a "already Rewind's/Snap's shortcut" message. HotKeyStore.load() deliberately
doesn't cross-check the two stored blobs either, for the same reason — it only ever sees
one key at a time. The guarantee holds for anything going through the app's own UI; a
`defaults write` that hand-crafts matching valid blobs for both keys is outside that
boundary and degrades to one shortcut failing to register (surfaced same as any other
registration failure), not a crash.

## 2026-07-31 — Rewind's default is ⇧⌘7

Sequential with Snap's ⇧⌘6 and easy to explain. Unlike ⇧⌘3/4/5, it isn't one of the
system's reserved screenshot combos, so it needs no Touch-Bar-only exception in
HotKeyValidator's reserved table — same self-consistency requirement the capture default
already has a test for (Reset to Default has to produce something the validator accepts).

## 2026-07-31 — HotKeyStore is keyed by a Shortcut enum, not duplicated members

`Shortcut: String, CaseIterable` (`.capture` / `.rewind`) backs both the UserDefaults key
(its raw value) and the per-shortcut fallback default. `load()`/`save()` stay single
parameterised methods instead of a load/loadRewind/save/saveRewind quartet, so the
existing corrupt-blob validation logic isn't duplicated. A future third shortcut is one
enum case, not new members. HotKeyManager reuses the same enum (via a typealias) to key
its Carbon `EventHotKeyID`s and to dispatch its shared event handler, rather than
inventing a second parallel "which shortcut" type.

## 2026-07-31 — Recording either hotkey suspends both, unconditionally

`HotKeyManager.unregister()` now tears down every registered shortcut rather than one.
Carbon consumes a registered combo before AppKit ever sees the keystroke, so leaving the
other shortcut live during recording would let it fire instead of being captured. Simpler
than threading "which shortcut is being recorded" through SettingsModel, and the two
recorder fields can't be interacted with simultaneously in the UI anyway.

## 2026-07-31 — Buffer duration is configurable; sampling interval and auto-delete TTL are stored but have no UI

`SettingsModel` persists three buffer-related numbers — `bufferWindowSeconds`,
`frameIntervalSeconds`, `autoDeleteTTLSeconds` — but `SettingsView` only exposes the
first, as a four-option segmented `Picker` (1/2/3/5 min) that appears once
`bufferEnabled` is on. Keeping duration configurable cost nothing: FrameSnap's
`AppSettings` already persisted it, so "fixed or configurable" had a working default
to keep rather than a UI to invent. Frame interval and TTL stay out of the UI on
purpose — two more interacting knobs (how often it samples, how long a delivered
clip survives before its temp files vanish) is a settings screen nobody would
understand relative to what it buys them, so both keep their stored defaults (10s
interval, 300s TTL, matching `AppSettings`'s registered defaults) and are only
reachable by editing `UserDefaults` directly.

## 2026-07-31 — TempFileManager and OptimizationPipeline are plain actors, not @MainActor (supersedes the entry below)

Review caught that `@MainActor` pinned JPEG encoding and file I/O to the main thread. Nothing
consumes this code yet, but Task 3's capture loop pushes every captured frame through
`OptimizationPipeline` at a sub-second interval, and this menu bar app's scrubber UI can't
afford that contention. Switched both types to a plain `actor` instead — isolation still
serialises access to `tempFileManager`, closing the same race, without binding the work to
one thread.

Five production call sites became `await` and seven ported test methods became `async
throws`. `TempFileManagerTests` swapped `defer` for XCTest's async `addTeardownBlock`, since
`defer` bodies can't contain `await`.

## 2026-07-31 — TempFileManager and OptimizationPipeline are @MainActor, not locked (superseded — see entry above)

Porting FrameSnap's pipeline into the Kit surfaced a real (if compiler-silent) data
race: `TempFileManager`'s cleanup timer ran on a background GCD queue while writes
land on whatever thread the caller uses — `Dispatch`'s handler closures aren't
`@Sendable` in this SDK, so Swift 6 never flagged it. Isolated both types to
`@MainActor` instead of adding a lock, matching FrameSnap's own `CaptureViewModel`
(already `@MainActor`, already owning the pipeline). The background timer became a
MainActor-confined `Task` with `Task.sleep`. First `@MainActor` types in the Kit —
Task 2/3's capture loop and scrubber UI need to consume them on that assumption, or
this isolation needs revisiting.

## 2026-07-31 — CapturedFrame's Sendable conformance is real, not @unchecked

The port brief expected `@unchecked Sendable` for the CGImage-holding struct, since
older SDKs never marked CGImage Sendable. Checked rather than assumed: this
toolchain (Swift 6.3.3) already conforms CGImage to Sendable, confirmed with a
throwaway generic-constraint compile check plus a non-Sendable negative control
before trusting it. No `@unchecked` anywhere in the ported pipeline.

## 2026-07-31 — Clipboard-only keeps the capture; the menu bar confirms it

The 3-second clipboard wipe used to run on the clipboard-only path too, which
destroyed the capture before most people could paste it — `NSPasteboard.changeCount`
counts writes, so a user pressing ⌘V never bumped it and never cancelled the wipe.
On that path the clipboard *is* the delivery, so the wipe is gone; it stays on the
auto-paste path, where the capture has already been handed over. With nothing coming
to the front to signal success, the status item now flashes a tick for a second.
Chose the icon over a notification: no authorization to request, nothing the user
can silently disable, no way to reintroduce the same no-feedback bug.

## 2026-07-31 — Bundle ID is now com.duncansmith.framegentic

The rename changed the bundle identifier, and macOS treats a new identifier as a
different app. Screen Recording and Accessibility grants do not carry over — both
must be granted again, followed by a quit and relaunch. The old `ClaudeShot.app`
also stays in `/Applications` until it is deleted, and its TCC entries linger until
`tccutil reset ScreenCapture com.duncansmith.claudeshot` (and the Accessibility
equivalent) clear them. Accepted rather than aliased: keeping the old identifier
to preserve grants would have kept Anthropic's trademark in the app's identity,
which is the whole thing the rename set out to fix.

## 2026-07-31 — Shipped the rename and delivery targets

Steps 1–2 of the merge design landed: the app is Framegentic, delivery is a
chosen target, and clipboard-only is the default. The app no longer requires
Accessibility unless the user opts into auto-paste. FrameSnap's ring buffer and
the Rewind mode follow in a separate plan.

## 2026-07-31 — Merge FrameSnap into this app as Framegentic

FrameSnap and ClaudeShot do adjacent halves of one job — capture the screen for an
AI — on the same platform, the same framework and the same Kit/App split. Each has
the better implementation of something the other also has: ClaudeShot's hotkey
system (Carbon, configurable, validated, 34 tests) against FrameSnap's capture
(ring buffer, adaptive rate, dedup). Merging takes the stronger half of each.

This repo is the target rather than FrameSnap's: it is SwiftPM and Swift 6, has the
notarizing release workflow, and is current. FrameSnap is an Xcode project untouched
since June. See docs/superpowers/specs/2026-07-31-framegentic-merge-design.md.

## 2026-07-31 — Delivery is a target, not a mode; clipboard-only is the default

The two apps disagree about the last step — FrameSnap copies and stops, ClaudeShot
activates and pastes. Rather than ship two modes, delivery becomes a chosen target
(bundle ID, name, autoPaste flag) with clipboard-only as the default. Adding Cursor
or ChatGPT later is a table entry, not a code path.

Clipboard-only defaults because auto-paste needs Accessibility, simulates keystrokes
and steals focus — the source of most support burden today. Opt-in means most users
never grant Accessibility at all.

It also fixes the trademark posture: Claude becomes a target the tool works with
rather than the product's identity, which is referential use and defensible.

## 2026-07-31 — The frame buffer is off by default and never touches disk

Merging a continuous screen buffer into an app whose pitch is "nothing persists"
weakens a claim worth keeping. So Snap works with the buffer off, enabling Rewind is
what turns continuous capture on, frames live only in memory, and the menu bar shows
when the buffer is running. The "no network code" claim survives the merge unchanged.


## 2026-07-29 — Validate the stored shortcut in `HotKeyStore.load()`, not at registration

A foreign `defaults write` of a bare key would otherwise register globally and turn every
"a" into a capture. The check goes in the store because that is where the untrusted
boundary is, because `load()` already promises a working hotkey out of a corrupt blob, and
because `SettingsModel` sits in the untested app target where the fallback could not be
tested. Cost: `HotKeyStore` now depends on `HotKeyValidator` — same module, no cycle.

## 2026-07-29 — ⌘, joins the reserved-combo blocklist

⌘, is the app's own Settings… menu equivalent, and `RegisterEventHotKey` would take it
globally, so Preferences would stop opening in every other app. Same trap as the existing
⌘Q/W/H/M rows. Supersedes the ~18-row count in the entry below: the table is now 20 rows.

## 2026-07-29 — Two tests renamed to stop claiming unobservable invariants

Mutation testing showed that reversing the rule order in `validate`, and the lookup order
in `displayString`, changed no test result — both are equivalent mutants, because no
reserved row lacks ⌘/⌃/⌥ and `layoutCharacter`'s guard nils out every key in the glyph
table. The tests now pin the preconditions that make those orderings harmless, and say so
in comments, rather than asserting an ordering they cannot detect. `Reserved`/`reserved`
were relaxed from private to internal so the suite can pin the table's size and the
reachability of every row.

## 2026-07-29 — Shortcut customization shipped

Recorder, validator, `UserDefaults` persistence and a SwiftUI settings window, with the
menu bar keeping its own toggles. Implemented per
`docs/superpowers/specs/2026-07-29-shortcut-customization-design.md`.

## 2026-07-29 — Keep Auto-send and Start-at-login in both the menu and Settings

The settings window duplicates the two existing menu toggles rather than absorbing them.
Both surfaces read and write one `@Observable SettingsModel`; the menu rebuilds from it
on open, so they cannot drift. Costs a little duplication to avoid making a one-click
toggle a two-click one.

## 2026-07-29 — ⌘⇧6 stays off the reserved-combo blocklist

⌘⇧6 is the Touch Bar screenshot shortcut, but only on Touch Bar Macs, and it is the
app's default. A validator that rejects its own default is incoherent, so registration
failure is what reports it on the machines where it is actually taken. A unit test
asserts the validator accepts the default, to catch anyone adding it later.

## 2026-07-29 — Blocklist known system shortcuts on top of try-and-report

`RegisterEventHotKey` is the authoritative gate, but its failure gives no reason. A
curated table of ~18 system combos with owner names ("⌘Space is Spotlight") produces a
useful message instead. The list is explicitly a courtesy, not a guarantee: it cannot
know third-party bindings and will drift with macOS releases.

## 2026-07-29 — Hand-roll the shortcut recorder instead of using KeyboardShortcuts

sindresorhus/KeyboardShortcuts solves this well, but it is roughly twice the size of the
app, and adopting it would delete `HotKeyManager` and `HotKeyConfig` along with the
documented reasoning about why Carbon is used. Hand-rolling keeps the repo
zero-dependency and puts parse/validate/format in `ClaudeShotKit` where it gets unit
tested like `PasteGuard`. Cost: mapping keyCode to a display glyph across keyboard
layouts is ours to handle, via `UCKeyTranslate` with a US-ANSI fallback for headless CI.

## 2026-07-29 — Shortcut recorder is an NSView, not a SwiftUI view

Two behaviours SwiftUI does not expose. `performKeyEquivalent(with:)` has to be
overridden or the recorder never sees any combo containing ⌘, since AppKit routes those
down the key-equivalent chain ahead of `keyDown`. And the Carbon global hotkey must be
unregistered while recording, because it consumes its own combo before AppKit dispatch —
otherwise re-recording the current shortcut fires a screenshot instead.

## 2026-07-29 — Registration succeeds before the shortcut is persisted

`HotKeyStore` is only written after `RegisterEventHotKey` returns success, so a shortcut
that does not work can never end up saved. On failure the previous shortcut is
re-registered and nothing changes.
