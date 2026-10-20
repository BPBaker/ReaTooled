--[[
-- @description ReaTooled - Restore ripple mode
-- @version 1.0
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Restores the ripple editing mode saved by "ReaTooled - Save ripple mode".
    Does nothing if no mode has been saved yet. Made for use inside custom
    actions: it runs instantly and adds no undo point.
-- CHANGELOG
-- v1.0 Initial version
--]]

local COMMANDS = {
  [0] = 40309,   -- Options: Set ripple editing off
  [1] = 40310,   -- Options: Set ripple editing per-track
  [2] = 40311,   -- Options: Set ripple editing all tracks
}

local mode = tonumber(reaper.GetExtState("ReaTooled", "SavedRippleMode"))
if mode and COMMANDS[mode] then
  reaper.Main_OnCommand(COMMANDS[mode], 0)
end

reaper.defer(function() end)   -- no undo point
