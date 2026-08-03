-- Module: insight.lua
-- Responsibility: Hotkey scan, thin host metrics, light performance probes (Phase 4).
local M = {}

local function isoNow()
  local z = os.date('%z') or '+0000'
  if #z == 5 then z = z:sub(1, 3) .. ':' .. z:sub(4, 5) end
  return os.date('%Y-%m-%dT%H:%M:%S') .. z
end

local function httpGetStatus(url)
  local okCall, status = pcall(function()
    local code = hs.http.get(url, nil)
    return tonumber(code) or -1
  end)
  if not okCall then return -1 end
  return tonumber(status) or -1
end

local function timed(fn)
  local t0 = hs.timer.secondsSinceEpoch()
  local ok, a, b, c = pcall(fn)
  local ms = math.floor((hs.timer.secondsSinceEpoch() - t0) * 1000 + 0.5)
  return ok, ms, a, b, c
end

--- Inventory Hammerspoon-registered hotkeys; flag chord duplicates inside HS only.
function M.scanHotkeys()
  local entries = {}
  local byChord = {}
  local hotkeys = {}
  pcall(function()
    hotkeys = hs.hotkey.getHotkeys() or {}
  end)

  for _, h in ipairs(hotkeys) do
    local idx = tostring(h.idx or h.msg or '?')
    local msg = tostring(h.msg or '')
    local chord = idx
    -- normalize common idx forms like "C^⌘R" / stored idx
    entries[#entries + 1] = {
      idx = idx,
      msg = msg,
    }
    byChord[chord] = byChord[chord] or {}
    local bucket = byChord[chord]
    bucket[#bucket + 1] = msg ~= '' and msg or idx
  end

  local conflicts = {}
  for chord, msgs in pairs(byChord) do
    if #msgs > 1 then
      conflicts[#conflicts + 1] = {
        chord = chord,
        bindings = msgs,
        note = 'Duplicate Hammerspoon registration (macOS/Raycast/Cursor not scanned)',
      }
    end
  end

  table.sort(conflicts, function(a, b) return tostring(a.chord) < tostring(b.chord) end)
  table.sort(entries, function(a, b) return tostring(a.idx) < tostring(b.idx) end)

  return {
    at = isoNow(),
    count = #entries,
    entries = entries,
    conflicts = conflicts,
    conflict_count = #conflicts,
    scope = 'hammerspoon_only',
    note = 'Does not detect macOS, Raycast, or Cursor shortcut collisions.',
  }
end

--- Thin host metrics via hs.host (not a process browser).
function M.hostMetrics()
  local cpu = nil
  local mem = nil
  local battery = nil

  pcall(function()
    if hs.host and hs.host.cpuUsage then
      local u = hs.host.cpuUsage()
      if type(u) == 'table' and u.overall then
        cpu = {
          user = u.overall.user,
          system = u.overall.system,
          active = u.overall.active,
          idle = u.overall.idle,
        }
      elseif type(u) == 'number' then
        cpu = { active = u }
      end
    end
  end)

  pcall(function()
    if hs.host and hs.host.vmStat then
      local vm = hs.host.vmStat()
      if type(vm) == 'table' then
        local pageSize = vm.pageSize or 4096
        local free = (vm.pagesFree or 0) * pageSize
        local active = (vm.pagesActive or 0) * pageSize
        local wired = (vm.pagesWired or 0) * pageSize
        local compressed = (vm.pagesCompressed or 0) * pageSize
        mem = {
          free_mb = math.floor(free / (1024 * 1024)),
          active_mb = math.floor(active / (1024 * 1024)),
          wired_mb = math.floor(wired / (1024 * 1024)),
          compressed_mb = math.floor(compressed / (1024 * 1024)),
        }
      end
    end
  end)

  pcall(function()
    if hs.battery then
      battery = {
        percentage = hs.battery.percentage and hs.battery.percentage() or nil,
        is_charging = hs.battery.isCharging and hs.battery.isCharging() or nil,
        power_source = hs.battery.powerSource and hs.battery.powerSource() or nil,
      }
    end
  end)

  local loadavg = nil
  pcall(function()
    if hs.host and hs.host.cpuLoad then
      loadavg = hs.host.cpuLoad()
    end
  end)

  return {
    at = isoNow(),
    cpu = cpu,
    memory = mem,
    battery = battery,
    loadavg = loadavg,
  }
end

--- Timed allowlisted probes (no APM).
function M.runPerfProbes()
  local probes = {}

  local okG, msG = timed(function()
    return hs.application.find('Ghostty') ~= nil
  end)
  probes[#probes + 1] = {
    id = 'ghostty_find',
    ms = msG,
    ok = okG,
    detail = okG and 'hs.application.find(Ghostty)' or 'error',
  }

  local okO, msO, codeO = timed(function()
    return httpGetStatus('http://127.0.0.1:11434/api/tags')
  end)
  probes[#probes + 1] = {
    id = 'ollama_latency',
    ms = msO,
    ok = okO and codeO == 200,
    detail = 'HTTP ' .. tostring(codeO),
  }

  local okN, msN, codeN = timed(function()
    return httpGetStatus('http://127.0.0.1:5678')
  end)
  probes[#probes + 1] = {
    id = 'n8n_latency',
    ms = msN,
    ok = okN and (codeN == 200 or codeN == 404),
    detail = 'HTTP ' .. tostring(codeN),
  }

  local okL, msL, codeL = timed(function()
    return httpGetStatus('http://127.0.0.1:1234/v1/models')
  end)
  probes[#probes + 1] = {
    id = 'lm_studio_latency',
    ms = msL,
    ok = okL and codeL == 200,
    detail = 'HTTP ' .. tostring(codeL),
  }

  local ops = package.loaded['modules.operations_console']
  local reloadAge = nil
  pcall(function()
    local st = ops and ops.getStatus and ops.getStatus()
    if st and st.hammerspoon and st.hammerspoon.last_reload then
      reloadAge = st.hammerspoon.last_reload
    end
  end)
  probes[#probes + 1] = {
    id = 'last_reload_marker',
    ms = nil,
    ok = reloadAge ~= nil,
    detail = reloadAge or 'unknown',
  }

  return {
    at = isoNow(),
    probes = probes,
  }
end

return M
