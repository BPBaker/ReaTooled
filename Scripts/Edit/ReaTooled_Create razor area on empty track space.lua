-- @description ReaTooled - Create Razor Edit to Fill Gap at Edit Cursor
-- @version 1.5
-- @date 2026.04.13
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Creates a track-area Razor Edit that exactly spans the empty space (gap) surrounding
--   the edit cursor on a target track.
--   Target track resolution (in order of preference):
--     1) Track under mouse (native hit-test; pinned-track safe), else
--     2) Track under mouse via SWS (fallback), else
--     3) Single selected track, else
--     4) Last touched track.
--   Handles edge cases:
--     • Gap from project start (0) to the first item
--     • Gap from the last item to project end
--     • Tracks with no items (entire project length)
--   Project end is resolved in order of priority:
--     1) Marker named "=END"
--     2) Explicit Project Settings end time ("PROJECT_LENGTH")
--     3) Automatic length (GetProjectLength)
--   If no gap encompasses the edit cursor (e.g., cursor is inside an item), no changes are made.
-- CHANGELOG
--   v1.5 - Add LANE_AWARE toggle: when true, gap detection only considers items on the
--           active fixed lane when the track has fixed lanes enabled. Items on hidden or
--           inactive lanes are ignored, matching what the user sees and hears.
--   v1.4 - Fix track-under-mouse when tracks are pinned (use GetTrackFromPoint first)

local reaper = reaper

-- ─────────────────────────────────────────────────────────────────────────────
-- USER TOGGLE
-- When true: gap detection ignores items that live on hidden/inactive lanes,
-- so only the active lane's items are used to determine empty space.
-- When false: all items on the track are considered regardless of lane (original behaviour).
local LANE_AWARE = true
-- ─────────────────────────────────────────────────────────────────────────────

local DEBUG = false
local function msg(s) if DEBUG then reaper.ShowConsoleMsg(tostring(s) .. "\n") end end

-- Return a target track using mouse hit-test (pinned-track safe), then SWS, selection, or last-touched fallback
local function resolve_target_track()
  -- 1) Native track hit-test under mouse (works with pinned tracks)
  local mx, my = reaper.GetMousePosition()
  if mx and my then
    local tr = reaper.GetTrackFromPoint(mx, my)
    if tr then return tr end
  end

  -- 2) SWS mouse context fallback (can be wrong with pinned tracks, so not first choice)
  if reaper.BR_GetMouseCursorContext then
    reaper.BR_GetMouseCursorContext()
    local tr = reaper.BR_GetMouseCursorContext_Track()
    if tr then return tr end
  end

  -- 3) Single selected track
  local sel_cnt = reaper.CountSelectedTracks(0)
  if sel_cnt == 1 then return reaper.GetSelectedTrack(0, 0) end

  -- 4) Last touched track
  local last = reaper.GetLastTouchedTrack()
  if last then return last end

  return nil
end

-- Return project end time, checking =END marker, then Project Settings ("PROJECT_LENGTH"), then auto length
local function get_project_end()
  local proj = 0

  -- 1) Marker named "=END"
  local _, num_markers, num_regions = reaper.CountProjectMarkers(proj)
  local total = (num_markers or 0) + (num_regions or 0)
  for i = 0, total - 1 do
    local ok, isrgn, pos, rgnend, name = reaper.EnumProjectMarkers(i)
    if ok and not isrgn and name and name == "=END" then
      return pos or 0.0
    end
  end

  -- 2) Explicit Project Settings end time
  local proj_len_setting = reaper.GetSetProjectInfo(proj, "PROJECT_LENGTH", 0, false)
  if proj_len_setting and proj_len_setting > 0 then
    return proj_len_setting
  end

  -- 3) Fallback: automatic project length
  return reaper.GetProjectLength(proj) or 0.0
end

-- Return true if the track has fixed lanes enabled and LANE_AWARE is on.
-- Also returns the index of the currently active (playing/shown) fixed lane.
local function get_active_lane(track)
  if not LANE_AWARE then return false, nil end

  -- I_FREEMODE: 0 = normal, 1 = free-item-positioning, 2 = fixed lanes
  local freemode = reaper.GetMediaTrackInfo_Value(track, "I_FREEMODE")
  if freemode ~= 2 then return false, nil end

  -- I_FIXEDLANE: the index of the active fixed lane (0-based)
  local active_lane = reaper.GetMediaTrackInfo_Value(track, "I_FIXEDLANE")
  return true, math.floor(active_lane + 0.5)
end

-- Find the gap boundaries that contain pos on track, considering project edges.
-- When LANE_AWARE is true and the track has fixed lanes enabled, only items on
-- the active lane are used; items on all other lanes are skipped.
local function find_gap_on_track(track, pos, proj_end)
  local item_count = reaper.CountTrackMediaItems(track)
  local lanes_active, active_lane = get_active_lane(track)

  msg(("lanes_active=%s  active_lane=%s"):format(tostring(lanes_active), tostring(active_lane)))

  -- No items on this track → entire project span is a gap
  if item_count == 0 then
    if pos >= 0 and pos <= proj_end then
      return 0.0, proj_end
    else
      return nil, nil
    end
  end

  local left_end    = nil   -- nearest item end <= pos
  local right_start = nil   -- nearest item start >= pos
  local first_start = nil   -- earliest item start
  local last_end    = nil   -- latest item end
  local any_item    = false -- did we find at least one qualifying item?

  for i = 0, item_count - 1 do
    local it = reaper.GetTrackMediaItem(track, i)

    -- Lane filter: skip items that are not on the active lane when lane-aware mode is on
    if lanes_active then
      local item_lane = math.floor(reaper.GetMediaItemInfo_Value(it, "I_LANE") + 0.5)
      if item_lane ~= active_lane then
        msg(("  skip item %d: lane %d ≠ active %d"):format(i, item_lane, active_lane))
        goto continue
      end
    end

    do
      local it_start = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local it_len   = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local it_end   = it_start + it_len
      any_item = true

      msg(("  item %d: %.5f → %.5f"):format(i, it_start, it_end))

      if not first_start or it_start < first_start then first_start = it_start end
      if not last_end   or it_end   > last_end   then last_end   = it_end   end

      if it_end <= pos then
        if (not left_end) or (it_end > left_end) then left_end = it_end end
      end
      if it_start >= pos then
        if (not right_start) or (it_start < right_start) then right_start = it_start end
      end
    end

    ::continue::
  end

  -- If every item was filtered out treat the lane as empty
  if not any_item then
    if pos >= 0 and pos <= proj_end then
      return 0.0, proj_end
    else
      return nil, nil
    end
  end

  -- Interior gap surrounding the cursor
  if left_end and right_start and left_end < right_start and pos >= left_end and pos <= right_start then
    return left_end, right_start
  end

  -- Cursor before the first item → gap 0 → first_start
  if (not left_end) and first_start and pos >= 0 and pos <= first_start then
    return 0.0, first_start
  end

  -- Cursor after the last item → gap last_end → project_end
  if (not right_start) and last_end and pos >= last_end and pos <= proj_end then
    return last_end, proj_end
  end

  return nil, nil
end

-- Apply a single Razor Edit to a track for [start, end)
local function set_razor_for_track(track, start_pos, end_pos)
  if not (start_pos and end_pos) then return end
  if end_pos <= start_pos then return end
  local re_str = string.format("%.17f %.17f \"\"", start_pos, end_pos)
  reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", re_str, true)
end

-- MAIN
local function main()
  local cursor = reaper.GetCursorPosition()
  local track = resolve_target_track()
  if not track then
    msg("No suitable target track found.")
    return
  end

  local proj_end = get_project_end()
  local gap_start, gap_end = find_gap_on_track(track, cursor, proj_end)
  if not (gap_start and gap_end) then
    msg("No gap at edit cursor on target track; no changes made.")
    return
  end

  set_razor_for_track(track, gap_start, gap_end)
  msg(("Razor set: %.9f → %.9f"):format(gap_start, gap_end))
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("ReaTooled - Create Razor Edit to Fill Gap at Edit Cursor", -1)
