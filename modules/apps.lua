-- Module: apps.lua
-- Responsibility: App launcher and focuser.
local M = {}

local function shellQuote(s)
  return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

M.mainBrowser = 'ChatGPT Atlas'
M.mainBrowserPath = '/Applications/ChatGPT Atlas.app'

M.knownPaths = {
  ['ChatGPT Atlas'] = M.mainBrowserPath,
  ['IBKR Desktop']  = '/Users/eduardofgiovannini/Applications/IBKR Desktop/IBKR Desktop.app',
}

function M.openWithMainBrowser(filePath)
  if not filePath or filePath == '' then
    hs.alert.show('⚠ apps.openWithMainBrowser: no path')
    return false
  end
  local attrs = hs.fs.attributes(M.mainBrowserPath)
  if not attrs then
    hs.alert.show('⚠ Browser not found\n' .. M.mainBrowserPath)
    return false
  end
  hs.execute('open -a ' .. shellQuote(M.mainBrowserPath) .. ' ' .. shellQuote(filePath))
  return true
end

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

function M.launchPath(path, label)
  if not path or path == '' then
    hs.alert.show('⚠ apps.launchPath: no path')
    return false
  end
  local attrs = hs.fs.attributes(path)
  if not attrs then
    hs.alert.show('⚠ App not found\n' .. path)
    return false
  end
  hs.execute('open ' .. shellQuote(path))
  hs.alert.show('▶ ' .. (label or 'App'))
  return true
end

function M.launchITerm()
  local app = hs.application.find('iTerm') or hs.application.find('iTerm2')
  if app then
    app:activate()
    return true
  end
  hs.application.launchOrFocus('iTerm')
  return true
end

function M.launch(name)
  if not name or name == '' then hs.alert.show('⚠ apps.launch: no app name'); return end
  if name == 'BlackDragon' then M.launchBlackDragon(); return end
  if name == 'iTerm' or name == 'iTerm2' then M.launchITerm(); return end
  local known = M.knownPaths[name]
  if known then M.launchPath(known, name); return end
  if name:find('/') then M.launchPath(name, name:match('([^/]+)%.app$') or name); return end
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
