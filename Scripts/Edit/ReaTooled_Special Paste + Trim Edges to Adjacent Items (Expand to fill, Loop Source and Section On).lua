-- @description ReaTooled_Special Paste (Expand to fill gaps per track, Loop Source and Section On)
-- @version 4.1
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @changelog
--   4.1 (2026-04-28)
--   • REWORK: Gap detection, item identity, option guards, and right-neighbor locking
--     all brought in line with ReaTooled_Special Paste v3.9.
--     - GUID-based item diffing (collect_all_items_guid_set / diff_new_items) replaces
--       pointer-identity snapshot, which is fragile after a paste operation.
--     - Gap snapshot is taken BEFORE the paste on all tracks so the pre-paste gap
--       geometry is available after pasted items occupy the gap.
--     - Right neighbors are locked before paste and unlocked immediately after,
--       preventing REAPER from deleting or damaging them when the clipboard item is
--       longer than the gap.
--     - Ripple mode is forced off for the operation and restored exactly afterward.
--     - Auto-crossfade and "Trim content behind media items" are disabled for the
--       operation and restored exactly afterward.
--     - Arrange view is snapshotted and restored so the screen never scrolls.
--     - EPS widened from 1e-6 to 1e-4 (0.1 ms) to match v3.9 and tolerate
--       floating-point drift at high sample rates.
--     - MIN_ITEM_LEN constant introduced to replace magic 0.0001 literal.
--   4.0
--   • Always performs a normal paste.
--   • Each pasted item is processed independently on its own track.
--   • If a bounded gap exists (left + right neighbors), the pasted item is forced
--     to fill the entire gap.
--   • Loop Source is enabled on pasted items.
--   • Loop SECTION is preserved or created if missing.
-- @about
--   Pastes clipboard items and forces each one to fill the bounded gap on its track.
--   Unlike the context-sensitive Special Paste, this script always fills — no Razor,
--   no over-body, no left-fill logic. Items with no bounded gap on their track are
--   left at their pasted position. Loop Source is enabled and a loop section is
--   created or preserved on every pasted item.

local reaper = reaper

-- EPS: tolerance for timeline position comparisons (0.1 ms).
local EPS = 1e-4

-- MIN_ITEM_LEN: floor applied when setting item length directly.
local MIN_ITEM_LEN = 0.0001

-- ========= Arrange view guards (SWS-first) =========
local function snapshot_arrange_view()
  if reaper.BR_GetArrangeView then
    local s, e = reaper.BR_GetArrangeView(0)
    return {start_time = s, end_time = e, sws = true}
  end
  if reaper.GetSet_ArrangeView2 then
    local s, e = reaper.GetSet_ArrangeView2(0, false, 0, 0)
    return {start_time = s, end_time = e, sws = false}
  end
  return {start_time = nil, end_time = nil, sws = false}
end
local function restore_arrange_view(s)
  if not s then return end
  if s.sws and reaper.BR_SetArrangeView and s.start_time and s.end_time then
    reaper.BR_SetArrangeView(0, s.start_time, s.end_time); return
  end
  if reaper.GetSet_ArrangeView2 and s.start_time and s.end_time then
    reaper.GetSet_ArrangeView2(0, true, s.start_time, s.end_time)
  end
end

-- ========= Option guards =========
local function snapshot_and_disable_edit_collateral()
  local AUTO = 40041  -- Options: Toggle auto-crossfade
  local TRIM = 41117  -- Options: Trim content behind media items when editing
  local auto_on = reaper.GetToggleCommandStateEx(0, AUTO) == 1
  local trim_on = reaper.GetToggleCommandStateEx(0, TRIM) == 1
  if auto_on then reaper.Main_OnCommand(AUTO, 0) end
  if trim_on then reaper.Main_OnCommand(TRIM, 0) end
  return {auto=auto_on, trim=trim_on, AUTO=AUTO, TRIM=TRIM}
end
local function restore_edit_collateral(s)
  if not s then return end
  if s.auto then reaper.Main_OnCommand(s.AUTO, 0) end
  if s.trim then reaper.Main_OnCommand(s.TRIM, 0) end
end

-- ========= Ripple guard =========
local function snapshot_and_force_ripple_off()
  local all_on = reaper.GetToggleCommandStateEx(0, 40310) == 1
  local per_on = reaper.GetToggleCommandStateEx(0, 40311) == 1
  reaper.Main_OnCommand(40309, 0)
  return {all = all_on, per = per_on}
end
local function restore_ripple_mode(snap)
  if not snap then return end
  if snap.all then
    if reaper.GetToggleCommandStateEx(0, 40310) == 0 then reaper.Main_OnCommand(40310, 0) end
  elseif snap.per then
    if reaper.GetToggleCommandStateEx(0, 40311) == 0 then reaper.Main_OnCommand(40311, 0) end
  else
    if reaper.GetToggleCommandStateEx(0, 40310) == 1 or reaper.GetToggleCommandStateEx(0, 40311) == 1 then
      reaper.Main_OnCommand(40309, 0)
    end
  end
end

-- ========= Item identity helpers =========
local function collect_all_items_guid_set()
  local set = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local ok, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if ok and guid ~= "" then set[guid] = it end
  end
  return set
end
local function diff_new_items(before_guid_set)
  local out = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local ok, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if ok and guid ~= "" and not before_guid_set[guid] then
      out[#out + 1] = it
    end
  end
  return out
end

-- ========= Gap detection =========
-- Returns [prev_item_end, next_item_start] around time t on the given track,
-- or nil, nil if t is inside an item or the gap is zero-width.
local function get_gap_around_time_on_track(track, t)
  local prev_end, next_start
  local n = reaper.CountTrackMediaItems(track)
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if e <= t + EPS and (not prev_end  or e > prev_end)   then prev_end   = e end
    if s >= t - EPS and (not next_start or s < next_start) then next_start = s end
  end
  if prev_end and next_start and (next_start - prev_end) > EPS then
    return prev_end, next_start
  end
  return nil, nil
end

-- ========= Neighbor helpers =========
local function find_left_neighbor_at_time(track, time_s)
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if math.abs(e - time_s) <= EPS then return it end
  end
  return nil
end
local function find_right_neighbor_at_time(track, time_s)
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if math.abs(s - time_s) <= EPS then return it end
  end
  return nil
end

-- ========= Fade helpers =========
local function zero_fades_item_both_edges(it)
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0)
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", 0)
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0)
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", 0)
end
local function zero_fade_on_left_edge(it)
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0)
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", 0)
end
local function zero_fade_on_right_edge(it)
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0)
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", 0)
end

-- ========= Loop helpers =========
local function loop_source_on(items)
  for _, it in ipairs(items) do
    reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 1)
  end
end

local function take_has_section(take)
  if not take then return false end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return false end
  return reaper.GetMediaSourceType(src, "") == "SECTION"
end

local function ensure_section_if_missing(items, orig_bounds)
  local cmd = reaper.NamedCommandLookup("_SWS_LOOPITEMSECTION")
  if cmd == 0 then return end

  for _, it in ipairs(items) do
    local take = reaper.GetActiveTake(it)
    if take and not take_has_section(take) then
      local b = orig_bounds[it]
      if b then
        reaper.SelectAllMediaItems(0, false)
        reaper.SetMediaItemSelected(it, true)
        reaper.GetSet_LoopTimeRange(true, false, b.s, b.e, false)
        reaper.Main_OnCommand(cmd, 0)
      end
    end
  end

  -- Clear time selection
  reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
end

-- ========= Main =========
local function main()
  local cursor = reaper.GetCursorPosition()

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local view_snap   = snapshot_arrange_view()
  local ripple_snap = snapshot_and_force_ripple_off()
  local edit_snap   = snapshot_and_disable_edit_collateral()

  local function cleanup_end(msg)
    restore_edit_collateral(edit_snap)
    restore_ripple_mode(ripple_snap)
    restore_arrange_view(view_snap)
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(msg or "Special Paste (Loop)", -1)
  end

  -- Snapshot each track's gap BEFORE the paste. After the paste the pasted items
  -- occupy the gap, so get_gap_around_time_on_track() would return nil if called then.
  -- We use the edit cursor position as the probe point, matching v3.9 behavior.
  local track_gaps = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local gs, ge = get_gap_around_time_on_track(tr, cursor)
    if gs and ge then
      track_gaps[tr] = {gs = gs, ge = ge}
    end
  end

  -- Lock right neighbors before pasting to prevent REAPER from deleting or
  -- damaging them when the clipboard item is longer than the gap.
  local right_neighbor_locks = {}
  for tr, gap in pairs(track_gaps) do
    local rn = find_right_neighbor_at_time(tr, gap.ge)
    if rn and not right_neighbor_locks[rn] then
      right_neighbor_locks[rn] = reaper.GetMediaItemInfo_Value(rn, "C_LOCK")
      reaper.SetMediaItemInfo_Value(rn, "C_LOCK", 1)
    end
  end

  local before = collect_all_items_guid_set()
  reaper.Main_OnCommand(40058, 0)  -- Paste

  -- Restore right neighbor locks immediately, before any resizing.
  for rn, was in pairs(right_neighbor_locks) do
    reaper.SetMediaItemInfo_Value(rn, "C_LOCK", was)
  end

  local pasted = diff_new_items(before)

  if #pasted == 0 then
    cleanup_end("Special Paste (Loop): nothing pasted")
    return
  end

  -- Capture original bounds for loop section creation (before gap reshaping).
  local orig_bounds = {}
  for _, it in ipairs(pasted) do
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    orig_bounds[it] = {s = s, e = e}
  end

  -- Force each pasted item to fill its track's pre-paste gap.
  -- Items on tracks with no detected gap are left at their pasted position.
  local n_filled = 0
  for _, it in ipairs(pasted) do
    local tr = reaper.GetMediaItemTrack(it)
    local gap = tr and track_gaps[tr]
    if gap then
      reaper.SetMediaItemInfo_Value(it, "D_POSITION", gap.gs)
      reaper.SetMediaItemInfo_Value(it, "D_LENGTH", math.max(MIN_ITEM_LEN, gap.ge - gap.gs))
      zero_fades_item_both_edges(it)
      local L = find_left_neighbor_at_time(tr, gap.gs)
      local R = find_right_neighbor_at_time(tr, gap.ge)
      if L then zero_fade_on_right_edge(L) end
      if R then zero_fade_on_left_edge(R) end
      n_filled = n_filled + 1
    end
  end

  -- Loop handling after gap fill.
  loop_source_on(pasted)
  ensure_section_if_missing(pasted, orig_bounds)

  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(pasted) do reaper.SetMediaItemSelected(it, true) end
  reaper.SetEditCurPos(cursor, false, false)

  local label = "Special Paste (Loop; fill gaps; loop source + section)"
  if n_filled < #pasted then
    label = label .. string.format(" [%d item(s) had no gap, left at pasted position]",
      #pasted - n_filled)
  end
  cleanup_end(label)
end

main()
