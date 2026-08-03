# Operations Control Panel — Multi-Phase Design

**Date:** 2026-08-03  
**Status:** Approved (Approach A + audit-informed Phase 0a/0b)  
**Approach:** A — Deepen the existing Operations Console (Lua → `runtime/*.json` → `USER_GUIDE.html`)  
**Scope:** Long-term architecture to turn the Phase 1 guide/console into a production-quality operational control panel

---

## 1. Goal

Evolve the BlackDragon Hammerspoon companion from a hybrid of static docs + Phase 1 health cards into a **self-validating, maintainable operations control panel** — without a second UI, without a localhost API, and without weakening the browser→Hammerspoon allowlist.

Success looks like: open `⌘⌃H`, see truthful live state, run diagnostics/self-test/backup from one place, and trust that documentation actions still map to real modules.

---

## 2. Architecture spine (non-negotiable)

```text
init.lua
  → modules.operations_console.start()
       writes  runtime/operations_status.json   (≈30s refresh)
       writes  runtime/operations_events.json   (max 200)
  → docs/USER_GUIDE.html
       polls JSON via file:// fetch (≈10s)
       fires hammerspoon://operations/run?action=<allowlisted>
       fires hammerspoon://guide/run?action=<legacy>
```

| Constraint | Rule |
|------------|------|
| No localhost HTTP server | Status is file JSON only |
| No arbitrary shell from browser | Named allowlisted actions only |
| No arbitrary Lua from browser | Console tab stays copy-paste recipes; open HS console for REPL |
| Additive schema | Extend `operations_status.json`; do not rename breaking fields |
| Single status truth | HTML never invents health; it only renders Lua output |
| Runtime is machine-local | `runtime/` stays gitignored; never commit live state |

Reference docs remain in the same HTML file below the live console. Guide tabs are not replaced; they gain live sections where Phase work requires them.

---

## 3. Disposition of the original 18 ideas

| # | Idea | Verdict | Landing |
|---|------|---------|---------|
| 1 | Live System Status Dashboard | **Extend** | Already Phase 1; complete missing checks + UI |
| 2 | Automatic diagnostics | **Merge** | Structured checks via `run_diagnostics` |
| 3 | Environment Audit | **Merge** | Same engine; separate audit section/score |
| 4 | Live Module Status | **Extend** | Surface + enrich `status.modules` |
| 5 | Search Everything | **Extend** | Client-side index across guide sections |
| 6 | Interactive Lua Console | **Reject as-is** | Breaks allowlist; keep recipes + open HS console |
| 7 | Live Logs | **Extend** | Improve event stream UX / sources |
| 8 | Hotkey Conflict Scanner | **Defer (Phase 4)** | HS-registered scan first; no Raycast/Cursor DB |
| 9 | Project Detection | **Extend** | Capabilities matrix on `services.project` |
| 10 | AI Prompt Library | **Extend** | Grow `ai.lua` + allowlisted prompt names |
| 11 | System Health (full AM) | **Defer thin** | Light HS metrics only; not Activity Monitor |
| 12 | Workflow Recorder | **Stretch (Phase 5)** | Optional; high effort |
| 13 | Configuration Backup | **Adopt** | Allowlisted archive under `backups/` |
| 14 | Installation Wizard | **Extend** | Verify-gated walkthrough steps |
| 15 | Architecture Explorer | **Thin adopt** | Static clickable diagram fed by status edges |
| 16 | Performance Metrics | **Adopt light** | Event/probe timings; no APM stack |
| 17 | Full Self-Test | **Adopt** | Expand `verify.lua` + persist results |
| 18 | Docs Auto-Generator | **Stretch (Phase 5)** | Prefer curated HTML until drift hurts |

### Explicit non-goals

- Spencer as a first-class health card (deprecated / unwired)
- Browser-executed Lua REPL
- Full macOS TCC matrix / third-party shortcut conflict databases
- Separate Ops App or HTTP control plane (Approaches B/C)

---

## 4. Phase roadmap

```text
Phase 0a Stabilize       Audit P1: hotkeys, paths, URL allowlists, hygiene
Phase 0b Status truth    Fix runShell; trust operations_status.json
Phase 1  Status complete Ideas 1, 4, 9 (+ LM Studio / OpenClaw / clipboard)
Phase 2  Self-test       Ideas 2, 3, 17
Phase 3  Ops UX          Ideas 5, 7, 10, 13, 14
Phase 4  Insight         Ideas 8, 11 (thin), 15, 16
Phase 5  Stretch         Ideas 12, 18 — only if still needed
```

Each phase must ship usable alone. Later phases never invent a second status pipeline.
**Do not start Phase 1 until 0a and 0b exit criteria pass.**

### Phase 0a — Stabilize (from repository audit 2026-08-03)

**Owner decisions (locked):**

| Question | Decision |
|----------|----------|
| Who owns `⌃⌥⌘O` / `⌃⌥⌘S`? | **AI keeps them** (documented). OpenClaw rebinds to `⌃⌥⌘U` (Control UI) and `⌃⌥⌘I` (gateway status). |
| Canonical project root? | `~/Documents/GitHub/AI_Engineering_OS` via `paths.lua` (env override `TERMINAL_OPS_PROJECT_DIR` still wins). |
| `hammerspoon://` auth? | Trusted-local IPC; **allowlists only** — no shared-secret query param. |
| Root `USER_GUIDE.html` symlink? | **Remove** (or replace with relative link under `.hammerspoon/docs/` only). |

**Work:**

- Rebind OpenClaw off colliding chords; update alerts + USER_GUIDE OpenClaw docs
- Unify `.command` default with `paths.lua`; fix USER_GUIDE project path strings to `AI_Engineering_OS`
- Allowlist `guide` launch targets (app names / known paths); allowlist n8n webhook suffixes in `n8n.lua` + guide/ops callers (`hs/daily-log` at minimum)
- Remove root guide symlink pointing at Apple_M4_Workflows
- Fix or remove UniFi known path; archive `debug-histexpand.zsh`; scrub live Spencer restore instructions; align HOW_TO alert text with `init.lua`

**Exit criteria:** Distinct OpenClaw vs AI hotkeys; CLI and HS resolve the same project dir; arbitrary `hammerspoon://guide?action=launch&path=…` rejected; root symlink gone or points inside this repo.

### Phase 0b — Status truth

**Problem:** `runShell` in `operations_console.lua` misreads `hs.execute` return values (`stdout, status, type, rc`), so project git fields in live JSON can be wrong (e.g. branch `"true"`).

**Work:**

- Fix `runShell` to use `(output, status, exitType, rc)` correctly
- Re-validate `checkProject` (and any other shell-backed checks)
- Confirm `operations_status.json` shows real branch / dirty / commit / disk usage after reload

**Exit criteria:** Project card and diagnostics text show accurate git metadata on a known repo.

### Phase 1 — Status completeness

**Work:**

- UI: module status grid (data already partially present)
- UI: show `last_reload` / `generated_at` clearly on Hammerspoon card
- Enrich `services.project` with capabilities: Terminal Ops configs, `launch.sh` / `pane.sh`, overrides, AI-related paths when present
- Add service probes: LM Studio (`http://127.0.0.1:1234/v1/models`); OpenClaw via HTTP GET to `http://127.0.0.1:18789/` (CLI `gateway status` only as fallback if HTTP fails)
- Export clipboard history count / watcher alive from `clipboard.lua` into status
- Score weights: n8n, Ollama, LM Studio, and OpenClaw are **warn-only** — any one alone must not force `CRITICAL`

**Exit criteria:** Guide shows truthful cards for HS, Ghostty, accessibility, project capabilities, modules, clipboard; optional AI/automation services visible when present.

### Phase 2 — Diagnostics, audit, self-test

**New module:** `modules/diagnostics.lua`

- Owns named checks only: `PASS` | `FAIL` | `WARNING` + detail string
- No URL handler of its own; called by `operations_console.execute`
- Checks are allowlisted internally (e.g. `which ghostty`, config path exists, curl localhost endpoints, `hs.accessibilityState`, module requires) — **not** arbitrary shell from HTML

**Expand:** `modules/verify.lua`

- Keep layout/display verify as a suite
- Add `M.runFull()` (or equivalent) for stack self-test: reload signal, Ghostty present, clipboard round-trip smoke, AI prompt generation dry-run, n8n/LM/Ollama pings, window move smoke, notification smoke, project path
- Return structured `{ pass, fail, warn, checks[], at }` — not only a printed string

**New actions:**

| Action | Effect |
|--------|--------|
| `run_diagnostics` | Run diagnostics suite → write `status.diagnostics` + event |
| `run_environment_audit` | Versions/PATH/shell/symlink/config presence → `status.environment` |
| `run_full_self_test` | Full verify suite → `status.verification` |

**Scoring rule:** Self-test / audit update `overall` only when explicitly run (not every 30s poll), to avoid flapping when optional services are intentionally offline.

**Exit criteria:** One-button diagnostics and self-test produce PASS/FAIL/WARNING lists and a health score the user can copy.

### Phase 3 — Ops UX

**Work:**

- **Search:** Expand hotkey search into a client-side index covering commands, workflows, modules, troubleshooting, Ghostty, AI, and notable HS APIs documented in the guide
- **Logs:** Improve event stream with source badges, denser filters, and `source` tagging for module-originated actions
- **Installation wizard:** Upgrade walkthrough so steps call verify actions and auto-advance on PASS where possible (still allow Mark complete / Skip)
- **AI Prompt Library:** Expand `allowedAiPrompts` + `ai.lua` catalog (Explain, Optimize, Summarize, Debug, Generate Tests, Architecture/Security/language reviews); guide previews prompt text before handoff
- **Backup:** `backup_configuration` creates dated archive under `~/.hammerspoon/backups/` including: `~/.hammerspoon` (excluding `runtime/`, `.git/`, and secret-like filenames), Ghostty config paths, and a short `BACKUP_MANIFEST.txt`. Guide `localStorage` prefs stay browser-side — HTML gains an “Export guide prefs” button that writes a JSON file into the backup folder when the user runs backup from the guide. Do not pack arbitrary home-directory dotfiles beyond paths listed in the manifest.

**Exit criteria:** User can search the guide usefully, run wizard verify steps, preview AI prompts, and produce one backup archive from the console.

### Phase 4 — Insight (light)

**Work:**

- **Hotkey scan:** Inventory Hammerspoon-registered hotkeys; flag obvious duplicates inside HS; document that macOS/Raycast/Cursor conflicts are out of band
- **Thin system metrics:** CPU/mem/battery via `hs.host` (and related) APIs already available in Hammerspoon — not a process browser
- **Architecture explorer:** Static SVG/HTML diagram (Shortcuts → HS → Ghostty → Terminal Ops → project scripts → logs) with nodes lit from current status
- **Performance:** Record durations for allowlisted probes (Ghostty launch attempt timing, reload marker, webhook latency) into `status.metrics` / events — no external APM

**Exit criteria:** User can see HS hotkey collisions, a status-lit architecture map, and a few recent timings.

### Phase 5 — Stretch (optional)

- Workflow recorder (app launches / layout applies → generated Lua or AppleScript sketch)
- Documentation auto-generator (parse modules for hotkeys/exports → regenerate HTML sections)

Only start if Phase 0–4 still leave documentation drift or workflow authoring as top pain.

---

## 5. Status schema (additive)

```text
operations_status.json
├── schema_version          ← NEW integer (start at 2 after Phase 1)
├── generated_at
├── overall { status, score, last_error }
├── hammerspoon { status, config_loaded, last_reload, accessibility, screen_count, focused_screen }
├── services
│   ├── ghostty
│   ├── ollama
│   ├── n8n
│   ├── project             ← + capabilities[] / flags
│   ├── lm_studio           ← NEW (warn-only in score)
│   └── openclaw            ← NEW (warn-only in score)
├── displays
├── modules                 ← enrich beyond "healthy"/"unavailable" when cheap
├── clipboard               ← NEW { history_count, watcher_alive }
├── verification            ← NEW last run payload
├── diagnostics             ← NEW last run payload
├── environment             ← NEW audit score + issues[]
├── metrics                 ← NEW (Phase 4)
└── diagnostics_text        ← keep copy-ready summary
```

Individual check failures must not abort a full refresh (existing Phase 1 behavior).

---

## 6. Module boundaries

| Module | Responsibility |
|--------|----------------|
| `operations_console.lua` | Status assembly, events, allowlist dispatch, schema version, timer |
| `diagnostics.lua` (Phase 2) | Named PASS/FAIL/WARN checks; no URL handler |
| `verify.lua` | Layout verify + full self-test suites; structured return values |
| `clipboard.lua` | Export count/watcher for status (minimal API) |
| `ai.lua` | Prompt catalog + clipboard handoff |
| `guide.lua` | Legacy URL bridge; stay thin |
| `openclaw_button.lua` | UI launcher; status probe folded into console |
| `USER_GUIDE.html` | Render + fire allowlisted actions only |
| `docs/OPERATIONS_CONSOLE.md` | Keep in sync with schema/actions each phase |

---

## 7. UI surface

Keep one HTML companion. Grow sections inside the existing Operations Console + Walkthrough + tabs:

| Surface | Role by phase |
|---------|----------------|
| Ops header score/pill | Already live; remain source of truth |
| Service cards | Phase 1: add/complete cards (modules, clipboard, LM Studio, OpenClaw, project capabilities) |
| Quick Actions | Phase 2–3: Diagnostics, Self-Test, Audit, Backup |
| Event Stream | Phase 3: richer filters/sources (= “live logs”) |
| Diagnostics Summary | Phase 2: structured list in addition to text blob |
| Walkthrough | Phase 3: verify-gated wizard steps |
| New/expanded tabs or panels | Environment Audit, Module Status, Architecture (thin), Prompt Library preview |
| Console tab | Remains recipes + “Open Hammerspoon Console” — **not** a browser REPL |
| Search | Phase 3: global client-side index |

Stale warning behavior (≥30s) remains.

---

## 8. Security and privacy

| Rule | Detail |
|------|--------|
| Allowlist only | Unknown `operations` actions rejected + warning event |
| Launch apps / AI prompts | Continue finite allowlists |
| Diagnostics | Fixed check IDs; no user-supplied shell |
| Events never log | Clipboard contents, AI prompt bodies, credentials, tokens, document bodies (existing rule) |
| Backup | Exclude secrets files; document what is included |
| Optional services | Probe only; do not auto-start n8n/Ollama/LM Studio/OpenClaw unless a future explicit allowlisted action is added and documented |

---

## 9. Error handling

- HTTP probes (Ollama, n8n, LM Studio, OpenClaw) stay async with timeouts; failures mark service degraded/unreachable, not a Lua crash
- Shell helpers must treat non-zero `rc` as failure and never coerce boolean `status` into string fields
- Self-test steps that need GUI automation fail soft with WARNING if Accessibility is missing
- HTML `fetch` failure shows existing stale/unavailable UX; never fabricates HEALTHY

---

## 10. Testing / verification per phase

| Phase | Manual verification |
|-------|---------------------|
| 0 | Reload HS; inspect `runtime/operations_status.json` project fields against `git` CLI |
| 1 | Cards match reality; kill Ollama → optional warn; quit Ghostty → score reflects |
| 2 | Run Diagnostics / Self-Test / Audit; PASS/FAIL lists match intentional faults |
| 3 | Search hits non-hotkey content; backup archive extracts; wizard verify advances |
| 4 | Hotkey duplicate flagged; architecture nodes match status; metrics update after probe |
| 5 | Only if implemented: recorder output compiles mentally; generator doesn’t wipe curated copy |

---

## 11. Success criteria (program-level)

1. Status JSON is trustworthy (Phase 0 done and stays done).
2. Opening the guide answers “is my automation stack OK?” without opening the HS console.
3. One-button diagnostics and self-test exist and write structured results.
4. Browser cannot run arbitrary Lua or shell.
5. Each shipped phase updates `docs/OPERATIONS_CONSOLE.md` and the walkthrough “Phase 2+” hints.
6. Deprecated Spencer is not resurrected as a status dependency.

---

## 12. Implementation notes for agents

- Prefer editing `operations_console.lua`, `verify.lua`, `USER_GUIDE.html`, and `docs/OPERATIONS_CONSOLE.md` over new top-level folders
- New module `diagnostics.lua` is allowed under `modules/` when Phase 2 starts
- Do not commit `runtime/` artifacts
- After moving paths, grep `*.lua`, `scripts/`, and `docs/USER_GUIDE.html` for stale references (per `AGENTS.md`)
- Commit only when the owner asks

---

## 13. Open questions (resolved)

| Question | Decision |
|----------|----------|
| Full multi-phase vs next-slice only | Full multi-phase design |
| Architecture approach | A — deepen existing console |
| Spine + disposition (§1) | Approved |
| Phases + schema (§2) | Approved |
| UI / security / success (§3) | Approved |
| Audit 2026-08-03 sequencing | Phase 0a absorb audit Stage 1 before Phase 1 |
| OpenClaw vs AI chords | AI keeps `⌃⌥⌘O`/`⌃⌥⌘S`; OpenClaw → `⌃⌥⌘U`/`⌃⌥⌘I` |
| Canonical project | `AI_Engineering_OS` via `paths.lua` |
| URL scheme auth | Allowlists only; no shared secret |
| Root guide symlink | Remove / keep inside this repo only |

---

## 14. Next step after approval

Implement **Phase 0a + 0b + Phase 1** per `docs/superpowers/plans/2026-08-03-ops-phase0-phase1.md`. Phases 2–5 get their own implementation plans when started.
