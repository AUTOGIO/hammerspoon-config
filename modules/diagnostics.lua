-- Module: diagnostics.lua
-- Responsibility: Named PASS/FAIL/WARNING checks for diagnostics and environment audit.
-- No URL handler — called only via operations_console allowlisted actions.
local M = {}

local paths = require('modules.paths')

local HOME = os.getenv('HOME') or ''
local GHOSTTY_CONFIG = HOME .. '/.config/ghostty/config'
local TERMINAL_OPS_CONFIG = hs.configdir .. '/scripts/ghostty/ghostty-terminal-ops-center.conf'
local PANE_SCRIPT = hs.configdir .. '/scripts/ghostty/terminal-ops-pane.sh'
local LAUNCH_COMMAND = hs.configdir .. '/scripts/ghostty/launch-terminal-operations-center.command'

local OLLAMA_URL = 'http://127.0.0.1:11434/api/tags'
local N8N_URL = 'http://127.0.0.1:5678'
local LM_STUDIO_URL = 'http://127.0.0.1:1234/v1/models'
local OPENCLAW_URL = 'http://127.0.0.1:18789/'

local function isoNow()
  local z = os.date('%z') or '+0000'
  if #z == 5 then z = z:sub(1, 3) .. ':' .. z:sub(4, 5) end
  return os.date('%Y-%m-%dT%H:%M:%S') .. z
end

local function pathExists(path)
  return hs.fs.attributes(path) ~= nil
end

local function isDir(path)
  local attrs = hs.fs.attributes(path)
  return attrs and attrs.mode == 'directory'
end

-- hs.http.get returns status, body, headers
local function httpGetStatus(url)
  local okCall, status = pcall(function()
    local code = hs.http.get(url, nil)
    return tonumber(code) or -1
  end)
  if not okCall then return -1 end
  return tonumber(status) or -1
end

local function scoreFromChecks(checks)
  local pass, fail, warn = 0, 0, 0
  local weighted, total = 0, 0
  for _, c in ipairs(checks) do
    total = total + 1
    if c.result == 'PASS' then
      pass = pass + 1
      weighted = weighted + 1
    elseif c.result == 'WARNING' then
      warn = warn + 1
      weighted = weighted + 0.5
    else
      fail = fail + 1
    end
  end
  local score = total > 0 and math.floor((weighted / total) * 100 + 0.5) or 0
  return score, pass, fail, warn
end

local function add(checks, id, result, detail)
  checks[#checks + 1] = {
    id = id,
    result = result,
    detail = detail or '',
  }
end

function M.runDiagnostics()
  local checks = {}

  add(checks, 'hammerspoon_running', 'PASS', 'diagnostics module executing')

  local accessibility = nil
  pcall(function()
    if hs.accessibilityState then accessibility = hs.accessibilityState() end
  end)
  if accessibility == false then
    add(checks, 'accessibility', 'FAIL', 'Accessibility not granted')
  elseif accessibility == true then
    add(checks, 'accessibility', 'PASS', 'granted')
  else
    add(checks, 'accessibility', 'WARNING', 'could not read accessibility state')
  end

  if isDir(hs.configdir) then
    add(checks, 'config_dir', 'PASS', hs.configdir)
  else
    add(checks, 'config_dir', 'FAIL', 'hs.configdir missing: ' .. tostring(hs.configdir))
  end

  local ghosttyApp = pathExists('/Applications/Ghostty.app')
  local ghosttyRunning = hs.application.find('Ghostty') ~= nil
  if ghosttyApp or ghosttyRunning then
    add(checks, 'ghostty_app', 'PASS', ghosttyRunning and 'installed + running' or 'installed')
  else
    add(checks, 'ghostty_app', 'FAIL', 'Ghostty.app not found')
  end

  if pathExists(GHOSTTY_CONFIG) then
    add(checks, 'ghostty_config', 'PASS', GHOSTTY_CONFIG)
  else
    add(checks, 'ghostty_config', 'WARNING', 'missing ' .. GHOSTTY_CONFIG)
  end

  if pathExists(TERMINAL_OPS_CONFIG) then
    add(checks, 'terminal_ops_config', 'PASS', TERMINAL_OPS_CONFIG)
  else
    add(checks, 'terminal_ops_config', 'WARNING', 'missing terminal ops conf')
  end

  local proj = paths.resolveBlackDragonProject()
  if isDir(proj) then
    add(checks, 'project_path', 'PASS', proj)
  else
    add(checks, 'project_path', 'FAIL', 'not a directory: ' .. tostring(proj))
  end

  local coreOk = true
  local coreDetail = {}
  for _, name in ipairs({ 'windows', 'layouts', 'paths' }) do
    local ok = pcall(require, 'modules.' .. name)
    if ok then
      coreDetail[#coreDetail + 1] = name .. '=ok'
    else
      coreOk = false
      coreDetail[#coreDetail + 1] = name .. '=FAIL'
    end
  end
  add(checks, 'module_core', coreOk and 'PASS' or 'FAIL', table.concat(coreDetail, ', '))

  local ollamaCode = httpGetStatus(OLLAMA_URL)
  if ollamaCode == 200 then
    add(checks, 'ollama_endpoint', 'PASS', 'HTTP 200')
  else
    add(checks, 'ollama_endpoint', 'WARNING', 'HTTP ' .. tostring(ollamaCode))
  end

  local n8nCode = httpGetStatus(N8N_URL)
  if n8nCode == 200 or n8nCode == 404 then
    add(checks, 'n8n_endpoint', 'PASS', 'HTTP ' .. tostring(n8nCode))
  else
    add(checks, 'n8n_endpoint', 'WARNING', 'HTTP ' .. tostring(n8nCode))
  end

  local lmCode = httpGetStatus(LM_STUDIO_URL)
  if lmCode == 200 then
    add(checks, 'lm_studio_endpoint', 'PASS', 'HTTP 200')
  else
    add(checks, 'lm_studio_endpoint', 'WARNING', 'HTTP ' .. tostring(lmCode))
  end

  local ocCode = httpGetStatus(OPENCLAW_URL)
  if ocCode == 200 then
    add(checks, 'openclaw_endpoint', 'PASS', 'HTTP 200')
  else
    add(checks, 'openclaw_endpoint', 'WARNING', 'HTTP ' .. tostring(ocCode))
  end

  local score, pass, fail, warn = scoreFromChecks(checks)
  return {
    at = isoNow(),
    score = score,
    pass = pass,
    fail = fail,
    warn = warn,
    checks = checks,
  }
end

function M.runEnvironmentAudit()
  local checks = {}

  local shell = os.getenv('SHELL') or ''
  if shell ~= '' then
    add(checks, 'shell', 'PASS', shell)
  else
    add(checks, 'shell', 'WARNING', 'SHELL unset')
  end

  local pathEnv = os.getenv('PATH') or ''
  if pathEnv:find('/opt/homebrew/bin', 1, true) or pathExists('/opt/homebrew/bin') then
    add(checks, 'path_homebrew', 'PASS', 'Homebrew bin available')
  else
    add(checks, 'path_homebrew', 'WARNING', '/opt/homebrew/bin not in PATH')
  end

  local hsLink = HOME .. '/.hammerspoon'
  local linkAttrs = hs.fs.symlinkAttributes(hsLink)
  if linkAttrs and linkAttrs.mode == 'link' then
    add(checks, 'hs_config_symlink', 'PASS', 'symlink → ' .. tostring(linkAttrs.target or '?'))
  elseif isDir(hsLink) or isDir(hs.configdir) then
    add(checks, 'hs_config_symlink', 'PASS', 'real directory ' .. tostring(hs.configdir))
  else
    add(checks, 'hs_config_symlink', 'FAIL', '~/.hammerspoon missing')
  end

  if pathExists(GHOSTTY_CONFIG) then
    add(checks, 'ghostty_config', 'PASS', GHOSTTY_CONFIG)
  else
    add(checks, 'ghostty_config', 'WARNING', 'missing Ghostty config')
  end

  if pathExists(PANE_SCRIPT) then
    add(checks, 'ops_pane_script', 'PASS', PANE_SCRIPT)
  else
    add(checks, 'ops_pane_script', 'FAIL', 'terminal-ops-pane.sh missing')
  end

  if pathExists(LAUNCH_COMMAND) then
    add(checks, 'launch_command', 'PASS', LAUNCH_COMMAND)
  else
    add(checks, 'launch_command', 'FAIL', 'launch-terminal-operations-center.command missing')
  end

  local proj = paths.resolveBlackDragonProject()
  if proj and proj ~= '' then
    add(checks, 'paths_module', 'PASS', proj)
  else
    add(checks, 'paths_module', 'FAIL', 'empty project resolve')
  end

  local aiOk = pcall(require, 'modules.ai')
  add(checks, 'ai_module', aiOk and 'PASS' or 'FAIL', aiOk and 'loaded' or 'require failed')

  local clipOk, clip = pcall(require, 'modules.clipboard')
  if clipOk and clip and clip.watcherAlive and clip.watcherAlive() then
    add(checks, 'clipboard_watcher', 'PASS', 'watcher alive, count=' .. tostring(clip.count and clip.count() or '?'))
  elseif clipOk then
    add(checks, 'clipboard_watcher', 'WARNING', 'clipboard loaded but watcher not alive')
  else
    add(checks, 'clipboard_watcher', 'FAIL', 'clipboard module unavailable')
  end

  if pathExists(HOME .. '/.zshrc') then
    add(checks, 'zshrc_hint', 'PASS', '~/.zshrc present')
  else
    add(checks, 'zshrc_hint', 'WARNING', '~/.zshrc missing')
  end

  local score, pass, fail, warn = scoreFromChecks(checks)
  local issues = {}
  for _, c in ipairs(checks) do
    if c.result == 'FAIL' or c.result == 'WARNING' then
      issues[#issues + 1] = { id = c.id, detail = c.detail, result = c.result }
    end
  end

  return {
    at = isoNow(),
    score = score,
    pass = pass,
    fail = fail,
    warn = warn,
    issues = issues,
    checks = checks,
  }
end

return M
