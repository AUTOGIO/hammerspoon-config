# BlackDragon Operations Console — Audit Report

**Date:** 2026-07-10  
**Auditor:** Phase 1 pre-implementation audit (read-only)  
**Repository:** `/Users/eduardofgiovannini/.hammerspoon`

---

## 1. Architecture Summary

BlackDragon Hammerspoon is a **flat Lua module system** with a single entry point (`init.lua`), no package manager, and browser-driven actions via `hammerspoon://` URL events.

### Directory structure (relevant)

```text
~/.hammerspoon/
├── init.lua                    # Entry point, path watcher, module requires
├── USER_GUIDE.html             # Local interactive guide (file://)
├── modules/
│   ├── windows.lua             # Auto-tiler, snap, center
│   ├── layouts.lua             # Named layouts + menubar picker
│   ├── hotkeys.lua             # Central hotkey registry
│   ├── apps.lua                # App launcher (incl. BlackDragon)
│   ├── terminal_ops.lua          # Ghostty Ops Center launcher
│   ├── clipboard.lua             # Pasteboard history
│   ├── ai.lua                    # AI clipboard handoff hotkeys
│   ├── n8n.lua                   # localhost:5678 webhooks
│   ├── guide.lua                 # URL bridge + guide hotkey
│   ├── verify.lua                # Display/layout diagnostics (on-demand)
│   └── spencer.lua               # DEPRECATED, not wired in init
├── scripts/ghostty/              # Terminal Ops AppleScript + config
└── (no docs/, runtime/ yet)
```

### Module loading order (`init.lua`)

1. `hs.allowAppleScript(true)` + `require("hs.ipc")`
2. `modules.windows` (starts auto-tile on load)
3. `modules.layouts` → `showMenu()` (menubar 🗂)
4. `modules.hotkeys`
5. `modules.apps`
6. `modules.n8n`
7. `modules.clipboard` (starts watcher on load)
8. `modules.ai` (registers AI hotkeys on load)
9. `modules.guide` (registers URL handler + ⌘⌃H)
10. Path watcher on `~/.hammerspoon/` → `hs.reload`
11. Alert: "Hammerspoon ready"

**Not loaded at init:** `verify.lua`, `terminal_ops.lua` (lazy via hotkeys/guide), `spencer.lua`.

### Reload behavior

- **Auto-reload:** `hs.pathwatcher` on entire `~/.hammerspoon/` directory
- **Manual reload:** ⌘⌃R (`hotkeys.lua`) or guide action `reload`
- **No debounce** on path watcher — rapid saves may trigger multiple reloads

---

## 2. Current Action Flow

### Browser → Hammerspoon

```text
USER_GUIDE.html button click
    → buildGuideURL() → hammerspoon://guide/run?action=...&layout=...&app=...
    → fireURL() creates hidden iframe with URL
    → Hammerspoon hs.urlevent.bind('guide', 'run', run)
    → guide.lua dispatches to module functions
```

### Registered URL handlers

| Handler | Module | Function |
|---------|--------|----------|
| `guide/run` | `guide.lua` | `run(params)` — sole `hs.urlevent.bind` in repo |

**No** `operations` URL handler exists yet.

### guide.lua action map

| Action | Target |
|--------|--------|
| `snap-left/right`, `maximize`, `center` | `windows.*` |
| `clipboard` | `clipboard.showHistory()` |
| `reload` | `hs.reload()` |
| `terminal-ops` | `terminal_ops.launch()` |
| `open-guide` | `guide.open()` |
| `launch` + `app` param | `apps.launch()` |
| `n8n-trigger`, `n8n-post` | `n8n.*` |
| `ai-*` | `ai.run(name)` |
| `layout-apply` + `layout` | `layouts.apply()` |
| `tile-toggle`, `tile-cycle` | `windows.*` |
| `verify` | `verify.run()` |

Unknown actions → `hs.alert.show` warning.

### Hotkey registrations (`hotkeys.lua` + `guide.lua` + `ai.lua`)

| Hotkey | Action |
|--------|--------|
| ⌘⌃⌥⇧ arrows | Window snap/maximize/center |
| ⌘⌃1–4 | Launch BlackDragon, Notes, Cursor, Terminal |
| ⌘⌃5 | Terminal Ops |
| ⌘⌃V | Clipboard history |
| ⌘⌃R | Reload config |
| ⌘⌃T | Toggle auto-tile |
| ⌘⌃L | Cycle tiler mode |
| ⌘⌃⇧1–4 | Layouts: coding, ai_workflow, ops, writing |
| ⌘⌃H | Open guide (`guide.lua`) |
| ⌃⌥⌘ G/S/C/P/A/R | AI actions (`ai.lua`) |

---

## 3. Reusable Components

| Component | Location | Reuse for console |
|-----------|----------|-------------------|
| Layout apply | `layouts.apply(name)` | Direct call |
| Verification | `verify.run()` → report string | Wrap for structured output |
| Display info | `hs.screen.allScreens()`, `windows.modeFor()` | Status cards |
| Auto-tile state | `windows.autoTile`, `windows.toggleAutoTile()` | Status + action |
| Terminal Ops | `terminal_ops.launch()`, `terminal_ops.projectDir` | Health + action |
| n8n HTTP | `n8n.baseURL` pattern | Health check template |
| Guide open | `guide.open()` | Preserve |
| Logging | `hs.logger.new()` per module | Console events |
| JSON | `hs.json.encode/decode` | Status/event files |
| Async HTTP | `hs.http.asyncGet` | Ollama/n8n checks |

### verify.lua outputs

- Text report via `print` + `hs.alert`
- Returns `report, pass, fail` — suitable for diagnostics summary
- Checks: modules loaded, auto-tile, display count, ultrawide/built-in, layout catalog

### layouts.lua public API

- `M.apply(name)`, `M.layouts`, `M.order`, `M.activeLayout`
- `M.showMenu()`, `M.dumpScreen(screen)`

### windows.lua public API

- `M.autoTile`, `M.toggleAutoTile()`, `M.modeFor(screen)`, `M.retileAll()`
- `M.ultrawideAspect` (2.0)

---

## 4. Missing Components

| Item | Status |
|------|--------|
| `modules/operations_console.lua` | **Missing** |
| `runtime/` directory | **Missing** |
| `runtime/operations_status.json` | **Missing** |
| `runtime/operations_events.json` | **Missing** |
| `docs/` directory | **Missing** (created for this audit) |
| Operations URL handler | **Missing** |
| Status polling in HTML | **Missing** |
| Event stream | **Missing** |
| Health checks (Ollama, n8n, Ghostty, Git) | **Missing** as structured JSON |
| Action allowlist / security layer | **Partial** — guide.lua uses string matching, no allowlist |
| Accessibility status reporting | **Missing** |
| Atomic JSON writes | **Missing** |
| `verify.lua` in init | Not required — lazy require works |

### External paths (audit machine state)

On audit date, these paths were **not present** on disk (checks may report degraded — expected):

- `~/.config/ghostty/config`
- `~/Documents/01_Projects/BlackDragon_Project`

Console must handle missing paths gracefully without crashing.

---

## 5. Identified Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| `guide.lua` accepts `ai-*` prefix broadly | Medium | New console uses separate allowlist |
| `guide.lua` `n8n-post` accepts arbitrary path | Low | Console won't expose; Phase 1 no new n8n paths |
| `reload` action from browser can interrupt operations | Low | Document; preserve existing behavior |
| Path watcher reload during status write | Low | Atomic write (tmp + rename) |
| `file://` fetch CORS for JSON polling | Medium | Same-origin relative path; document Safari vs Chrome |
| Duplicate action definitions (guide vs new console) | Medium | Console uses `operations/run`; guide unchanged |
| `hs.reload()` destroys in-flight HTTP callbacks | Low | Refresh re-triggers on next poll |
| AI actions log clipboard if instrumented | High | **Do not** log AI/clipboard content in events |
| `apps.lua` BlackDragon finder uses `io.popen` | Info | Read-only in health checks |
| Spencer buttons in HTML still reference layouts | Info | Deprecated module; buttons use `layout-apply` now |

### Potentially destructive actions (existing, not in Phase 1 console)

- `hs.reload()` — config reload
- `layouts.apply()` — hides other apps
- `ai.snapshot()` — writes file to iCloud
- `n8n.trigger/post` — external HTTP

Phase 1 console will **omit** service stop/restart/kill actions.

---

## 6. Proposed Minimal Changes

### New files

```text
modules/operations_console.lua
runtime/operations_status.json      # seed empty structure
runtime/operations_events.json      # seed []
docs/AUDIT_REPORT.md                # this file
docs/OPERATIONS_CONSOLE.md
docs/IMPLEMENTATION_REPORT.md
```

### Modified files

```text
init.lua              # require operations_console.start()
USER_GUIDE.html       # Operations Console UI at top; preserve all tabs
```

### Unchanged (preserve behavior)

```text
modules/guide.lua     # Keep hammerspoon://guide/run for existing buttons
modules/hotkeys.lua
modules/layouts.lua
modules/windows.lua
modules/terminal_ops.lua
modules/verify.lua
modules/ai.lua
modules/n8n.lua
modules/clipboard.lua
modules/apps.lua
```

### Communication architecture

```text
USER_GUIDE.html
    → fetch('runtime/operations_status.json?t=...')  [poll 10s]
    → hammerspoon://operations/run?action=<allowlisted>
operations_console.lua
    → refreshStatus() writes runtime/*.json atomically
    → execute(action) → existing module APIs
    → recordEvent() appends to bounded event log
```

**No localhost server** unless `file://` polling fails in validation (unlikely for Safari same-directory fetch).

### New URL handler

```text
hammerspoon://operations/run?action=refresh_status
```

Separate from `guide/run` to avoid widening guide.lua attack surface.

---

## 7. Exact Files to Create or Modify

| File | Action |
|------|--------|
| `docs/AUDIT_REPORT.md` | **Create** |
| `modules/operations_console.lua` | **Create** |
| `runtime/operations_status.json` | **Create** (seed) |
| `runtime/operations_events.json` | **Create** (seed) |
| `docs/OPERATIONS_CONSOLE.md` | **Create** |
| `docs/IMPLEMENTATION_REPORT.md` | **Create** |
| `init.lua` | **Modify** — add `require('modules.operations_console').start()` |
| `USER_GUIDE.html` | **Modify** — add Operations Console section + JS |

### Backup before modify

```text
backups/operations-console-YYYYMMDD-HHMMSS/
├── init.lua
└── USER_GUIDE.html
```

---

## 8. Deviations from Prompt Assumptions

| Assumption | Actual state |
|------------|--------------|
| `terminal_ops.lua` in init | Loaded lazily via hotkeys/guide — **works without init require** |
| `verify.lua` in modules list | Exists, not in init — **on-demand require OK** |
| Multiple URL handlers | Only `guide/run` — **add `operations/run`** |
| Ghostty config at `~/.config/ghostty/config` | May be absent — report `missing` |
| BlackDragon project path | May be absent on audit machine — report gracefully |
| `open_hammerspoon_console` | No native `hs.openConsole()` guaranteed — use Hammerspoon activate + IPC fallback |

Implementation will adapt to actual repository structure; no forced new architecture beyond the minimal layer described above.

---

## 9. Audit Conclusion

The repository is **ready for Phase 1**. The existing `guide.lua` URL bridge and module APIs provide a solid foundation. The smallest stable path is:

1. Add `operations_console.lua` with status writer, event log, and allowlisted actions
2. Extend `USER_GUIDE.html` with a polling dashboard section
3. Wire `init.lua` to start the console module
4. Leave `guide.lua` and all hotkeys untouched for regression safety

**Proceed to Step 2 (backups) and implementation.**
