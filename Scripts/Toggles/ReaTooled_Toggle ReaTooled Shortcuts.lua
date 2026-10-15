--[[
-- @description ReaTooled - Toggle ReaTooled Shortcuts
-- @version 1.0
-- @date 2024.01.18
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
    Toggles between the ReaTooled Keymap (alt 16) and Main Keymap
--]]


local cmd_id = ({reaper.get_action_context()})[4] -- gets command ID for this script
local toggleState = reaper.GetToggleCommandStateEx(0,cmd_id)

if toggleState ~= 1 then
            toggleState = 1
            reaper.SetExtState("ReaTooled", "ReaTooledKeymapOn", tonumber(1), true)
            reaper.Main_OnCommand(24818, 0)  -- Toggle ReaTooled Keymap Alt 16
            else
            toggleState = 0
            reaper.Main_OnCommand(24800, 0)  -- Clear Keymap Override
            reaper.SetExtState("ReaTooled", "ReaTooledKeymapOn", tonumber(0), true)
    end

reaper.SetToggleCommandState( 0, cmd_id, toggleState)
reaper.RefreshToolbar2(0, cmd_id)


reaper.defer(function() end) --this prevents undo
