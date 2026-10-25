-- @description ReaTooled - Razor Select Tool (Selector Tool)
-- @version 1.5
-- @date 2026.10.24
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # This script loads a set of mouse modifiers focusing on creating razor edit selection, similar to ProTools' "Selector Tool."
-- CHANGELOG
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
    ["_RSd77ea649952c67db183a19cece290cf3e1b3d49d"] = 0,
    ["_RSb08c9a159d1a7537eda8df72b777b1cc4c9422e8"] = 1,
    ["_RSc2c7d733888679038b4a4341074dc703d0f7f9c2"] = 0,
    ["_RS5e85a066efd01fde2482832bf4a3502dce0427b6"] = 0,
    ["_RS27973b4ea6ddfabb982b8206b117b31843c68991"] = 0,
    ["_RSb90cf42a9ad3d180fdab1c2fbe82e70a76347b1f"] = 0
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
killTrimTool()
updateToolbar()

