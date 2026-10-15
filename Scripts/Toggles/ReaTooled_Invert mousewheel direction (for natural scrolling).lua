-- @description Toggle ReaTooled Mousewheel Inversion
-- @version 1.0
-- @author Wizard

local section, key = "ReaTooled", "WheelInvert"
local val = tonumber(reaper.GetExtState(section, key)) or 0
local new_val = (val == 1) and 0 or 1
reaper.SetExtState(section, key, tostring(new_val), true)

reaper.ShowMessageBox("Mousewheel inversion is now " .. (new_val == 1 and "ON" or "OFF"), "ReaTooled", 0)
