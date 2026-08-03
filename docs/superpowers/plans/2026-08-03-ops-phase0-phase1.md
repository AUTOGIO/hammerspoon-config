# Ops Console Phase 0a/0b + Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize the live Hammerspoon config (audit P1), make `operations_status.json` trustworthy, then complete Phase 1 live status cards (modules, project capabilities, clipboard, LM Studio, OpenClaw).

**Architecture:** Keep Approach A — Lua status engine → `runtime/*.json` → `docs/USER_GUIDE.html` + allowlisted `hammerspoon://` bridges. No localhost API. No browser Lua REPL.

**Tech Stack:** Hammerspoon LuaJIT (`hs.*`), `hs.http`, `hs.urlevent`, static HTML/JS in `USER_GUIDE.html`, zsh `.command` launcher.

**Spec:** `docs/superpowers/specs/2026-08-03-operations-control-panel-design.md`  
**Audit:** `~/Reports/RepositoryAudits/repository_audit_hammerspoon_2026-08-03_02-14-28.md`

## Global Constraints

- Do not commit `runtime/` artifacts or secrets
- Do not add a localhost HTTP server
- Browser may only trigger allowlisted actions / apps / n8n paths / AI prompts
- AI keeps `⌃⌥⌘O` and `⌃⌥⌘S`; OpenClaw uses `⌃⌥⌘U` and `⌃⌥⌘I`
- Canonical project default: `~/Documents/GitHub/AI_Engineering_OS` (`paths.lua`); env `TERMINAL_OPS_PROJECT_DIR` wins when set and valid
- Prefer editing existing files; new module only if a later phase requires it (not this plan)
- Commit only when the owner explicitly asks
- After path moves, grep `*.lua`, `scripts/`, `docs/USER_GUIDE.html` for stale references

## File map

| File | Responsibility this plan |
|------|--------------------------|
| `modules/openclaw_button.lua` | Rebind hotkeys; update ready alert |
| `modules/ai.lua` | Unchanged chords; docs comments if needed |
| `modules/paths.lua` | Already canonical — consumers must use it |
| `scripts/ghostty/launch-terminal-operations-center.command` | Default project = same as `paths.lua` |
| `modules/n8n.lua` | Webhook path allowlist |
| `modules/guide.lua` | Allowlist launch; reject free-form paths |
| `modules/operations_console.lua` | Fix `runShell`; extend MODULE_KEYS; project capabilities; LM Studio/OpenClaw/clipboard status; scoring |
| `modules/clipboard.lua` | Export `count()` / `watcherAlive()` |
| `modules/apps.lua` | UniFi path fix/remove |
| `docs/USER_GUIDE.html` | Paths, hotkeys, Spencer scrub, module/status UI |
| `docs/HOW_TO_MAKE_A_CHANGE.md` | Alert string match `init.lua` |
| `docs/OPERATIONS_CONSOLE.md` | Schema/actions notes for Phase 1 |
| Root `USER_GUIDE.html` | Remove external symlink |
| `scripts/ghostty/debug-histexpand.zsh` | Move to `archive/` |
| `modules/spencer.lua` | Move to `archive/` after guide scrub |

---

### Task 1: Resolve OpenClaw / AI hotkey collision (REPO-001)

**Files:**
- Modify: `modules/openclaw_button.lua`
- Modify: `docs/USER_GUIDE.html` (OpenClaw / AI hotkey strings mentioning OpenClaw on O/S)

**Interfaces:**
- Consumes: existing `hs.hotkey.bind` pattern in `openclaw_button.lua`
- Produces: OpenClaw Control UI on `⌃⌥⌘U`; gateway status on `⌃⌥⌘I`; AI retains `⌃⌥⌘O` / `⌃⌥⌘S`

- [ ] **Step 1: Rebind OpenClaw keys**

In `modules/openclaw_button.lua`, change header comments and bindings:

```lua
-- Hotkey: Ctrl + Option + Cmd + U  → Control UI
--         Ctrl + Option + Cmd + I  → Gateway status
local HOTKEY_MODS = {"ctrl", "alt", "cmd"}
local HOTKEY_KEY  = "u"
```

Bind status on `"i"` (not `"s"`). Update the ready alert string to show `⌃⌥⌘U` instead of `⌃⌥⌘O`.

- [ ] **Step 2: Update USER_GUIDE OpenClaw mentions**

Grep `USER_GUIDE.html` for `OpenClaw`, `⌃⌥⌘O`, `⌃⌥⌘S` in OpenClaw context. Document Control UI as `⌃⌥⌘U` and status as `⌃⌥⌘I`. Leave AI rows documenting `⌃⌥⌘O` (console) and `⌃⌥⌘S` (summary).

- [ ] **Step 3: Verify**

Reload Hammerspoon (`⌘⌃R`). In Hammerspoon Console:

```lua
for _,h in ipairs(hs.hotkey.getHotkeys()) do print(h.idx, h.msg) end
```

Expected: distinct entries for AI `o`/`s` and OpenClaw `u`/`i` (exact print format varies). Manually: `⌃⌥⌘S` → Notes summary path; `⌃⌥⌘U` → OpenClaw UI attempt.

---

### Task 2: Unify project path defaults (REPO-002)

**Files:**
- Modify: `scripts/ghostty/launch-terminal-operations-center.command`
- Modify: `docs/USER_GUIDE.html` (all `Active_Projects` / stale BlackDragon path strings)

**Interfaces:**
- Consumes: `paths.lua` default `~/Documents/GitHub/AI_Engineering_OS`
- Produces: `.command` and docs resolve to the same default when env unset

- [ ] **Step 1: Fix `.command` default**

Replace:

```zsh
DEFAULT_PROJECT_DIR="$HOME/Documents/01_Projects/BlackDragon_Project"
```

with:

```zsh
DEFAULT_PROJECT_DIR="$HOME/Documents/GitHub/AI_Engineering_OS"
```

Keep `PROJECT_DIR` / `TERMINAL_OPS_PROJECT_DIR` override order as today.

- [ ] **Step 2: Fix USER_GUIDE path strings**

Replace every `Active_Projects/BlackDragon_Project` (and any other non-canonical BlackDragon path in troubleshooting) with `Documents/GitHub/AI_Engineering_OS`. Mention env override `TERMINAL_OPS_PROJECT_DIR`.

- [ ] **Step 3: Verify**

```bash
unset PROJECT_DIR TERMINAL_OPS_PROJECT_DIR
# dry: only print resolved default — do not require full Ghostty launch
zsh -c 'DEFAULT_PROJECT_DIR="$HOME/Documents/GitHub/AI_Engineering_OS"; echo $DEFAULT_PROJECT_DIR; test -d "$DEFAULT_PROJECT_DIR" && echo OK'
```

In HS Console: `print(require('modules.paths').resolveBlackDragonProject())` — same existing directory.

---

### Task 3: Allowlist guide launch + n8n webhooks (REPO-003)

**Files:**
- Modify: `modules/n8n.lua`
- Modify: `modules/guide.lua`
- Modify: `modules/operations_console.lua` (`trigger_n8n` branch)
- Modify: `docs/USER_GUIDE.html` (webhook simulator: constrain path to allowlisted value or dropdown)

**Interfaces:**
- Consumes: `n8n.trigger(path)`, `n8n.post(path, body)`, guide `action=launch`
- Produces: `n8n.isAllowedPath(path) -> boolean`; rejected paths alert + no HTTP

- [ ] **Step 1: Add allowlist to `n8n.lua`**

```lua
local ALLOWED_PATHS = {
  ['hs/daily-log'] = true,
}

function M.isAllowedPath(path)
  return type(path) == 'string' and ALLOWED_PATHS[path] == true
end

function M.trigger(path)
  if not M.isAllowedPath(path) then
    hs.alert.show('⚠ n8n: path not allowlisted')
    return
  end
  -- existing HTTP GET logic
end

function M.post(path, body)
  if not M.isAllowedPath(path) then
    hs.alert.show('⚠ n8n: path not allowlisted')
    return
  end
  -- existing HTTP POST logic
end
```

Keep error handling on `hs.http` calls (log/alert on failure).

- [ ] **Step 2: Harden `guide.lua` launch**

Replace free-form `params.path` launch with name-based launch only:

```lua
if action == 'launch' then
  local name = params.app or params.name
  if name and name ~= '' then
    apps.launch(name)
  else
    hs.alert.show('⚠ guide: launch requires allowlisted app name')
  end
  return
end
```

If the HTML currently passes `path=`, update those buttons to `app=` / `name=` matching `apps.launch` keys. Reject any remaining `params.path` for launch (do not call `apps.launchPath` from the URL bridge).

- [ ] **Step 3: Harden ops `trigger_n8n`**

In `operations_console.lua`, before `n8n.post`:

```lua
local path = (payload and payload.path) or 'hs/daily-log'
local n8n = require('modules.n8n')
if not n8n.isAllowedPath(path) then
  -- record warning event; do not post
  return
end
n8n.post(path, { ... })
```

- [ ] **Step 4: Verify**

From terminal (should fail closed after reload):

```bash
open 'hammerspoon://guide?action=launch&path=/Applications/Calculator.app'
open 'hammerspoon://guide?action=n8n-trigger&path=evil/path'
```

Expected: alerts / no Calculator launch / no arbitrary webhook. Allowlisted `hs/daily-log` still works when n8n is up.

---

### Task 4: Hygiene — symlink, UniFi, debug script, Spencer, HOW_TO (REPO-004/005/006/008/009)

**Files:**
- Delete or replace: root `USER_GUIDE.html` symlink
- Modify: `modules/apps.lua`
- Modify: `modules/hotkeys.lua` (UniFi binding behavior if path removed)
- Move: `scripts/ghostty/debug-histexpand.zsh` → `archive/`
- Move: `modules/spencer.lua` → `archive/` (after grep confirms no live require)
- Modify: `docs/USER_GUIDE.html` (Spencer live restore instructions → historical/layouts-only)
- Modify: `docs/HOW_TO_MAKE_A_CHANGE.md` (alert text)

**Interfaces:**
- Produces: no external-repo guide at root; no dead UniFi path; no live Spencer module

- [ ] **Step 1: Remove bad root symlink**

```bash
# Only if it is a symlink to Apple_M4_Workflows (verify first)
readlink /Users/eduardofgiovannini/.hammerspoon/USER_GUIDE.html
rm /Users/eduardofgiovannini/.hammerspoon/USER_GUIDE.html
```

Do **not** recreate a symlink into another repo. Optional: add a one-line `USER_GUIDE.html` at root that is **not** needed — `guide.lua` already opens `docs/USER_GUIDE.html`. Prefer no root file.

- [ ] **Step 2: UniFi**

UniFi app is missing under `~/Applications`. Remove the `knownPaths` entry for `UniFi Gateway`. Change hotkey `⌘⌃6` to alert `UniFi Gateway not installed` (or remove the bind and update USER_GUIDE). Update USER_GUIDE launch catalog accordingly.

- [ ] **Step 3: Archive dead/deprecated files**

```bash
mv scripts/ghostty/debug-histexpand.zsh archive/
mv modules/spencer.lua archive/
```

Grep: no `require('modules.spencer')` outside archive.

- [ ] **Step 4: Scrub Spencer + HOW_TO**

In USER_GUIDE, remove or mark historical any “restore Spencer workspace” live instructions; point to `layouts.apply(...)`. In HOW_TO, replace `Hammerspoon ready` with the current `init.lua` alert string exactly.

- [ ] **Step 5: Verify**

```bash
test ! -e USER_GUIDE.html || readlink USER_GUIDE.html | grep hammerspoon/docs
rg -n "modules.spencer|Active_Projects|Hammerspoon ready|DaNigga_Cloud_Gateway" --glob '!archive/**' .
```

Expected: no stale hits outside intentional historical notes (if any remain, they must say historical).

---

### Task 5: Fix `runShell` / project git fields (Phase 0b)

**Files:**
- Modify: `modules/operations_console.lua` (`runShell`, callers if needed)

**Interfaces:**
- Consumes: `hs.execute(cmd)` → `stdout, status, type, rc`
- Produces: `runShell(cmd) -> ok:boolean, output:string` where `ok` means `rc == 0`

- [ ] **Step 1: Replace `runShell`**

```lua
local function runShell(cmd)
  local output, _, _, rc = hs.execute(cmd .. ' 2>/dev/null')
  if type(output) ~= 'string' then output = tostring(output or '') end
  output = output:gsub('%s+$', '')
  return tonumber(rc) == 0, output
end
```

- [ ] **Step 2: Audit `checkProject` / pgrep helpers**

Ensure branch/dirty/commit/disk commands use `ok, output = runShell(...)` and only parse `output` when `ok` (or when empty output is meaningful). Never assign the boolean `ok` into JSON string fields.

- [ ] **Step 3: Verify**

Reload HS. Inspect:

```bash
python3 -c "import json; d=json.load(open('runtime/operations_status.json')); print(d['services']['project'])"
```

Expected: `branch` is a real git branch name (not `"true"`); `dirty` boolean; `latest_commit` looks like a hash/subject line.

---

### Task 6: Clipboard status exports (Phase 1)

**Files:**
- Modify: `modules/clipboard.lua`
- Modify: `modules/operations_console.lua` (include `clipboard` in status snapshot)

**Interfaces:**
- Produces: `clipboard.count() -> number`, `clipboard.watcherAlive() -> boolean`

- [ ] **Step 1: Export APIs**

```lua
function M.count()
  return #history
end

function M.watcherAlive()
  return watcher ~= nil
end
```

- [ ] **Step 2: Wire into status**

In status assembly, add:

```lua
clipboard = {
  history_count = require('modules.clipboard').count(),
  watcher_alive = require('modules.clipboard').watcherAlive(),
}
```

Bump `schema_version` to `2` on the status object when writing.

- [ ] **Step 3: Verify**

After copying text a few times, status JSON `clipboard.history_count` > 0 and `watcher_alive` true.

---

### Task 7: Extend module health + project capabilities (Phase 1 / REPO-007)

**Files:**
- Modify: `modules/operations_console.lua`
- Modify: `docs/USER_GUIDE.html` (module status grid + project capabilities on cards)

**Interfaces:**
- Produces: `MODULE_KEYS` includes all `init.lua`-started modules; `services.project.capabilities` array/object

- [ ] **Step 1: Expand `MODULE_KEYS`**

```lua
local MODULE_KEYS = {
  'paths', 'layouts', 'windows', 'terminal_ops', 'clipboard', 'ai', 'n8n',
  'guide', 'verify', 'hotkeys', 'apps', 'openclaw_button', 'operations_console',
}
```

`checkModuleHealth('operations_console')` via `package.loaded` or `pcall(require)` is fine (module already loaded).

- [ ] **Step 2: Project capabilities**

In `checkProject`, after resolving `dir`, set flags such as:

```lua
capabilities = {
  launch_sh = pathExists(dir .. '/launch.sh') or pathExists(dir .. '/scripts/launch.sh'),
  pane_sh = pathExists(hs.configdir .. '/scripts/ghostty/terminal-ops-pane.sh'),
  terminal_ops_conf = pathExists(TERMINAL_OPS_CONFIG),
  ghostty_config = pathExists(GHOSTTY_CONFIG),
  -- add other real paths you already document; do not invent files
}
```

Prefer probing paths that exist in this repo / known project layout; skip fictional flags.

- [ ] **Step 3: UI**

In `USER_GUIDE.html` ops renderer: add a modules grid from `status.modules` and list project capabilities under the project card. Show `hammerspoon.last_reload` and `generated_at`.

- [ ] **Step 4: Verify**

Break-test mentally: temporarily rename is unnecessary — confirm JSON lists `openclaw_button` / `hotkeys` / `apps` as `healthy` after reload.

---

### Task 8: LM Studio + OpenClaw service probes + scoring (Phase 1)

**Files:**
- Modify: `modules/operations_console.lua`
- Modify: `docs/USER_GUIDE.html` (cards)
- Modify: `docs/OPERATIONS_CONSOLE.md` (schema)

**Interfaces:**
- Produces: `services.lm_studio`, `services.openclaw`; warn-only in `computeOverall`

- [ ] **Step 1: Sync stubs + async HTTP**

Mirror Ollama pattern:

- LM Studio: `GET http://127.0.0.1:1234/v1/models`
- OpenClaw: `GET http://127.0.0.1:18789/` first; on failure, optional CLI `openclaw gateway status` parse into `failure_reason` / reachable flag

Do not auto-start services. Use existing `hs.http.asyncGet` error handling.

- [ ] **Step 2: Scoring**

Make Ollama warn-only like n8n (design: optional services must not solely force CRITICAL). Add LM Studio and OpenClaw as warn-only weights (or exclude from denominator when not installed — pick one approach and document in OPERATIONS_CONSOLE.md: **exclude from score until process/endpoint ever seen this session**, else warn-only points that cannot drop below DEGRADED alone).

Concrete rule for this task:

- Required: Hammerspoon running, accessibility not false, Ghostty installed/config, project path, core modules
- Warn-only (do not add failure weight that alone yields CRITICAL): Ollama, n8n, LM Studio, OpenClaw

Adjust `computeOverall` so a machine with HS+Ghostty+project healthy stays ≥ DEGRADED even if all four optionals are down.

- [ ] **Step 3: Docs + UI cards**

Add service cards; update `docs/OPERATIONS_CONSOLE.md` status schema section with new fields + `schema_version: 2`.

- [ ] **Step 4: Verify**

With LM Studio/OpenClaw stopped: cards show unreachable/warn; overall not CRITICAL if core stack is fine. Start LM Studio: card flips after refresh.

---

### Task 9: Final verification checklist

**Files:** none (manual)

- [ ] **Step 1: Run through exit criteria**

| Check | Expected |
|-------|----------|
| `⌃⌥⌘S` | AI summary (not OpenClaw) |
| `⌃⌥⌘U` | OpenClaw UI |
| `resolveBlackDragonProject()` vs `.command` default | Same path |
| `guide?action=launch&path=/Applications/Calculator.app` | Rejected |
| `operations_status.json` project.branch | Real branch string |
| `modules.openclaw_button` in status | `healthy` |
| `clipboard.history_count` | Number |
| Root `USER_GUIDE.html` | Absent or inside-repo only |
| Grep Spencer live restore | Gone |
| Optional services down | Not sole CRITICAL |

- [ ] **Step 2: Update walkthrough hint**

In `USER_GUIDE.html`, change “Ready for Phase 2” copy to mention Phase 0/1 complete and next is diagnostics/self-test (Phase 2), not “command palette” alone.

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| Phase 0a hotkeys / paths / allowlists / hygiene | 1–4 |
| Phase 0b runShell | 5 |
| Phase 1 clipboard | 6 |
| Phase 1 modules + project capabilities | 7 |
| Phase 1 LM Studio / OpenClaw / scoring | 8 |
| Exit verification | 9 |
| Phases 2–5 | Out of scope (separate plans) |

## Self-review notes

- No browser Lua REPL; no Spencer health card
- Commit steps omitted unless owner requests commits (per user rules)
- UniFi: remove, don’t invent a fake path
