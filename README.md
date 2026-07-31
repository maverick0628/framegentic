# ClaudeShot — one-hotkey screenshots into Claude

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14%2B-000000)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138)](Package.swift)
[![Tests](https://img.shields.io/badge/tests-34-brightgreen)](Tests/)
[![Network](https://img.shields.io/badge/network%20code-none-success)](#privacy)

A free, open-source **macOS menu bar app** that captures your screen and drops it
straight into the **Claude desktop app**. One hotkey grabs the screen, copies it
to the clipboard, switches to Claude and pastes. No save dialog, no Finder, no
drag and drop.

**Before:** press ⇧⌘4, drag a region, find the file on the Desktop, drag it into
Claude, wait, delete the file.
**After:** press one key.

It sends nothing anywhere. There is no network code in the binary at all — it
captures, copies and types. See [Privacy](#privacy).

> Not affiliated with or endorsed by Anthropic. "Claude" is Anthropic's
> trademark; this is an independent tool that works with their desktop app.

## How it works

Press `⇧⌘6` (or pick **Screenshot → Claude** from the menu bar). ClaudeShot:

1. Captures your main display with ScreenCaptureKit at its native scale.
2. Writes the image to the clipboard as PNG, marked concealed so clipboard managers and Handoff skip it.
3. Activates Claude, launching it if needed, and waits until it's actually frontmost.
4. Pastes with a simulated `⌘V` — only after verifying Claude has focus. If anything else grabbed focus, it aborts and tells you.

Sending is manual by default: review the screenshot, press Return yourself. Turn on **Send Automatically After Paste** in the menu if you want the old one-keystroke flow. The clipboard is cleared a few seconds after delivery so the screenshot doesn't linger.

## Changing the shortcut

Open **Settings…** from the menu bar, click the shortcut field and press the combo you
want. It takes effect immediately and survives a relaunch.

A shortcut needs at least one of ⌘, ⌃ or ⌥ — Shift alone would fire while you type.
ClaudeShot also refuses a short list of combos macOS owns, naming the owner when it
does, and refuses anything the system will not hand over. Nothing is saved unless it
registers, so you cannot end up with a shortcut that silently does nothing.

**Reset to Default** goes back to ⇧⌘6. On a Touch Bar Mac that combo belongs to the
system screenshot shortcut, so the reset will be refused there — pick something else.

It runs as a background accessory (`LSUIElement`), so there's no Dock icon, just a menu bar item.

## Privacy

One hotkey puts your whole screen in front of Claude. Before you press it, know what that means:

- Everything visible gets captured — passwords, messages, notifications, all of it.
- The screenshot replaces whatever was on your clipboard. ClaudeShot clears it a few seconds after pasting.
- With auto-send on, the image reaches Anthropic's servers the moment Return fires. There's no undo.

ClaudeShot itself sends nothing anywhere. It has no network code — it captures, copies and types.

There is no telemetry, no analytics, no update check and no crash reporting. The
binary links nothing that opens a socket. You can verify that claim rather than
take it on trust:

```bash
otool -L /Applications/ClaudeShot.app/Contents/MacOS/ClaudeShot | grep -i -E 'network|curl|http'
```

## How it compares

| | ClaudeShot | macOS ⇧⌘4 | CleanShot X / Shottr |
|---|---|---|---|
| Screenshot to Claude | one keypress | 5 steps via Desktop | 3–4 steps via clipboard |
| Region select, annotation | **no** | yes | yes |
| Screenshot history | **no** | Desktop files | yes |
| Price | free, MIT | built in | paid / freemium |
| Sends data anywhere | never | never | varies |

This is deliberately not a general screenshot tool. It captures the full main
display and does exactly one thing with it. If you want region select,
annotation or a history, use a real screenshot app — they are better at it, and
this is not trying to compete.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode or Command Line Tools)
- The Claude desktop app

ClaudeShot needs two permissions:

- **Screen Recording** — prompted at first launch. The first capture after granting fails; press the hotkey again.
- **Accessibility** — prompted the first time it pastes.

Grant both in System Settings → Privacy & Security, then quit and relaunch ClaudeShot. Neither takes effect on a running app. The menu bar shows **Grant…** shortcuts while either is missing.

## Build

```bash
./scripts/build.sh
```

This compiles a release build, bundles and signs `ClaudeShot.app` into `.build/`. It signs with your Apple Development certificate if you have one (ad-hoc signatures reset the permission grants on every rebuild), falling back to ad-hoc. To install:

```bash
rm -rf /Applications/ClaudeShot.app && cp -R .build/ClaudeShot.app /Applications/ && open /Applications/ClaudeShot.app
```

A plain `swift build -c release` compiles the binary but skips the bundle — permissions won't stick to an unbundled binary, so use `build.sh` for anything you actually run.

There's no App Store version and there won't be: simulated keystrokes can't live inside the App Store sandbox. Signed and notarized releases come from CI on version tags — see [docs/RELEASING.md](docs/RELEASING.md).

## Troubleshooting

**Hotkey does nothing** — Screen Recording isn't granted, or the shortcut is taken by something else (on Touch Bar Macs the default `⇧⌘6` is the system's Touch Bar screenshot shortcut). The menu says so and the warning opens Settings, where you can pick another. The menu item works regardless.

**Screenshot lands on the clipboard but never pastes** — Accessibility isn't granted. Grant it, quit and relaunch.

**Worked, then stopped after a rebuild** — ad-hoc signatures change every build, which invalidates permission grants. Build with an Apple Development certificate (the default when one exists) or re-grant both permissions.

**"Another app took focus"** — something stole focus before the paste fired. Your screenshot is still on the clipboard; paste it manually with `⌘V`.

Logs: `log stream --predicate 'subsystem == "com.duncansmith.claudeshot"'`, or filter the subsystem in Console.app.

## Uninstall

Quit ClaudeShot from the menu bar, then:

```bash
rm -rf /Applications/ClaudeShot.app && tccutil reset ScreenCapture com.duncansmith.claudeshot && tccutil reset Accessibility com.duncansmith.claudeshot
```

The `tccutil` calls remove the permission grants. Skip them if you plan to reinstall.

## Structure

```
Sources/ClaudeShotKit/    Pure decision logic (display selection, capture geometry,
                          Claude resolution, paste guard, hotkey config, validation
                          and persistence) — unit tested
Sources/ClaudeShot/       AppKit glue: menu bar, capture, activation, keystrokes
Tests/ClaudeShotKitTests/ The kit's test suite
Resources/                Info.plist, app and menu bar icons
scripts/                  build.sh and icon generators
docs/                     Release process
```

## Notes

ClaudeShot captures the full main display only. There's no region select, no multi-monitor picker and no history. It's a single-purpose shortcut, not a general screenshot tool. Issues and PRs welcome — keep it single-purpose.
