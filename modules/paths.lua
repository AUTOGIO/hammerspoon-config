-- Module: paths.lua
-- Responsibility: Canonical filesystem paths for BlackDragon + Terminal Ops.
local M = {}

local home = os.getenv('HOME') or ''

-- Override anytime: export TERMINAL_OPS_PROJECT_DIR=~/your/repo
M.blackDragonProject = os.getenv('TERMINAL_OPS_PROJECT_DIR')
  or (home .. '/Documents/GitHub/AI_Engineering_OS')

-- Legacy location (pre–Jul 2026 reorganize); used only as fallback probe.
M.legacyBlackDragonProject = home .. '/Documents/01_Projects/BlackDragon_Project'

function M.resolveBlackDragonProject()
  local env = os.getenv('TERMINAL_OPS_PROJECT_DIR')
  if env and env ~= '' then
    local attrs = hs.fs.attributes(env)
    if attrs and attrs.mode == 'directory' then return env end
  end

  local attrs = hs.fs.attributes(M.blackDragonProject)
  if attrs and attrs.mode == 'directory' then return M.blackDragonProject end

  attrs = hs.fs.attributes(M.legacyBlackDragonProject)
  if attrs and attrs.mode == 'directory' then return M.legacyBlackDragonProject end

  return M.blackDragonProject
end

return M
