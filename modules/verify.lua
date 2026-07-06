-- Module: verify.lua
-- Responsibility: Phase 1 diagnostics for displays, tiler, and layouts.
local M = {}

local windows = require('modules.windows')
local layouts = require('modules.layouts')

local function aspect(screen)
  local f = screen:frame()
  if f.h <= 0 then return 0 end
  return f.w / f.h
end

function M.run()
  local lines = { '=== Hammerspoon layout verify ===' }
  local pass, fail = 0, 0

  local function check(label, ok, detail)
    if ok then
      pass = pass + 1
      lines[#lines + 1] = string.format('[OK] %s — %s', label, detail or '')
    else
      fail = fail + 1
      lines[#lines + 1] = string.format('[FAIL] %s — %s', label, detail or '')
    end
  end

  check('windows module', windows ~= nil, 'loaded')
  check('layouts module', layouts ~= nil, tostring(#layouts.order) .. ' layouts')
  check('auto-tile enabled', windows.autoTile == true, tostring(windows.autoTile))

  local screens = hs.screen.allScreens()
  check('display count', #screens >= 1, tostring(#screens) .. ' screen(s)')

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

  check('ultrawide detected', ultrawide >= 1, ultrawide .. ' ultrawide(s)')
  check('built-in detected', builtIn >= 1, builtIn .. ' non-ultrawide(s)')

  for _, key in ipairs(layouts.order) do
    local layout = layouts.layouts[key]
    check('layout: ' .. key, layout ~= nil, layout and layout.label or 'missing')
  end

  lines[#lines + 1] = string.format('=== %d passed, %d failed ===', pass, fail)
  local report = table.concat(lines, '\n')
  print(report)
  hs.alert.show(string.format('Verify: %d ok, %d fail', pass, fail), 3)
  return report, pass, fail
end

return M
