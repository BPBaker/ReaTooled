-- @description ReaTooled - Move Tool
-- @version 1.8.1
-- @date 2026.10.30
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # This script loads a set of mouse modifiers focusing on moving items, which gives similar functionality to ProTools' "Grabber Tool."
-- CHANGELOG
-- # v1.8 Cmd+click or Option+click on the toolbar button shows a menu of the tool's options (Separation, Swap left and right drag) instead of choosing the tool
-- # v1.7 Stopping the Trim Tool and the toolbar buttons are shared with the other tools (ReaTooled_Tools lib.lua), which also knows the new Pencil Tool
-- # v1.6 Right-drag in the arrange selects a razor area (left-drag in empty track space is marquee)
-- # v1.5 For click, set SHIFT and CMD to "5 m" and "4 m," respectively
-- # v1.4 Kill Trim Tool, clean up script
-- # v1.3 Many revisions to mouse modifiers for more features control
-- # v1.2 Changed item left click to new companion script '_RS428db9286d6f978287e14df7cf9227628394585d' (Script: ReaTooled_Move Tool Left Click)
-- # v1.1 Multiple tweaks to mouse modifier to more closely align with PT behavior

----------------------------------------
-- Cmd+click or Option+click on the toolbar button: a menu of the tool's options
-- (Separation, Swap left and right drag) instead of choosing the tool. A keyboard
-- shortcut always chooses the tool. (ReaTooled_Tools lib.lua)
----------------------------------------
do
  local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])") or ""
  local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
  if ok and type(tools) == "table" and tools.options_click and tools.options_click() then
    tools.tool_options("grabber")
    reaper.defer(function() end)   -- no undo point
    return
  end
end

----------------------------------------
-- Utility Functions
----------------------------------------
local function setModifiers(context, modifiers)
  for index, value in pairs(modifiers) do
    reaper.SetMouseModifier(context, index, value)
  end
end


----------------------------------------
-- Set All Mouse Modifiers
----------------------------------------

local mouseMods = {
  MM_CTX_ITEM = {
    [0]='13 m', [1]='58 m', [2]='51 m', [3]='9 m', [4]='2 m', [5]='59 m',
    [6]='39 m', [7]='70 m', [8]='32 m', [9]='61 m', [10]='12 m', [11]='59 m',
    [12]='36 m', [13]='55 m', [14]='68 m', [15]='7 m'
  },
  MM_CTX_ITEMLOWER = {
    [0]='13 m', [1]='58 m', [2]='51 m', [3]='9 m', [4]='2 m', [5]='59 m',
    [6]='39 m', [7]='61 m', [8]='32 m', [9]='70 m', [10]='12 m', [11]='59 m',
    [12]='36 m', [13]='55 m', [14]='68 m', [15]='7 m'
  },
  MM_CTX_ITEMEDGE = {
    [0]='0', [1]='0', [2]='0', [3]='0', [4]='10 m', [5]='12 m',
    [6]='6 m', [7]='8 m', [12]='6 m', [14]='19 m'
  },
  MM_CTX_TRACK = {
    [0]='9 m', [1]='13 m', [2]='1 m', [3]='2 m', [4]='0', [5]='-1',   -- (Option-drag: no marquee zoom)
    [6]='16 m', [7]='17 m', [8]='10 m', [9]='-1', [10]='-1', [11]='-1',
    [12]='-1', [13]='-1', [14]='18 m', [15]='23 m'    
  },
  MM_CTX_TRACK_CLK = {
    [0]='1 m', [1]='0', [2]='2 m', [3]='6 m', [4]='8 m', [6]='4 m'
  },
  MM_CTX_ITEM_CLK = {
    [0]='_RS428db9286d6f978287e14df7cf9227628394585d', [1]='17 m', [2]='4 m',
    [3]='24 m', [4]='-1', [5]='-1', [6]='-1', [7]='-1', [8]='42391 c', [9]='18 m',
    [10]='24 m', [11]='-1', [12]='-1', [13]='-1', [14]='-1', [15]='-1'
  },
  MM_CTX_ITEMLOWER_CLK = {
    [0]='_RS428db9286d6f978287e14df7cf9227628394585d', [1]='17 m', [2]='4 m',
    [3]='24 m', [4]='-1', [5]='-1', [6]='-1', [7]='-1', [8]='42391 c', [9]='18 m',
    [10]='24 m', [11]='-1', [12]='-1', [13]='-1', [14]='-1', [15]='-1'
  },
  MM_CTX_ITEM_DBLCLK = {
    [0]='6 m', [1]='5 m', [4]='41848 c', [8]='7 m', [14]='_RSc420542ec64750db62f5b15acd998feac1ec6d1d',
    [15]='_2a3da20698f4486896f47d9c6f093caf'
  },
  MM_CTX_ITEMLOWER_DBLCLK = {
    [0]='6 m', [1]='5 m', [4]='41848 c', [8]='7 m', [14]='_RSc420542ec64750db62f5b15acd998feac1ec6d1d',
    [15]='_2a3da20698f4486896f47d9c6f093caf'
  }
}

for context, mods in pairs(mouseMods) do
  setModifiers(context, mods)
end

----------------------------------------
-- Locking & Arrange Cleanup
----------------------------------------
reaper.Main_OnCommand(40569, 0) -- Enable locking
reaper.Main_OnCommand(40595, 0) -- Set item edges lock
reaper.Main_OnCommand(40598, 0) -- Set item fades lock
reaper.Main_OnCommand(41852, 0) -- Set item stretch markers lock
reaper.Main_OnCommand(41849, 0) -- Set item envelope
reaper.Main_OnCommand(40572, 0) -- Set time selection to UNlock
reaper.Main_OnCommand(42621, 0) -- Clear arrange override mode

----------------------------------------
-- Run cleanup and refresh states
----------------------------------------

----------------------------------------
-- Finish: Trim Tool off, drag swap, Pencil cleanup, toolbar buttons
-- (shared by every tool: ReaTooled_Tools lib.lua)
----------------------------------------
do
  local dir = ({reaper.get_action_context()})[2]:match("^(.*[/\\])") or ""
  local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
  if ok and type(tools) == "table" then
    tools.finish("grabber")
  else
    reaper.ShowConsoleMsg("ReaTooled: tools library not loaded: " .. tostring(tools) .. "\n")
  end
end


-- Optional: Uncomment to enable continuous toolbar state detection
-- reaper.defer(UpdateState)
