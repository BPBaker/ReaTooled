--[[
@description ReaTooled - Toggle: Ripple All affects Regions/Markers
@version 1.2
@date 2025-10-31
@author Brendan Baker
@link http://brendanpatrickbaker.com/reatooled/
@about
  Toggles REAPER's native option:
  "Options: Ripple edit all affects regions/markers" (command ID 43690)
  Replaces the older marker-lock workflow. Stores state in ExtState for recall.
  CHANGELOG
  v1.2  Replace marker-lock actions with native toggle 43690; robust toolbar sync
]]

local reaper = reaper

-- Get this script's command ID for proper toolbar toggle syncing
local _, _, sectionID, scriptCmdID = reaper.get_action_context()
sectionID = sectionID or 0

local CMD_RIPPLE_ALL_AFFECTS_RM = 43690 -- Options: Ripple edit all affects regions/markers

-- Validate command availability (older REAPER versions safeguard)
local cur_state = reaper.GetToggleCommandStateEx(sectionID, CMD_RIPPLE_ALL_AFFECTS_RM)
if cur_state == -1 then
  reaper.MB(
    "Command 43690 not found.\nUpdate REAPER to a version that includes\n'Options: Ripple edit all affects regions/markers'.",
    "ReaTooled", 0)
  return
end

-- Toggle the native option by executing it once
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
reaper.Main_OnCommand(CMD_RIPPLE_ALL_AFFECTS_RM, 0)
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("ReaTooled: Toggle Ripple All affects Regions/Markers", -1)

-- Read post-toggle state (0/1)
local new_state = reaper.GetToggleCommandStateEx(sectionID, CMD_RIPPLE_ALL_AFFECTS_RM)
if new_state < 0 then new_state = 0 end

-- Persist for recall (new key) + keep your old key for compatibility
reaper.SetExtState("ReaTooled", "RippleAllAffectsRegionsMarkers", new_state, true)
reaper.SetExtState("ReaTooled", "MarkersLockedState",            new_state, true) -- legacy key

-- Reflect in this script's toolbar button
if scriptCmdID and scriptCmdID > 0 then
  reaper.SetToggleCommandState(sectionID, scriptCmdID, new_state)
  reaper.RefreshToolbar2(sectionID, scriptCmdID)
end

-- No undo point on subsequent defers
local function NoUndoPoint() end
reaper.defer(NoUndoPoint)
