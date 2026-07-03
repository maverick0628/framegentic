# ClaudeShot

A macOS menu bar app that captures your screen and drops it straight into the Claude desktop app. One hotkey grabs the screen, copies it to the clipboard, switches to Claude and pastes. No save dialog, no drag and drop.

## How it works

Press `⌘⇧6` (or pick **Screenshot → Claude** from the menu bar). ClaudeShot:

1. Captures your main display with ScreenCaptureKit at its native scale.
2. Writes the image to the clipboard as PNG, marked concealed so clipboard managers and Handoff skip it.
3. Activates Claude, launching it if needed, and waits until it's actually frontmost.
4. Pastes with a simulated `⌘V` — only after verifying Claude has focus. If anything else grabbed focus, it aborts and tells you.

Sending is manual by default: review the screenshot, press Return yourself. Turn on **Send Automatically After Paste** in the menu if you want the old one-keystroke flow. The clipboard is cleared a few seconds after delivery so the screenshot doesn't linger.

It runs as a background accessory (`LSUIElement`), so there's no Dock icon, just a menu bar item.

## Privacy

One hotkey puts your whole screen in front of Claude. Before you press it, know what that means:

- Everything visible gets captured — passwords, messages, notifications, all of it.
- The screenshot replaces whatever was on your clipboard. ClaudeShot clears it a few seconds after pasting.
- With auto-send on, the image reaches Anthropic's servers the moment Return fires. There's no undo.

ClaudeShot itself sends nothing anywhere. It has no network code — it captures, copies and types.

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

**Hotkey does nothing** — Screen Recording isn't granted, or `⌘⇧6` is taken (on Touch Bar Macs it's the system's Touch Bar screenshot shortcut — the menu will say so). The menu item works regardless.

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
                          Claude resolution, paste guard, hotkey config) — unit tested
Sources/ClaudeShot/       AppKit glue: menu bar, capture, activation, keystrokes
Tests/ClaudeShotKitTests/ The kit's test suite
Resources/                Info.plist, app and menu bar icons
scripts/                  build.sh and icon generators
docs/                     Release process
```

## Notes

ClaudeShot captures the full main display only. There's no region select, no multi-monitor picker and no history. It's a single-purpose shortcut, not a general screenshot tool. Issues and PRs welcome — keep it single-purpose.
