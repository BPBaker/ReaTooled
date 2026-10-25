-- @description ReaTooled - Default Multi Tool (Smart)
-- @version 1.6.4
-- @date 2026.10.24
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # This script loads ReaTooled's default set of mouse modifiers, which gives similar functionality to ProTools' "Smart Tool." 
-- CHANGELOG
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
-- Utility Functions
----------------------------------------
local function setModifiers(context, modifiers)
  for index, value in pairs(modifiers) do
    reaper.SetMouseModifier(context, index, value)
  end
end

-- === Hardened Trim Tool killer (matches worker's keys/heartbeat) ===
local RT_NS        = "ReaTooled"
local RT_RUN_KEY   = "TrimToolWorkerRunning"
local RT_KILL_KEY  = "KillTrimTool"
local RT_HEARTBEAT = "TrimToolHeartbeat"
local RT_STALE_SEC = 0.8   -- must match the worker script

local function _trimToolAlive()
  if not reaper.HasExtState(RT_NS, RT_RUN_KEY) then return false end
  local hb = tonumber(reaper.GetExtState(RT_NS, RT_HEARTBEAT) or "") or 0
  if hb == 0 then return true end  -- unknown, assume alive to be safe
  local age = reaper.time_precise() - hb
  return age <= RT_STALE_SEC
end

local function killTrimTool()
  -- Persist the kill so the worker sees it even if we ran first or block briefly
  reaper.SetExtState(RT_NS, RT_KILL_KEY, "1", true)

  -- Best-effort immediate cursor neutralization (visual fix while worker exits)
  if reaper.JS_Mouse_LoadCursor and reaper.JS_Mouse_SetCursor then
    local arrow = reaper.JS_Mouse_LoadCursor(32512)
    if arrow then pcall(reaper.JS_Mouse_SetCursor, arrow) end
  end

  -- Do NOT busy-wait here: it blocks the worker from processing the kill.
  -- If a stale worker left RUN_KEY behind, opportunistically clean it up
  -- when heartbeat is older than RT_STALE_SEC.
  local hb = tonumber(reaper.GetExtState(RT_NS, RT_HEARTBEAT) or "") or 0
  if hb ~= 0 and (reaper.time_precise() - hb) > RT_STALE_SEC then
    pcall(reaper.DeleteExtState, RT_NS, RT_RUN_KEY, false)
    pcall(reaper.DeleteExtState, RT_NS, RT_RUN_KEY, true)
  end
end

local function updateToolbar()
  local toggleCommands = {
    ["_RS21aa0b14cf72a27be535d32efe0d05513523aec9"] = 0,
    ["_RSd77ea649952c67db183a19cece290cf3e1b3d49d"] = 1,
    ["_RSb08c9a159d1a7537eda8df72b777b1cc4c9422e8"] = 1,
    ["_RSc2c7d733888679038b4a4341074dc703d0f7f9c2"] = 1,
    ["_RS5e85a066efd01fde2482832bf4a3502dce0427b6"] = 1,
    ["_RS27973b4ea6ddfabb982b8206b117b31843c68991"] = 0, -- scrub tool
    ["_RSb90cf42a9ad3d180fdab1c2fbe82e70a76347b1f"] = 0, -- TCE tool
  }

  for command_id, state in pairs(toggleCommands) do
    local cmd = reaper.NamedCommandLookup(command_id)
    if cmd ~= 0 then
      reaper.SetToggleCommandState(0, cmd, state)
    end
  end
  reaper.RefreshToolbar(0)
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
killTrimTool()
updateToolbar()

