-- @description ReaTooled_Convert Time or Loop Selection to Razor Area on All Tracks (for mouse modifier)
-- @version 1.0
-- @date 2025.04.15
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- Waits for REAPER to apply a time or loop selection (useful when triggered by mouse modifiers), then creates razor edit areas across all tracks and matches time selection.
-- CHANGELOG
--   + Initial release

function try_apply_razor_edit()
    -- Check for time selection
    local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

    -- If time selection is zero-length, check loop selection
    if math.abs(ts_end - ts_start) < 0.000001 then
        ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
    end

    -- Still no valid selection? Wait for the mouse action to complete
    if math.abs(ts_end - ts_start) < 0.000001 then
        reaper.defer(try_apply_razor_edit)
        return
    end

    -- Apply razor edit + time selection
    reaper.Undo_BeginBlock()

    -- Set time selection (explicitly)
    reaper.GetSet_LoopTimeRange(true, false, ts_start, ts_end, false)

    local num_tracks = reaper.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local razor_str = string.format("%f %f \"\"", ts_start, ts_end)
            reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", razor_str, true)
        end
    end

    reaper.Undo_EndBlock("ReaTooled: Time Selection to Razor Area (All Tracks)", -1)
    reaper.UpdateArrange()
end

-- Start the loop
try_apply_razor_edit()

