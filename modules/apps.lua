-- Module: apps.lua
-- Responsibility: App launcher and focuser.
local M = {}

local function findBlackDragonApp()
  local configs = { 'Release', 'Debug' }
  for _, config in ipairs(configs) do
    local pattern = '*Build/Products/' .. config .. '/*'
    local cmd = "find ~/Library/Developer/Xcode/DerivedData -name 'BlackDragon.app' "
      .. "-path '" .. pattern .. "' -type d 2>/dev/null | head -1"
    local f = io.popen(cmd)
    if f then
      local path = f:read('*l')
      f:close()
      if path and path ~= '' then return path end
    end
  end
  return nil
end

function M.launchBlackDragon()
  if hs.application.find('BlackDragon') then
    hs.application.launchOrFocus('BlackDragon')
    return
  end
  local path = findBlackDragonApp()
  if path then
    hs.execute("open '" .. path:gsub("'", "'\\''") .. "'")
    hs.alert.show('🐉 Launching BlackDragon')
    return
  end
  hs.alert.show('⚠ BlackDragon not built — run ./launch.sh release')
end

function M.launch(name)
  if not name or name == '' then hs.alert.show('⚠ apps.launch: no app name'); return end
  if name == 'BlackDragon' then M.launchBlackDragon(); return end
  hs.application.launchOrFocus(name)
end

function M.focus(name)
  local app = hs.application.find(name)
  if app then app:activate() else hs.alert.show('⚠ ' .. name .. ' not running') end
end

function M.toggle(name)
  local app = hs.application.find(name)
  if not app then M.launch(name); return end
  if app:isFrontmost() then app:hide() else app:activate() end
end

return M
