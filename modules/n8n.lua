-- Module: n8n.lua
-- Responsibility: HTTP webhook triggers.
local M = {}
M.baseURL = 'http://localhost:5678/webhook'

local ALLOWED_PATHS = {
  ['hs/daily-log'] = true,
}

function M.isAllowedPath(path)
  return type(path) == 'string' and ALLOWED_PATHS[path] == true
end

function M.trigger(path)
  if not path then hs.alert.show('⚠ n8n.trigger: path required'); return end
  if not M.isAllowedPath(path) then
    hs.alert.show('⚠ n8n: path not allowlisted')
    return
  end
  hs.http.asyncGet(M.baseURL .. '/' .. path, nil, function(status, body)
    if status == 200 then hs.alert.show('✅ n8n: ' .. path)
    else hs.alert.show('⚠ n8n: HTTP ' .. tostring(status)) end
  end)
end

function M.post(path, payload, callback)
  if not path then return end
  if not M.isAllowedPath(path) then
    hs.alert.show('⚠ n8n: path not allowlisted')
    return
  end
  hs.http.asyncPost(M.baseURL .. '/' .. path, hs.json.encode(payload or {}),
    {['Content-Type']='application/json'},
    function(status, body)
      if type(callback) == 'function' then
        callback(status, body)
        return
      end
      hs.alert.show(status==200 and '✅ n8n POST: '..path or '⚠ n8n POST: HTTP '..tostring(status))
    end)
end

return M
