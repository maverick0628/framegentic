# Decisions

## 2026-09-25 — README screenshots are window-only captures

The menu and Settings screenshots are captured per window with `screencapture -l`, so they carry
no menu bar clock, other status items or desktop. They show a Claude target and a custom `⇧⌘7`
shortcut rather than a fresh install's defaults, and the README says so beside them. Rewind's
popover is left out because it ships disabled.

## 2026-07-31 — Rewind ships disabled behind one flag, code kept

Rewind's output failed its first real use. A delivered clip lands in Claude as several images
attached to one message, and a row of thumbnails turns out to be a bad way to show an agent what
happened — you cannot read any single frame, and the sequence carries less than one well-chosen
screenshot. That is not a tuning problem: the frames go out at 1024px, the same width a Snap
uses, so there is no parameter to raise.

Cut rather than iterate, because the thing to fix is the format and nobody knows yet what
replaces it. Deleting the code would have been the wrong version of that. The buffer, the
perceptual-hash dedup, the idle backoff and the temp-file lifecycle are all sound and all tested
— what failed sits at the last inch of the pipeline. So the feature is gated on
`SettingsModel.isRewindAvailable = false` and everything behind it stays in the tree.

The flag hangs off `bufferEnabled` rather than being checked by each consumer, because
`bufferEnabled` was already the one gate every Rewind path asked. Making it read
`isRewindAvailable && stored` disables capture, the popover's contents and the settings
sub-controls in one move, and the stored preference survives untouched for whoever flips it back.
Only three things needed touching directly: hotkey registration (both sites — `endRecording()`
re-registers too, and would otherwise have resurrected the combo after any shortcut edit), the
settings section, and the menu's "Rewind hotkey unavailable" warning, which would otherwise have
become permanent by describing a deliberate non-registration as a collision.

The README says Rewind is parked and why, rather than dropping the section. A public repo with a
`RewindPopover.swift` in it should explain itself.

## 2026-07-31 — Concurrency annotations state their reasoning in-place, not per-SDK

The branch built clean here and failed to compile on the runner, for the second time on this
project after ScreenCaptureKit. Both errors were drift, not logic: `CIContext` is `Sendable` on
the macOS 26.5 SDK this machine has and not on the macOS 15 SDK the runner uses, and the
runner's older compiler applies a region-isolation rule to `claimingDelivery`'s generic return
that Swift 6.3 no longer applies.

The rule taken from it is that an annotation has to be true on both toolchains, not merely
sufficient on one. `nonisolated(unsafe)` on the shared `CIContext` clears the runner but earns a
redundancy warning locally, so the conformance is asserted once in an `@unchecked Sendable` box
instead — same claim, same reasoning, no SDK-conditional spelling. `@preconcurrency import
CoreImage` was rejected for scope: it would drop `Sendable` checking on the whole framework to
settle one property that had actually been reasoned about.

`claimingDelivery`'s closure parameter is now `@MainActor` rather than its `T` being constrained
`Sendable`. Both callers happen to return `Sendable` types, so the constraint would have worked,
but the closure never leaves `MainActor` — it wraps the pasteboard write, the pipeline and the
claim flag — and saying so removes the crossing that produced the error rather than permitting
it. Cheaper too: no hop.

Fix 1 was reproduced locally by typechecking against the macOS 15.4 SDK in CommandLineTools,
which is worth remembering the next time this class of failure lands. Fix 2 was not — that needs
an older compiler, and there isn't one on this machine.

## 2026-07-31 — One DeliveryService for the whole app, and its in-flight guard covers Snap too

Snap and Rewind each built their own `DeliveryService`, so the guard added to `deliverClip`
was per-instance — it serialised clip against clip and nothing else. The state a second
delivery corrupts isn't inside that class, though. It's the system pasteboard and the target
app's keystroke stream, both global: a Snap fired during a clip's ten-second cold-launch wait
calls `clearContents()` on the clip's file URLs, then posts a second ⌘V and Return into the
same app. One PNG pasted twice, two messages submitted, and a toast still reading "6 frames
copied". There is no undo.

Both halves were needed. Sharing the instance alone leaves `deliver` consulting no guard;
widening the guard alone leaves two instances that can't see each other. So `AppDelegate` now
owns the only `DeliveryService` and injects it into `RewindViewModel`, and the flag is claimed
by a `claimingDelivery` helper that both entry points route through, releasing on every exit
including a throw.

The Snap entry point became `deliverSnap(to:autoSend:writeCapture:)` — a closure, so the
pasteboard write happens *inside* the claim rather than before it. `deliver` went private
behind it. That shape was chosen over a public check-then-call because the write is the
destructive half: guarding only the paste would still let a Snap wipe a clip mid-delivery and
then refuse politely. Third time on this branch that a guard was placed where it couldn't see
the second caller; making the unguarded path unreachable is what stops a fourth.

The refusal reaches the user through the menu bar, not `report`'s alert. `report` calls
`NSApp.activate()` and runs a modal, and a Snap is only ever refused while another delivery is
waiting for its target to come frontmost — so explaining the refusal that way would trip
`checkGuard` and abort the delivery the refusal exists to protect. The status item already
flashes for "the hotkey did something you can't otherwise see"; a refusal glyph reuses it.

## 2026-07-31 — Delivered temp files are deleted synchronously at terminate

`OptimizationPipeline.cleanup()` had no caller outside the tests, and neither
`applicationWillTerminate` nor `TempFileManager.deinit` (which doesn't run at process exit)
removed anything — so quitting inside the TTL left full-resolution JPEGs of the screen in
`/var/folders` until macOS's periodic sweep, days later, against a README that says they
delete themselves on a timer.

Cleanup at terminate can't `await`: the process can exit before a suspended task is ever
resumed, so an awaited cleanup is a cleanup that might not happen. `TempFileManager` gained a
`nonisolated func removeSessionDirectory()` that calls `removeItem` directly instead — safe
off the actor because `sessionDir` is immutable, and it finishes before the call returns. The
cost is that pending cleanup tasks aren't cancelled and `writtenURLs` isn't cleared, neither
of which outlives the process doing the quitting. `cleanup()` stays for the async case.

Accepted cost: a clip delivered but not yet pasted no longer survives a quit. The README said
those files delete themselves and they didn't, so the honest fix is to make the code true and
say plainly that quitting is the other deadline — not to soften the claim.

## 2026-07-31 — Rewind distinguishes "stopped" from "still filling"

`didStopWithError` stops cleanly and leaves `bufferEnabled` true — deliberate, and unchanged.
But `RewindViewModel.state` derived `.empty` from `bufferEnabled && frames.isEmpty`, so after
a monitor unplug or a fast user switch killed the stream, every future Rewind open said
"Rewind just turned on. Give it a few seconds" — forever, with no recovery but toggling
Settings off and on. Same class as the permission bug fixed earlier; that fix only covered the
preflight branch.

The missing input was the capture service's own state. `CaptureService.willBuffer` (`.starting
|| .running`) is deliberately not `isBuffering`: `isBuffering` means "frames are arriving now",
which is false for a second or two after every toggle and would report a healthy start as
dead. `willBuffer` answers the question the empty state actually asks — will frames arrive? A
`.stopped` state names the cause (a display change, a user switch) and the cure (toggle Rewind
off and back on), since nothing retries the stream on its own.

## 2026-07-31 — A refused clipboard write reports zero frames, not the frame count

`ClipboardWriter.writeFileURLs` discarded the `Bool` from `writeObjects` and returned a change
count regardless, so a refused write — with `clearContents()` already done, leaving the
clipboard holding nothing — came back indistinguishable from a good one and the toast claimed
frames the user didn't have. It now returns `Int?`, without `@discardableResult`, so the
failure is impossible to drop by accident. `processAndCopy` maps `nil` to zero frames, which
`confirmSelection` already surfaces as "Couldn't copy those frames. Try again."

Cleanup is still scheduled on the failing path, before that return. The files exist either
way, and a refused write is the one case where nothing on the clipboard will ever point at
them — orphans with no deadline otherwise.

## 2026-07-31 — Delivery detaches from its UI, and never cancels

The Rewind popover is `.transient`, so the target app coming to the front closes it —
mid-sequence, every time an auto-paste works. Cancelling the delivery from
`popoverDidClose` would reach into a running keystroke sequence and cut its delays to
nothing: ⌘V before the app can accept it and, with auto-send on, Return straight after,
submitting an empty message. Keystrokes can't be recalled once posted; only the UI has
anything left to stop doing. So `releaseFrames()` detaches instead — it bumps a session
counter, and every UI mutation in `confirmSelection` is gated on the session it started in.
The delivery finishes its keystrokes and then changes nothing on screen.

## 2026-07-31 — Paste-sequence delays use a timer, not Task.sleep

`Task.sleep` returns the *instant* its task is cancelled. Every pause in the paste sequence is
load-bearing — the settle gives a just-activated app time to accept input, the paste-to-send
gap keeps Return from firing before ⌘V has landed, and `waitForFrontmost`'s poll is the only
thing keeping a ten-second cold-launch wait from being a hot loop. A cancelled caller would
collapse all three to zero and auto-send an empty message into Claude, which there is no undo
for. `try? await Task.sleep` is worse than plain `Task.sleep`, not better: it swallows the
cancellation error and carries straight on to the keystroke.

`DeliveryService.delay(_:)` wraps `DispatchQueue.main.asyncAfter` in a checked continuation
instead. A timer has no cancellation to observe, which makes the delay a property of the
sequence rather than of whoever happens to call it. Every delay on the keystroke path goes
through it; `Task.sleep` survives only where an early return is harmless (the clipboard-clear
timer, which additionally re-checks `Task.isCancelled` before clearing).

## 2026-07-31 — Temp files are grouped per batch, one directory per delivered clip

A clip's toast tells the user when its frames disappear, so delivering a second clip a minute
later must not quietly move the first one's deadline out to match. Two timers over one shared
directory couldn't honour that either: every clip numbers its frames from zero, so the second
clip's `frame-000.jpg` overwrites the first's, and then the first's deadline deletes the
second's frames. `TempFileManager` therefore opens a fresh batch directory on every
`scheduleCleanup`, and each batch's deletion task closes over its own directory. The promise
made on screen is per clip, so the unit of deletion is per clip.

## 2026-07-31 — Batch pruning compares .path, not URL equality

`removeBatch` pruned `writtenURLs` by comparing `$0.deletingLastPathComponent()` against the
batch directory, and the comparison silently never matched:
`deletingLastPathComponent()` always returns a directory-flagged URL (trailing slash), while
`batchDir` never picked one up, since `appendingPathComponent(_:)` defaults a component to
non-directory. Two URLs naming the same path that don't compare equal. Comparing `.path` on
both sides strings the trailing slash away.

Disk state looked correct throughout — the files really were deleted, only the bookkeeping
list lagged — which is why `testCurrentSessionURLsPrunesExpiredBatch` exists as a separate
test from `testEachBatchExpiresOnItsOwnDeadline`. The disk-state test passes either way.

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

## 2026-07-31 — confirmSelection() is a deliberate stub pending Task 6 (superseded — Task 6 landed; see "Rewind clips go to the clipboard as file URLs" above)

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
since June.

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
menu bar keeping its own toggles.

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
