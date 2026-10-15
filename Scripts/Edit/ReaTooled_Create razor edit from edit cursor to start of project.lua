-- @description ReaTooled - Create razor edit from the edit cursor to the start of project
-- @version 1.2
-- @date 2025.09.01
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Creates a track-area Razor Edit from project start (0.0) to the edit cursor.
--   If no tracks are selected, applies to ALL tracks.
--   If at least one track is selected AND the helper script (_RSf28451a9bd28e7b3d270c4e5ce58052377a5e3df) is NOT running,
--     ignore selected tracks and apply ONLY to the focused (last touched) track.
-- CHANGELOG
--   v1.0 - Initial release
--   v1.1 - If no tracks are selected, apply to all tracks; high-precision Razor write; UI refresh guard
--   v1.2 - If >=1 track selected AND helper not running, target last-touched track instead of selected tracks

local reaper = reaper

-- Get the edit cursor position
local edit_cursor_pos = reaper.GetCursorPosition()
if edit_cursor_pos < 0 then edit_cursor_pos = 0 end

-- Determine whether helper script is "running" (toggle state == 1)
local HELPER_CMD_ID_STR = "_RSf28451a9bd28e7b3d270c4e5ce58052377a5e3df"
local helper_cmd = reaper.NamedCommandLookup(HELPER_CMD_ID_STR)
local helper_running = (helper_cmd ~= 0) and (reaper.GetToggleCommandStateEx(0, helper_cmd) == 1)

-- Begin undo block / UI guard
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Build target track list
local targets = {}
local num_selected_tracks = reaper.CountSelectedTracks(0)

if num_selected_tracks == 0 then
  -- No selection: apply to ALL tracks
  local track_count = reaper.CountTracks(0)
  for i = 0, track_count - 1 do
    targets[#targets+1] = reaper.GetTrack(0, i)
  end
else
  if not helper_running then
    -- >=1 selected AND helper NOT running: use the focused/last-touched track instead
    local focused = reaper.GetLastTouchedTrack()
    if focused then
      targets[#targets+1] = focused
    else
      -- Fallback if no last-touched track available: use the selected tracks
      for i = 0, num_selected_tracks - 1 do
        targets[#targets+1] = reaper.GetSelectedTrack(0, i)
      end
    end
  else
    -- Helper running: keep original behavior (selected tracks)
    for i = 0, num_selected_tracks - 1 do
      targets[#targets+1] = reaper.GetSelectedTrack(0, i)
    end
  end
end

-- Build Razor string (track-area triplet: start end "")
local razor_str = string.format("%.17f %.17f \"\"", 0.0, edit_cursor_pos)

-- Apply Razor to each target track (replace behavior, matching original)
for _, track in ipairs(targets) do
  if track then
    reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", razor_str, true)
  end
end

-- End undo / UI guard
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Create Razor Edit from project start to cursor (selected/all or focused track)", -1)

-- Update arrange
reaper.UpdateArrange()
