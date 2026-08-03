-- Module: ai.lua
-- Responsibility: AI-powered hotkeys for BlackDragon workflow.
-- Hotkey prefix: Ctrl + Option + Cmd (no Shift — distinct from hyper)
-- All actions are clipboard-handoff only. Nothing auto-submits to AI.
-- Requires Accessibility permission for hs.eventtap.keyStroke.

local M = {}

local AI = {"ctrl", "alt", "cmd"}
local PROMPTS_PATH = os.getenv("HOME") .. "/Documents/prompts.md"
local PROMPTS_TEMPLATE = [[# Prompts

Edit sections below. Each ## heading becomes a choosable prompt.
Deliver with ⌃⌥⌘D — copies to clipboard and opens Claude (paste with ⌘V).

## daily-review
What are my top 3 priorities today based on my current projects?

## code-audit
You are a senior code reviewer. Audit the following code for bugs, complexity, security, and simplifications.
]]

local function captureSelection(callback)
  local old = hs.pasteboard.getContents()
  hs.pasteboard.clearContents()
  hs.eventtap.keyStroke({"cmd"}, "c", 0)
  hs.timer.doAfter(0.25, function()
    local sel = hs.pasteboard.getContents()
    hs.timer.doAfter(2, function() hs.pasteboard.setContents(old or "") end)
    if not sel or sel == "" then
      hs.alert.show("⚠️  No text selected")
      return
    end
    callback(sel)
  end)
end

local function openURL(url)
  hs.execute("open '" .. url .. "'")
end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ensurePromptsFile()
  local attrs = hs.fs.attributes(PROMPTS_PATH)
  if attrs then return true end
  local f = io.open(PROMPTS_PATH, "w")
  if not f then
    hs.alert.show("❌ Could not create prompts file\n" .. PROMPTS_PATH)
    return false
  end
  f:write(PROMPTS_TEMPLATE)
  f:close()
  hs.alert.show("📝 Created starter prompts.md")
  return true
end

local function readPromptsFile()
  if not ensurePromptsFile() then return nil end
  local f = io.open(PROMPTS_PATH, "r")
  if not f then
    hs.alert.show("❌ Could not read prompts file\n" .. PROMPTS_PATH)
    return nil
  end
  local content = f:read("*a")
  f:close()
  content = trim(content)
  if content == "" then
    hs.alert.show("⚠️  prompts.md is empty")
    return nil
  end
  return content
end

local function parseSections(content)
  local sections = {}
  local currentName, currentBody = nil, {}

  for line in (content .. "\n"):gmatch("(.-)\r?\n") do
    local heading = line:match("^##%s+(.+)$")
    if heading then
      if currentName then
        sections[#sections + 1] = { name = currentName, body = trim(table.concat(currentBody, "\n")) }
      end
      currentName = trim(heading)
      currentBody = {}
    elseif currentName then
      currentBody[#currentBody + 1] = line
    end
  end

  if currentName then
    sections[#sections + 1] = { name = currentName, body = trim(table.concat(currentBody, "\n")) }
  end
  return sections
end

local function handoffToClaude(prompt, label)
  hs.pasteboard.setContents(prompt)
  hs.application.launchOrFocus("Claude")
  hs.alert.show("📋 " .. (label or "Prompt") .. " ready — paste with ⌘V")
end

function M.deliverPrompt(sectionName)
  local content = readPromptsFile()
  if not content then return end

  local sections = parseSections(content)
  if #sections == 0 then
    handoffToClaude(content, "Prompt")
    return
  end

  if sectionName and sectionName ~= "" then
    local key = sectionName:lower()
    for _, section in ipairs(sections) do
      if section.name:lower() == key then
        handoffToClaude(section.body, section.name)
        return
      end
    end
    hs.alert.show("⚠️  No prompt section: " .. sectionName)
    return
  end

  if #sections == 1 then
    handoffToClaude(sections[1].body, sections[1].name)
    return
  end

  local choices = {}
  for i, section in ipairs(sections) do
    local preview = section.body:gsub("\n", " ")
    if #preview > 72 then preview = preview:sub(1, 69) .. "…" end
    choices[i] = {
      text = section.name,
      subText = preview,
      section = section,
    }
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice or not choice.section then return end
    handoffToClaude(choice.section.body, choice.section.name)
  end)
  chooser:choices(choices)
  chooser:placeholderText("Select a prompt from prompts.md")
  chooser:show()
end

function M.openConsole()
  local opened = false
  pcall(function()
    if hs.openConsole then hs.openConsole(); opened = true end
  end)
  if not opened then
    hs.application.launchOrFocus("Hammerspoon")
  end
end

local quickCommands = {
  {
    text = "Reload Hammerspoon",
    subText = "Apply config changes",
    run = function() hs.reload() end,
  },
  {
    text = "Open config folder",
    subText = hs.configdir,
    run = function() hs.execute("open '" .. hs.configdir:gsub("'", "'\\''") .. "'") end,
  },
  {
    text = "Open Hammerspoon Console",
    subText = "Lua REPL",
    run = M.openConsole,
  },
  {
    text = "Run verification",
    subText = "Display and health checks",
    run = function() require("modules.verify").run() end,
  },
  {
    text = "Copy diagnostics",
    subText = "Operations status snapshot",
    run = function() require("modules.operations_console").execute("copy_diagnostics") end,
  },
  {
    text = "Open prompts.md",
    subText = PROMPTS_PATH,
    run = function()
      ensurePromptsFile()
      hs.execute("open '" .. PROMPTS_PATH:gsub("'", "'\\''") .. "'")
    end,
  },
}

function M.quickCommand()
  local choices = {}
  for i, cmd in ipairs(quickCommands) do
    choices[i] = { text = cmd.text, subText = cmd.subText, cmd = cmd }
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice or not choice.cmd then return end
    choice.cmd.run()
  end)
  chooser:choices(choices)
  chooser:placeholderText("Hammerspoon quick command")
  chooser:show()
end

function M.explain(sel)
  local prompt = "Please explain the following in simple, plain English:\n\n" .. sel
  hs.pasteboard.setContents(prompt)
  openURL("https://chatgpt.com")
  hs.alert.show("📋 Prompt ready — paste into ChatGPT")
end

function M.summary(sel)
  local date  = os.date("%Y-%m-%d")
  local title = "Summary — " .. date
  local md = "# " .. title .. "\n\n"
          .. "## Summary\n\n> (write your summary here)\n\n"
          .. "## Key Points\n\n- \n\n"
          .. "## Source\n\n" .. sel .. "\n\n"
          .. "---\n*Created: " .. date .. "*\n"
  hs.pasteboard.setContents(md)
  hs.application.launchOrFocus("Notes")
  hs.alert.show("📋 Notes template ready — paste with ⌘V")
end

function M.codex(sel)
  local prompt = "You are a senior code reviewer. Audit the following code.\n"
              .. "Focus only on actionable findings in these categories:\n"
              .. "1. Bugs — logic errors, off-by-one, null/undefined risks\n"
              .. "2. Complexity — unnecessary complexity, hard-to-read patterns\n"
              .. "3. Security — injection, exposure, unsafe operations\n"
              .. "4. Simplifications — idiomatic rewrites, dead code removal\n\n"
              .. "Return findings as a numbered list. Skip categories with no issues.\n\n"
              .. "```\n" .. sel .. "\n```"
  hs.pasteboard.setContents(prompt)
  openURL("https://chatgpt.com")
  hs.alert.show("📋 Codex audit prompt ready — paste into ChatGPT")
end

function M.snapshot()
  local snapDir = os.getenv("HOME")
    .. "/Library/Mobile Documents/com~apple~CloudDocs/Obsidian/AUTOGIO_PROJECT_SNAPSHOTS"

  hs.execute("mkdir -p '" .. snapDir .. "'")

  local stamp    = os.date("%Y-%m-%d_%H-%M")
  local filename = "project_snapshot_" .. stamp .. ".md"
  local filepath = snapDir .. "/" .. filename

  local f = io.open(filepath, "r")
  if f then
    f:close()
    hs.alert.show("⚠️  Snapshot already exists: " .. filename)
    return
  end

  local activeApp = "Unknown"
  local win = hs.window.focusedWindow()
  if win then activeApp = win:application():name() end

  local date = os.date("%Y-%m-%d %H:%M")
  local content = "# Project Snapshot — " .. date .. "\n\n"
               .. "| Field         | Value |\n"
               .. "|---------------|-------|\n"
               .. "| Date          | " .. date .. " |\n"
               .. "| Active App    | " .. activeApp .. " |\n"
               .. "| Status        | *(fill in)* |\n"
               .. "| Next Action   | *(fill in)* |\n"
               .. "| Blockers      | *(fill in)* |\n"
               .. "| Notes         | *(fill in)* |\n\n"
               .. "---\n*Auto-generated by Hammerspoon*\n"

  local out = io.open(filepath, "w")
  if out then
    out:write(content)
    out:close()
    hs.alert.show("📸 Snapshot saved: " .. filename)
  else
    hs.alert.show("❌ Could not write snapshot — check iCloud path")
  end
end

function M.compare(sel)
  local prompt = "Compare and contrast the following from multiple perspectives.\n"
              .. "Provide: (1) key similarities, (2) key differences, "
              .. "(3) when to prefer each, (4) your recommendation with rationale.\n\n"
              .. sel
  hs.pasteboard.setContents(prompt)
  openURL("https://chatgpt.com")
  hs.timer.doAfter(0.4, function() openURL("https://claude.ai/new") end)
  hs.timer.doAfter(0.8, function() openURL("https://gemini.google.com/app") end)
  hs.alert.show("📋 Compare prompt ready — paste into each AI tab")
end

function M.structured(sel)
  local prompt = "Transform the following raw idea or text into a structured prompt.\n\n"
              .. "Return your response with exactly these sections:\n"
              .. "## 🎯 Objective\n(what we want to achieve)\n\n"
              .. "## ⚠️ Risks\n(top 3 risks to execution)\n\n"
              .. "## 🔧 Complexity\n(estimated complexity: Low / Medium / High — and why)\n\n"
              .. "## 🚀 MVP\n(minimum viable version to validate the idea)\n\n"
              .. "## 🗺 Implementation Roadmap\n(phased steps, max 5 phases)\n\n"
              .. "## 80/20 Principle\n(the 20% of effort that delivers 80% of value)\n\n"
              .. "---\nRaw input:\n\n" .. sel
  hs.pasteboard.setContents(prompt)
  openURL("https://chatgpt.com")
  hs.alert.show("📋 Structured prompt ready — paste into ChatGPT")
end

local actions = {
  explain    = function() captureSelection(M.explain) end,
  summary    = function() captureSelection(M.summary) end,
  codex      = function() captureSelection(M.codex) end,
  snapshot   = M.snapshot,
  compare    = function() captureSelection(M.compare) end,
  structured = function() captureSelection(M.structured) end,
  deliver    = M.deliverPrompt,
  console    = M.openConsole,
  quick      = M.quickCommand,
}

function M.run(name)
  local fn = actions[name]
  if fn then fn() else hs.alert.show('⚠ ai: unknown action — ' .. tostring(name)) end
end

hs.hotkey.bind(AI, "g", function() M.run("explain") end)
hs.hotkey.bind(AI, "s", function() M.run("summary") end)
hs.hotkey.bind(AI, "c", function() M.run("codex") end)
hs.hotkey.bind(AI, "p", M.snapshot)
hs.hotkey.bind(AI, "a", function() M.run("compare") end)
hs.hotkey.bind(AI, "r", function() M.run("structured") end)
hs.hotkey.bind(AI, "d", function() M.run("deliver") end)
hs.hotkey.bind(AI, "o", function() M.run("console") end)
hs.hotkey.bind(AI, "q", function() M.run("quick") end)

return M
