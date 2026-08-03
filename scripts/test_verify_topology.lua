-- Run: hs -c 'dofile(os.getenv("HOME").."/.hammerspoon/scripts/test_verify_topology.lua")'
local verify = require('modules.verify')
local fails = 0

local function expect(label, cond, detail)
  if cond then
    print('[PASS]', label)
  else
    fails = fails + 1
    print('[FAIL]', label, detail or '')
  end
end

local function find(checks, id)
  for _, c in ipairs(checks or {}) do
    if c.id == id then return c end
  end
  return nil
end

-- Single ultrawide: missing built-in must be WARNING, not FAIL
local single = verify.classifyTopology(1, 1, 0)
expect('single returns table', type(single) == 'table')
local bi = find(single, 'built_in')
expect('single missing built-in is WARNING', bi and bi.result == 'WARNING', bi and bi.result)
local uw = find(single, 'ultrawide')
expect('single ultrawide present is PASS', uw and uw.result == 'PASS', uw and uw.result)

-- Dual missing ultrawide: FAIL
local dual = verify.classifyTopology(2, 0, 2)
local uw2 = find(dual, 'ultrawide')
expect('dual missing ultrawide is FAIL', uw2 and uw2.result == 'FAIL', uw2 and uw2.result)

-- Dual healthy
local ok = verify.classifyTopology(2, 1, 1)
expect('dual healthy ultrawide PASS', find(ok, 'ultrawide').result == 'PASS')
expect('dual healthy built-in PASS', find(ok, 'built_in').result == 'PASS')

-- Structured layout suite must expose subchecks on runLayoutChecks
local layout = verify.runLayoutChecks()
expect('runLayoutChecks returns checks', type(layout) == 'table' and type(layout.checks) == 'table')
expect('runLayoutChecks has pass/fail/warn', layout.pass ~= nil and layout.fail ~= nil and layout.warn ~= nil)

print(string.format('=== topology tests: %d failed ===', fails))
if fails > 0 then error(fails .. ' topology assertion(s) failed') end
