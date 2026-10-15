-- @description ReaTooled_Copy Razor (Union) or Time Selection to All Tracks + Set Time Selection
-- @version 1.6
-- @date 2024.04.16
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- Creates a unified razor area from all razor edits (min start to max end), applies it to all tracks, and sets matching time selection.
-- If no razor exists, falls back to time selection. Exits silently if neither is set.
-- CHANGELOG
--   + Union of all razor areas across all tracks

-- Get union of all razor ranges across all tracks
local function get_razor_union_range()
    local min_start = math.huge
    local max_end = -math.huge
    local found = false
    local num_tracks = reaper.CountTracks(0)

    for i = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        local ok, razor_str = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
        if ok and razor_str and razor_str ~= "" then
            for start_s, end_s in razor_str:gmatch("([%d%.]+)%s+([%d%.]+)%s+\".-\"") do
                local start = tonumber(start_s)
                local finish = tonumber(end_s)
                if start and finish then
                    found = true
                    min_start = math.min(min_start, start)
                    max_end = math.max(max_end, finish)
                end
            end
        end
    end

    if found then
        return min_start, max_end
    else
        return nil, nil
    end
end

-- First try to get razor union
local start_pos, end_pos = get_razor_union_range()

-- If no razor edits, fall back to time selection
if not start_pos or not end_pos then
    start_pos, end_pos = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if not start_pos or not end_pos or math.abs(end_pos - start_pos) < 0.000001 then
        return -- exit silently
    end
end

-- Build razor string
local razor_str = string.format("%f %f \"\"", start_pos, end_pos)

-- Apply to all tracks
reaper.Undo_BeginBlock()

-- Set time selection
reaper.GetSet_LoopTimeRange(true, false, start_pos, end_pos, false)

local num_tracks = reaper.CountTracks(0)
for i = 0, num_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", razor_str, true)
end

reaper.Undo_EndBlock("Extend Razor Area + Time Selection to All Tracks", -1)
reaper.UpdateArrange()

