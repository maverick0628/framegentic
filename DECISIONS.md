# Decisions

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
