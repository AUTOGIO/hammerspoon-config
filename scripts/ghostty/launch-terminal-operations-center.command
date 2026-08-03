#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
DEFAULT_PROJECT_DIR="$HOME/Documents/GitHub/AI_Engineering_OS"
PROJECT_DIR="${PROJECT_DIR:-${TERMINAL_OPS_PROJECT_DIR:-$DEFAULT_PROJECT_DIR}}"
PROJECT_DIR_ESCAPED="${PROJECT_DIR//\"/\\\"}"
PANE_SCRIPT="$SCRIPT_DIR/terminal-ops-pane.sh"
PANE_SCRIPT_ESCAPED="${PANE_SCRIPT//\"/\\\"}"

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "Project directory not found: $PROJECT_DIR"
  echo "Set PROJECT_DIR and run again, for example:"
  echo "  PROJECT_DIR=/path/to/your/repo $0"
  exit 1
fi

BODY_FILE="$SCRIPT_DIR/launch-terminal-operations-center.applescript"
if [[ ! -f "$BODY_FILE" ]]; then
  echo "Missing AppleScript body: $BODY_FILE"
  exit 1
fi

# Pipe avoids zsh history expansion on "!" when this file is pasted into an
# interactive shell (e.g. [[ ! -d ... ]] or a stray #!/bin/zsh line).
if [[ ! -x "$PANE_SCRIPT" ]]; then
  echo "Missing pane bootstrap script: $PANE_SCRIPT"
  exit 1
fi

SCRIPT_FILE="$(mktemp "${TMPDIR:-/tmp}/ghostty-ops-center.XXXXXX.applescript")"
trap 'rm -f "$SCRIPT_FILE"' EXIT INT TERM
{
  print -r "set projectDir to \"${PROJECT_DIR_ESCAPED}\""
  print -r "set paneScript to \"${PANE_SCRIPT_ESCAPED}\""
  cat "$BODY_FILE"
} > "$SCRIPT_FILE"
osascript "$SCRIPT_FILE"
