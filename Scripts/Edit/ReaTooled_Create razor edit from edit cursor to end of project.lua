-- @description ReaTooled - Create razor edit from the edit cursor to the end of project
-- @version 1.2
-- @date 2025.09.01
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Creates a track-area Razor Edit from the edit cursor to the end of the project.
--   If no tracks are selected, applies to ALL tracks. Replaces existing Razor on those tracks.
--   If ≥1 track is selected AND helper (_RSf28451a9bd28e7b3d270c4e5ce58052377a5e3df) is NOT running,
--   ignore the selected tracks and apply ONLY to the focused (last-touched) track.
-- CHANGELOG
--   v1.0 - Initial release
--   v1.1 - If no tracks are selected, apply to all tracks; high-precision Razor write; UI refresh guard
--   v1.2 - If ≥1 selected AND helper not running, target last-touched track instead of selected tracks

local reaper = reaper

-- Helper-running toggle (NamedCommand)
local HELPER_CMD_ID_STR = "_RSf28451a9bd28e7b3d270c4e5ce58052377a5e3df"

-- Get edit cursor and project end
local edit_cursor_pos = reaper.GetCursorPosition()
if edit_cursor_pos < 0 then edit_cursor_pos = 0 end
local project_end     = reaper.GetProjectLength(0)

-- Determine whether helper script is "running" (toggle state == 1)
local helper_cmd    = reaper.NamedCommandLookup(HELPER_CMD_ID_STR)
local helper_running = (helper_cmd ~= 0) and (reaper.GetToggleCommandStateEx(0, helper_cmd) == 1)

-- Start undo block / UI guard
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Determine target tracks
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
    -- ≥1 selected AND helper NOT running: use last-touched (focused) track
    local focused = reaper.GetLastTouchedTrack()
    if focused then
      targets[#targets+1] = focused
    else
      -- Fallback: selected tracks if no last-touched track available
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

-- Build Razor string once (track-area: start end "")
local razor_str = string.format("%.17f %.17f \"\"", edit_cursor_pos, project_end)

-- Apply Razor to each target track (replace behavior, as in original)
for _, track in ipairs(targets) do
  if track then
    reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", razor_str, true)
  end
end

-- End undo / UI guard
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Create Razor Edit from cursor to project end (selected/all or focused track)", -1)

-- Update arrange
reaper.UpdateArrange()
