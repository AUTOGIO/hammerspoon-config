# Ops Console Phase 3 — Ops UX

> **For agentic workers:** Implement task-by-task. Commit only when the owner asks.

**Goal:** Search everything, richer event logs, verify-gated walkthrough steps, AI prompt library with preview, and configuration backup.

**Architecture:** Approach A — extend `operations_console` allowlist + `ai.lua` catalog + `USER_GUIDE.html` client features. No localhost server.

## Global Constraints

- Allowlisted browser actions only; no arbitrary shell/Lua from HTML
- Do not commit `runtime/` or secrets
- Backup excludes `runtime/`, `.git/`, `.env*`
- Events never log clipboard/AI prompt bodies/credentials

## Tasks

1. `backup_configuration` action → dated dir under `~/.hammerspoon/backups/` + MANIFEST
2. Expand `ai.lua` prompt library + `allowedAiPrompts`
3. USER_GUIDE: global search, event source filters/badges, prompt library preview UI, backup + prefs export buttons
4. Walkthrough: diagnostics/self-test steps auto-detect PASS; docs update

Exit: search works across sections; wizard can run/verify suites; prompt preview then handoff; one backup archive from console.
