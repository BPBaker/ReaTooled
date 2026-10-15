-- @description Zoom Horizontally by Mousewheel (ReaTooled-Compatible)
-- @version 1.2
-- @author Brendan
-- @link https://brendanpatrickbaker.com/reatooled/
-- @changelog
--   + v1.2 Switched to Command ID 1012/1011 for proper zoom control
--   + Fully working with ReaTooled inversion toggle
-- @about
--   Zooms horizontally using the mousewheel.
--   Honors ReaTooled scroll inversion setting via ExtState.

-- ========== CONFIG ==========
local speed = 1 -- number of zoom steps per scroll

-- ========== SCROLL INPUT ==========
local _, _, _, _, _, _, val = reaper.get_action_context()
if not val or val == 0 then return end

-- Apply ReaTooled inversion
local invert = tonumber(reaper.GetExtState("ReaTooled", "WheelInvert")) or 0
if invert == 1 then val = -val end

-- ========== EXECUTE ZOOM ==========
local cmd = (val > 0) and 1012 or 1011 -- 1012 = Zoom in, 1011 = Zoom out

for i = 1, speed do
  reaper.Main_OnCommand(cmd, 0)
end
