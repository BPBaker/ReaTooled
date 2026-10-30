-- @description ReaTooled - Default Multi Tool (Smart)
-- @version 1.6.7
-- @date 2026.10.30
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # This script loads ReaTooled's default set of mouse modifiers, which gives similar functionality to ProTools' "Smart Tool." 
-- CHANGELOG
-- # v1.6.7 Cmd+click or Option+click on the toolbar button shows a menu of the tool's options (Separation, Swap left and right drag) instead of choosing the tool
-- # v1.6.6 Stopping the Trim Tool and the toolbar buttons are shared with the other tools (ReaTooled_Tools lib.lua), which also knows the new Pencil Tool
-- # v1.6.5 Follows "Toggle swap left and right drag": with it on, right-drag selects razor areas and left-drag in empty track space is marquee
-- # v1.6.4 Shift+Ctrl double-click on an item (top and bottom half) runs ReaTooled_Clear take envelopes and Reset Volume to 0db.lua
--        (the old custom action no longer exists); clears the Cmd+Opt+Ctrl item edge double-click
-- # v1.6.3 Add/update edge mouse modifiers for new ripple options
-- # v1.6.2 Revert 1.6.1 changes, set SHIFT and CMD to "5 m" and "4 m," respectively
-- # v1.6.1 Changes item lower shift+click to "Add razor edit area to selection, including space between items" and command+click to "Add razor edit area to selection"
-- # v1.6 kills Trim Tool properly, switch to razor edits instead of razor+time selection, shift+drag on track adds razor area to selection
-- # v1.5 Many revisions to mouse modifiers for more features control
-- # v1.4 Revision, changed item left click to new companion script '_RS428db9286d6f978287e14df7cf9227628394585d' (Script: ReaTooled_Move Tool Left Click)
-- # v1.3 Revision, resulting in no change
-- # v1.2 Revert Track Left Drag to Marquee Select Items AND Time (instead of just marquee select)
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
    tools.tool_options("smart")
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
    [0]='62 m', [1]='64 m', [2]='64 m', [3]='66 m', [4]='48 m', [5]='12 m',
    [6]='0', [7]='0', [8]='28 m', [9]='20 m', [10]='31 m', [11]='-1',
    [12]='-1', [13]='11 m', [14]='68 m', [15]='69 m'
  },
  MM_CTX_ITEMLOWER = {
    [0]='13 m', [1]='58 m', [2]='51 m', [3]='9 m', [4]='2 m', [5]='59 m',
    [6]='39 m', [7]='61 m', [8]='32 m', [9]='70 m', [10]='12 m', [11]='59 m',
    [12]='36 m', [13]='55 m', [14]='68 m', [15]='7 m'
  },
  MM_CTX_ITEMEDGE = {
    [0]='1 m', [1]='9 m', [2]='35 m', [3]='5 m', [4]='2 m', [5]='10 m',
    [6]='36 m', [7]='40 m', [8]='27 m', [9]='-1', [10]='-1', [11]='-1',
    [12]='28 m', [13]='32 m', [14]='19 m', [15]='-1'
  },
  MM_CTX_TRACK = {
    [0]='25 m', [1]='27 m', [2]='1 m', [3]='2 m', [4]='22 m', [5]='-1',
    [6]='16 m', [7]='17 m', [8]='10 m', [9]='-1', [10]='-1', [11]='-1',
    [12]='-1', [13]='-1', [14]='18 m', [15]='23 m'    
  },
  MM_CTX_TRACK_CLK = {
    [0]='1 m', [1]='_RS4cd42631d7e27097addcb69ffcee753c0db8b856', [2]='2 m', [3]='6 m', [4]='8 m', [5]='-1',
    [6]='-1', [7]='-1', [8]='4 m', [9]='-1', [10]='-1', [11]='-1',
    [12]='-1', [13]='-1', [14]='-1', [15]='-1'
  },
  MM_CTX_ITEM_CLK = {
    [0]='_RSdda1871a056aceb420ea3e0c7f210ccc87e7c62b', [1]='_RS4cd42631d7e27097addcb69ffcee753c0db8b856', [2]='42577 c', [3]='40748 c', [4]='43179 c', [5]='43180 c',
    [6]='42575 c', [7]='40746 c', [8]='42391 c', [9]='18 m', [10]='15 m', [11]='24 m',
    [12]='-1', [13]='-1', [14]='-1', [15]='-1'
  },
  MM_CTX_ITEMLOWER_CLK = {
    [0]='_RS428db9286d6f978287e14df7cf9227628394585d', [1]='17 m', [2]='4 m',
    [3]='24 m', [4]='-1', [5]='-1', [6]='-1', [7]='-1', [8]='42391 c', [9]='18 m',
    [10]='24 m', [11]='-1', [12]='-1', [13]='-1', [14]='-1', [15]='-1'
  },
  MM_CTX_ITEM_DBLCLK = {
    [0]='42630 c', [1]='42409 c', [2]='42577 c', [3]='-1', [4]='41848 c', [5]='40653 c',
    [6]='-1', [7]='-1', [8]='7 m', [9]='_RS327ff00f699011e13052101611800ca4663627b2',
    [10]='-1', [11]='-1', [12]='-1', [13]='_468b46ab8e3d4145b3af6c337ef2ac96',
    [14]='-1', [15]='_047b1ae44c6a4c398916caefec363247'
  },
  MM_CTX_ITEMLOWER_DBLCLK = {
    [0]='6 m', [1]='5 m', [2]='-1', [3]='-1', [4]='41848 c', [5]='-1',
    [6]='-1', [7]='-1', [8]='7 m', [9]='_RS327ff00f699011e13052101611800ca4663627b2', [10]='-1', [11]='-1',
    [12]='-1', [13]='-1', [14]='_RSc420542ec64750db62f5b15acd998feac1ec6d1d',
    [15]='_2a3da20698f4486896f47d9c6f093caf'
  },
  -- Cmd+Opt+Ctrl double-click on an item edge pointed at a script that no longer exists
  MM_CTX_ITEMEDGE_DBLCLK = {
    [14]='-1'
  }
}

for context, mods in pairs(mouseMods) do
  setModifiers(context, mods)
end

----------------------------------------
-- Locking & Arrange Cleanup
----------------------------------------
reaper.Main_OnCommand(40570, 0) -- Disable locking
reaper.Main_OnCommand(40578, 0) -- Clear left/right locking
reaper.Main_OnCommand(40581, 0) -- Clear up/down locking
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
    tools.finish("smart")
  else
    reaper.ShowConsoleMsg("ReaTooled: tools library not loaded: " .. tostring(tools) .. "\n")
  end
end


