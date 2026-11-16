--[[
-- @description ReaTooled - Toggle ReaTooled Shortcuts
-- @version 1.2
-- @date 2026.11.15
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
    Toggles between the ReaTooled Keymap (alt 16) and Main Keymap.
    Off: the Main keymap and your own mouse modifiers (as they were before ReaTooled
    was set up, then as you left them the last time shortcuts were off), with no tool
    chosen. On: ReaTooled's keys and mouse modifiers exactly as they were when
    shortcuts went off, with the same tool. Changes made in one never reach the other.
    MIDI editor shortcuts and mouse modifiers stay ReaTooled's either way.
    Cmd+click or Option+click (Ctrl/Alt+click on Windows) the toolbar button for the
    option to switch only the shortcuts, and keep ReaTooled's mouse modifiers.
-- @changelog
    v1.2 Cmd/Option+click on the button: "Switch mouse modifiers too" (on by default).
         The first time shortcuts go off, a short note says what changed.
    v1.1 Mouse modifiers switch with the shortcuts (two setups side by side)
--]]

local NS = "ReaTooled"
local SWITCH_KEY = "ShortcutsSwitchMouse"    -- "0": only the shortcuts switch (kept)
local NOTICE_KEY = "ShortcutsOffNoticeShown" -- the note has been shown (kept)

local _, _, section, cmd_id = reaper.get_action_context()
local toggleState = reaper.GetToggleCommandStateEx(0, cmd_id)

local function tools_lib()
  local path = reaper.GetResourcePath():gsub("\\", "/") .. "/Scripts/ReaTooled/Tools/ReaTooled_Tools lib.lua"
  if not reaper.file_exists(path) then return nil end
  local ok, t = pcall(dofile, path)
  if ok and type(t) == "table" and t.mouse_setup_on then return t end
end

local tools = tools_lib()
local function switch_mouse() return reaper.GetExtState(NS, SWITCH_KEY) ~= "0" end

-- Cmd/Option+click on the button: the option, not a toggle
if tools and tools.options_click and tools.options_click() then
  local label = (switch_mouse() and "!" or "") ..
    "Switch mouse modifiers too (your own while shortcuts are off)"
  local title = "ReaTooled Shortcuts options"
  local x, y = reaper.GetMousePosition()
  gfx.init(title, 0, 0, 0, x, y)
  if reaper.JS_Window_Find and reaper.JS_Window_SetOpacity then
    local w = reaper.JS_Window_Find(title, true)
    if w then reaper.JS_Window_SetOpacity(w, "ALPHA", 0) end
  end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(label)
  gfx.quit()
  if choice == 1 then
    local on = not switch_mouse()
    reaper.SetExtState(NS, SWITCH_KEY, on and "1" or "0", true)
    if toggleState ~= 1 then   -- (shortcuts off now: the mouse follows the new choice)
      if on then tools.mouse_setup_off() else tools.mouse_setup_on() end
    end
  end
  reaper.defer(function() end)
  return
end

if toggleState ~= 1 then
  toggleState = 1
  reaper.SetExtState(NS, "ReaTooledKeymapOn", tonumber(1), true)
  if tools then tools.mouse_setup_on() end   -- (nothing to do when already on, e.g. at startup)
  reaper.Main_OnCommand(24818, 0)  -- Toggle ReaTooled Keymap Alt 16
else
  toggleState = 0
  local mouse = tools and switch_mouse() and tools.mouse_setup_off()
  reaper.Main_OnCommand(24800, 0)  -- Clear Keymap Override
  reaper.SetExtState(NS, "ReaTooledKeymapOn", tonumber(0), true)
  if reaper.GetExtState(NS, NOTICE_KEY) ~= "1" then
    reaper.SetExtState(NS, NOTICE_KEY, "1", true)
    reaper.ShowMessageBox("ReaTooled Shortcuts are off: REAPER's own keyboard shortcuts" ..
      (mouse and " and your own mouse modifiers (as you had them before ReaTooled), with no tool chosen." or ".") ..
      "\n\nTurn them back on and ReaTooled is exactly as you left it" ..
      (mouse and ", with the same tool." or ".") ..
      "\n\nTo choose whether the mouse modifiers switch too, Cmd+click or Option+click the button" ..
      " (Ctrl+click or Alt+click on Windows).\n\n(This note is shown once.)", "ReaTooled", 0)
  end
end

reaper.SetToggleCommandState(section, cmd_id, toggleState)
reaper.RefreshToolbar2(section, cmd_id)

reaper.defer(function() end) --this prevents undo
