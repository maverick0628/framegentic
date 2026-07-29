# Shortcut customization — design

Date: 2026-07-29
Status: approved

## Problem

The capture hotkey is hardcoded. `HotKeyConfig` exposes `keyCode`, `carbonModifiers`,
`menuKeyEquivalent` and `menuModifiers` as `let` stored properties fixed at ⌘⇧6, and
`HotKeyManager.register()` reads `HotKeyConfig.standard` directly. On a Touch Bar Mac
⌘⇧6 belongs to the system screenshot shortcut, so registration fails and the app's only
remedy is a disabled menu item that says so. There is no way to pick a different combo.

## Goal

Let the user record any shortcut, persist it, and have both the global hotkey and the
menu item follow it. Reject combos that would be useless or hostile before they are
saved, and never save one that failed to register.

## Non-goals

Multiple shortcuts, per-action bindings, sync across machines, import/export, and a
shortcut for anything other than capture. The app has one action; this gives that one
action a configurable trigger. Nothing else.

## Architecture

The shortcut becomes a value. `ClaudeShotKit` owns the value type, its validation and
its persistence as pure logic. The app target owns the recorder view, the settings
window and Carbon registration.

```
ClaudeShotKit (unit tested)
  HotKeyConfig       value type + derived display/menu representations
  HotKeyValidator    baseline modifier rule + reserved-combo blocklist
  KeyCodeNames       keyCode → glyph
  HotKeyStore        UserDefaults load/save with fallback

ClaudeShot (AppKit/SwiftUI glue)
  SettingsModel            @Observable single source of truth
  ShortcutRecorderField    NSView capture + NSViewRepresentable wrapper
  SettingsView             SwiftUI content
  SettingsWindowController NSWindow + NSHostingController
  HotKeyManager            register(_:) / unregister()
  AppDelegate              owns model, rebuilds menu, opens settings
```

### `HotKeyConfig` (modified)

`keyCode` and `carbonModifiers` stay the stored source of truth, because that pair is
exactly what `RegisterEventHotKey` consumes. Everything else derives.

```swift
public struct HotKeyConfig: Sendable, Equatable, Codable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32)

    public static let `default` = HotKeyConfig(
        keyCode: UInt32(kVK_ANSI_6),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    public var menuModifiers: NSEvent.ModifierFlags { get }
    public var menuKeyEquivalent: String { get }
    public var displayString: String { get }
}
```

`standard` is renamed `default` and every call site updated. Carbon virtual keycodes and
`NSEvent.keyCode` share the same `kVK_*` space, so no conversion is needed between the
recorder and the registration call.

`displayString` renders modifiers in canonical ⌃⌥⇧⌘ order regardless of the order they
were pressed, then the key glyph.

`menuKeyEquivalent` follows AppKit convention: lowercase base character with the shift
flag carried in `menuModifiers`, function keys as their `NSF1FunctionKey`-style unicode
constants, and the special keys as `\r`, `\t`, `" "`, `\u{8}`, `\u{1b}` and the
`NSUpArrowFunctionKey` family.

### `HotKeyValidator` (new)

```swift
public enum HotKeyRejection: Equatable, Sendable {
    case missingRequiredModifier
    case reserved(owner: String)
}

public enum HotKeyValidation: Equatable, Sendable {
    case valid
    case rejected(HotKeyRejection)
}

public enum HotKeyValidator {
    public static func validate(_ config: HotKeyConfig) -> HotKeyValidation
}
```

Two rules, in order.

**Baseline modifier rule.** At least one of ⌘, ⌃, ⌥ must be present. Shift alone (or no
modifier at all) would fire while typing, so those are rejected with
`.missingRequiredModifier`.

**Reserved-combo blocklist.** A static table of combos with the name of what owns each:

| Combo | Owner shown |
|---|---|
| ⌘Space, ⌥⌘Space | Spotlight, Finder search |
| ⌃⌘Space | Emoji & Symbols |
| ⌃Space | Input source switching |
| ⌘Tab, ⌘⇧Tab | App switcher |
| ⌘Q, ⌘W, ⌘H, ⌘M | Quit, Close window, Hide, Minimise |
| ⌘⇧3, ⌘⇧4, ⌘⇧5 | Screenshot |
| ⌃↑, ⌃↓, ⌃←, ⌃→ | Mission Control and Spaces |
| ⌥⌘Esc | Force Quit |
| ⌃⌘Q | Lock Screen |

The ⌘Q/W/H/M entries are app-level menu equivalents rather than global hotkeys, so
`RegisterEventHotKey` would happily accept them. They are blocked anyway — a global ⌘Q
that screenshots instead of quitting is a trap.

**⌘⇧6 is deliberately absent from the list.** It is the Touch Bar screenshot shortcut,
but only on Touch Bar Macs, and it is this app's own default. A validator that rejects
its own default is incoherent. On the machines where it is genuinely taken,
`RegisterEventHotKey` fails and the registration path reports it.

The blocklist exists to produce a better error message than "already taken", not to be
authoritative. It cannot know about third-party apps and it will drift with each macOS
release. `RegisterEventHotKey` is the real gate; the list is a courtesy in front of it.

### `KeyCodeNames` (new)

`displayString(for:)` resolves in order:

1. Non-printing key table — `↩ ⇥ ␣ ⌫ ⎋ ← ↑ → ↓`, `F1`–`F20`. Pure, tested.
2. `UCKeyTranslate` against the current keyboard layout, so a Dvorak or AZERTY board
   shows the letter actually engraved on the key.
3. US-ANSI fallback table, for when `TISCopyCurrentKeyboardLayoutInputSource` returns
   nothing — which happens in headless CI. Pure, tested.
4. `"Key \(keyCode)"` as a last resort, so the UI degrades to something legible rather
   than blank.

Step 2 depends on live system state and is not unit tested. Steps 1 and 3 are.

### `HotKeyStore` (new)

```swift
public struct HotKeyStore {
    public init(defaults: UserDefaults = .standard)
    public func load() -> HotKeyConfig
    public func save(_ config: HotKeyConfig)
}
```

JSON blob under a single key. `load()` returns `HotKeyConfig.default` when the key is
unset **or** when decoding fails. `defaults` is injectable so tests use a scratch suite.

No migration path is needed: existing installs have nothing stored, so they load the
default and stay on ⌘⇧6 exactly where they are today.

## Recording

`ShortcutRecorderField` is an `NSView` wrapped in `NSViewRepresentable`, not a native
SwiftUI view, because two behaviours have to be intercepted that SwiftUI does not
expose.

**`performKeyEquivalent(with:)` must be overridden, not just `keyDown`.** AppKit routes
⌘-modified key events down the key-equivalent chain, so a recorder that only implements
`keyDown` never sees any combo containing ⌘ — which is most of them. `NSWindow` walks its
content view's `performKeyEquivalent` before the main menu gets a look, so returning
`true` while recording takes the event.

**The global hotkey must be unregistered while recording.** `RegisterEventHotKey`
installs on the application event target and consumes its combo before AppKit dispatch
happens at all. With ⌘⇧6 live you could never re-record ⌘⇧6 — pressing it would fire a
screenshot instead of registering a keystroke. `HotKeyManager` therefore gains
`unregister()`, and entering record mode brackets itself with unregister / re-register
so the old shortcut is restored whether the user commits or cancels.

`flagsChanged` drives a live "⌘⇧…" preview while modifiers are held. Escape cancels
recording rather than being recorded. Clicking away cancels and commits nothing.

Recording commits on the first non-modifier key-down — there is no confirm button. That
keystroke runs the full validate → register → save path immediately, and the field either
shows the new shortcut or stays on the old one with an error beneath it.

## Settings window

**Settings…** in the menu opens a single ~380pt window: `NSWindow` hosting a SwiftUI
`SettingsView` through `NSHostingController`. One instance, reused; reopening brings the
existing window forward.

Contents: the recorder field, a **Reset to Default** button, and the Auto-send and
Start-at-login toggles.

**Reset to Default** takes the same validate → register → save path as a recording rather
than only repopulating the field, so it can fail and report like any other combo — which
is exactly what happens on a Touch Bar Mac, where ⌘⇧6 is unavailable. It is disabled when
the current config already equals the default.

Those two toggles **also stay in the menu bar**. Both surfaces read and write a single
`@Observable SettingsModel` held by `AppDelegate` — menu actions mutate the model rather
than touching `UserDefaults` directly, and the model writes through to storage. The menu
is rebuilt from the model on every open via the existing `menuNeedsUpdate`, and the
window binds to it, so the two views cannot drift.

Start-at-login is external state (`SMAppService.mainApp.status`) and not observable. The
model refreshes it when the window appears and after each toggle.

Menu after the change: Screenshot → Claude (key equivalent tracking the live config),
Settings…, Auto-send, Start at Login, the permission grant items, About, Quit.

## Failure paths

**Recorded combo is rejected by the validator.** Previous shortcut stays registered.
Inline text names the owner — "⌘Space is Spotlight". Nothing is saved.

**Recorded combo passes validation but `RegisterEventHotKey` fails.** The previous
shortcut is re-registered, inline text reads "already taken by another app", nothing is
saved. Registration succeeding is the precondition for persisting, in that order — the
store is never written with a shortcut that does not work.

**Saved shortcut fails to register at launch**, because another app claimed it since.
The existing "Hotkey unavailable" menu item becomes *enabled* and opens Settings when
clicked, and its copy names the actual configured shortcut instead of today's hardcoded
"⌘⇧6".

**Stored blob is corrupt.** Silently falls back to ⌘⇧6.

## Testing

New suites in `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift`:

- `HotKeyConfig` — `Codable` round-trip; `.default` still asserts ⌘⇧6, keeping the
  existing test's guarantee so the default cannot drift silently; modifier mapping in
  both directions across empty, single and all-four cases; canonical ⌃⌥⇧⌘ display order
  from deliberately scrambled input.
- `HotKeyValidator` — rejects no modifier and shift-only with
  `.missingRequiredModifier`; rejects each blocklist family with the right `owner`;
  accepts ⌥⇧C and other ordinary combos; **accepts `HotKeyConfig.default`**, which is
  the self-consistency trap that catches anyone later adding ⌘⇧6 to the blocklist.
- `KeyCodeNames` — non-printing glyph table and US-ANSI fallback table.
- `HotKeyStore` — returns default when unset, round-trips a saved config, returns
  default on a corrupt blob.

`ShortcutRecorderField`, `SettingsView` and `SettingsWindowController` stay untested,
consistent with how the app target is structured today — `ClaudeShotKit` holds the
decisions, `ClaudeShot` holds the glue.

## Files

New:

- `Sources/ClaudeShotKit/HotKeyValidator.swift`
- `Sources/ClaudeShotKit/KeyCodeNames.swift`
- `Sources/ClaudeShotKit/HotKeyStore.swift`
- `Sources/ClaudeShot/SettingsModel.swift`
- `Sources/ClaudeShot/ShortcutRecorderField.swift`
- `Sources/ClaudeShot/SettingsView.swift`
- `Sources/ClaudeShot/SettingsWindowController.swift`

Modified:

- `Sources/ClaudeShotKit/HotKeyConfig.swift` — configurable value type, derived
  representations, `standard` → `default`
- `Sources/ClaudeShot/HotKeyManager.swift` — `register(_ config:)`, `unregister()`
- `Sources/ClaudeShot/AppDelegate.swift` — owns `SettingsModel`, menu reflects live
  config, Settings… item, clickable unavailable-hotkey item
- `Tests/ClaudeShotKitTests/ClaudeShotKitTests.swift` — new suites
- `README.md` — document customization, update the ⌘⇧6 troubleshooting entry
