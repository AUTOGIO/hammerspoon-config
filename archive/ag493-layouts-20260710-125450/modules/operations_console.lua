-- Module: operations_console.lua
-- Responsibility: Local operations dashboard — status JSON, event log, allowlisted actions.
local M = {}

local log = hs.logger.new('operations', 'info')

local RUNTIME_DIR   = hs.configdir .. '/runtime'
local STATUS_PATH   = RUNTIME_DIR .. '/operations_status.json'
local EVENTS_PATH   = RUNTIME_DIR .. '/operations_events.json'
local MAX_EVENTS    = 200
local REFRESH_SEC   = 30

local GHOSTTY_CONFIG       = os.getenv('HOME') .. '/.config/ghostty/config'
local TERMINAL_OPS_CONFIG  = hs.configdir .. '/scripts/ghostty/ghostty-terminal-ops-center.conf'
local DEFAULT_PROJECT_DIR  = os.getenv('HOME') .. '/Documents/01_Projects/BlackDragon_Project'
local OLLAMA_URL           = 'http://127.0.0.1:11434/api/tags'
local N8N_URL              = 'http://127.0.0.1:5678'

local statusCache = {}
local refreshTimer = nil
local startedAt = nil
local httpPending = 0

local allowedActions = {
  refresh_status          = true,
  launch_terminal_ops     = true,
  reload_hammerspoon      = true,
  apply_coding_layout     = true,
  apply_ai_layout         = true,
  apply_ops_layout        = true,
  apply_writing_layout    = true,
  toggle_auto_tile        = true,
  run_verification        = true,
  open_guide              = true,
  open_hammerspoon_folder = true,
  open_project_folder     = true,
  open_ghostty_config     = true,
  open_terminal_ops_config = true,
  copy_diagnostics        = true,
  open_event_log          = true,
  clear_event_display     = true,
  open_hammerspoon_console = true,
}

local MODULE_KEYS = { 'layouts', 'windows', 'terminal_ops', 'clipboard', 'ai', 'n8n', 'guide', 'verify' }

-- ── Utilities ────────────────────────────────────────────────────────────────

local function isoNow()
  local z = os.date('%z') or '+0000'
  if #z == 5 then z = z:sub(1, 3) .. ':' .. z:sub(4, 5) end
  return os.date('%Y-%m-%dT%H:%M:%S') .. z
end

local function shellQuote(s)
  return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

local function pathExists(path)
  local attrs = hs.fs.attributes(path)
  return attrs ~= nil
end

local function isDir(path)
  local attrs = hs.fs.attributes(path)
  return attrs and attrs.mode == 'directory'
end

local function ensureRuntimeDir()
  if not isDir(RUNTIME_DIR) then
    hs.fs.mkdir(RUNTIME_DIR)
  end
  return isDir(RUNTIME_DIR)
end

local function atomicWriteJSON(path, data)
  ensureRuntimeDir()
  local body = hs.json.encode(data, true)
  if not body then return false, 'json encode failed' end
  local tmp = path .. '.tmp'
  local f, err = io.open(tmp, 'w')
  if not f then return false, err or 'open failed' end
  f:write(body)
  f:close()
  os.remove(path)
  local ok, renameErr = os.rename(tmp, path)
  if not ok then
    os.remove(tmp)
    return false, renameErr or 'rename failed'
  end
  return true
end

local function readJSON(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local body = f:read('a')
  f:close()
  if not body or body == '' then return nil end
  return hs.json.decode(body)
end

local function runShell(cmd)
  local ok, output = hs.execute(cmd .. ' 2>/dev/null')
  if type(output) ~= 'string' then output = tostring(output or '') end
  output = output:gsub('%s+$', '')
  return ok, output
end

local function projectDir()
  local terminal_ops = package.loaded['modules.terminal_ops']
  if terminal_ops and terminal_ops.projectDir then
    return terminal_ops.projectDir
  end
  return DEFAULT_PROJECT_DIR
end

-- ── Events ─────────────────────────────────────────────────────────────────

function M.recordEvent(event)
  ensureRuntimeDir()
  local events = readJSON(EVENTS_PATH) or {}
  if type(events) ~= 'table' then events = {} end

  local entry = {
    timestamp = event.timestamp or isoNow(),
    severity  = event.severity or 'info',
    source    = event.source or 'operations',
    action    = event.action,
    message   = event.message or '',
    success   = event.success,
  }

  table.insert(events, 1, entry)
  while #events > MAX_EVENTS do
    table.remove(events)
  end

  atomicWriteJSON(EVENTS_PATH, events)
  return entry
end

local function loadEvents()
  local events = readJSON(EVENTS_PATH)
  if type(events) ~= 'table' then return {} end
  return events
end

-- ── Health checks ────────────────────────────────────────────────────────────

local function checkModuleHealth(name)
  local ok, mod = pcall(require, 'modules.' .. name)
  if ok and mod then return 'healthy' end
  return 'unavailable'
end

local function checkHammerspoon()
  local accessibility = nil
  pcall(function()
    if hs.accessibilityState then
      accessibility = hs.accessibilityState()
    end
  end)

  local screens = hs.screen.allScreens()
  local focused = nil
  pcall(function()
    local w = hs.window.focusedWindow()
    if w then focused = w:screen():name() end
  end)

  return {
    status = 'running',
    config_loaded = true,
    last_reload = startedAt or isoNow(),
    accessibility = accessibility,
    screen_count = #screens,
    focused_screen = focused,
  }
end

local function checkGhostty()
  local app = hs.application.find('Ghostty')
  local running = app ~= nil
  local pidCount = 0
  if running then pidCount = 1 end

  local ok, out = runShell('pgrep -x Ghostty | wc -l | tr -d " "')
  if ok and out ~= '' then
    local n = tonumber(out)
    if n and n > 0 then pidCount = n end
  end

  local configExists = pathExists(GHOSTTY_CONFIG)
  local opsConfigExists = pathExists(TERMINAL_OPS_CONFIG)
  local proj = projectDir()
  local projectExists = isDir(proj)

  local state = 'stopped'
  if running then state = 'running' end

  local diagnostic = {}
  if not configExists then diagnostic[#diagnostic + 1] = 'ghostty config missing' end
  if not opsConfigExists then diagnostic[#diagnostic + 1] = 'terminal ops config missing' end
  if not projectExists then diagnostic[#diagnostic + 1] = 'project dir missing' end

  return {
    status = state,
    pid_count = pidCount,
    installed = pathExists('/Applications/Ghostty.app') or running,
    config_exists = configExists,
    terminal_ops_config_exists = opsConfigExists,
    project_dir_exists = projectExists,
    project_dir = proj,
    diagnostic = table.concat(diagnostic, '; '),
  }
end

local function checkOllamaSync()
  local ok, out = runShell('pgrep -x ollama >/dev/null; echo $?')
  local processRunning = false
  local _, rcOut = runShell('pgrep -x ollama >/dev/null && echo yes || echo no')
  processRunning = rcOut == 'yes'

  return {
    status = processRunning and 'running' or 'stopped',
    process_running = processRunning,
    endpoint_reachable = false,
    models = {},
    failure_reason = processRunning and 'endpoint unreachable' or 'process not running',
  }
end

local function checkN8nSync()
  local ok, out = runShell('pgrep -f n8n >/dev/null && echo yes || echo no')
  local processDetected = out == 'yes'
  return {
    status = 'degraded',
    process_detected = processDetected,
    endpoint_reachable = false,
    failure_reason = 'endpoint unreachable',
  }
end

local function checkProject()
  local dir = projectDir()
  local exists = isDir(dir)
  local info = {
    path_exists = exists,
    path = dir,
    git_repository = false,
    branch = nil,
    dirty = nil,
    latest_commit = nil,
    disk_usage = nil,
  }

  if not exists then
    info.diagnostic = 'project directory not found'
    return info
  end

  local _, gitRoot = runShell(string.format('git -C %s rev-parse --is-inside-work-tree', shellQuote(dir)))
  info.git_repository = gitRoot == 'true'

  if info.git_repository then
    local _, branch = runShell(string.format('git -C %s rev-parse --abbrev-ref HEAD', shellQuote(dir)))
    info.branch = branch ~= '' and branch or nil

    local _, dirty = runShell(string.format('git -C %s status --porcelain', shellQuote(dir)))
    info.dirty = dirty ~= nil and dirty ~= ''

    local _, commit = runShell(string.format('git -C %s log -1 --oneline', shellQuote(dir)))
    info.latest_commit = commit ~= '' and commit or nil
  end

  local _, du = runShell(string.format('/usr/bin/du -sh %s | cut -f1', shellQuote(dir)))
  info.disk_usage = du ~= '' and du or nil
  info.diagnostic = info.git_repository
    and string.format('branch %s, %s', info.branch or '?', info.dirty and 'dirty' or 'clean')
    or 'not a git repository'

  return info
end

local function checkDisplays()
  local windows = package.loaded['modules.windows']
  local layouts = package.loaded['modules.layouts']
  local items = {}
  local warnings = {}

  for _, screen in ipairs(hs.screen.allScreens()) do
    local f = screen:frame()
    local vf = f
    pcall(function()
      local v = screen:visibleFrame()
      if v then vf = v end
    end)
    local mode = 'unknown'
    if windows and windows.modeFor then
      local mok, mval = pcall(windows.modeFor, windows, screen)
      if mok then mode = mval end
    end
    local aspect = f.h > 0 and (f.w / f.h) or 0
    items[#items + 1] = {
      name = screen:name() or '?',
      width = f.w,
      height = f.h,
      visible_width = vf.w,
      visible_height = vf.h,
      aspect = math.floor(aspect * 100) / 100,
      mode = mode,
      main = screen == hs.screen.mainScreen(),
    }
  end

  if layouts and layouts.layouts then
    for _, key in ipairs(layouts.order or {}) do
      if not layouts.layouts[key] then
        warnings[#warnings + 1] = 'missing layout: ' .. key
      end
    end
  end

  local focusedName = nil
  pcall(function()
    local w = hs.window.focusedWindow()
    if w then focusedName = w:screen():name() end
  end)

  return {
    count = #items,
    items = items,
    auto_tile_enabled = windows and windows.autoTile or nil,
    active_layout = layouts and layouts.activeLayout or nil,
    layout_catalog = layouts and layouts.order or {},
    focused_display = focusedName,
    warnings = warnings,
  }
end

local function computeOverall(services, modules)
  local score = 0
  local total = 0
  local lastError = nil

  local function weigh(points, ok, errMsg)
    total = total + points
    if ok then score = score + points else lastError = errMsg or lastError end
  end

  weigh(15, services.hammerspoon and services.hammerspoon.status == 'running', nil)
  weigh(10, services.hammerspoon and services.hammerspoon.accessibility ~= false,
    'accessibility permission may be missing')
  weigh(15, services.ghostty and services.ghostty.status == 'running', 'ghostty not running')
  weigh(10, services.ghostty and services.ghostty.config_exists, 'ghostty config missing')
  weigh(15, services.ollama and services.ollama.endpoint_reachable, services.ollama and services.ollama.failure_reason)
  weigh(10, services.n8n and services.n8n.endpoint_reachable, services.n8n and services.n8n.failure_reason)
  weigh(15, services.project and services.project.path_exists, 'project path missing')
  weigh(10, services.project and services.project.git_repository, nil)

  for _, state in pairs(modules or {}) do
    total = total + 2
    if state == 'healthy' then score = score + 2 end
  end

  local pct = total > 0 and math.floor((score / total) * 100) or 0
  local label = 'UNKNOWN'
  if pct >= 85 then label = 'HEALTHY'
  elseif pct >= 60 then label = 'DEGRADED'
  else label = 'CRITICAL' end

  return {
    status = label,
    score = pct,
    last_error = lastError,
  }
end

local function buildDiagnosticsText(st)
  st = st or statusCache
  local o = st.overall or {}
  local lines = {
    'BlackDragon Diagnostics',
    string.format('Health: %s/100', tostring(o.score or '?')),
    string.format('Hammerspoon: %s', (st.hammerspoon and st.hammerspoon.status) or '?'),
    string.format('Ghostty: %s', (st.services and st.services.ghostty and st.services.ghostty.status) or '?'),
    string.format('Ollama: %s', (st.services and st.services.ollama and st.services.ollama.endpoint_reachable) and 'Running' or 'Unreachable'),
    string.format('n8n: %s', (st.services and st.services.n8n and st.services.n8n.endpoint_reachable) and 'Running' or 'Unreachable'),
    string.format('Displays: %s', tostring(st.displays and st.displays.count or '?')),
  }

  local proj = st.services and st.services.project
  if proj then
    lines[#lines + 1] = string.format('Project: %s, branch %s',
      proj.dirty and 'Dirty' or (proj.path_exists and 'Clean' or 'Missing'),
      proj.branch or 'n/a')
  end

  if o.last_error then
    lines[#lines + 1] = 'Last error: ' .. tostring(o.last_error)
  end

  return table.concat(lines, '\n')
end

-- ── Status refresh ───────────────────────────────────────────────────────────

local function writeStatus(data)
  statusCache = data
  local ok, err = atomicWriteJSON(STATUS_PATH, data)
  if not ok then
    log.ef('status write failed: %s', tostring(err))
    M.recordEvent({
      severity = 'error',
      source = 'operations',
      action = 'refresh_status',
      message = 'Failed to write status JSON: ' .. tostring(err),
      success = false,
    })
  end
  return ok
end

local function finalizeStatus(partial)
  partial.generated_at = isoNow()
  partial.modules = partial.modules or {}
  for _, name in ipairs(MODULE_KEYS) do
    partial.modules[name] = checkModuleHealth(name)
  end

  partial.services = partial.services or {}
  partial.services.project = partial.services.project or checkProject()
  partial.displays = partial.displays or checkDisplays()
  partial.hammerspoon = partial.hammerspoon or checkHammerspoon()
  partial.overall = computeOverall({
    hammerspoon = partial.hammerspoon,
    ghostty = partial.services.ghostty,
    ollama = partial.services.ollama,
    n8n = partial.services.n8n,
    project = partial.services.project,
  }, partial.modules)

  partial.diagnostics_text = buildDiagnosticsText(partial)
  writeStatus(partial)
end

function M.refreshStatus()
  local ok, err = pcall(function()
    local partial = {
      generated_at = isoNow(),
      hammerspoon = checkHammerspoon(),
      services = {
        ghostty = checkGhostty(),
        ollama = checkOllamaSync(),
        n8n = checkN8nSync(),
        project = checkProject(),
      },
      displays = checkDisplays(),
    }

    partial.modules = {}
    for _, name in ipairs(MODULE_KEYS) do
      partial.modules[name] = checkModuleHealth(name)
    end

    partial.overall = computeOverall({
      hammerspoon = partial.hammerspoon,
      ghostty = partial.services.ghostty,
      ollama = partial.services.ollama,
      n8n = partial.services.n8n,
      project = partial.services.project,
    }, partial.modules)
    partial.diagnostics_text = buildDiagnosticsText(partial)
    writeStatus(partial)

    httpPending = 2

    hs.http.asyncGet(OLLAMA_URL, nil, function(code, body)
      httpPending = httpPending - 1
      local ollama = statusCache.services and statusCache.services.ollama or {}
      if code == 200 then
        ollama.endpoint_reachable = true
        ollama.status = 'running'
        ollama.failure_reason = nil
        local decoded = hs.json.decode(body)
        if decoded and decoded.models then
          local names = {}
          for _, m in ipairs(decoded.models) do
            if m.name then names[#names + 1] = m.name end
          end
          ollama.models = names
        end
      else
        ollama.endpoint_reachable = false
        ollama.failure_reason = 'HTTP ' .. tostring(code)
        if ollama.status ~= 'running' then ollama.status = 'degraded' end
      end
      statusCache.services.ollama = ollama
      if httpPending <= 0 then finalizeStatus(statusCache) end
    end)

    hs.http.asyncGet(N8N_URL, nil, function(code, body)
      httpPending = httpPending - 1
      local n8n = statusCache.services and statusCache.services.n8n or {}
      if code == 200 or code == 404 then
        n8n.endpoint_reachable = true
        n8n.status = 'running'
        n8n.failure_reason = nil
      else
        n8n.endpoint_reachable = false
        n8n.status = 'degraded'
        n8n.failure_reason = 'HTTP ' .. tostring(code)
      end
      statusCache.services.n8n = n8n
      if httpPending <= 0 then finalizeStatus(statusCache) end
    end)
  end)

  if not ok then
    log.ef('refreshStatus failed: %s', tostring(err))
    M.recordEvent({
      severity = 'error',
      source = 'operations',
      action = 'refresh_status',
      message = 'Status refresh failed: ' .. tostring(err),
      success = false,
    })
    return false, err
  end

  return true
end

function M.getStatus()
  if not statusCache or not statusCache.generated_at then
    local disk = readJSON(STATUS_PATH)
    if disk then statusCache = disk end
  end
  return statusCache
end

-- ── Actions ──────────────────────────────────────────────────────────────────

local function actionResult(name, success, message, detail, nextCheck)
  return {
    action = name,
    success = success,
    message = message,
    detail = detail,
    next_check = nextCheck,
    timestamp = isoNow(),
  }
end

local function openPath(path)
  if not pathExists(path) and not isDir(path) then
    return false, 'path not found: ' .. path
  end
  hs.execute('open ' .. shellQuote(path))
  return true
end

function M.execute(actionName, payload)
  if not allowedActions[actionName] then
    M.recordEvent({
      severity = 'warning',
      source = 'operations',
      action = actionName,
      message = 'Rejected unknown action: ' .. tostring(actionName),
      success = false,
    })
    return actionResult(actionName, false, 'Unknown or disallowed action',
      tostring(actionName), 'Use only console allowlisted actions')
  end

  local ok, errMsg, detail, nextCheck = false, nil, nil, nil

  if actionName == 'refresh_status' then
    M.refreshStatus()
    ok = true
    errMsg = 'Status refresh started'

  elseif actionName == 'launch_terminal_ops' then
    local terminal_ops = require('modules.terminal_ops')
    terminal_ops.launch()
    ok = true
    errMsg = 'Terminal Ops launch requested'

  elseif actionName == 'reload_hammerspoon' then
    M.recordEvent({
      severity = 'info', source = 'operations', action = actionName,
      message = 'Reloading Hammerspoon config', success = true,
    })
    hs.reload()
    ok = true
    errMsg = 'Reloading…'

  elseif actionName == 'apply_coding_layout' then
    require('modules.layouts').apply('coding')
    ok = true
    errMsg = 'Coding layout applied'

  elseif actionName == 'apply_ai_layout' then
    require('modules.layouts').apply('ai_workflow')
    ok = true
    errMsg = 'AI Workflow layout applied'

  elseif actionName == 'apply_ops_layout' then
    require('modules.layouts').apply('ops')
    ok = true
    errMsg = 'Ops layout applied'

  elseif actionName == 'apply_writing_layout' then
    require('modules.layouts').apply('writing')
    ok = true
    errMsg = 'Writing layout applied'

  elseif actionName == 'toggle_auto_tile' then
    local state = require('modules.windows').toggleAutoTile()
    ok = true
    errMsg = 'Auto-tile ' .. (state and 'ON' or 'OFF')

  elseif actionName == 'run_verification' then
  local report, pass, fail = require('modules.verify').run()
    ok = fail == 0
    errMsg = string.format('Verify: %d ok, %d fail', pass, fail)
    detail = report

  elseif actionName == 'open_guide' then
    require('modules.guide').open()
    ok = true
    errMsg = 'Guide opened'

  elseif actionName == 'open_hammerspoon_folder' then
    ok = openPath(hs.configdir)

  elseif actionName == 'open_project_folder' then
    ok = openPath(projectDir())

  elseif actionName == 'open_ghostty_config' then
    ok, errMsg = openPath(GHOSTTY_CONFIG)
    if not ok then nextCheck = 'Create ~/.config/ghostty/config' end

  elseif actionName == 'open_terminal_ops_config' then
    ok, errMsg = openPath(TERMINAL_OPS_CONFIG)

  elseif actionName == 'copy_diagnostics' then
    M.refreshStatus()
    local text = buildDiagnosticsText(statusCache)
    hs.pasteboard.setContents(text)
    ok = true
    errMsg = 'Diagnostics copied to clipboard'
    detail = text

  elseif actionName == 'open_event_log' then
    ensureRuntimeDir()
    ok = openPath(EVENTS_PATH)

  elseif actionName == 'clear_event_display' then
    atomicWriteJSON(EVENTS_PATH, {})
    ok = true
    errMsg = 'Event display cleared'

  elseif actionName == 'open_hammerspoon_console' then
    local opened = false
    pcall(function()
      if hs.openConsole then hs.openConsole(); opened = true end
    end)
    if not opened then
      hs.application.launchOrFocus('Hammerspoon')
    end
    ok = true
    errMsg = 'Hammerspoon Console requested'
    nextCheck = 'Menu bar → Hammerspoon → Console'
  end

  if ok == true and errMsg == nil then errMsg = 'OK' end
  if ok == false and errMsg == nil then errMsg = 'Action failed' end

  M.recordEvent({
    severity = ok and 'success' or 'error',
    source = 'operations',
    action = actionName,
    message = errMsg or (ok and 'OK' or 'Failed'),
    success = ok,
  })

  return actionResult(actionName, ok, errMsg, detail, nextCheck)
end

-- ── URL handler ──────────────────────────────────────────────────────────────

local function handleURL(params)
  local action = params and params.action
  if not action or action == '' then
    hs.alert.show('⚠ operations: action required')
    return
  end
  local result = M.execute(action, params)
  if not result.success then
    local msg = result.message or 'Failed'
    if result.next_check then msg = msg .. '\n' .. result.next_check end
    hs.alert.show('⚠ ' .. msg)
  end
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────

local function seedRuntimeFiles()
  ensureRuntimeDir()
  if not pathExists(STATUS_PATH) then
    atomicWriteJSON(STATUS_PATH, {
      generated_at = isoNow(),
      overall = { status = 'UNKNOWN', score = 0 },
      note = 'Awaiting first refresh',
    })
  end
  if not pathExists(EVENTS_PATH) then
    atomicWriteJSON(EVENTS_PATH, {})
  end
end

function M.start()
  if M._started then return M end
  M._started = true
  startedAt = isoNow()

  seedRuntimeFiles()
  hs.urlevent.bind('operations', 'run', handleURL)

  M.recordEvent({
    severity = 'info',
    source = 'operations',
    action = 'start',
    message = 'Operations console started',
    success = true,
  })

  M.refreshStatus()

  if refreshTimer then refreshTimer:stop() end
  refreshTimer = hs.timer.doEvery(REFRESH_SEC, function()
    M.refreshStatus()
  end)

  log.i('operations console started')
  return M
end

return M
