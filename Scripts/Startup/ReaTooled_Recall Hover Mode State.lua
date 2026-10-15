--[[
-- @description ReaTooled - Hover Edit Mode Saved State
-- @version 1.0
-- @date 2024.01.18
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
    # Recalls Hover Mode State
--]]

local hover_mode_state = tonumber(reaper.GetExtState("ReaTooled", "HoverModeState"))

if hover_mode_state == 1 then
  reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS7cb08a92f7a211ce66734644b4fbe99a91bd42f5"), 0)  -- run ReaTooled Hover Edit Mode script
  else
end
