-- @description ReaTooled - Scrub Tool
-- @version 1.1
-- @date 2025.04.16
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- 
--   # This script loads ReaTooled's Scrub Tool
-- # v1.1 Kill Trim Tool

local CMD_ID_1 = reaper.NamedCommandLookup("_RS21aa0b14cf72a27be535d32efe0d05513523aec9")
local CMD_ID_2 = reaper.NamedCommandLookup("_RSd77ea649952c67db183a19cece290cf3e1b3d49d")
local CMD_ID_3 = reaper.NamedCommandLookup("_RSb08c9a159d1a7537eda8df72b777b1cc4c9422e8")
local CMD_ID_4 = reaper.NamedCommandLookup("_RSc2c7d733888679038b4a4341074dc703d0f7f9c2")
local CMD_ID_7 = reaper.NamedCommandLookup("_RS5e85a066efd01fde2482832bf4a3502dce0427b6")

was_set=-1

reaper.Main_OnCommand(42632, 0)


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


-- Set toolbar button states for additional scripts/buttons
reaper.SetToggleCommandState(0, CMD_ID_1, 0) -- Turn off button 1
reaper.SetToggleCommandState(0, CMD_ID_2, 0) -- Turn off button 2
reaper.SetToggleCommandState(0, CMD_ID_3, 0) -- Turn off button 3
reaper.SetToggleCommandState(0, CMD_ID_4, 0) -- Turn off button 4
reaper.SetToggleCommandState(0, CMD_ID_7, 0) -- Turn off button 7
reaper.SetToggleCommandState(0, reaper.NamedCommandLookup("_RS27973b4ea6ddfabb982b8206b117b31843c68991"), 1) -- scrub tool
reaper.SetToggleCommandState(0, reaper.NamedCommandLookup("_RSb90cf42a9ad3d180fdab1c2fbe82e70a76347b1f"), 0) -- TCE tool
reaper.RefreshToolbar(0)
