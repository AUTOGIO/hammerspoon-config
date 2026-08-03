# BlackDragon Operations Console

Phase 1 local operations dashboard for the Hammerspoon BlackDragon automation stack.

## Architecture

```text
USER_GUIDE.html
    ↓ fetch (10s poll) + cache-bust
runtime/operations_status.json
runtime/operations_events.json
    ↑ atomic write
modules/operations_console.lua
    ↓ allowlisted actions only
existing modules (layouts, windows, terminal_ops, verify, guide, …)
```

Browser actions use a **separate** URL scheme from the legacy guide bridge:

```text
hammerspoon://operations/run?action=<allowlisted_action>
```

Existing guide buttons continue to use:

```text
hammerspoon://guide/run?action=...
```

No localhost server is required. Status is read via relative `fetch()` from the same `file://` origin as `USER_GUIDE.html`.

## Files

| Path | Role |
|------|------|
| `modules/operations_console.lua` | Status engine, event log, URL handler |
| `runtime/operations_status.json` | Live health snapshot |
| `runtime/operations_events.json` | Bounded event stream (max 200) |
| `docs/USER_GUIDE.html` | Operations Console UI + preserved guide |
| `init.lua` | Starts console on load |

## Status schema

Top-level fields:

- `schema_version` — integer schema revision (`2` for this phase)
- `generated_at` — ISO-like local timestamp
- `overall` — `{ status, score, last_error }` where status is `HEALTHY`, `DEGRADED`, `CRITICAL`, or `UNKNOWN`
- `hammerspoon` — runtime, accessibility, screens
- `services` — `ghostty`, `ollama`, `n8n`, `lm_studio`, `openclaw`, `project`
- `displays` — screen list, auto-tile, active layout
- `modules` — load health per module
- `diagnostics_text` — copy-ready summary

Individual check failures do not abort the full refresh.

Scoring rule: Hammerspoon, accessibility, Ghostty config/runtime, project path, and core modules are required. `ollama`, `n8n`, `lm_studio`, and `openclaw` are warn-only and do not need to be healthy for the console to stay out of `CRITICAL`.

## Action allowlist

| Action | Behavior |
|--------|----------|
| `refresh_status` | Recompute and write status JSON |
| `launch_terminal_ops` | `terminal_ops.launch()` |
| `reload_hammerspoon` | `hs.reload()` |
| `apply_coding_layout` | `layouts.apply('coding')` |
| `apply_ai_layout` | `layouts.apply('ai_workflow')` |
| `apply_ops_layout` | `layouts.apply('ops')` |
| `apply_writing_layout` | `layouts.apply('writing')` |
| `toggle_auto_tile` | `windows.toggleAutoTile()` |
| `run_verification` | `verify.run()` |
| `open_guide` | `guide.open()` |
| `open_hammerspoon_folder` | Finder → `~/.hammerspoon` |
| `open_project_folder` | Finder → BlackDragon project |
| `open_ghostty_config` | Open `~/.config/ghostty/config` |
| `open_terminal_ops_config` | Open Terminal Ops Ghostty conf |
| `copy_diagnostics` | Clipboard ← diagnostics summary |
| `open_event_log` | Open `runtime/operations_events.json` |
| `clear_event_display` | Clears console event JSON only |
| `open_hammerspoon_console` | Focus Hammerspoon / open console if supported |

Unknown actions are rejected and logged as warnings. No arbitrary shell commands, paths, or Lua expressions are accepted from the browser.

## Refresh behavior

- **Automatic (Lua):** every 30 seconds while Hammerspoon is running
- **Automatic (HTML):** every 10 seconds via `fetch`
- **Manual:** Operations Console **Refresh** button or `refresh_status` action
- **Stale warning:** UI warns if status is older than 30 seconds or unreadable

Ollama (`http://127.0.0.1:11434/api/tags`), n8n (`http://127.0.0.1:5678`), LM Studio (`http://127.0.0.1:1234/v1/models`), and OpenClaw (`http://127.0.0.1:18789/`) checks are async and do not start services. OpenClaw falls back to `openclaw gateway status` when the HTTP probe fails.

## Event model

```json
{
  "timestamp": "2026-07-10T10:31:02-03:00",
  "severity": "info",
  "source": "operations",
  "action": "apply_coding_layout",
  "message": "Coding layout applied",
  "success": true
}
```

Severity: `info`, `success`, `warning`, `error`.

**Never logged:** clipboard contents, AI prompts, credentials, tokens, or document bodies.

## Open the console

1. `⌘⌃H` or open `file:///Users/<you>/.hammerspoon/docs/USER_GUIDE.html`
2. Operations Console is at the top; guide tabs remain below

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Status stuck at UNKNOWN | Reload Hammerspoon (`⌘⌃R`); confirm `init.lua` loads `operations_console` |
| `fetch` failed in browser | Use Safari or same-folder `file://` open; reload Hammerspoon to regenerate JSON |
| Action does nothing | Hammerspoon menu → Console for errors; confirm URL is `operations/run` |
| Ghostty degraded | Install Ghostty, grant Automation permission |
| Ollama/n8n unreachable | Start manually; console does not auto-start services |
| Rapid duplicate start events | Path watcher reload loop — avoid editing `~/.hammerspoon` while testing |

## Disable the console safely

1. Comment out in `init.lua`:

   ```lua
   -- require('modules.operations_console').start()
   ```

2. Reload Hammerspoon (`⌘⌃R`)

The guide and hotkeys continue to work. Runtime JSON files are inert when the module is not started.

## Restore from backup

Backups live under:

```text
~/.hammerspoon/backups/operations-console-YYYYMMDD-HHMMSS/
```

Example rollback:

```bash
BACKUP=~/.hammerspoon/backups/operations-console-20260710-102621
cp "$BACKUP/init.lua" ~/.hammerspoon/init.lua
cp "$BACKUP/USER_GUIDE.html" ~/.hammerspoon/docs/USER_GUIDE.html
rm -f ~/.hammerspoon/modules/operations_console.lua
# optional: remove runtime + docs added in Phase 1
```

Reload Hammerspoon after restoring files.
