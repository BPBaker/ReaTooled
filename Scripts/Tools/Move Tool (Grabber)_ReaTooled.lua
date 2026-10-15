-- @description ReaTooled - Move Tool
-- @version 1.5
-- @date 2025.04.17
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # This script loads a set of mouse modifiers focusing on moving items, which gives similar functionality to ProTools' "Grabber Tool."
-- CHANGELOG
-- # v1.5 For click, set SHIFT and CMD to "5 m" and "4 m," respectively
-- # v1.4 Kill Trim Tool, clean up script
-- # v1.3 Many revisions to mouse modifiers for more features control
-- # v1.2 Changed item left click to new companion script '_RS428db9286d6f978287e14df7cf9227628394585d' (Script: ReaTooled_Move Tool Left Click)
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
    ["_RSb08c9a159d1a7537eda8df72b777b1cc4c9422e8"] = 0,
    ["_RSc2c7d733888679038b4a4341074dc703d0f7f9c2"] = 1,
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
    [0]='9 m', [1]='13 m', [2]='1 m', [3]='2 m', [4]='22 m', [5]='-1',
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
killTrimTool()
updateToolbar()

-- Optional: Uncomment to enable continuous toolbar state detection
-- reaper.defer(UpdateState)
