# Framegentic — Public Release Sweep

**Status:** in progress, 2026-08-01
**Goal:** get the repo ready to be flipped public, following the pattern used for
CipherGate and the other four OSS repos (audit → fix → verify on a fresh clone).

The audit is done. What it found, and what each finding costs if shipped as-is:

| # | Finding | Risk |
|---|---|---|
| 1 | GitHub description still advertises Rewind — "or rewind and send the last two minutes" | **Real.** First thing a visitor reads, and it promises a feature that is switched off. |
| 2 | Topics include `rewind` and `screen-recording` | Same, on the discovery surface. |
| 3 | `.claude/` is ignored only by `.git/info/exclude`, `.letta/` only by a global gitignore — neither is in the repo's `.gitignore` | **Real.** Both are local-only. A contributor cloning the public repo gets them tracked. Same class as the CipherGate CI gotcha: passes here, breaks on a fresh clone. |
| 4 | PLAN.md carried 7 absolute paths into `/Users/duncansmith/repos/framesnap`, a private repo | Reader-hostile — dead paths to a 404 — plus it leaks the local tree layout. |
| 5 | CI pins no toolchain | **Real.** SDK drift has broken this build twice. Public repo means contributor PRs, and they would hit it blind. |
| 6 | No release artifacts in `.gitignore` (`cert.p12`, `key.p8`, `*.zip`) | Low but cheap. Release steps write a signing cert and an ASC key to the repo root. |

Clean, and deliberately left alone:

- **No secrets, ever.** Full-history scan found none. Every `secrets.*` hit is a GitHub Actions secret *name*, which is what it should be.
- **No personal email in history.** Authors are `26542471+maverick0628@users.noreply.github.com` only.
- **LICENSE** is MIT and matches what the README claims.
- **`com.duncansmith.framegentic`** stays. A reverse-DNS bundle ID is an identifier, not a leak, and changing it resets every user's TCC grant.
- **DECISIONS.md and `docs/superpowers/specs/` keep their FrameSnap and ClaudeShot references.** Dated history, and the merge spec's trademark section is the record of the rename being reasoned about rather than stumbled into. Renaming history would be dishonest; the CipherGate sweep drew the same line.

---

## Tasks

- [ ] **1. Fix the GitHub description and topics** — drop the Rewind clause, drop `rewind` and `screen-recording`.
- [ ] **2. Close the `.gitignore` gaps** — `.claude/`, `.letta/`, and the release artifacts. Verify by fresh clone, not by `git status` here.
- [ ] **3. Clear the executed Rewind plan from PLAN.md** — done as part of writing this file. Its Completed summary is the archive, the design spec holds the reasoning, and git history holds the rest.
- [ ] **4. Pin the CI toolchain** — `maxim-lobanov/setup-xcode` at a fixed version, so a contributor's PR fails for their reasons and not the runner's.
- [ ] **5. Verify on a fresh clone** — clone from the remote into a temp dir, build, test, bundle. This is the check that catches ignore-rule mistakes; nothing local can.
- [ ] **6. Flag what needs Duncan** — the six release secrets, the fresh-VM gate, and the visibility flip itself.

**Not doing without a decision:** rewriting history to remove the ClaudeShot name. It appears in old file paths and commit messages. Low risk — nominative use, and the rename is documented — but it is Duncan's call, and history rewrites on this account have gone badly before.

---

## Outstanding — manual GUI checks

Nothing here has been verified. The app target has no unit tests by design, so these are the only
checks that can confirm the built app behaves.

Rewind is disabled (`SettingsModel.isRewindAvailable = false`), so the checks below are what
"off" should look like — its feature checklist is archived with the completed plan.

- [ ] Settings shows no Rewind section at all — no toggle, no duration control, no second recorder
- [ ] The menu bar shows no "Rewind hotkey unavailable" warning
- [ ] ⇧⌘7 does nothing in Framegentic and is free for another app to claim
- [ ] The menu bar icon never enters the buffering state
- [ ] Snap captures and delivers to Clipboard only, with no Accessibility prompt
- [ ] Snap captures, activates and pastes with Claude selected; auto-send submits
- [ ] Recording a new Snap shortcut works, takes effect immediately and survives relaunch
- [ ] **Reset to Default** returns to ⇧⌘6
- [ ] Start at login toggles and reports its real state

One known-correct behaviour, so it is not mistaken for a bug: a stored `BufferEnabled = true` from
an older build reads as off and stays stored — flipping `isRewindAvailable` back restores it.

---

## Completed

**2026-07-31 — ClaudeShot → Framegentic reference sweep.** Everything outside the
repo that still pointed at the old name. Two Claude Code memory files renamed with
all four parts each — filename, `name:` frontmatter, `MEMORY.md` pointer and
`[[wikilink]]` — plus the knowledge-sync state keys that indexed them, the portfolio
card in `digital-landscape/landscape.html`, and the vault's archived project note,
whose `project-path` pointed at the dead `~/repos/claudeshot` and whose banner still
claimed the GitHub repo was archived read-only.

The rule that shaped it: rename the product name, never bare "Claude" where it means
Anthropic's app, and never rewrite dated history. That last one mattered more than
expected. Two live automations string-match `**ClaudeShot**` against real archive
data — the `/eod` skill's test fixtures and a one-time dedupe verification task — so
renaming them would have broken a passing test and a scheduled check. Session
transcripts, RoutineLog, RSS digests and dated session-close reports were left as
written for the same reason.

Left for Duncan: a stale `ClaudeShot` login item sitting beside the live Framegentic
one, and whether the vault note should come out of `Archive/` now the project is
active again. The old `/Applications/ClaudeShot.app` turned out to be in `~/.Trash`
already, trashed 2026-07-29.

**2026-07-31 — Rewind mode.** Seven tasks via subagent-driven development. Ported
FrameSnap's buffer, perceptual hashing, image pipeline and temp-file lifecycle into
the kit; added buffer settings off by default, the continuous capture loop, a second
hotkey, the scrubber popover, and clip delivery. 74 kit tests.

Four of seven tasks needed fix rounds, and the same failure shape recurred three
times: a guard placed where it could not see a second caller. Task 3's serialisation
sat in `AppDelegate` while `didStopWithError` bypassed it; Task 6's in-flight flag
sat in the view model while the delivery detached; and the final review found the
flag was per-instance while the contended state — the system pasteboard — is global,
letting a Snap destroy an in-flight clip's URLs and submit two messages. Spec:
`docs/superpowers/specs/2026-07-31-framegentic-merge-design.md`.


**2026-07-31 — Framegentic rename and delivery targets.** Seven tasks executed via
subagent-driven development, merged as PR #4. The app is renamed, delivery is a
chosen target, and clipboard-only is the default — so Accessibility is now opt-in.
A final whole-branch review caught a critical bug no per-task review could see: the
clipboard-only path inherited a 3-second clipboard wipe from the auto-paste path,
destroying the capture before the user could paste it. Fixed, with six lesser
findings. 42 kit tests. Spec:
`docs/superpowers/specs/2026-07-31-framegentic-merge-design.md`.

**2026-07-29 — Shortcut customization.** Nine tasks. Shipped `KeyCodeNames`,
`HotKeyConfig` as a value type, `HotKeyValidator` (20 reserved combos),
`HotKeyStore`, a configurable `HotKeyManager`, `SettingsModel`,
`ShortcutRecorderField` and the settings window. Spec:
`docs/superpowers/specs/2026-07-29-shortcut-customization-design.md`.
