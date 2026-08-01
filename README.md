# Framegentic — screenshots straight into your AI

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14%2B-000000)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138)](Package.swift)
[![Tests](https://img.shields.io/badge/tests-74-brightgreen)](Tests/)
[![Network](https://img.shields.io/badge/network%20code-none-success)](#privacy)

A free, open-source **macOS menu bar app** that captures your screen and gets
it to an AI in one keypress. One hotkey grabs the screen and copies it to the
clipboard. No save dialog, no Finder, no drag and drop.

Clipboard is the default delivery target — paste the capture wherever you're
chatting. Point delivery at Claude instead and Framegentic activates the app
and pastes it there for you.

**Before:** press ⇧⌘4, drag a region, find the file on the Desktop, drag it into
Claude, wait, delete the file.
**After:** press one key, paste anywhere.

It sends nothing anywhere. There is no network code in the binary at all — it
captures, copies to the clipboard and, for targets that auto-paste, types. See
[Privacy](#privacy).

> Not affiliated with or endorsed by Anthropic. "Claude" is Anthropic's
> trademark; this is an independent tool that works with their desktop app.

## How it works

Press `⇧⌘6` (or pick the capture item from the menu bar — it reads **Capture
to Clipboard** or **Capture → Claude**, matching your current delivery
target). Framegentic:

1. Captures your main display with ScreenCaptureKit at its native scale.
2. Writes the image to the clipboard as PNG, marked concealed so clipboard managers and Handoff skip it.

That's the whole flow for **Clipboard only**, the default: the menu bar icon ticks for a second to confirm, and the capture is ready to paste anywhere. Pick a target that auto-pastes (Claude, today) and two more steps happen automatically:

3. Activates the target app, launching it if needed, and waits until it's actually frontmost.
4. Pastes with a simulated `⌘V` — only after verifying the target app has focus. If anything else grabbed focus, it aborts and tells you.

Sending is manual even then: review the screenshot, press Return yourself. Turn on **Send Automatically After Paste** in Settings if you want a one-keystroke flow. Once the paste lands, the clipboard is cleared a few seconds later so the screenshot doesn't linger — unless something else has copied over it in the meantime.

## Delivery targets

Where a capture goes is a setting, not a fixed behavior — pick it from **Deliver to** in Settings.

**Clipboard only** is the default. Nothing gets activated and nothing gets pasted; the capture sits on the clipboard until you paste it yourself, into whatever has focus. The menu bar icon flashes a tick so you know the shortcut fired. That buys you three things:

- No Accessibility permission. Framegentic never asks for it unless you choose a target that pastes.
- Works with every chat UI there is, not just the ones Framegentic knows about.
- Nothing can steal your focus mid-capture, because nothing gets activated.

**Claude** is the one auto-paste target today. Pick it and Framegentic activates the Claude desktop app, waits for it to come to the front and pastes for you — turn on **Send Automatically After Paste** if you want it submitted too. Adding another target — ChatGPT, Cursor, whatever's next — is a table entry, not a rewrite.

## Changing the shortcut

Open **Settings…** from the menu bar, click the shortcut field and press the combo you
want. It takes effect immediately and survives a relaunch.

A shortcut needs at least one of ⌘, ⌃ or ⌥ — Shift alone would fire while you type.
Framegentic also refuses a short list of combos macOS owns, naming the owner when it
does, and refuses anything the system will not hand over. Nothing is saved unless it
registers, so you cannot end up with a shortcut that silently does nothing.

**Reset to Default** goes back to ⇧⌘6. On a Touch Bar Mac that combo belongs to the
system screenshot shortcut, so the reset will be refused there — pick something else.

It runs as a background accessory (`LSUIElement`), so there's no Dock icon, just a menu bar item.

## Privacy

Framegentic captures your screen one way: a single grab of the main display at
the instant you press the hotkey. Nothing runs between keypresses. Know what
that means before you rely on it:

- Everything visible gets captured — passwords, messages, notifications, all of it.
- How long a capture stays on the clipboard depends on what it is and where it's going. A single Snap replaces whatever was there as image data: an auto-pasting target clears it a few seconds after a successful paste, **Clipboard only** leaves it until you copy something else since the clipboard *is* the delivery, and a failed delivery leaves it too, deliberately, so you can paste it yourself.
- With auto-send on, a capture is submitted the instant Return fires — for Claude, that means it reaches Anthropic's servers. There's no undo.

Framegentic itself sends nothing anywhere. It has no network code — it captures, copies and, for targets that auto-paste, types.

There is no telemetry, no analytics, no update check and no crash reporting. The
binary links nothing that opens a socket. You can verify that claim rather than
take it on trust:

```bash
otool -L /Applications/Framegentic.app/Contents/MacOS/Framegentic | grep -i -E 'network|curl|http'
```

## How it compares

| | Framegentic | macOS ⇧⌘4 | CleanShot X / Shottr |
|---|---|---|---|
| Screenshot to an AI chat | one keypress | 5 steps via Desktop | 3–4 steps via clipboard |
| Region select, annotation | **no** | yes | yes |
| Screenshot history | **no** | Desktop files | yes |
| Price | free, MIT | built in | paid / freemium |
| Sends data anywhere | never | never | varies |

This is deliberately not a general screenshot tool. It captures the full main
display and does exactly one thing with it. If you want region select,
annotation or a browsable history, use a real screenshot app; they are better at
it, and this is not trying to compete.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode or Command Line Tools), to build from source

Framegentic always needs one permission:

- **Screen Recording** — prompted at first launch. The first capture after granting fails; press the hotkey again.

A delivery target that auto-pastes (Claude, today) needs two more things:

- **Accessibility** — prompted the first time it pastes.
- The target app, installed.

**Clipboard only** needs neither of those. That's the whole reason it's the default.

Grant permissions in System Settings → Privacy & Security, then quit and relaunch Framegentic. Neither takes effect on a running app. The menu bar shows **Grant…** shortcuts for whatever's missing — Accessibility's only appears once you've picked a target that needs it.

## Build

```bash
./scripts/build.sh
```

This compiles a release build, bundles and signs `Framegentic.app` into `.build/`. It signs with your Apple Development certificate if you have one (ad-hoc signatures reset the permission grants on every rebuild), falling back to ad-hoc. To install:

```bash
rm -rf /Applications/Framegentic.app && cp -R .build/Framegentic.app /Applications/ && open /Applications/Framegentic.app
```

A plain `swift build -c release` compiles the binary but skips the bundle — permissions won't stick to an unbundled binary, so use `build.sh` for anything you actually run.

There's no App Store version and there won't be: simulated keystrokes can't live inside the App Store sandbox. Signed and notarized releases come from CI on version tags — see [docs/RELEASING.md](docs/RELEASING.md).

## Troubleshooting

**Hotkey does nothing** — Screen Recording isn't granted, or the shortcut is taken by something else (on Touch Bar Macs the default `⇧⌘6` is the system's Touch Bar screenshot shortcut). The menu says so and the warning opens Settings, where you can pick another. The menu item works regardless.

**Picked an auto-paste target but it never pastes** — Accessibility isn't granted. Grant it, quit and relaunch. (Clipboard only never pastes, by design — that's not a bug.)

**Worked, then stopped after a rebuild** — ad-hoc signatures change every build, which invalidates permission grants. Build with an Apple Development certificate (the default when one exists) or re-grant Screen Recording and, if you use an auto-paste target, Accessibility.

**"Another app took focus"** — something stole focus before the paste fired. Your capture is still on the clipboard; paste it manually with `⌘V`.

Logs: `log stream --predicate 'subsystem == "com.duncansmith.framegentic"'`, or filter the subsystem in Console.app.

## Uninstall

Quit Framegentic from the menu bar, then:

```bash
rm -rf /Applications/Framegentic.app && tccutil reset ScreenCapture com.duncansmith.framegentic && tccutil reset Accessibility com.duncansmith.framegentic
```

The `tccutil` calls remove the permission grants. Skip them if you plan to reinstall.

## Structure

```
Sources/FramegenticKit/    Pure decision logic (display selection, capture geometry,
                           app resolution, delivery targets, paste guard, hotkey
                           config, validation, persistence, and the parked ring
                           buffer, dedup and temp-file lifecycle) — unit tested
Sources/Framegentic/       AppKit/SwiftUI glue: menu bar, capture, delivery,
                           settings, parked Rewind popover
Tests/FramegenticKitTests/ The kit's test suite
Resources/                 Info.plist, app and menu bar icons
scripts/                   build.sh and icon generators
docs/                      Release process
```

## Rewind (parked)

An earlier build shipped a second mode: a rolling in-memory buffer of the last
few minutes, with a timeline scrubber to trim a clip and send it. The buffer and
the pipeline work. The delivery format is what didn't — a clip arrives as several
images attached to one chat message, and a strip of thumbnails turns out to be a
poor way to show an agent what happened.

It's disabled rather than deleted. The code and its tests are still in the tree
behind a single flag, so a better answer to "how do you hand an agent a span of
time" can bring it back. Snap is unaffected.

## Notes

Framegentic captures the full main display only. There's no region select, no multi-monitor picker and no history. It's a single-purpose shortcut, not a general screenshot tool. Issues and PRs welcome — keep it single-purpose.
