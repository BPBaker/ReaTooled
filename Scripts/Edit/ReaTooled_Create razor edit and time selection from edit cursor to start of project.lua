-- @description ReaTooled - Create razor edit and time selection from the edit cursor to the start of project
-- @version 1.0
-- @date 2025.04.15
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- CHANGELOG

-- Get edit cursor position
local edit_cursor_pos = reaper.GetCursorPosition()

-- Set the time selection from 0 to the edit cursor
reaper.GetSet_LoopTimeRange(true, false, 0, edit_cursor_pos, false)

-- Start undo block
reaper.Undo_BeginBlock()

-- Count selected tracks
local num_selected_tracks = reaper.CountSelectedTracks(0)

-- Loop through only selected tracks
for i = 0, num_selected_tracks - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    if track then
        -- Format: [start] [end] "" (empty GUID for all lanes)
        local razor_str = string.format("0 %f \"\"", edit_cursor_pos)
        reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", razor_str, true)
    end
end

-- End undo block
reaper.Undo_EndBlock("Create razor edits and time selection from project start to edit cursor", -1)

-- Update arrange
reaper.UpdateArrange()

