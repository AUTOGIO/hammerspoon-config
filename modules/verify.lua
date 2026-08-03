-- Module: verify.lua
-- Responsibility: Layout/display verify + full stack self-test.
local M = {}

local windows = require('modules.windows')
local layouts = require('modules.layouts')
local paths = require('modules.paths')

local function aspect(screen)
  local f = screen:frame()
  if f.h <= 0 then return 0 end
  return f.w / f.h
end

local function isoNow()
  local z = os.date('%z') or '+0000'
  if #z == 5 then z = z:sub(1, 3) .. ':' .. z:sub(4, 5) end
  return os.date('%Y-%m-%dT%H:%M:%S') .. z
end

local function pathExists(path)
  return hs.fs.attributes(path) ~= nil
end

local function httpGetStatus(url)
  local okCall, status = pcall(function()
    local code = hs.http.get(url, nil)
    return tonumber(code) or -1
  end)
  if not okCall then return -1 end
  return tonumber(status) or -1
end

--- Pure topology classifier (testable).
--- On a single display, missing ultrawide/built-in is WARNING (laptop-only or UW-only OK).
--- On 2+ displays, missing either role is FAIL.
function M.classifyTopology(screenCount, ultrawide, builtIn)
  local checks = {}
  local soft = (tonumber(screenCount) or 0) <= 1
  local function add(id, ok, detail)
    local result
    if ok then
      result = 'PASS'
    elseif soft then
      result = 'WARNING'
    else
      result = 'FAIL'
    end
    checks[#checks + 1] = {
      id = id,
      result = result,
      detail = detail or '',
    }
  end
  add('ultrawide', (tonumber(ultrawide) or 0) >= 1, tostring(ultrawide or 0) .. ' ultrawide(s)')
  add('built_in', (tonumber(builtIn) or 0) >= 1, tostring(builtIn or 0) .. ' non-ultrawide(s)')
  return checks
end

--- Structured layout checks used by verify.run / runFull / tests.
function M.runLayoutChecks()
  local checks = {}
  local lines = { '=== Hammerspoon layout verify ===' }
  local pass, fail, warn = 0, 0, 0

  local function add(id, result, detail)
    checks[#checks + 1] = { id = id, result = result, detail = detail or '' }
    if result == 'PASS' then
      pass = pass + 1
      lines[#lines + 1] = string.format('[OK] %s — %s', id, detail or '')
    elseif result == 'WARNING' then
      warn = warn + 1
      lines[#lines + 1] = string.format('[WARN] %s — %s', id, detail or '')
    else
      fail = fail + 1
      lines[#lines + 1] = string.format('[FAIL] %s — %s', id, detail or '')
    end
  end

  local function check(id, ok, detail)
    add(id, ok and 'PASS' or 'FAIL', detail)
  end

  check('windows_module', windows ~= nil, 'loaded')
  check('layouts_module', layouts ~= nil, tostring(#layouts.order) .. ' layouts')
  check('auto_tile', windows.autoTile == true, tostring(windows.autoTile))

  local screens = hs.screen.allScreens()
  check('display_count', #screens >= 1, tostring(#screens) .. ' screen(s)')

  local ultrawide, builtIn = 0, 0
  for _, s in ipairs(screens) do
    local f = s:frame()
    local a = aspect(s)
    local mode = windows.modeFor(s)
    local kind = a >= windows.ultrawideAspect and 'ultrawide' or 'built-in'
    if kind == 'ultrawide' then ultrawide = ultrawide + 1 else builtIn = builtIn + 1 end
    lines[#lines + 1] = string.format(
      '  %s: %dx%d aspect=%.2f mode=%s main=%s',
      s:name() or '?', f.w, f.h, a, mode, tostring(s == hs.screen.mainScreen())
    )
  end

  for _, topo in ipairs(M.classifyTopology(#screens, ultrawide, builtIn)) do
    add(topo.id, topo.result, topo.detail)
  end

  for _, key in ipairs(layouts.order) do
    local layout = layouts.layouts[key]
    check('layout_' .. key, layout ~= nil, layout and layout.label or 'missing')
  end

  local proj = paths.resolveBlackDragonProject()
  local attrs = hs.fs.attributes(proj)
  local projOk = attrs and attrs.mode == 'directory'
  check('project_dir', projOk, proj)

  lines[#lines + 1] = string.format('=== %d passed, %d failed, %d warn ===', pass, fail, warn)
  return {
    checks = checks,
    pass = pass,
    fail = fail,
    warn = warn,
    report = table.concat(lines, '\n'),
  }
end

function M.run()
  local layout = M.runLayoutChecks()
  print(layout.report)
  hs.alert.show(string.format('Verify: %d ok, %d fail, %d warn', layout.pass, layout.fail, layout.warn), 3)
  return layout.report, layout.pass, layout.fail, layout.warn
end

function M.runFull()
  local checks = {}
  local function add(id, result, detail, extra)
    local row = { id = id, result = result, detail = detail or '' }
    if extra then
      for k, v in pairs(extra) do row[k] = v end
    end
    checks[#checks + 1] = row
  end

  local layout = M.runLayoutChecks()
  local layoutIssues = {}
  for _, c in ipairs(layout.checks) do
    if c.result ~= 'PASS' then
      layoutIssues[#layoutIssues + 1] = c
    end
  end

  if layout.fail == 0 then
    local detail = string.format('%d ok, %d warn', layout.pass, layout.warn)
    add('layout_suite', layout.warn > 0 and 'WARNING' or 'PASS', detail, {
      subchecks = layout.checks,
    })
  else
    add('layout_suite', 'FAIL', string.format('%d ok, %d fail, %d warn', layout.pass, layout.fail, layout.warn), {
      subchecks = layout.checks,
    })
  end

  add('config_loaded', 'PASS', 'verify.runFull executing (no hs.reload in suite)')

  local ghosttyInstalled = pathExists('/Applications/Ghostty.app')
  local ghosttyRunning = hs.application.find('Ghostty') ~= nil
  if not ghosttyInstalled and not ghosttyRunning then
    add('ghostty', 'FAIL', 'Ghostty not installed')
  elseif not ghosttyRunning then
    add('ghostty', 'WARNING', 'installed but not running')
  else
    add('ghostty', 'PASS', 'running')
  end

  local proj = paths.resolveBlackDragonProject()
  local projAttrs = hs.fs.attributes(proj)
  if projAttrs and projAttrs.mode == 'directory' then
    add('project_path', 'PASS', proj)
  else
    add('project_path', 'FAIL', tostring(proj))
  end

  local clipOk, clip = pcall(require, 'modules.clipboard')
  if clipOk and clip and clip.watcherAlive and clip.watcherAlive() then
    add('clipboard', 'PASS', 'watcher alive, items=' .. tostring(clip.count and clip.count() or 0))
  elseif clipOk then
    add('clipboard', 'WARNING', 'module loaded; watcher not alive')
  else
    add('clipboard', 'FAIL', 'clipboard require failed')
  end

  local aiOk, ai = pcall(require, 'modules.ai')
  if aiOk and ai and type(ai.run) == 'function' then
    add('ai_module', 'PASS', 'ai.run available (dry-run; no chat handoff)')
  else
    add('ai_module', 'FAIL', 'ai module or ai.run missing')
  end

  local ollama = httpGetStatus('http://127.0.0.1:11434/api/tags')
  add('ollama_ping', ollama == 200 and 'PASS' or 'WARNING', 'HTTP ' .. tostring(ollama))

  local n8n = httpGetStatus('http://127.0.0.1:5678')
  add('n8n_ping', (n8n == 200 or n8n == 404) and 'PASS' or 'WARNING', 'HTTP ' .. tostring(n8n))

  local lm = httpGetStatus('http://127.0.0.1:1234/v1/models')
  add('lm_studio_ping', lm == 200 and 'PASS' or 'WARNING', 'HTTP ' .. tostring(lm))

  local notifyOk = pcall(function()
    hs.alert.show('Self-test OK', 0.8)
  end)
  add('notification_smoke', notifyOk and 'PASS' or 'WARNING', notifyOk and 'alert shown' or 'alert failed')

  local win = hs.window.focusedWindow()
  if win then
    local fr = win:frame()
    add('window_smoke', 'PASS', string.format('%dx%d', fr.w or 0, fr.h or 0))
  else
    add('window_smoke', 'WARNING', 'no focused window')
  end

  local coreNames = { 'paths', 'windows', 'layouts', 'terminal_ops', 'guide', 'operations_console' }
  local coreFail = {}
  for _, name in ipairs(coreNames) do
    local ok = pcall(require, 'modules.' .. name)
    if not ok then coreFail[#coreFail + 1] = name end
  end
  if #coreFail == 0 then
    add('core_modules', 'PASS', table.concat(coreNames, ', '))
  else
    add('core_modules', 'FAIL', 'unavailable: ' .. table.concat(coreFail, ', '))
  end

  local pass, fail, warn, weighted, total = 0, 0, 0, 0, 0
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

  local lines = { '=== Full self-test ===', string.format('Score %d/100 (%d pass, %d fail, %d warn)', score, pass, fail, warn) }
  for _, c in ipairs(checks) do
    lines[#lines + 1] = string.format('[%s] %s — %s', c.result, c.id, c.detail)
    if c.subchecks then
      for _, s in ipairs(c.subchecks) do
        if s.result ~= 'PASS' then
          lines[#lines + 1] = string.format('  [%s] %s — %s', s.result, s.id, s.detail)
        end
      end
    end
  end
  local report = table.concat(lines, '\n')
  print(report)
  hs.alert.show(string.format('Self-test: %d/100', score), 3)

  local issues = {}
  for _, c in ipairs(checks) do
    if c.result ~= 'PASS' then
      issues[#issues + 1] = { id = c.id, result = c.result, detail = c.detail }
    end
    if c.subchecks then
      for _, s in ipairs(c.subchecks) do
        if s.result ~= 'PASS' then
          issues[#issues + 1] = { id = 'layout:' .. s.id, result = s.result, detail = s.detail }
        end
      end
    end
  end

  return {
    at = isoNow(),
    score = score,
    pass = pass,
    fail = fail,
    warn = warn,
    checks = checks,
    issues = issues,
    layout_checks = layout.checks,
    report = report,
  }
end

return M
