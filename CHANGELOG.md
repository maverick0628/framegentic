# Changelog

## v1.0.0 — 2026-08-01

First release.

Framegentic puts a screenshot into an AI chat in one keypress. Press `⇧⌘6`, paste.
No save dialog, no file left on the Desktop to clean up afterwards.

**Clipboard is the default target.** The capture lands on your clipboard and stops
there. That works with any chat UI, and it means the app never asks for
Accessibility permission. Point delivery at Claude instead and Framegentic
activates the app and pastes for you, re-checking that the target is frontmost
before every keystroke so a capture cannot land in the wrong window. Sending stays
manual unless you turn on **Send Automatically After Paste**.

**No network code.** Not a policy, a property of the binary. There is nothing in it
that opens a socket, no telemetry, no analytics, no update check, no crash
reporting. Check for yourself:

```bash
otool -L /Applications/Framegentic.app/Contents/MacOS/Framegentic | grep -i -E 'network|curl|http'
```

**The shortcut is yours.** `⇧⌘6` out of the box, rebindable from Settings with a
recorder that refuses combinations macOS has already claimed.

### Requirements

macOS 14 or later. Screen Recording, prompted at first launch — the first capture
after granting it fails, so press the hotkey again. Accessibility only if you pick a
delivery target that pastes for you.

### Install

Download the zip, unzip it and move `Framegentic.app` to `/Applications`. The build
is signed with Developer ID and notarized, so Gatekeeper opens it without argument.
Verify the download against the published checksum:

```bash
shasum -a 256 -c Framegentic-1.0.0.zip.sha256
```

### Not in this release

Rewind — a rolling buffer of the last few minutes with a scrubber to trim and send a
clip — is built and switched off. The buffer works. The delivery format is what
didn't: a clip arrives as a strip of thumbnails, which carries less than one
well-chosen screenshot. The code and its tests stay in the tree behind a flag.

There is no region select, no annotation and no history. Framegentic captures the
full main display and does one thing with it. If you want a general screenshot tool,
use a real one.

MIT licensed. Not affiliated with or endorsed by Anthropic. "Claude" is Anthropic's
trademark; this is an independent tool that works with their desktop app.
