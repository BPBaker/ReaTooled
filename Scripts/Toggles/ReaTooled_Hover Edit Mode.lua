--[[
-- @description ReaTooled - Hover Edit Mode
-- @version 1.0
-- @date 2024.01.18
-- @author Brendan Baker adapted from TJF/Tim Farrell (http://github.com/sonictim/TJF-Scripts/)
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
  # Will Turn "Hover mode" on or off
  Will create a toggle stage for this function, that my trim scripts will read.
--]]


local cmd_id = ({reaper.get_action_context()})[4] -- gets command ID for this script
local state = reaper.GetToggleCommandStateEx(0,cmd_id)

    if state ~= 1 then
            state = 1
            reaper.SetExtState("ReaTooled", "HoverModeState", tonumber(1), true)
            else
            state = 0
            reaper.SetExtState("ReaTooled", "HoverModeState", tonumber(0), true)
    end

reaper.SetToggleCommandState( 0, cmd_id, state)
reaper.RefreshToolbar2(0, cmd_id)


reaper.defer(function() end) --this prevents undo
