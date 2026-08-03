# Hammerspoon config (live)

Personal macOS automation loaded by Hammerspoon from `~/.hammerspoon/`.
Window layouts, hotkeys, Operations Console, and AI/terminal helpers.

**Run:** Hammerspoon loads this folder automatically. Reload with `⌘⌃R` (or save a file — path watcher).
**Guide:** `⌘⌃H` or open `docs/USER_GUIDE.html`.
**First change (simple):** follow `docs/HOW_TO_MAKE_A_CHANGE.md`.
**Verify:** in the Hammerspoon Console run `require('modules.verify').run()`.

## Where things live

- `init.lua` + `modules/` + `Spoons/` — app code (must stay at root; Hammerspoon convention)
- `scripts/` — shell / AppleScript helpers (Ghostty ops center)
- `docs/` — user guide, tuning notes, operations docs
- `runtime/` — machine-written status JSON (gitignored)
- `archive/` — old backups and superseded files

Layout rules for editors/agents: see `AGENTS.md`.
