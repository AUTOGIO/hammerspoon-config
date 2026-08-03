hs.allowAppleScript(true)
require("hs.ipc")
-- BlackDragon :: Hammerspoon Init
require('modules.windows')
require('modules.layouts').showMenu()
require('modules.hotkeys')
require('modules.apps')
require('modules.n8n')
require('modules.clipboard')
require('modules.ai')
require('modules.guide')
require('modules.operations_console').start()
require('modules.openclaw_button').start()

local configDir = os.getenv('HOME') .. '/.hammerspoon/'
local reloadTimer = nil

local function shouldTriggerReload(files)
  for _, path in ipairs(files) do
    if path:match('/%.hammerspoon/runtime/')
       or path:match('/%.hammerspoon/archive/')
       or path:match('/%.hammerspoon/%.git/')
       or path:match('/%.hammerspoon/docs/') then
      -- skip: runtime status writes, archived files, git metadata, docs
    else
      return true
    end
  end
  return false
end

hs.pathwatcher.new(configDir, function(files)
  if not shouldTriggerReload(files) then return end
  if reloadTimer then reloadTimer:stop() end
  reloadTimer = hs.timer.doAfter(0.5, function()
    reloadTimer = nil
    hs.reload()
  end)
end):start()

hs.alert.show('WE ARE READY, MOTHER FUCKER')
