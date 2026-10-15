-- @description ReaTooled_Zoom Out Horizontally to Entire Project
-- @version 1.0
-- @date 2025.04.15
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- Horizontally zooms out to fit the entire project using REAPER's native action. Vertical zoom is preserved.
-- CHANGELOG
--   + Simple version using Action ID 40031

reaper.Undo_BeginBlock()
reaper.Main_OnCommand(40295, 0) -- View: Zoom out project
reaper.Undo_EndBlock("ReaTooled: Zoom Horizontally to Entire Project", -1)

