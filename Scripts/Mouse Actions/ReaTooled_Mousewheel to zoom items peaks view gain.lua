-- @description Adjust Peaks View Gain by Mousewheel (ReaTooled Compatible)
-- @version 1.1
-- @author Brendan
-- @link https://brendanpatrickbaker.com/reatooled/
-- @changelog
--   + v1.1 Added ReaTooled mousewheel inversion support
--   + Preserved looped gain speed control
-- @about
--   Adjusts the visual peak gain of media items using the mousewheel.
--   Uses REAPER native actions 40155 / 40156.
--   Scroll direction is invertible via ReaTooled inversion toggle.

-- ========== CONFIG ==========
local speed = 3 -- Number of repeat actions per scroll step

-- ========== NORMALIZE SCROLL DELTA ==========
local _, _, _, _, _, _, val = reaper.get_action_context()
if not val or val == 0 then return end

local invert = tonumber(reaper.GetExtState("ReaTooled", "WheelInvert")) or 0
if invert == 1 then val = -val end

-- ========== MAIN FUNCTION ==========
reaper.PreventUIRefresh(1)

local command = (val > 0) and 40156 or 40155 -- Increase / Decrease peaks view gain

for i = 1, speed + 1 do
  reaper.Main_OnCommand(command, 0)
end

reaper.PreventUIRefresh(-1)
