#!/bin/zsh
# #region agent log
LOG="/Users/e.f.g./.cursor/debug-logs/debug-a3a110.log"
log() {
  print -r -- "{\"sessionId\":\"a3a110\",\"runId\":\"pre-fix\",\"hypothesisId\":\"$1\",\"location\":\"debug-histexpand.zsh\",\"message\":\"$2\",\"data\":$3,\"timestamp\":$(date +%s000)}" >>"$LOG"
}
# #endregion

setopt | grep -q '^banghist$' && HIST_ON=1 || HIST_ON=0
log "A" "bang_hist_option" "{\"bangHist\":$HIST_ON,\"interactive\":$([[ -o interactive ]] && echo 1 || echo 0)}"

# Hypothesis A: shebang line triggers expansion when submitted to interactive zsh
if [[ -o interactive && -o banghist ]]; then
  OUT=$( ( setopt localoptions; print -rn -- '#!/bin/zsh' ) 2>&1 )
  log "A" "shebang_simulation" "{\"output\":\"${OUT//\"/\\\"}\"}"
fi

# Hypothesis B: unquoted heredoc expands ! inside shell test from pasted .command
OUT_B=$(zsh -c 'setopt BANG_HIST; print -rn -- "[[ ! -d foo ]]"' 2>&1) || true
log "B" "bang_in_test" "{\"output\":\"${OUT_B//\"/\\\"}\"}"

# Hypothesis C: applescript body has no bang
BODY="/Users/e.f.g./.hammerspoon/scripts/ghostty/launch-terminal-operations-center.applescript"
BANGS=$(grep -c '!' "$BODY" 2>/dev/null || echo 0)
log "C" "applescript_bang_count" "{\"file\":\"$BODY\",\"bangCount\":$BANGS}"

# Hypothesis D: pipe launcher avoids histexpand on body
CMD="/Users/e.f.g./.hammerspoon/scripts/ghostty/launch-terminal-operations-center.command"
log "D" "launcher_exists" "{\"exists\":$([[ -f $CMD ]] && echo 1 || echo 0)}"
