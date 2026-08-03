# AGENTS.md — Repository layout rules

This is a live Hammerspoon (macOS automation, Lua) configuration. `init.lua`,
`modules/`, and `Spoons/` MUST stay at the root — Hammerspoon loads them from
`~/.hammerspoon/` by convention. Do not move them into `src/` or `app/`.

## Folder model

| Folder     | Contents |
|------------|----------|
| `modules/` | Application code (Lua modules, loaded via `require('modules.name')` — no `.lua` extension) |
| `Spoons/`  | Hammerspoon Spoon plugins |
| `scripts/` | Runnable helpers (`.sh`, `.zsh`, `.command`, AppleScript) |
| `docs/`    | Guides, design notes, reports (`USER_GUIDE.html` lives here) |
| `runtime/` | Machine-written status/event JSON — never edit or commit |
| `archive/` | Obsolete files kept for safety, not loaded by anything |
| Root       | Only `init.lua`, `README.md`, `AGENTS.md`, `.gitignore`, `.cursorrules`, `*.code-workspace` |

## Rules

- Prefer moving/editing existing files over creating new ones.
- No new top-level folders without asking the owner first.
- No filename versioning (`foo_v1.0.md`, `*.bak`); superseded files go to `archive/`.
- Never commit secrets or runtime state (`runtime/`, `.reload-trigger`).
- Folder names stay English; file content may be Portuguese or English.
- After moving any file, grep for its old path in `*.lua`, `scripts/`, and
  `docs/USER_GUIDE.html` and fix references.
