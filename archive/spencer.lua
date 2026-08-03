-- Module: spencer.lua
-- DEPRECATED: Layouts are now defined in modules/layouts.lua (Hammerspoon-native).
-- This module is kept for manual CLI use only; it is no longer wired in guide.lua.
-- Responsibility: Spencer CLI bridge for layout restore and update.
local M = {}

local log = hs.logger.new('spencer', 'info')
local cli = os.getenv('HOME') .. '/.local/bin/spencer'

local function shellQuote(s)
  return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

local function run(args)
  local cmd = cli .. ' ' .. args .. ' 2>&1'
  local ok, output = hs.execute(cmd)
  output = (output or ''):gsub('%s+$', '')
  if not ok then
    hs.alert.show('⚠ Spencer failed\n' .. (output ~= '' and output or 'command error'))
    log.ef('spencer cmd failed: %s', args)
    return false, output
  end
  return true, output
end

function M.list()
  local ok, output = run('--list')
  if not ok then return {} end
  local layouts = {}
  for line in output:gmatch('[^\r\n]+') do
    if line:match('^%s+%S') then
      table.insert(layouts, line:match('^%s*(.-)%s*$'))
    end
  end
  return layouts
end

function M.restoreActive(launchApps)
  local flag = launchApps and '--launch-apps=true' or '--launch-apps=false'
  local ok = run('--restore-active ' .. flag)
  if ok then hs.alert.show('📐 Spencer: active layout restored') end
end

function M.updateActive()
  local ok = run('--update-active')
  if ok then hs.alert.show('📐 Spencer: active layout saved') end
end

function M.updateActiveDesktop()
  local ok = run('--update-active-desktop')
  if ok then hs.alert.show('📐 Spencer: desktop saved to active layout') end
end

function M.restore(name, launchApps)
  if not name or name == '' then
    hs.alert.show('⚠ Spencer: layout name required')
    return
  end
  local flag = launchApps and '--launch-apps=true' or '--launch-apps=false'
  local ok = run('--restore ' .. shellQuote(name) .. ' ' .. flag)
  if ok then hs.alert.show('📐 Spencer: ' .. name) end
end

return M
