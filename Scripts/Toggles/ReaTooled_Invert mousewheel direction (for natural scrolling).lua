-- @description Toggle ReaTooled Mousewheel Inversion
-- @version 1.1
-- @changelog
--   v1.1 Message uses the same words as "Scrolling and zooming" (Standard / Reversed)
--   v1.0 Initial version
-- @author Wizard

local section, key = "ReaTooled", "WheelInvert"
local val = tonumber(reaper.GetExtState(section, key)) or 0
local new_val = (val == 1) and 0 or 1
reaper.SetExtState(section, key, tostring(new_val), true)

reaper.ShowMessageBox("ReaTooled wheel scripts are now " .. (new_val == 1 and "Reversed" or "Standard") ..
  ".\n\nTo see what that does, run \"ReaTooled_Scrolling settings\".", "ReaTooled", 0)
