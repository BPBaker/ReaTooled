--[[
-- @description ReaTooled - Toggle Tab to Transient
-- @version 1.0
@date 2024 03 12
-- @author Brendan Baker (modified from TJF/Tim Farrell)
-- @link http://brendanpatrickbaker.com/reatooled/
@about
  # Mimics Protools tab function toggle 
  Will create a toggle stage for this function, that will alter the behavior of the tab function script.
  + Adds ReaTooled ExtState for later recall
--]]


local cmd_id = ({reaper.get_action_context()})[4] -- gets command ID for this script
local state = reaper.GetToggleCommandStateEx(0,cmd_id)

    if state ~= 1 then
            state = 1
            reaper.SetExtState("ReaTooled", "TabToTransientState", tonumber(1), true)            
            else
            state = 0
            reaper.SetExtState("ReaTooled", "TabToTransientState", tonumber(0), true)

    end

reaper.SetToggleCommandState( 0, cmd_id, state)
reaper.RefreshToolbar2(0, cmd_id)


reaper.defer(function() end) --this prevents undo
