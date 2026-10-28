-- @description ReaTooled - Razor Select Tool (Selector Tool)
-- @version 1.7
-- @date 2026.10.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # This script loads a set of mouse modifiers focusing on creating razor edit selection, similar to ProTools' "Selector Tool."
-- CHANGELOG
-- # v1.7 Stopping the Trim Tool and the toolbar buttons are shared with the other tools (ReaTooled_Tools lib.lua), which also knows the new Pencil Tool
-- # v1.6 Puts right-drag back to marquee when "Toggle swap left and right drag" had changed it
-- # v1.5 Shift+Ctrl double-click on an item (top and bottom half) runs ReaTooled_Clear take
--        envelopes and Reset Volume to 0db.lua (the old custom action no longer exists)
-- # v1.4 Cleaned structure for maintainability, kept all original mouse modifier behaviors
-- # v1.3 Kills Trim Tool Properly, shift+drag on track adds razor area to selection, switch to razor selection only
-- # v1.2 Many revisions to mouse modifiers for more features control
-- # v1.1 Multiple tweaks to mouse modifier to more closely align with PT behavior

----------------------------------------
-- Utility Functions
----------------------------------------
local function setModifiers(context, modifiers)
  for index, value in pairs(modifiers) do
    reaper.SetMouseModifier(context, index, value)
  end
end


----------------------------------------
-- Mouse Modifier Definitions
----------------------------------------
local mouseMods = {
  MM_CTX_ITEM = {
    [0]='62 m', [1]='64 m', [2]='64 m', [3]='66 m', [4]='48 m', [5]='12 m',
    [6]='0', [7]='0', [8]='28 m', [9]='20 m', [10]='31 m', [11]='-1',
    [12]='-1', [13]='11 m', [14]='68 m', [15]='69 m'
  },
  MM_CTX_ITEMLOWER = {
    [0]='62 m', [1]='64 m', [2]='64 m', [3]='66 m', [4]='48 m', [5]='12 m',
    [6]='0', [7]='0', [8]='28 m', [9]='20 m', [10]='31 m', [11]='-1',
    [12]='-1', [13]='11 m', [14]='68 m', [15]='69 m'
  },
  MM_CTX_TRACK = {
    [0]='25 m', [1]='27 m', [2]='27 m', [3]='0',    [4]='22 m', [5]='-1',
    [6]='0',    [7]='0',    [8]='10 m', [9]='-1',   [10]='-1', [11]='-1',
    [12]='-1', [13]='-1', [14]='-1', [15]='-1'
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
    [0]='_RSdda1871a056aceb420ea3e0c7f210ccc87e7c62b', [1]='_RS4cd42631d7e27097addcb69ffcee753c0db8b856', [2]='42577 c', [3]='40748 c', [4]='43179 c', [5]='43180 c',
    [6]='42575 c', [7]='40746 c', [8]='42391 c', [9]='18 m', [10]='15 m', [11]='24 m',
    [12]='-1', [13]='-1', [14]='-1', [15]='-1'
  },
  MM_CTX_ITEM_DBLCLK = {
    [0]='42630 c', [1]='42409 c', [2]='42577 c', [3]='-1', [4]='41848 c', [5]='40653 c',
    [6]='-1', [7]='-1', [8]='7 m', [9]='_RS327ff00f699011e13052101611800ca4663627b2',
    [10]='-1', [11]='-1', [12]='-1', [13]='_468b46ab8e3d4145b3af6c337ef2ac96',
    [14]='-1', [15]='_047b1ae44c6a4c398916caefec363247'
  },
  MM_CTX_ITEMLOWER_DBLCLK = {
    [0]='42630 c', [1]='42409 c', [2]='42577 c', [3]='-1', [4]='41848 c', [5]='40653 c',
    [6]='-1', [7]='-1', [8]='7 m', [9]='_RS327ff00f699011e13052101611800ca4663627b2',
    [10]='-1', [11]='-1', [12]='-1', [13]='_468b46ab8e3d4145b3af6c337ef2ac96',
    [14]='-1', [15]='_047b1ae44c6a4c398916caefec363247'
  }
}

for context, mods in pairs(mouseMods) do
  setModifiers(context, mods)
end

----------------------------------------
-- Locking Settings
----------------------------------------
reaper.Main_OnCommand(40569,0) -- Enable locking
reaper.Main_OnCommand(40595,0) -- Lock item edges
reaper.Main_OnCommand(40598,0) -- Lock item fades
--reaper.Main_OnCommand(40599,0) -- Clear item fades lock
reaper.Main_OnCommand(41852,0) -- Lock item stretch markers
reaper.Main_OnCommand(41849,0) -- Lock item envelope
reaper.Main_OnCommand(40572,0) -- Time selection unlocked
reaper.Main_OnCommand(42621,0) -- Clear arrange override mode

----------------------------------------
-- Execute Final Setup
----------------------------------------

----------------------------------------
-- Finish: Trim Tool off, drag swap, Pencil cleanup, toolbar buttons
-- (shared by every tool: ReaTooled_Tools lib.lua)
----------------------------------------
do
  local dir = ({reaper.get_action_context()})[2]:match("^(.*[/\\])") or ""
  local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
  if ok and type(tools) == "table" then
    tools.finish("selector")
  else
    reaper.ShowConsoleMsg("ReaTooled: tools library not loaded: " .. tostring(tools) .. "\n")
  end
end


