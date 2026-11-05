-- @description ReaTooled - Nudge left by next larger setting
-- @version 1.0
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Like Smart Nudge Left, but by the next larger of the Grid and Nudge Settings presets
--   than the current nudge value (in the same unit): with 10 ms set, it nudges by 100 ms.
--   At the largest preset (or in grid units, which have none) it nudges by twice the
--   current value. The nudge setting itself doesn't change.
-- @changelog
--   v1.0 First version
DIRECTION = -1
NUDGE_LARGER = true
dofile(reaper.GetResourcePath() .. "/Scripts/ReaTooled/Edit/ReaTooled_SmartNudge_Core.lua")
