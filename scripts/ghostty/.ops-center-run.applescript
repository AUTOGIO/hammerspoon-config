set projectDir to "/Users/e.f.g./Documents/01_Projects/BlackDragon_Project"
set paneScript to "/Users/e.f.g./.hammerspoon/scripts/ghostty/terminal-ops-pane.sh"
-- Ghostty Terminal Operations Center launcher for macOS.
-- Hammerspoon (modules/terminal_ops.lua) or launch-terminal-operations-center.command
-- inject: set projectDir and paneScript before this script body runs.
-- Note: no handlers — AppleScript fails to resolve Ghostty terms inside handlers.

tell application "Ghostty"
	activate

	set cfg to new surface configuration
	set initial working directory of cfg to projectDir
	set font size of cfg to 13
	set envVars to {"EDITOR=nvim", "PAGER=less", "TERM=xterm-256color", "TERMINAL_OPS_PROJECT_DIR=" & projectDir}
	set environment variables of cfg to envVars

	set initial input of cfg to "clear; echo " & quoted form of "Backend | Orchestration" & "; " & quoted form of paneScript & " " & quoted form of "backend-orchestration" & return
	set win to new window with configuration cfg
	set tab1 to selected tab of win
	set pane1 to terminal 1 of tab1

	set initial input of cfg to "clear; echo " & quoted form of "Backend | Telemetry" & "; " & quoted form of paneScript & " " & quoted form of "backend-telemetry" & return
	set pane2 to split pane1 direction right with configuration cfg

	set initial input of cfg to "clear; echo " & quoted form of "AI | Model Ops" & "; " & quoted form of paneScript & " " & quoted form of "ai-model-ops" & return
	set tab2 to new tab in win with configuration cfg
	set ai1 to terminal 1 of tab2

	set initial input of cfg to "clear; echo " & quoted form of "AI | Eval + Prompt" & "; " & quoted form of paneScript & " " & quoted form of "ai-eval-prompt" & return
	set ai2 to split ai1 direction right with configuration cfg

	set initial input of cfg to "clear; echo " & quoted form of "Data | PostgreSQL" & "; " & quoted form of paneScript & " " & quoted form of "data-postgresql" & return
	set tab3 to new tab in win with configuration cfg
	set db1 to terminal 1 of tab3

	set initial input of cfg to "clear; echo " & quoted form of "Data | Redis" & "; " & quoted form of paneScript & " " & quoted form of "data-redis" & return
	set db2 to split db1 direction right with configuration cfg

	set initial input of cfg to "clear; echo " & quoted form of "Automation | Workers" & "; " & quoted form of paneScript & " " & quoted form of "automation-workers" & return
	set tab4 to new tab in win with configuration cfg
	set q1 to terminal 1 of tab4

	set initial input of cfg to "clear; echo " & quoted form of "Automation | Queue Health" & "; " & quoted form of paneScript & " " & quoted form of "automation-queue-health" & return
	set q2 to split q1 direction right with configuration cfg

	set initial input of cfg to "clear; echo " & quoted form of "Git | Deploy" & "; " & quoted form of paneScript & " " & quoted form of "git-deploy" & return
	set tab5 to new tab in win with configuration cfg
	set ops1 to terminal 1 of tab5

	set initial input of cfg to "clear; echo " & quoted form of "Git | Logs" & "; " & quoted form of paneScript & " " & quoted form of "git-logs" & return
	set ops2 to split ops1 direction right with configuration cfg

	focus pane1
end tell
