-- @description ReaTooled_Toggle In-Lane Volume Envelope (Using Action 40891)
-- @version 1.0
-- @date 2025.04.15
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- Toggles the volume envelope visibility in in-lane mode using REAPER's built-in actions.
-- CHANGELOG
--   + Uses action 40891 to toggle lane mode

local function toggle_inlane_volume(track)
    -- Get the volume envelope
    local env = reaper.GetTrackEnvelopeByName(track, "Volume")
    local visible = 0
    if env then
        visible = reaper.CountEnvelopePoints(env) > 0 and 1 or 0
    end

    -- Select only this track
    reaper.SetOnlyTrackSelected(track)

    -- If envelope not visible, activate + show it
    if not env or visible == 0 then
        reaper.Main_OnCommand(40406, 0) -- Toggle track volume envelope visible
        reaper.Main_OnCommand(40891, 0) -- Toggle volume envelope in-lane
    else
        -- Envelope is active → hide it completely
        reaper.Main_OnCommand(40406, 0) -- Toggle off
    end
end

-- Save selection
reaper.Undo_BeginBlock()

local tracks = {}
local num_sel = reaper.CountSelectedTracks(0)
for i = 0, num_sel - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    tracks[#tracks + 1] = track
end

-- Apply toggle to each selected track
for _, track in ipairs(tracks) do
    toggle_inlane_volume(track)
end

-- Restore original selection
reaper.Main_OnCommand(40297, 0) -- Unselect all
for _, track in ipairs(tracks) do
    reaper.SetTrackSelected(track, true)
end

reaper.Undo_EndBlock("ReaTooled: Toggle In-Lane Volume Envelope (Using 40891)", -1)
reaper.UpdateArrange()

