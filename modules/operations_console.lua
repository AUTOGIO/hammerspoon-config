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
local paths                = require('modules.paths')
local OLLAMA_URL           = 'http://127.0.0.1:11434/api/tags'
local N8N_URL              = 'http://127.0.0.1:5678'
local LM_STUDIO_URL        = 'http://127.0.0.1:1234/v1/models'
local OPENCLAW_URL         = 'http://127.0.0.1:18789/'
local OPENCLAW_BIN         = '/opt/homebrew/bin/openclaw'

local statusCache = {}
local refreshTimer = nil
local startedAt = nil
local refreshGen = 0

local allowedActions = {
  refresh_status          = true,
  launch_terminal_ops     = true,
  reload_hammerspoon      = true,
  apply_coding_layout     = true,
  apply_ai_layout         = true,
  apply_ops_layout        = true,
  apply_writing_layout    = true,
  apply_command_center_layout = true,
  apply_dev_console_layout = true,
  toggle_auto_tile        = true,
  cycle_tiler_mode        = true,
  run_verification        = true,
  run_diagnostics         = true,
  run_environment_audit   = true,
  run_full_self_test      = true,
  backup_configuration    = true,
  open_guide              = true,
  open_hammerspoon_folder = true,
  open_project_folder     = true,
  open_ghostty_config     = true,
  open_terminal_ops_config = true,
  copy_diagnostics        = true,
  open_event_log          = true,
  clear_event_display     = true,
  open_hammerspoon_console = true,
  trigger_n8n           = true,
  launch_app            = true,
  ai_prompt             = true,
  run_hotkey_scan       = true,
  run_perf_probes       = true,
}

local allowedLaunchApps = {
  BlackDragon = true,
  Cursor = true,
  Ghostty = true,
  Claude = true,
  Codex = true,
  ['ChatGPT Atlas'] = true,
  Obsidian = true,
  Notes = true,
  Hammerspoon = true,
}

local allowedAiPrompts = {
  explain = true,
  optimize = true,
  summary = true,
  summarize = true,
  debug = true,
  generate_tests = true,
  architecture_review = true,
  security_review = true,
  swift_review = true,
  shell_review = true,
  applescript_review = true,
  markdown_review = true,
  codex = true,
  snapshot = true,
  deliver = true,
  compare = true,
  structured = true,
  console = true,
  quick = true,
}

local MODULE_KEYS = {
  'paths', 'layouts', 'windows', 'terminal_ops', 'clipboard', 'ai', 'n8n',
  'guide', 'verify', 'hotkeys', 'apps', 'openclaw_button', 'operations_console', 'diagnostics', 'insight',
}

-- ── Utilities ────────────────────────────────────────────────────────────────

local function isoNow()
  local z = os.date('%z') or '+0000'
  if #z == 5 then z = z:sub(1, 3) .. ':' .. z:sub(4, 5) end
  return os.date('%Y-%m-%dT%H:%M:%S') .. z
end

local function shellQuote(s)
  return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

local function trim(s)
  return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function firstLine(text)
  local line = tostring(text or ''):match('([^\r\n]+)')
  return trim(line or '')
end

local function shortText(text, maxLen)
  local value = trim(text)
  local limit = maxLen or 120
  if #value > limit then
    return value:sub(1, limit - 3) .. '...'
  end
  return value
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
  local output, _, _, rc = hs.execute(cmd .. ' 2>/dev/null')
  if type(output) ~= 'string' then output = tostring(output or '') end
  output = output:gsub('%s+$', '')
  return tonumber(rc) == 0, output
end

local function runShellWithOutput(cmd)
  local output, _, _, rc = hs.execute(cmd .. ' 2>&1')
  if type(output) ~= 'string' then output = tostring(output or '') end
  output = trim(output)
  return tonumber(rc) == 0, output
end

local function projectDir()
  local terminal_ops = package.loaded['modules.terminal_ops']
  if terminal_ops and terminal_ops.getProjectDir then
    return terminal_ops.getProjectDir()
  end
  return paths.resolveBlackDragonProject()
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
  local ok, rcOut = runShell('pgrep -x ollama >/dev/null && echo yes || echo no')
  local processRunning = ok and rcOut == 'yes'

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
  local processDetected = ok and out == 'yes'
  return {
    status = 'degraded',
    process_detected = processDetected,
    endpoint_reachable = false,
    failure_reason = 'endpoint unreachable',
  }
end

local function checkLmStudioSync()
  return {
    status = 'degraded',
    endpoint_reachable = false,
    models = {},
    failure_reason = 'endpoint unreachable',
  }
end

local function openclawCommand()
  return pathExists(OPENCLAW_BIN) and OPENCLAW_BIN or 'openclaw'
end

local function checkOpenClawCli()
  local cmd = openclawCommand() .. ' gateway status'
  local ok, out = runShellWithOutput(cmd)
  local text = trim(out)
  local info = {
    cli_checked = true,
    cli_command = cmd,
    endpoint_reachable = false,
    status = 'degraded',
    gateway_status = text ~= '' and firstLine(text) or nil,
    failure_reason = text ~= '' and shortText(firstLine(text)) or 'CLI unavailable',
  }

  if not ok or text == '' then
    return info
  end

  local lower = text:lower()
  local positive = lower:find('running', 1, true)
    or lower:find('ready', 1, true)
    or lower:find('connected', 1, true)
    or lower:find('healthy', 1, true)
    or lower:find('online', 1, true)
  local negative = lower:find('unreachable', 1, true)
    or lower:find('failed', 1, true)
    or lower:find('error', 1, true)
    or lower:find('stopped', 1, true)
    or lower:find('down', 1, true)
    or lower:find('unavailable', 1, true)

  if positive and not negative then
    info.endpoint_reachable = true
    info.status = 'running'
    info.failure_reason = nil
  else
    info.failure_reason = shortText(firstLine(text))
  end

  return info
end

local function checkOpenClawSync()
  return {
    status = 'degraded',
    endpoint_reachable = false,
    gateway_status = nil,
    failure_reason = 'endpoint unreachable',
  }
end

local function projectCapabilities(dir)
  return {
    launch_sh = pathExists(dir .. '/launch.sh') or pathExists(dir .. '/scripts/launch.sh'),
    pane_sh = pathExists(hs.configdir .. '/scripts/ghostty/terminal-ops-pane.sh'),
    terminal_ops_conf = pathExists(TERMINAL_OPS_CONFIG),
    ghostty_config = pathExists(GHOSTTY_CONFIG),
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
    capabilities = projectCapabilities(dir),
  }

  if not exists then
    info.diagnostic = 'project directory not found'
    return info
  end

  local okGit, gitRoot = runShell(string.format('git -C %s rev-parse --is-inside-work-tree', shellQuote(dir)))
  info.git_repository = okGit and gitRoot == 'true'

  if info.git_repository then
    local okBranch, branch = runShell(string.format('git -C %s rev-parse --abbrev-ref HEAD', shellQuote(dir)))
    if okBranch then info.branch = branch ~= '' and branch or nil end

    local okDirty, dirtyOut = runShell(string.format('git -C %s status --porcelain', shellQuote(dir)))
    if okDirty then info.dirty = dirtyOut ~= '' end

    local okCommit, commit = runShell(string.format('git -C %s log -1 --oneline', shellQuote(dir)))
    if okCommit then info.latest_commit = commit ~= '' and commit or nil end
  end

  local okDu, du = runShell(string.format('/usr/bin/du -sh %s | cut -f1', shellQuote(dir)))
  if okDu then info.disk_usage = du ~= '' and du or nil end
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
    local aspect = f.h > 0 and (f.w / f.h) or 0
    local windowsMod = package.loaded['modules.windows'] or (function()
      local ok, mod = pcall(require, 'modules.windows')
      return ok and mod or nil
    end)()
    if windowsMod and windowsMod.modeFor then
      local mok, mval = pcall(function() return windowsMod.modeFor(screen) end)
      if mok and mval then mode = mval end
    end
    if mode == 'unknown' and aspect >= (windowsMod and windowsMod.ultrawideAspect or 2.0) then
      mode = 'columns'
    elseif mode == 'unknown' and aspect > 0 then
      mode = 'stack'
    end
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
  local function weighOptional(points, service)
    if not service then return end
    if service.endpoint_reachable ~= true and service.status ~= 'running' then
      return
    end
    weigh(points, service.endpoint_reachable == true, service.failure_reason)
  end

  weighOptional(15, services.ollama)
  weighOptional(10, services.n8n)
  weighOptional(10, services.lm_studio)
  weighOptional(10, services.openclaw)
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
    string.format('LM Studio: %s', (st.services and st.services.lm_studio and st.services.lm_studio.endpoint_reachable) and 'Running' or 'Unreachable'),
    string.format('OpenClaw: %s', (st.services and st.services.openclaw and st.services.openclaw.endpoint_reachable) and 'Running' or 'Unreachable'),
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

local function recordLastAction(name, success, message)
  local entry = {
    name = name,
    success = success,
    message = message,
    timestamp = isoNow(),
  }
  statusCache.last_action = entry
  if pathExists(STATUS_PATH) then
    local disk = readJSON(STATUS_PATH) or {}
    disk.last_action = entry
    atomicWriteJSON(STATUS_PATH, disk)
  end
end

local function notifyAction(name, success, message)
  local title = success and 'Hammerspoon' or 'Hammerspoon Error'
  local body = (message or name) .. ' (' .. name .. ')'
  pcall(function()
    hs.notify.new({ title = title, informativeText = body }):send()
  end)
end

local function writeStatus(data)
  if statusCache and statusCache.last_action and data then
    data.last_action = data.last_action or statusCache.last_action
  end
  if data then
    data.schema_version = 2
    data.clipboard = {
      history_count = require('modules.clipboard').count(),
      watcher_alive = require('modules.clipboard').watcherAlive(),
    }
    -- Preserve last suite runs across 30s refresh (do not re-run suites here)
    if statusCache then
      data.diagnostics = data.diagnostics or statusCache.diagnostics
      data.environment = data.environment or statusCache.environment
      data.verification = data.verification or statusCache.verification
      data.hotkeys = data.hotkeys or statusCache.hotkeys
      data.metrics = data.metrics or statusCache.metrics
    end
    -- Fresh thin host metrics each write (cheap)
    local insightOk, insight = pcall(require, 'modules.insight')
    if insightOk and insight and insight.hostMetrics then
      data.system = insight.hostMetrics()
    end
  end
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
    lm_studio = partial.services.lm_studio,
    openclaw = partial.services.openclaw,
    project = partial.services.project,
  }, partial.modules)

  partial.diagnostics_text = buildDiagnosticsText(partial)
  if statusCache.last_action then
    partial.last_action = statusCache.last_action
  end
  writeStatus(partial)
end

function M.refreshStatus()
  local ok, err = pcall(function()
    refreshGen = refreshGen + 1
    local gen = refreshGen
    local pending = 4

    local partial = {
      generated_at = isoNow(),
      hammerspoon = checkHammerspoon(),
      services = {
        ghostty = checkGhostty(),
        ollama = checkOllamaSync(),
        n8n = checkN8nSync(),
        lm_studio = checkLmStudioSync(),
        openclaw = checkOpenClawSync(),
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
      lm_studio = partial.services.lm_studio,
      openclaw = partial.services.openclaw,
      project = partial.services.project,
    }, partial.modules)
    partial.diagnostics_text = buildDiagnosticsText(partial)
    if statusCache.last_action then
      partial.last_action = statusCache.last_action
    end
    writeStatus(partial)

    local function finishOne()
      if gen ~= refreshGen then return end
      pending = pending - 1
      if pending <= 0 then finalizeStatus(partial) end
    end

    hs.http.asyncGet(OLLAMA_URL, nil, function(code, body)
      if gen ~= refreshGen then return end
      local ollama = partial.services and partial.services.ollama or {}
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
      partial.services.ollama = ollama
      finishOne()
    end)

    hs.http.asyncGet(N8N_URL, nil, function(code, body)
      if gen ~= refreshGen then return end
      local n8n = partial.services and partial.services.n8n or {}
      if code == 200 or code == 404 then
        n8n.endpoint_reachable = true
        n8n.status = 'running'
        n8n.failure_reason = nil
      else
        n8n.endpoint_reachable = false
        n8n.status = 'degraded'
        n8n.failure_reason = 'HTTP ' .. tostring(code)
      end
      partial.services.n8n = n8n
      finishOne()
    end)

    hs.http.asyncGet(LM_STUDIO_URL, nil, function(code, body)
      if gen ~= refreshGen then return end
      local lmStudio = partial.services and partial.services.lm_studio or {}
      if code == 200 then
        lmStudio.endpoint_reachable = true
        lmStudio.status = 'running'
        lmStudio.failure_reason = nil
        local decoded = hs.json.decode(body)
        if decoded and decoded.data then
          local names = {}
          for _, model in ipairs(decoded.data) do
            local id = model.id or model.name
            if id then names[#names + 1] = id end
          end
          lmStudio.models = names
        end
      else
        lmStudio.endpoint_reachable = false
        lmStudio.status = 'degraded'
        lmStudio.failure_reason = 'HTTP ' .. tostring(code)
      end
      partial.services.lm_studio = lmStudio
      finishOne()
    end)

    hs.http.asyncGet(OPENCLAW_URL, nil, function(code, body)
      if gen ~= refreshGen then return end
      local openclaw = partial.services and partial.services.openclaw or {}
      if code == 200 then
        openclaw.endpoint_reachable = true
        openclaw.status = 'running'
        openclaw.gateway_status = 'HTTP 200'
        openclaw.failure_reason = nil
      else
        local cli = checkOpenClawCli()
        openclaw.cli_checked = cli.cli_checked
        openclaw.cli_command = cli.cli_command
        openclaw.gateway_status = cli.gateway_status
        openclaw.endpoint_reachable = cli.endpoint_reachable == true
        openclaw.status = cli.status or 'degraded'
        if cli.endpoint_reachable then
          openclaw.failure_reason = nil
        else
          openclaw.failure_reason = cli.failure_reason or ('HTTP ' .. tostring(code))
        end
      end
      if openclaw.endpoint_reachable then
        openclaw.status = 'running'
      elseif openclaw.status ~= 'running' then
        openclaw.status = 'degraded'
      end
      partial.services.openclaw = openclaw
      finishOne()
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
  local eventSource = 'operations'

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

  elseif actionName == 'apply_command_center_layout' then
    require('modules.layouts').apply('command_center')
    ok = true
    errMsg = 'Command Center layout applied'

  elseif actionName == 'apply_dev_console_layout' then
    require('modules.layouts').apply('dev_console')
    ok = true
    errMsg = 'Dev Console layout applied'

  elseif actionName == 'toggle_auto_tile' then
    local state = require('modules.windows').toggleAutoTile()
    ok = true
    errMsg = 'Auto-tile ' .. (state and 'ON' or 'OFF')

  elseif actionName == 'cycle_tiler_mode' then
    local win = hs.window.focusedWindow()
    require('modules.windows').cycleMode(win and win:screen() or hs.screen.mainScreen())
    ok = true
    errMsg = 'Tiler mode cycled'

  elseif actionName == 'trigger_n8n' then
    local path = (payload and payload.path) or 'hs/daily-log'
    local n8n = require('modules.n8n')
    if not n8n.isAllowedPath(path) then
      errMsg = 'n8n path not allowlisted: ' .. tostring(path)
      M.recordEvent({
        severity = 'warning',
        source = 'operations',
        action = actionName,
        message = errMsg,
        success = false,
      })
      recordLastAction(actionName, false, errMsg)
      notifyAction(actionName, false, errMsg)
      return actionResult(actionName, false, errMsg, tostring(path), 'Use allowlisted webhook paths only')
    end
    n8n.post(path, {
      timestamp = os.date('%Y-%m-%dT%H:%M:%S'),
      source = 'operations-console',
    }, function(status, body)
      local response = trim(body)
      if status == 200 then
        local successMsg = 'n8n webhook posted: ' .. path
        M.recordEvent({
          severity = 'success',
          source = 'operations',
          action = actionName,
          message = successMsg,
          success = true,
        })
        recordLastAction(actionName, true, successMsg)
        notifyAction(actionName, true, successMsg)
      else
        local failureMsg = 'n8n webhook failed: HTTP ' .. tostring(status)
        if response ~= '' then
          failureMsg = failureMsg .. ' - ' .. shortText(response)
        end
        M.recordEvent({
          severity = 'error',
          source = 'operations',
          action = actionName,
          message = failureMsg,
          success = false,
        })
        recordLastAction(actionName, false, failureMsg)
        notifyAction(actionName, false, failureMsg)
      end
    end)
    return actionResult(actionName, true, 'n8n request queued: ' .. path, tostring(path), 'Waiting for HTTP response')

  elseif actionName == 'launch_app' then
    local appName = payload and payload.app
    if not appName or not allowedLaunchApps[appName] then
      ok = false
      errMsg = 'App not allowlisted: ' .. tostring(appName)
    else
      require('modules.apps').launch(appName)
      ok = true
      errMsg = 'Launched ' .. appName
    end

  elseif actionName == 'ai_prompt' then
    local prompt = payload and payload.prompt
    if not prompt or not allowedAiPrompts[prompt] then
      ok = false
      errMsg = 'Prompt not allowlisted: ' .. tostring(prompt)
    else
      require('modules.ai').run(prompt)
      ok = true
      errMsg = 'AI prompt: ' .. prompt
    end

  elseif actionName == 'run_verification' then
    local report, pass, fail = require('modules.verify').run()
    ok = fail == 0
    errMsg = string.format('Verify: %d ok, %d fail', pass, fail)
    detail = report

  elseif actionName == 'run_diagnostics' then
    local result = require('modules.diagnostics').runDiagnostics()
    statusCache.diagnostics = result
    writeStatus(statusCache)
    ok = (result.fail or 0) == 0
    errMsg = string.format('Diagnostics: %d/100 (%d pass, %d fail, %d warn)',
      result.score or 0, result.pass or 0, result.fail or 0, result.warn or 0)
    detail = hs.json.encode(result)
    eventSource = 'diagnostics'

  elseif actionName == 'run_environment_audit' then
    local result = require('modules.diagnostics').runEnvironmentAudit()
    statusCache.environment = result
    writeStatus(statusCache)
    ok = (result.fail or 0) == 0
    errMsg = string.format('Environment audit: %d/100 (%d issues)',
      result.score or 0, result.issues and #result.issues or 0)
    detail = hs.json.encode(result)
    eventSource = 'diagnostics'

  elseif actionName == 'run_full_self_test' then
    local result = require('modules.verify').runFull()
    statusCache.verification = result
    writeStatus(statusCache)
    ok = (result.fail or 0) == 0
    errMsg = string.format('Self-test: %d/100 (%d pass, %d fail, %d warn)',
      result.score or 0, result.pass or 0, result.fail or 0, result.warn or 0)
    detail = result.report or hs.json.encode(result)
    eventSource = 'diagnostics'

  elseif actionName == 'backup_configuration' then
    local backupRoot = hs.configdir .. '/backups'
    if not isDir(backupRoot) then hs.fs.mkdir(backupRoot) end
    local stamp = os.date('%Y%m%d-%H%M%S')
    local dest = backupRoot .. '/ops-' .. stamp
    hs.fs.mkdir(dest)

    local manifest = {
      'BlackDragon configuration backup',
      'Created: ' .. isoNow(),
      'Includes:',
      '  - hammerspoon/ (excludes runtime/, .git/, backups/, .superpowers/, .env*)',
      '  - ghostty/config (if present)',
      '  - terminal-ops Ghostty conf (if present)',
      'Guide localStorage prefs are browser-side — use Export guide prefs in the guide.',
      '',
    }

    local hsDest = dest .. '/hammerspoon'
    hs.fs.mkdir(hsDest)
    local tarCmd = string.format(
      'tar -C %s -cf - --exclude=runtime --exclude=.git --exclude=backups --exclude=.superpowers --exclude=.env --exclude=.env.* . | tar -C %s -xf -',
      shellQuote(hs.configdir),
      shellQuote(hsDest)
    )
    local tarOk = select(1, runShell(tarCmd))
    if not tarOk then
      local keyFiles = { 'init.lua', 'AGENTS.md', 'README.md', '.cursorrules', '.gitignore' }
      for _, f in ipairs(keyFiles) do
        local src = hs.configdir .. '/' .. f
        if pathExists(src) then
          hs.execute('cp ' .. shellQuote(src) .. ' ' .. shellQuote(hsDest .. '/' .. f))
        end
      end
      hs.execute('cp -R ' .. shellQuote(hs.configdir .. '/modules') .. ' ' .. shellQuote(hsDest .. '/modules'))
      hs.execute('cp -R ' .. shellQuote(hs.configdir .. '/docs') .. ' ' .. shellQuote(hsDest .. '/docs'))
      hs.execute('cp -R ' .. shellQuote(hs.configdir .. '/scripts') .. ' ' .. shellQuote(hsDest .. '/scripts'))
      manifest[#manifest + 1] = 'Note: used fallback copy (tar failed)'
    end

    if pathExists(GHOSTTY_CONFIG) then
      local gDest = dest .. '/ghostty'
      hs.fs.mkdir(gDest)
      hs.execute('cp ' .. shellQuote(GHOSTTY_CONFIG) .. ' ' .. shellQuote(gDest .. '/config'))
    else
      manifest[#manifest + 1] = 'Missing: Ghostty config'
    end

    if pathExists(TERMINAL_OPS_CONFIG) then
      local tDest = dest .. '/ghostty-ops'
      hs.fs.mkdir(tDest)
      hs.execute('cp ' .. shellQuote(TERMINAL_OPS_CONFIG) .. ' ' .. shellQuote(tDest .. '/ghostty-terminal-ops-center.conf'))
    end

    local mf = io.open(dest .. '/BACKUP_MANIFEST.txt', 'w')
    if mf then
      mf:write(table.concat(manifest, '\n') .. '\n')
      mf:close()
    end

    openPath(dest)
    ok = true
    errMsg = 'Backup created: ' .. dest
    detail = dest

  elseif actionName == 'run_hotkey_scan' then
    local result = require('modules.insight').scanHotkeys()
    statusCache.hotkeys = result
    writeStatus(statusCache)
    ok = (result.conflict_count or 0) == 0
    errMsg = string.format('Hotkey scan: %d bindings, %d conflicts',
      result.count or 0, result.conflict_count or 0)
    detail = hs.json.encode(result)
    eventSource = 'insight'

  elseif actionName == 'run_perf_probes' then
    local result = require('modules.insight').runPerfProbes()
    statusCache.metrics = result
    writeStatus(statusCache)
    ok = true
    local parts = {}
    for _, p in ipairs(result.probes or {}) do
      parts[#parts + 1] = string.format('%s=%s', p.id, p.ms and (p.ms .. 'ms') or tostring(p.detail))
    end
    errMsg = 'Perf probes: ' .. table.concat(parts, ', ')
    detail = hs.json.encode(result)
    eventSource = 'insight'

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
    source = eventSource or 'operations',
    action = actionName,
    message = errMsg or (ok and 'OK' or 'Failed'),
    success = ok,
  })

  recordLastAction(actionName, ok, errMsg)
  notifyAction(actionName, ok, errMsg)

  return actionResult(actionName, ok, errMsg, detail, nextCheck)
end

-- ── URL handler ──────────────────────────────────────────────────────────────

local function handleURL(_eventName, params)
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

local function seedRuntimeFiles()
  ensureRuntimeDir()
  if not pathExists(STATUS_PATH) then
    atomicWriteJSON(STATUS_PATH, {
      schema_version = 2,
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
  hs.urlevent.bind('operations', handleURL)

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
