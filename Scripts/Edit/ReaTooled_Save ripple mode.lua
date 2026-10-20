--[[
-- @description ReaTooled - Save ripple mode
-- @version 1.0
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Saves the current ripple editing mode (off, per-track or all tracks)
    to a persistent ReaTooled ExtState, so "ReaTooled - Restore ripple mode"
    can put it back later. Made for use inside custom actions: it runs
    instantly and adds no undo point.
-- CHANGELOG
-- v1.0 Initial version
--]]

local RIPPLE_PER_TRACK = 40310   -- Options: Set ripple editing per-track
local RIPPLE_ALL       = 40311   -- Options: Set ripple editing all tracks

local mode = 0   -- 0 = off, 1 = per-track, 2 = all tracks
if reaper.GetToggleCommandState(RIPPLE_ALL) == 1 then
  mode = 2
elseif reaper.GetToggleCommandState(RIPPLE_PER_TRACK) == 1 then
  mode = 1
end

reaper.SetExtState("ReaTooled", "SavedRippleMode", tostring(mode), true)

reaper.defer(function() end)   -- no undo point
