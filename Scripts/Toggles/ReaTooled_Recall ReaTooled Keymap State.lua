--[[
-- @description ReaTooled - Recall ReaTooled Keymap Saved State
-- @version 1.0
-- @date 2024.01.18
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
    # Recalls ReaTooled Shortcut State
--]]


local reatooled_keymap_state = tonumber(reaper.GetExtState("ReaTooled", "ReaTooledKeymapOn"))

if reatooled_keymap_state == 1 then
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS7e9fb26fe2faa9088b9d1aadabdbdfc97d417337"), 0)
  else
end
