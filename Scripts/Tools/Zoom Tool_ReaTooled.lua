-- @description ReaTooled - Zoom Tool (Zoomer Tool)
-- @version 1.5
-- @date 2026.10.15
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # This script loads a set of mouse modifiers focusing on zooming to a selection, which gives similar functionality to ProTools' "Zoomer Tool."
-- CHANGELOG
-- # v1.5 Click / Option-click now use ReaTooled's own zoom scripts (found by path) instead of
--        Archie's View scripts, which were no longer installed. Removed a dead toolbar ID.
-- # v1.4 Refactored structure and cleaned code, preserved logic and behavior
-- # v1.3 Kill Trim Tool
-- # v1.2 Added Opt+Click to Zoom Out, Changed Zoom In/out Archie_View scripts for better performance
-- # v1.1 Multiple tweaks to mouse modifier to more closely align with PT behavior

-- === Find ReaTooled scripts by path ===
-- Returns the "_RS..." command ID string for a script in Scripts/ReaTooled/,
-- or "-1" (REAPER's default action) if the file is missing.
local function script_action(rel)
  local path = reaper.GetResourcePath():gsub("\\", "/") .. "/Scripts/ReaTooled/" .. rel
  if not reaper.file_exists(path) then return "-1" end
  local id = reaper.AddRemoveReaScript(true, 0, path, true)
  if not id or id == 0 then return "-1" end
  return "_" .. reaper.ReverseNamedCommandLookup(id)
end

local ZOOM_IN  = script_action("Zoom/ReaTooled_Zoom Tool - Zoom in.lua")   -- click
local ZOOM_OUT = script_action("Zoom/ReaTooled_Zoom Tool - Zoom out.lua")  -- Option/Alt-click

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

local function setCommandToggleStates(activeIndex)
  local ids = {
    "_RS21aa0b14cf72a27be535d32efe0d05513523aec9", -- Zoom Tool
    "_RSd77ea649952c67db183a19cece290cf3e1b3d49d", -- Trim Tool
    "_RSb08c9a159d1a7537eda8df72b777b1cc4c9422e8", -- Razor Select Tool (Selector)
    "_RSc2c7d733888679038b4a4341074dc703d0f7f9c2", -- Move Tool (Grabber)
    "_RS5e85a066efd01fde2482832bf4a3502dce0427b6", -- Default Multi Tool (Smart)
    "_RS27973b4ea6ddfabb982b8206b117b31843c68991", -- Scrub Tool
  }
  for i, id in ipairs(ids) do
    local cmd = reaper.NamedCommandLookup(id)
    reaper.SetToggleCommandState(0, cmd, i == activeIndex and 1 or 0)
  end
  reaper.RefreshToolbar(0)
end

local function applyMouseModifiers()
  local modifiers = {
    -- context, modifiers
    { 'MM_CTX_ITEM',         { [0]='48 m', [1]='48 m', [2]='48 m', [3]='48 m', [4]='0 m', [5]='48 m', [6]='48 m', [7]='48 m', [8]='48 m', [9]='48 m', [10]='48 m', [11]='48 m', [12]='48 m', [13]='48 m', [14]='48 m', [15]='48 m' } },
    { 'MM_CTX_ITEMLOWER',    { [0]='48 m', [1]='48 m', [2]='48 m', [3]='48 m', [4]='-1',  [5]='48 m', [6]='48 m', [7]='48 m', [8]='48 m', [9]='48 m', [10]='48 m', [11]='48 m', [12]='48 m', [13]='48 m', [14]='48 m', [15]='48 m' } },
    { 'MM_CTX_ITEMEDGE',     { [0]='0',    [1]='0',    [2]='0',    [3]='0',    [4]='10 m',[5]='12 m',[6]='6 m', [7]='8 m', [8]='-1',   [9]='-1',   [10]='-1',   [11]='-1',   [12]='6 m', [13]='-1',   [14]='19 m',[15]='-1'    } },
    { 'MM_CTX_TRACK',        { [0]='22 m', [1]='22 m', [2]='22 m', [3]='22 m', [4]='-1',   [5]='-1',   [6]='0',  [7]='0',  [8]='0',   [9]='-1',   [10]='-1',   [11]='-1',   [12]='-1',  [13]='-1',   [14]='-1',  [15]='-1'    } },
    { 'MM_CTX_TRACK_CLK',    { [0]=ZOOM_IN, [1]='0', [2]='0', [3]='0', [4]=ZOOM_OUT, [5]='-1', [6]='0', [7]='-1', [8]='-1', [9]='-1', [10]='-1', [11]='-1', [12]='-1', [13]='-1', [14]='-1', [15]='-1' } },
    { 'MM_CTX_ITEM_CLK',     { [0]=ZOOM_IN, [1]='-1', [2]='-1', [3]='-1', [4]=ZOOM_OUT, [5]='-1', [6]='-1', [7]='-1', [8]='-1', [9]='-1', [10]='-1', [11]='-1', [12]='-1', [13]='-1', [14]='-1', [15]='-1' } },
    { 'MM_CTX_ITEMLOWER_CLK',{ [0]=ZOOM_IN, [1]='-1', [2]='-1', [3]='-1', [4]=ZOOM_OUT, [5]='-1', [6]='-1', [7]='-1', [8]='-1', [9]='-1', [10]='-1', [11]='-1', [12]='-1', [13]='-1', [14]='-1', [15]='-1' } },
    { 'MM_CTX_ITEM_DBLCLK',  { [0]='0', [1]='-1', [2]='-1', [3]='-1', [4]='40295 c', [5]='-1', [6]='-1', [7]='-1', [8]='-1', [9]='-1', [10]='-1', [11]='-1', [12]='-1', [13]='-1', [14]='-1', [15]='-1' } },
    { 'MM_CTX_ITEMLOWER_DBLCLK',{ [0]='0', [1]='-1', [2]='-1', [3]='-1', [4]='40295 c', [5]='-1', [6]='-1', [7]='-1', [8]='-1', [9]='-1', [10]='-1', [11]='-1', [12]='-1', [13]='-1', [14]='-1', [15]='-1' } },
  }

  for _, entry in ipairs(modifiers) do
    local context, mods = entry[1], entry[2]
    for i = 0, 15 do
      local val = mods[i]
      if val then
        reaper.SetMouseModifier(context, i, val)
      end
    end
  end
end

-- Apply all settings
applyMouseModifiers()

-- Locking and cleanup
reaper.Main_OnCommand(40569, 0)
reaper.Main_OnCommand(40595, 0)
reaper.Main_OnCommand(40598, 0)
reaper.Main_OnCommand(41852, 0)
reaper.Main_OnCommand(41849, 0)
reaper.Main_OnCommand(40572, 0)
reaper.Main_OnCommand(42621, 0)

-- Kill any active Trim Tool
killTrimTool()

-- Activate the Zoom Tool button in the toolbar
setCommandToggleStates(1)
