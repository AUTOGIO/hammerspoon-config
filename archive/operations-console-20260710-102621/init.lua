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

hs.pathwatcher.new(os.getenv('HOME')..'/.hammerspoon/', hs.reload):start()
hs.alert.show('Hammerspoon ready')
