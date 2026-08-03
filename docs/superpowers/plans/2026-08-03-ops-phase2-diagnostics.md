# Ops Console Phase 2 — Diagnostics, Audit, Self-Test

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one-button diagnostics, environment audit, and full stack self-test that write structured PASS/FAIL/WARNING results into `operations_status.json` and the guide UI.

**Architecture:** New `modules/diagnostics.lua` owns named checks. `verify.lua` gains `runFull()` returning structured results. `operations_console.execute` allowlists three actions that run suites and persist results. Periodic 30s refresh does **not** re-run suites or overwrite suite scores; live `overall` stays poll-based. Suite scores live on `diagnostics` / `environment` / `verification`.

**Tech Stack:** Hammerspoon LuaJIT, `hs.http` (sync GET for suite probes where needed), `USER_GUIDE.html` ops UI.

## Global Constraints

- Do not commit `runtime/` artifacts or secrets
- Do not add a localhost HTTP server
- Browser may only trigger allowlisted actions
- Diagnostics checks are fixed IDs — no arbitrary shell from HTML
- Prefer editing existing files; `modules/diagnostics.lua` is the allowed new module
- Commit only when the owner explicitly asks
- Events never log clipboard contents, AI prompt bodies, or credentials

## File map

| File | Role |
|------|------|
| `modules/diagnostics.lua` | Named PASS/FAIL/WARN checks + `runDiagnostics()` + `runEnvironmentAudit()` |
| `modules/verify.lua` | Keep `run()`; add `runFull()` structured stack self-test |
| `modules/operations_console.lua` | Allowlist + actions; persist suite results on status |
| `docs/USER_GUIDE.html` | Buttons + results panels |
| `docs/OPERATIONS_CONSOLE.md` | Document actions + schema |

---

### Task 1: `diagnostics.lua` — diagnostics + environment audit

**Files:**
- Create: `modules/diagnostics.lua`

**Interfaces:**
- Produces:
  - `diagnostics.runDiagnostics() -> { at, score, pass, fail, warn, checks[{id,result,detail}] }`
  - `diagnostics.runEnvironmentAudit() -> { at, score, pass, fail, warn, issues[], checks[{id,result,detail}] }`
- Result values: `"PASS"` | `"FAIL"` | `"WARNING"` only

- [ ] **Step 1: Implement helpers + diagnostics suite**

Fixed checks (examples — implement all of these IDs):

| id | Logic |
|----|--------|
| `hammerspoon_running` | always PASS if this code runs |
| `accessibility` | `hs.accessibilityState()` — FAIL if false |
| `config_dir` | `hs.configdir` is a directory |
| `ghostty_app` | `/Applications/Ghostty.app` or running app |
| `ghostty_config` | `~/.config/ghostty/config` exists — WARNING if missing |
| `terminal_ops_config` | ops conf under hammerspoon scripts — WARNING if missing |
| `project_path` | `paths.resolveBlackDragonProject()` is directory — FAIL if not |
| `module_core` | require windows, layouts, paths — FAIL if any fail |
| `ollama_endpoint` | sync GET `127.0.0.1:11434/api/tags` — WARNING if not 200 |
| `n8n_endpoint` | sync GET `127.0.0.1:5678` — WARNING if not 200/404 |
| `lm_studio_endpoint` | sync GET `127.0.0.1:1234/v1/models` — WARNING if not 200 |
| `openclaw_endpoint` | sync GET `127.0.0.1:18789/` — WARNING if not 200 |

Score: `round(100 * (pass + 0.5*warn) / total)` or equivalent; FAIL weighs 0, WARNING half, PASS full.

- [ ] **Step 2: Environment audit suite**

Checks:

| id | Logic |
|----|--------|
| `shell` | `$SHELL` set — WARNING if empty |
| `path_homebrew` | `/opt/homebrew/bin` in PATH or exists — WARNING if missing |
| `hs_config_symlink` | if `~/.hammerspoon` is symlink, PASS with target detail; else PASS “real dir” |
| `ghostty_config` | same as above |
| `ops_pane_script` | `scripts/ghostty/terminal-ops-pane.sh` executable/exists |
| `launch_command` | `launch-terminal-operations-center.command` exists |
| `paths_module` | paths.resolve returns non-empty |
| `ai_module` | `pcall(require, 'modules.ai')` |
| `clipboard_watcher` | clipboard.watcherAlive() |
| `zshrc_hint` | `~/.zshrc` exists — WARNING if missing (don’t parse aliases deeply) |

`issues[]` = list of `{id, detail}` for FAIL and WARNING only.

- [ ] **Step 3: Verify in Hammerspoon Console**

```lua
local d = require('modules.diagnostics')
local r = d.runDiagnostics()
print(r.score, r.pass, r.fail, r.warn)
```

---

### Task 2: Expand `verify.lua` with `runFull()`

**Files:**
- Modify: `modules/verify.lua`

**Interfaces:**
- Keep: `M.run() -> report, pass, fail` (existing behavior)
- Produces: `M.runFull() -> { at, score, pass, fail, warn, checks[], report }`

- [ ] **Step 1: Add structured helper + runFull**

`runFull` checks (soft where GUI needed):

1. Layout suite: call existing `run()` logic or internal shared checks — include pass/fail counts
2. Ghostty installed/running — WARNING if not running, FAIL if not installed
3. Project path exists — FAIL if not
4. Clipboard: watcher alive + count() callable — WARNING if watcher dead
5. AI module loadable — FAIL if require fails; dry-run: confirm `ai.run` exists without invoking chat
6. Sync ping Ollama / n8n / LM Studio — WARNING each if down
7. Notification smoke: `hs.notify` or `hs.alert` briefly — PASS if no error
8. Window smoke: focused window frame readable OR WARNING “no focused window”
9. Core modules from MODULE list loaded via pcall

Do **not** call `hs.reload()` inside the suite (would abort). Check `last_reload` / config_loaded via operations status or simply PASS “config loaded (verify running)”.

- [ ] **Step 2: Verify**

```lua
local v = require('modules.verify').runFull()
print(v.score, #v.checks, v.fail)
```

---

### Task 3: Wire actions + status persistence

**Files:**
- Modify: `modules/operations_console.lua`
- Modify: `docs/OPERATIONS_CONSOLE.md`

**Interfaces:**
- Actions: `run_diagnostics`, `run_environment_audit`, `run_full_self_test`
- Status fields: `diagnostics`, `environment`, `verification` (last run payloads)
- Do **not** change 30s `computeOverall` to re-run suites
- On suite actions: write field onto statusCache, `writeStatus`, recordEvent, notify

- [ ] **Step 1: Allowlist + execute branches**

```lua
run_diagnostics = true,
run_environment_audit = true,
run_full_self_test = true,
```

Each branch: run suite → `statusCache.diagnostics|environment|verification = result` → persist → event with pass/fail/warn summary.

- [ ] **Step 2: Include last suite payloads in refresh writes**

When `writeStatus` / finalize runs, preserve existing `diagnostics` / `environment` / `verification` from statusCache if present (don’t wipe on 30s refresh).

- [ ] **Step 3: Docs**

Update OPERATIONS_CONSOLE.md action table + schema.

---

### Task 4: USER_GUIDE UI

**Files:**
- Modify: `docs/USER_GUIDE.html`

- [ ] **Step 1: Quick actions**

Add buttons: Run Diagnostics, Environment Audit, Full Self-Test (alongside Run Verify).

- [ ] **Step 2: Results panel**

Render last `status.diagnostics` / `environment` / `verification` as PASS/FAIL/WARNING lists + score when present after poll.

- [ ] **Step 3: Walkthrough hint**

Update Phase 2 ready copy to mention diagnostics/self-test buttons.

- [ ] **Step 4: Manual verify**

Reload HS + refresh guide; click each button; confirm JSON fields and UI update.

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| diagnostics.lua named checks | 1 |
| environment audit | 1 |
| verify.runFull | 2 |
| allowlisted actions + status fields | 3 |
| Guide UI + exit criteria | 4 |
| Suites don’t flap 30s overall | 3 (preserve fields; overall stays poll-based) |

## Self-review notes

- No arbitrary shell from browser
- Optional services = WARNING not FAIL in diagnostics/self-test
- No `hs.reload()` inside self-test
