-- Module: layouts.lua
-- Responsibility: Named workspace layouts. Applying one launches missing apps,
-- positions them per recipe on the screen under the cursor, hides all other
-- visible apps, and pauses the auto-tiler for the duration of placement.
local M = {}

local log     = hs.logger.new('layouts', 'info')
local windows = require('modules.windows')

M.launchWait      = 0.45  -- seconds to wait after launchOrFocus before positioning
M.placementPause  = 2500  -- ms the tiler is paused while a layout is applied
M.ultrawideAspect = 2.0

M.activeLayout = hs.settings.get('layouts_active')
local menubar  = nil

-- ── Position recipes ─────────────────────────────────────────────────────────
--
-- Each recipe is (screen) -> {x=,y=,w=,h=} in absolute screen coordinates,
-- computed from screen:visibleFrame() so the dock and menu bar are respected.

local function frameFor(recipe, screen)
  local f = screen:visibleFrame()
  local gap = windows.tileGap or 0
  local recipes = {
    full     = function() return { x = f.x, y = f.y, w = f.w, h = f.h } end,
    left50   = function() return { x = f.x, y = f.y, w = (f.w - gap) / 2, h = f.h } end,
    right50  = function()
      local w = (f.w - gap) / 2
      return { x = f.x + w + gap, y = f.y, w = w, h = f.h }
    end,
    col1of3  = function()
      local w = (f.w - 2 * gap) / 3
      return { x = f.x, y = f.y, w = w, h = f.h }
    end,
    col2of3  = function()
      local w = (f.w - 2 * gap) / 3
      return { x = f.x + w + gap, y = f.y, w = w, h = f.h }
    end,
    col3of3  = function()
      local w = (f.w - 2 * gap) / 3
      return { x = f.x + 2 * (w + gap), y = f.y, w = w, h = f.h }
    end,
    center80 = function()
      return {
        x = f.x + f.w * 0.1, y = f.y + f.h * 0.1,
        w = f.w * 0.8,       h = f.h * 0.8,
      }
    end,
  }
  local fn = recipes[recipe]
  if not fn then
    log.wf('unknown recipe: %s', tostring(recipe))
    return recipes.full()
  end
  return fn()
end

-- ── Layout catalog ───────────────────────────────────────────────────────────

M.layouts = {
  coding = {
    label = 'Coding',
    apps  = {
      { name = 'Cursor',  where = 'left50' },
      { name = 'Ghostty', where = 'right50', fallback = 'Terminal' },
    },
  },
  ai_workflow = {
    label          = 'AI Workflow',
    ultrawide_only = true,
    apps           = {
      { name = 'Cursor',        where = 'col1of3' },
      { name = 'ChatGPT Atlas', where = 'col2of3', fallback = 'Safari' },
      { name = 'Ghostty',       where = 'col3of3', fallback = 'Terminal' },
    },
  },
  ops = {
    label   = 'Ops Center',
    trigger = function() require('modules.terminal_ops').launch() end,
  },
  writing = {
    label = 'Writing',
    apps  = {
      { name = 'Notes',         where = 'left50' },
      { name = 'ChatGPT Atlas', where = 'right50', fallback = 'Safari' },
    },
  },
}

M.order = { 'coding', 'ai_workflow', 'ops', 'writing' }

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function screenIsUltrawide(screen)
  local f = screen:frame()
  return f.h > 0 and (f.w / f.h) >= M.ultrawideAspect
end

local function pickTargetScreen()
  local ok, screen = pcall(function() return hs.mouse.getCurrentScreen() end)
  if ok and screen then return screen end
  return hs.screen.mainScreen()
end

local function findApp(name, fallback)
  local app = hs.application.find(name)
  if app then return app, name end
  if fallback then
    app = hs.application.find(fallback)
    if app then return app, fallback end
  end
  return nil, name
end

local function launchApp(name, fallback)
  hs.application.launchOrFocus(name)
  local app = hs.application.find(name)
  if app then return app, name end
  if fallback then
    hs.application.launchOrFocus(fallback)
    app = hs.application.find(fallback)
    if app then return app, fallback end
  end
  return nil, name
end

local function mainWindow(app)
  if not app then return nil end
  local win = app:mainWindow()
  if win then return win end
  local wins = app:allWindows()
  for _, w in ipairs(wins) do
    if w:isStandard() and w:isVisible() then return w end
  end
  return wins[1]
end

local function positionApp(app, recipe, screen)
  local win = mainWindow(app)
  if not win then
    log.wf('no window found for %s', app:name())
    return false
  end
  local target = frameFor(recipe, screen)
  win:setFrame(target)
  win:raise()
  return true
end

local function hideOthers(keepBundleIDs)
  for _, app in ipairs(hs.application.runningApplications()) do
    local bid  = app:bundleID()
    local name = app:name()
    if bid and not keepBundleIDs[bid]
       and not windows.excludedApps[name]
       and app:kind() == 1               -- 1 = regular GUI app
       and not app:isHidden() then
      pcall(function() app:hide() end)
    end
  end
end

-- ── Apply engine ─────────────────────────────────────────────────────────────

function M.apply(name)
  local layout = M.layouts[name]
  if not layout then
    hs.alert.show('⚠ Unknown layout: ' .. tostring(name))
    return
  end

  if layout.trigger then
    M.activeLayout = name
    hs.settings.set('layouts_active', name)
    hs.alert.show('🗂 ' .. layout.label)
    layout.trigger()
    return
  end

  local screen = pickTargetScreen()
  if layout.ultrawide_only and not screenIsUltrawide(screen) then
    hs.alert.show('⚠ ' .. layout.label .. ' needs the ultrawide display')
    return
  end

  windows.pauseFor(M.placementPause)

  local placed  = {}          -- bundleID -> true, for the "keep" set
  local pending = #layout.apps

  local function finalize()
    hideOthers(placed)
    -- Focus the first app in the layout so master-stack picks it up.
    local first = layout.apps[1]
    local app = first and hs.application.find(first.name)
    if app then app:activate() end
    M.activeLayout = name
    hs.settings.set('layouts_active', name)
    hs.alert.show('🗂 ' .. layout.label)
    log.i('applied layout: %s on %s', name, screen:name() or '?')
  end

  local function placeEntry(entry)
    local app, resolvedName = findApp(entry.name, entry.fallback)
    if not app then
      app, resolvedName = launchApp(entry.name, entry.fallback)
    end
    if not app then
      log.wf('cannot find or launch %s', entry.name)
      pending = pending - 1
      if pending == 0 then finalize() end
      return
    end

    local function tryPlace(retries)
      local win = mainWindow(app)
      if win then
        positionApp(app, entry.where, screen)
        if app:bundleID() then placed[app:bundleID()] = true end
        pending = pending - 1
        if pending == 0 then finalize() end
        return
      end
      if retries <= 0 then
        log.wf('%s launched but no window appeared', resolvedName)
        pending = pending - 1
        if pending == 0 then finalize() end
        return
      end
      hs.timer.doAfter(0.25, function() tryPlace(retries - 1) end)
    end

    hs.timer.doAfter(M.launchWait, function() tryPlace(4) end)
  end

  for _, entry in ipairs(layout.apps) do
    placeEntry(entry)
  end
end

-- ── Menu bar picker ──────────────────────────────────────────────────────────

function M.showMenu()
  if menubar then return menubar end
  menubar = hs.menubar.new()
  if not menubar then
    log.e('failed to create menubar item')
    return nil
  end
  menubar:setTitle('🗂')
  menubar:setTooltip('Named window layouts')

  local items = {}
  for _, key in ipairs(M.order) do
    local layout = M.layouts[key]
    if layout then
      items[#items + 1] = {
        title = layout.label,
        fn    = function() M.apply(key) end,
      }
    end
  end
  items[#items + 1] = { title = '-' }
  items[#items + 1] = {
    title = 'Toggle auto-tile',
    fn    = function() windows.toggleAutoTile() end,
  }
  items[#items + 1] = {
    title = 'Cycle tiler mode (focused screen)',
    fn    = function()
      local win = hs.window.focusedWindow()
      windows.cycleMode(win and win:screen() or hs.screen.mainScreen())
    end,
  }
  menubar:setMenu(items)
  return menubar
end

function M.hideMenu()
  if menubar then menubar:delete(); menubar = nil end
end

-- Dump visible standard windows on a screen (for authoring new layouts in Lua).
function M.dumpScreen(screen)
  screen = screen or hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local f = screen:visibleFrame()
  local lines = {
    string.format('-- screen: %s  visibleFrame %dx%d', screen:name() or '?', f.w, f.h),
  }
  for _, win in ipairs(screen:allWindows()) do
    if win:isStandard() and win:isVisible() and not win:isMinimized() then
      local app = win:application()
      local wf = win:frame()
      lines[#lines + 1] = string.format(
        "  { name = '%s', where = 'left50' },  -- %dx%d",
        app and app:name() or '?', wf.w, wf.h
      )
    end
  end
  local report = table.concat(lines, '\n')
  print(report)
  hs.alert.show('Layout dump printed to Console', 2)
  return report
end

return M
