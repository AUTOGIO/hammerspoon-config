-- Module: guide.lua
-- Responsibility: URL-event bridge so USER_GUIDE.html buttons trigger real actions.
local M = {}

local windows   = require('modules.windows')
local apps      = require('modules.apps')
local clipboard = require('modules.clipboard')
local n8n       = require('modules.n8n')
local ai           = require('modules.ai')
local terminal_ops = require('modules.terminal_ops')
local layouts      = require('modules.layouts')

local guidePath = os.getenv('HOME') .. '/.hammerspoon/USER_GUIDE.html'

function M.open()
  hs.execute("open '" .. guidePath .. "'")
end

local function run(params)
  local action = params and params.action
  if not action or action == '' then
    hs.alert.show('⚠ guide: action required')
    return
  end

  if action == 'snap-left'    then windows.snapLeft(); return end
  if action == 'snap-right'   then windows.snapRight(); return end
  if action == 'maximize'     then windows.maximize(); return end
  if action == 'center'        then windows.center(); return end
  if action == 'clipboard'    then clipboard.showHistory(); return end
  if action == 'reload'       then hs.reload(); return end
  if action == 'terminal-ops' then terminal_ops.launch(); return end
  if action == 'open-guide'   then M.open(); return end

  if action == 'launch' then
    apps.launch(params.app or '')
    return
  end

  if action == 'n8n-trigger' then
    n8n.trigger(params.path or 'hs/daily-log')
    return
  end

  if action == 'n8n-post' then
    n8n.post(params.path or 'hs/daily-log', {
      timestamp = os.date('%Y-%m-%dT%H:%M:%S'),
      source = 'user-guide',
    })
    return
  end

  if action:match('^ai%-') then
    ai.run(action:sub(4))
    return
  end

  if action == 'layout-apply' then
    layouts.apply(params.layout or '')
    return
  end
  if action == 'tile-toggle' then
    windows.toggleAutoTile()
    return
  end
  if action == 'tile-cycle' then
    local win = hs.window.focusedWindow()
    windows.cycleMode(win and win:screen() or hs.screen.mainScreen())
    return
  end
  if action == 'verify' then
    require('modules.verify').run()
    return
  end

  hs.alert.show('⚠ guide: unknown action — ' .. action)
end

hs.urlevent.bind('guide', 'run', run)

hs.hotkey.bind({'cmd', 'ctrl'}, 'h', M.open)

return M
