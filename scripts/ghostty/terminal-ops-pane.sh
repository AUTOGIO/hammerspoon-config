#!/bin/zsh
set -euo pipefail

pane="${1:-}"
project_dir="${TERMINAL_OPS_PROJECT_DIR:-${PROJECT_DIR:-$HOME}}"

if [[ -z "$pane" ]]; then
  echo "Usage: terminal-ops-pane.sh <pane-id>"
  echo "Override per project: \$project_dir/.terminal-ops/pane.sh (pane_<id> functions)"
  exit 1
fi

if [[ -f "$project_dir/.terminal-ops/pane.sh" ]]; then
  # shellcheck source=/dev/null
  source "$project_dir/.terminal-ops/pane.sh"
  if typeset -f "pane_$pane" >/dev/null 2>&1; then
    "pane_$pane"
    exit 0
  fi
fi

cd "$project_dir" 2>/dev/null || true

case "$pane" in
  backend-orchestration)
    if [[ -x ./launch.sh ]]; then
      ./launch.sh release
    elif [[ -f docker-compose.yml ]] && command -v docker >/dev/null 2>&1; then
      docker compose up
    elif [[ -f package.json ]]; then
      if command -v pnpm >/dev/null 2>&1; then pnpm dev; else npm run dev; fi
    elif [[ -f Makefile ]] && grep -q '^run:' Makefile 2>/dev/null; then
      make run
    else
      echo "No auto-start found — shell ready in $project_dir"
      exec "$SHELL" -l
    fi
    ;;
  backend-telemetry)
    if command -v log >/dev/null 2>&1; then
      log stream --style compact --level debug
    else
      echo "Install macOS log tool or override pane_backend-telemetry in .terminal-ops/pane.sh"
      tail -f /var/log/system.log 2>/dev/null || exec "$SHELL" -l
    fi
    ;;
  ai-model-ops)
    if command -v ollama >/dev/null 2>&1; then
      ollama serve
    else
      echo "ollama not found — brew install ollama"
      echo "Or LM Studio: curl -s http://localhost:1234/v1/models"
      exec "$SHELL" -l
    fi
    ;;
  ai-eval-prompt)
    if [[ -x ./launch.sh ]]; then
      ./launch.sh test
    elif [[ -f package.json ]]; then
      npm test 2>/dev/null || pnpm test 2>/dev/null || echo "Add a test script to package.json"
    else
      echo "Prompt / eval shell — override pane_ai-eval-prompt in .terminal-ops/pane.sh"
      exec "$SHELL" -l
    fi
    ;;
  data-postgresql)
    if command -v psql >/dev/null 2>&1 && [[ -n "${DATABASE_URL:-}" ]]; then
      psql "$DATABASE_URL"
    elif command -v psql >/dev/null 2>&1; then
      echo "Set DATABASE_URL or override pane_data-postgresql"
      exec "$SHELL" -l
    else
      echo "psql not found — override pane_data-postgresql in .terminal-ops/pane.sh"
      exec "$SHELL" -l
    fi
    ;;
  data-redis)
    if command -v redis-cli >/dev/null 2>&1; then
      redis-cli ${REDIS_URL:+-u "$REDIS_URL"}
    else
      echo "redis-cli not found — override pane_data-redis in .terminal-ops/pane.sh"
      exec "$SHELL" -l
    fi
    ;;
  automation-workers)
    if [[ -f Procfile ]] && command -v foreman >/dev/null 2>&1; then
      foreman start
    elif [[ -f docker-compose.yml ]] && command -v docker >/dev/null 2>&1; then
      docker compose up worker 2>/dev/null || docker compose up
    else
      echo "Worker shell — override pane_automation-workers in .terminal-ops/pane.sh"
      exec "$SHELL" -l
    fi
    ;;
  automation-queue-health)
    if command -v redis-cli >/dev/null 2>&1; then
      redis-cli INFO | grep -E '^(connected_clients|used_memory| instantaneous_ops)'
      redis-cli --scan --pattern '*queue*' 2>/dev/null | head -20
      exec "$SHELL" -l
    else
      echo "Queue health shell — override pane_automation-queue-health in .terminal-ops/pane.sh"
      exec "$SHELL" -l
    fi
    ;;
  git-deploy)
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git status -sb
      echo ""
      git diff --stat
    else
      echo "Not a git repo: $project_dir"
      exec "$SHELL" -l
    fi
    ;;
  git-logs)
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git log -20 --oneline --decorate
    else
      echo "Not a git repo: $project_dir"
      exec "$SHELL" -l
    fi
    ;;
  *)
    echo "Unknown pane: $pane"
    echo "Valid ids: backend-orchestration backend-telemetry ai-model-ops ai-eval-prompt"
    echo "             data-postgresql data-redis automation-workers automation-queue-health"
    echo "             git-deploy git-logs"
    exit 1
    ;;
esac
