-- Module: openclaw_button.lua
-- Responsibility: OpenClaw Control UI launcher, gateway status, floating button.
-- Hotkey: Ctrl + Option + Cmd + U  → Control UI
--         Ctrl + Option + Cmd + I  → Gateway status
local M = {}

local OPENCLAW_BIN = "/opt/homebrew/bin/openclaw"
local GATEWAY_URL  = "http://127.0.0.1:18789/"
local HOTKEY_MODS  = {"ctrl", "alt", "cmd"}
local HOTKEY_KEY   = "u"

local canvas = nil
local BUTTON_W, BUTTON_H = 44, 44

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function openControlUI()
  hs.http.asyncGet(GATEWAY_URL, nil, function(status)
    if status == 200 then
      hs.execute("open '" .. GATEWAY_URL .. "'")
      hs.alert.show("🦞 OpenClaw Control UI")
    else
      hs.alert.show("⚠ OpenClaw gateway unreachable (HTTP " .. tostring(status) .. ")\nCheck port 18789")
    end
  end)
end

local function gatewayStatus()
  local output = trim(hs.execute(OPENCLAW_BIN .. " gateway status 2>&1"))
  if output == "" then
    hs.alert.show("⚠ OpenClaw CLI failed — is " .. OPENCLAW_BIN .. " installed?")
    return
  end
  local runtime = output:match("Runtime:%s*(%S+)") or output:match("(%S+)") or output
  if #runtime > 80 then runtime = runtime:sub(1, 77) .. "…" end
  hs.alert.show("🦞 Gateway status\nRuntime: " .. runtime)
end

local function createButton()
  if canvas then return end

  local screen = hs.screen.mainScreen()
  local frame = screen:frame()
  local x = frame.x + frame.w - BUTTON_W - 24
  local y = frame.y + frame.h - BUTTON_H - 96

  canvas = hs.canvas.new({ x = x, y = y, w = BUTTON_W, h = BUTTON_H })
  canvas:level(hs.canvas.windowLevels.floating)
  canvas[1] = {
    type = "circle",
    action = "fill",
    fillColor = { alpha = 0.92, red = 0.95, green = 0.45, blue = 0.15 },
    radius = BUTTON_W / 2,
  }
  canvas[2] = {
    type = "text",
    text = "🦞",
    textSize = 20,
    textAlignment = "center",
    frame = { x = 0, y = 6, w = BUTTON_W, h = BUTTON_H },
  }
  canvas:show()

  local dragging, dragStart
  canvas:canvasMouseEvents(true, true, true, true)
  canvas:mouseCallback(function(_, msg, id, x, y)
    if msg == "mouseDown" then
      dragging = true
      dragStart = { x = x, y = y, cx = canvas:topLeft().x, cy = canvas:topLeft().y }
    elseif msg == "mouseUp" then
      if dragging and dragStart then
        local dx, dy = math.abs(x - dragStart.x), math.abs(y - dragStart.y)
        if dx < 4 and dy < 4 then openControlUI() end
      end
      dragging, dragStart = false, nil
    elseif msg == "mouseMove" and dragging and dragStart then
      canvas:topLeft({
        x = dragStart.cx + (x - dragStart.x),
        y = dragStart.cy + (y - dragStart.y),
      })
    end
  end)
end

function M.start()
  hs.hotkey.bind(HOTKEY_MODS, HOTKEY_KEY, openControlUI)
  hs.hotkey.bind(HOTKEY_MODS, "i", gatewayStatus)
  createButton()
  hs.alert.show("🦞 OpenClaw ready — ⌃⌥⌘U Control UI · ⌃⌥⌘I status")
end

return M
