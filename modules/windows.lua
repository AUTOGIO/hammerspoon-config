-- Module: windows.lua
-- Responsibility: Snapping, centering, and Yabai-style auto-tiling with
-- per-display smart modes (equal-columns on ultrawide, master-stack elsewhere).
local M = {}

local log = hs.logger.new('windows', 'info')

M.autoTile   = true
M.tileGap    = 6      -- px between tiled windows
M.tileDelay  = 0.35   -- seconds to wait for app placement animations
M.stackRatio = 0.60   -- master occupies this fraction of the width in stack mode
M.ultrawideAspect = 2.0  -- w/h ratio at or above which we default to columns

M.mode = {}           -- per-screen mode: 'columns' | 'stack' | 'off'

local excludedApps = {
  ['Hammerspoon'] = true,
  ['System Settings'] = true,
  ['System Preferences'] = true,
  ['SystemUIServer'] = true,
  ['Control Center'] = true,
  ['Notification Center'] = true,
  ['loginwindow'] = true,
  ['Finder'] = true,
  ['Spotlight'] = true,
  ['Raycast'] = true,
  ['Alfred'] = true,
  ['1Password'] = true,
}

-- Windows whose title contains any of these substrings stay floating (not tiled).
local floatTitlePatterns = { 'Preferences', 'Settings', 'Quick Note', 'About' }

M.excludedApps = excludedApps
M.floatMinW = 500   -- smaller windows are never auto-tiled
M.floatMinH = 400

local wf = nil
local retiling = false
local pauseUntil = 0

local function nowMs()
  return hs.timer.secondsSinceEpoch() * 1000
end

local function isPaused()
  return nowMs() < pauseUntil
end

function M.pauseFor(ms)
  ms = tonumber(ms) or 0
  pauseUntil = math.max(pauseUntil, nowMs() + ms)
  log.d('tiler paused for %dms', ms)
end

local function isTileable(win)
  if not win or not win:isStandard() then return false end
  if not win:isVisible() or win:isMinimized() then return false end
  local app = win:application()
  if not app or excludedApps[app:name()] then return false end
  local title = win:title() or ''
  for _, pattern in ipairs(floatTitlePatterns) do
    if title:find(pattern, 1, true) then return false end
  end
  local f = win:frame()
  if f.w < (M.floatMinW or 280) or f.h < (M.floatMinH or 180) then return false end
  return true
end

local function screenKey(screen)
  if not screen then return nil end
  local ok, uuid = pcall(function() return screen:getUUID() end)
  if ok and uuid then return uuid end
  return tostring(screen:id())
end

local function defaultModeFor(screen)
  local f = screen:frame()
  if f.h > 0 and (f.w / f.h) >= M.ultrawideAspect then
    return 'columns'
  end
  return 'stack'
end

function M.modeFor(screen)
  local key = screenKey(screen)
  if not key then return 'columns' end
  if not M.mode[key] then
    M.mode[key] = defaultModeFor(screen)
    log.d('screen %s default mode = %s', screen:name() or key, M.mode[key])
  end
  return M.mode[key]
end

local function tileableOnScreen(screen)
  local wins = {}
  for _, win in ipairs(screen:allWindows()) do
    if isTileable(win) then wins[#wins + 1] = win end
  end
  table.sort(wins, function(a, b) return a:id() < b:id() end)
  return wins
end

local function retileColumns(screen, wins)
  local n = #wins
  local frame = screen:visibleFrame()
  local gap = M.tileGap or 0
  local totalGap = gap * math.max(0, n - 1)
  local colW = (frame.w - totalGap) / n
  for i, win in ipairs(wins) do
    win:setFrame({
      x = frame.x + (i - 1) * (colW + gap),
      y = frame.y,
      w = colW,
      h = frame.h,
    })
  end
end

local function retileStack(screen, wins)
  local n = #wins
  local frame = screen:visibleFrame()
  local gap = M.tileGap or 0

  if n == 1 then
    wins[1]:setFrame(frame)
    return
  end

  -- Master is whichever tileable window is currently focused, else first.
  local focused = hs.window.focusedWindow()
  local masterIdx = 1
  if focused then
    for i, w in ipairs(wins) do
      if w:id() == focused:id() then masterIdx = i; break end
    end
  end

  local ratio = M.stackRatio
  local masterW = math.floor(frame.w * ratio - gap / 2)
  local stackW  = frame.w - masterW - gap
  local stackCount = n - 1
  local stackTotalGap = gap * math.max(0, stackCount - 1)
  local rowH = (frame.h - stackTotalGap) / stackCount

  wins[masterIdx]:setFrame({
    x = frame.x, y = frame.y, w = masterW, h = frame.h,
  })

  local slot = 0
  for i, win in ipairs(wins) do
    if i ~= masterIdx then
      win:setFrame({
        x = frame.x + masterW + gap,
        y = frame.y + slot * (rowH + gap),
        w = stackW,
        h = rowH,
      })
      slot = slot + 1
    end
  end
end

function M.retileScreen(screen)
  if not screen or retiling or isPaused() then return end
  local mode = M.modeFor(screen)
  if mode == 'off' then return end

  local wins = tileableOnScreen(screen)
  local n = #wins
  if n == 0 then return end

  retiling = true
  if mode == 'stack' then
    retileStack(screen, wins)
  else
    retileColumns(screen, wins)
  end
  log.d('retiled %d windows on %s (mode=%s)', n, screen:name() or '?', mode)
  hs.timer.doAfter(0.2, function() retiling = false end)
end

function M.retileAll()
  for _, screen in ipairs(hs.screen.allScreens()) do
    M.retileScreen(screen)
  end
end

local function scheduleRetile(screen)
  if not screen or not M.autoTile then return end
  hs.timer.doAfter(M.tileDelay, function()
    M.retileScreen(screen)
  end)
end

local function screenForWindow(win)
  if not win then return nil end
  local ok, screen = pcall(function() return win:screen() end)
  return ok and screen or nil
end

function M.startAutoTile()
  if not M.autoTile or wf then return end

  wf = hs.window.filter.new(true)
  wf:setOverrideFilter({ allowRoles = { 'AXStandardWindow' } })

  wf:subscribe(hs.window.filter.windowCreated, function(win)
    scheduleRetile(screenForWindow(win))
  end)

  wf:subscribe(hs.window.filter.windowDestroyed, function(win)
    scheduleRetile(screenForWindow(win))
  end)

  log.i('auto-tile enabled (gap=%dpx)', M.tileGap)
end

function M.stopAutoTile()
  if wf then
    wf:unsubscribeAll()
    wf = nil
    log.i('auto-tile disabled')
  end
end

function M.toggleAutoTile()
  M.autoTile = not M.autoTile
  if M.autoTile then
    M.startAutoTile()
    hs.alert.show('🧱 Auto-tile ON')
    M.retileAll()
  else
    M.stopAutoTile()
    hs.alert.show('🧱 Auto-tile OFF')
  end
  return M.autoTile
end

local cycleOrder = { columns = 'stack', stack = 'off', off = 'columns' }

function M.cycleMode(screen)
  screen = screen or hs.screen.mainScreen()
  local key = screenKey(screen)
  if not key then return end
  local current = M.modeFor(screen)
  local nextMode = cycleOrder[current] or 'columns'
  M.mode[key] = nextMode
  local label = ({ columns = 'Columns', stack = 'Master + Stack', off = 'Off' })[nextMode]
  hs.alert.show(string.format('%s → %s', screen:name() or 'Screen', label))
  if nextMode ~= 'off' then M.retileScreen(screen) end
  return nextMode
end

function M.setMode(screen, mode)
  local key = screenKey(screen)
  if not key then return end
  M.mode[key] = mode
  if mode ~= 'off' then M.retileScreen(screen) end
end

-- ── Manual hotkey actions ────────────────────────────────────────────────────

local function snap(unit)
  local win = hs.window.focusedWindow()
  if not win then hs.alert.show('⚠ No focused window'); return end
  win:moveToUnit(unit)
end

function M.snapLeft()   snap(hs.geometry.unitrect(0, 0, 0.5, 1)) end
function M.snapRight()  snap(hs.geometry.unitrect(0.5, 0, 0.5, 1)) end
function M.maximize()
  local win = hs.window.focusedWindow()
  if win then win:maximize() end
end
function M.center()
  local win = hs.window.focusedWindow()
  if not win then return end
  local screen = win:screen():frame()
  win:setFrame(hs.geometry.rect(
    screen.x + screen.w * 0.1,
    screen.y + screen.h * 0.1,
    screen.w * 0.8,
    screen.h * 0.8
  ))
end

M.startAutoTile()

return M
