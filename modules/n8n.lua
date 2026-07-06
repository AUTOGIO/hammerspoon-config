-- Module: n8n.lua
-- Responsibility: HTTP webhook triggers.
local M = {}
M.baseURL = 'http://localhost:5678/webhook'
function M.trigger(path)
  if not path then hs.alert.show('⚠ n8n.trigger: path required'); return end
  hs.http.asyncGet(M.baseURL .. '/' .. path, nil, function(status, body)
    if status == 200 then hs.alert.show('✅ n8n: ' .. path)
    else hs.alert.show('⚠ n8n: HTTP ' .. tostring(status)) end
  end)
end
function M.post(path, payload)
  if not path then return end
  hs.http.asyncPost(M.baseURL .. '/' .. path, hs.json.encode(payload or {}),
    {['Content-Type']='application/json'},
    function(status) hs.alert.show(status==200 and '✅ n8n POST: '..path or '⚠ n8n POST: HTTP '..tostring(status)) end)
end
return M
