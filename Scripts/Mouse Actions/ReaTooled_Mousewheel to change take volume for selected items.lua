-- @description @description Adjust Take Volume by Mousewheel
-- @version 1.1
-- @date 2025.06.03
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- Adjusts selected item take volume via mousewheel, in .5db increments 
-- CHANGELOG
--   + v1.1 Made mousewheel direction invertable via Script: ReaTooled_Invert mousewheel direction (for natural scrolling).lua

local speed = 0 -- how many times to nudge per scroll
local _, _, _, _, _, _, val = reaper.get_action_context()

-- Get inversion flag from ExtState
local invert = tonumber(reaper.GetExtState("ReaTooled", "WheelInvert")) or 0
if invert == 1 then val = -val end

-- SWS/Xenakios commands
local nudge_up = reaper.NamedCommandLookup("_XENAKIOS_NUDGETAKEVOLUP")
local nudge_down = reaper.NamedCommandLookup("_XENAKIOS_NUDGETAKEVOLDOWN")

local command = (val > 0) and nudge_up or nudge_down
for i = 1, speed + 1 do
  reaper.Main_OnCommand(command, 0)
end
