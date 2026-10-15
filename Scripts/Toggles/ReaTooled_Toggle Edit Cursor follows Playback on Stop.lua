-- @description ReaTooled Toggle Edit Cursor follows Playback on Stop
-- @date 2024.03.12
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @version 1.1
-- @about
--   # CREDITS: Copied from amagalma, toggles Edit Cursor follows Playback on Stop from Toggles behavior of Play-Stop actions between amagalma's custom or Reaper's default
--
--   - To be used in conjunction with "ReaTooled_Play-Stop (with memory, edit-play toggles, and no undo).lua"
-- CHANGELOG
-- v1.1 - + Adds ReaTooled ExtState for later recall
-------------------------------------------------------------------------------------------

local reaper = reaper

local cmdID = reaper.NamedCommandLookup("_RSe16d9e990f3d5fcec42256f63e00086d75b71288")
local script_state = reaper.GetToggleCommandStateEx(0,cmdID)

if script_state < 1 then 
  script_state = 1
  reaper.SetExtState("ReaTooled", "EditFollowsPlaybackState", tonumber(1), true)            
  
else
  script_state = 0
  reaper.SetExtState("ReaTooled", "EditFollowsPlaybackState", tonumber(0), true)
  
end

reaper.SetToggleCommandState(0,cmdID, script_state)
reaper.RefreshToolbar2(0,cmdID)

-- No undo point
function NoUndoPoint() end reaper.defer(NoUndoPoint)
