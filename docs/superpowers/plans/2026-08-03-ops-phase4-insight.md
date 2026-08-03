# Ops Console Phase 4 — Insight

> Implement and verify. Commit only when the owner asks.

**Goal:** Hotkey conflict scan (HS-only), thin host metrics, status-lit architecture map, light performance probe timings.

**Constraints:** Approach A; allowlist only; no Activity Monitor clone; macOS/Raycast/Cursor conflicts out of band (document in UI).

## Deliverables

1. `modules/insight.lua` — `scanHotkeys()`, `hostMetrics()`, `runPerfProbes()`
2. `operations_console` — include `system` metrics on refresh; actions `run_hotkey_scan`, `run_perf_probes`; preserve `hotkeys` / `metrics` across refresh
3. USER_GUIDE Insight panel — architecture diagram nodes lit from status; hotkey conflicts list; metrics + timings
4. Docs update in OPERATIONS_CONSOLE.md

Exit: see HS duplicates, lit architecture map, recent timings in status JSON.
