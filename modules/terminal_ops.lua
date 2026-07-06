-- Module: terminal_ops.lua
-- Responsibility: Launch Ghostty Terminal Operations Center layout.
local M = {}

local log = hs.logger.new('terminal_ops', 'info')
local scriptPath = hs.configdir .. '/scripts/ghostty/launch-terminal-operations-center.applescript'

local defaultProjectDir = os.getenv('HOME') .. '/Documents/01_Projects/BlackDragon_Project'
M.projectDir = os.getenv('TERMINAL_OPS_PROJECT_DIR') or defaultProjectDir
local paneScript = hs.configdir .. '/scripts/ghostty/terminal-ops-pane.sh'

local function escapeApplescriptString(s)
  return (s:gsub('\\', '\\\\'):gsub('"', '\\"'))
end

local function readScriptBody()
  local f, err = io.open(scriptPath, 'r')
  if not f then
    return nil, err or ('cannot open ' .. scriptPath)
  end
  local body = f:read('a')
  f:close()
  if not body or body == '' then
    return nil, 'empty AppleScript body'
  end
  return body
end

function M.launch()
  local projectDir = M.projectDir
  local attrs = hs.fs.attributes(projectDir)
  if not attrs or attrs.mode ~= 'directory' then
    hs.alert.show('⚠ Terminal Ops: project dir not found\n' .. tostring(projectDir))
    log.ef('project dir missing: %s', projectDir)
    return
  end

  local body, readErr = readScriptBody()
  if not body then
    hs.alert.show('⚠ Terminal Ops: ' .. tostring(readErr))
    log.ef('%s', readErr)
    return
  end

  local prelude = 'set projectDir to "' .. escapeApplescriptString(projectDir) .. '"\n'
    .. 'set paneScript to "' .. escapeApplescriptString(paneScript) .. '"\n'
  local tmpPath = (os.getenv('TMPDIR') or '/tmp/')
    .. 'ghostty-ops-center-' .. tostring(hs.host.uuid()) .. '.applescript'
  local tmp, openErr = io.open(tmpPath, 'w')
  if not tmp then
    hs.alert.show('⚠ Terminal Ops: cannot write temp script\n' .. tostring(openErr))
    log.ef('temp script open failed: %s', tostring(openErr))
    return
  end
  tmp:write(prelude .. body)
  tmp:close()

  local cmd = string.format('/usr/bin/osascript %q', tmpPath)
  local ok, output, exitType, rc = hs.execute(cmd)
  os.remove(tmpPath)
  if not ok or (rc and rc ~= 0) then
    local detail = tostring(output or 'unknown AppleScript error')
    hs.alert.show('⚠ Ghostty launch failed\n' .. detail)
    log.ef('osascript failed: %s', detail)
    return
  end

  hs.alert.show('🖥 Terminal Operations Center')
  log.i('launched Ghostty layout at %s', projectDir)
end

return M
