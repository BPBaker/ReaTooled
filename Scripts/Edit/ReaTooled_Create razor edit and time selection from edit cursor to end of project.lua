-- @description ReaTooled - Create razor edit and time selection from the edit cursor to the end of project
-- @version 1.0
-- @date 2025.04.15
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- CHANGELOG

-- Get edit cursor and project end
local edit_cursor_pos = reaper.GetCursorPosition()
local project_end = reaper.GetProjectLength(0)

-- Set time selection
reaper.GetSet_LoopTimeRange(true, false, edit_cursor_pos, project_end, false)

-- Start undo block
reaper.Undo_BeginBlock()

-- Count selected tracks
local num_selected_tracks = reaper.CountSelectedTracks(0)

-- Loop through selected tracks
for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
        local razor_str = string.format("%f %f \"\"", edit_cursor_pos, project_end)
        reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", razor_str, true)
    end
end

-- End undo block
reaper.Undo_EndBlock("Create razor edits and time selection from edit cursor to end of project", -1)

-- Update arrange
reaper.UpdateArrange()

