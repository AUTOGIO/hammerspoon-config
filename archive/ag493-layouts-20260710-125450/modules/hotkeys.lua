-- Module: hotkeys.lua
-- Responsibility: Central hotkey registry.
local windows      = require('modules.windows')
local apps         = require('modules.apps')
local clipboard    = require('modules.clipboard')
local terminal_ops = require('modules.terminal_ops')
local layouts      = require('modules.layouts')
local hyper   = {'cmd','ctrl','alt','shift'}
local mods    = {'cmd','ctrl'}
local shifted = {'cmd','ctrl','shift'}
hs.hotkey.bind(hyper, 'left',  windows.snapLeft)
hs.hotkey.bind(hyper, 'right', windows.snapRight)
hs.hotkey.bind(hyper, 'up',    windows.maximize)
hs.hotkey.bind(hyper, 'down',  windows.center)
hs.hotkey.bind(mods, '1', function() apps.launch('BlackDragon') end)
hs.hotkey.bind(mods, '2', function() apps.launch('Notes') end)
hs.hotkey.bind(mods, '3', function() apps.launch('Cursor') end)
hs.hotkey.bind(mods, '4', function() apps.launch('Terminal') end)
hs.hotkey.bind(mods, '5', terminal_ops.launch)
hs.hotkey.bind(mods, 'v', clipboard.showHistory)
hs.hotkey.bind(mods, 'r', function() hs.reload(); hs.alert.show('🔄 Reloading…') end)

-- Auto-tiler control
hs.hotkey.bind(mods, 't', windows.toggleAutoTile)
hs.hotkey.bind(mods, 'l', function()
  local win = hs.window.focusedWindow()
  windows.cycleMode(win and win:screen() or hs.screen.mainScreen())
end)

-- Named layouts
hs.hotkey.bind(shifted, '1', function() layouts.apply('coding') end)
hs.hotkey.bind(shifted, '2', function() layouts.apply('ai_workflow') end)
hs.hotkey.bind(shifted, '3', function() layouts.apply('ops') end)
hs.hotkey.bind(shifted, '4', function() layouts.apply('writing') end)
