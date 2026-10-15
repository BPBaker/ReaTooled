-- @description ReaTooled Toggle Link Track and Item and Razor Selection
-- @date 2024.03.14
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @version 1.0
-- @about
--   
-------------------------------------------------------------------------------------------
local reaper = reaper

local mainScriptCmdID = reaper.NamedCommandLookup("_RS0a8653eb2474467f0c9dd9684bd8b6d5ba70ae97")
local toggleScriptCmdID = reaper.NamedCommandLookup("_RSf28451a9bd28e7b3d270c4e5ce58052377a5e3df")

local extstate = reaper.GetExtState("ReaTooled", "LinkTrackItemState")
if not extstate or extstate == "" then
  extstate = "0"  -- Default to off if no extstate is found
end

local function RunMainScript()
  reaper.Main_OnCommandEx(mainScriptCmdID, 0, 0)
end

local function KillMainScript()
  reaper.Main_OnCommandEx(mainScriptCmdID, 0, 1)
end

if extstate == "0" then 
  -- If currently off, turn on and run the main script
  reaper.SetExtState("ReaTooled", "LinkTrackItemState", "1", true)
  reaper.SetToggleCommandState(0, toggleScriptCmdID, 1) -- Set button state on
  reaper.RefreshToolbar2(0, toggleScriptCmdID)
  RunMainScript()
else
  -- If currently on, turn off and kill the main script
  reaper.SetExtState("ReaTooled", "LinkTrackItemState", "0", true)
  reaper.SetToggleCommandState(0, toggleScriptCmdID, 0) -- Set button state off
  reaper.RefreshToolbar2(0, toggleScriptCmdID)
  KillMainScript()
end

-- No undo point
function NoUndoPoint() end reaper.defer(NoUndoPoint)

