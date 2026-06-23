# ClaudeShot

A macOS menu bar app that captures your screen and drops it straight into the Claude desktop app. One hotkey grabs the screen, copies it to the clipboard, switches to Claude, pastes and hits return. No save dialog, no drag and drop.

## How it works

Press `⌘⇧6` (or pick **Screenshot → Claude** from the menu bar). ClaudeShot:

1. Captures the main display with ScreenCaptureKit at 2x resolution.
2. Writes the image to the clipboard.
3. Activates the Claude app, launching it from `/Applications/Claude.app` if it isn't running.
4. Simulates `⌘V` then `Return` to paste and send.

It runs as a background accessory (`LSUIElement`) so there's no Dock icon, just a menu bar item.

## Requirements

- macOS 14 or later
- Swift 5.9 toolchain (Xcode or Command Line Tools)
- The Claude desktop app at `/Applications/Claude.app`

ClaudeShot needs two permissions, both prompted on first run:

- **Screen Recording** — to capture the display
- **Accessibility** — to send the paste and return keystrokes

Grant them in System Settings → Privacy & Security, then relaunch.

## Build

```bash
./scripts/build.sh
```

This compiles a release binary, bundles `ClaudeShot.app` and ad-hoc signs it. To install:

```bash
cp -R ClaudeShot.app /Applications/
open /Applications/ClaudeShot.app
```

For a plain build without the app bundle:

```bash
swift build -c release
```

## Structure

```
Sources/ClaudeShot/
  main.swift              NSApplication bootstrap (accessory mode)
  AppDelegate.swift       Menu bar, capture → paste → send orchestration
  ScreenshotService.swift ScreenCaptureKit display capture to clipboard
  HotKeyManager.swift     Carbon global hotkey (⌘⇧6)
Resources/                Info.plist, app and menu bar icons
scripts/                  build.sh and icon generators
```

## Notes

ClaudeShot captures the full main display only. There's no region select, no multi-monitor picker and no history. It's a single-purpose shortcut, not a general screenshot tool.
