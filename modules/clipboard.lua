-- Module: clipboard.lua
-- Responsibility: Clipboard watcher + 20-item history chooser.
local M = {}
local history, maxHistory, watcher, chooser = {}, 20, nil, nil
local function pushHistory(text)
  if not text or text == '' then return end
  for i,v in ipairs(history) do if v==text then table.remove(history,i); break end end
  table.insert(history, 1, text)
  if #history > maxHistory then table.remove(history, #history) end
end
function M.startWatcher()
  if watcher then return end
  watcher = hs.pasteboard.watcher.new(function(content)
    if type(content)=='string' then pushHistory(content) end
  end)
  watcher:start()
end
function M.showHistory()
  if #history == 0 then hs.alert.show('📋 Clipboard history empty'); return end
  local choices = {}
  for i,text in ipairs(history) do
    table.insert(choices, {text=text:sub(1,80):gsub('\n',' '), subText='#'..i..' — '..#text..' chars', item=text})
  end
  if not chooser then
    chooser = hs.chooser.new(function(choice)
      if choice then hs.pasteboard.setContents(choice.item); hs.eventtap.keyStroke({'cmd'},'v') end
    end)
  end
  chooser:choices(choices); chooser:show()
end
function M.clearHistory() history = {}; hs.alert.show('📋 Cleared') end
function M.count() return #history end
function M.watcherAlive() return watcher ~= nil end
M.startWatcher()
return M
