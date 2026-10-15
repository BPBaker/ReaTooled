-- @description ReaTooled - ReaTooled_Special Paste + Trim Item Edges to Next and Previous Items (Expand to fill between neighboring items)
-- @version 3.13
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @changelog
--   3.13 (2026-07-18)
--   • FIX: Confirmed via console trace — get_anchor_track()'s heuristics
--     (mouse hover / GetLastTouchedTrack / selected item) could resolve to a
--     DIFFERENT track than the one REAPER's own native paste (40058) actually
--     puts items on, since our script never drove REAPER's internal
--     current-track state and was only guessing at it. When the guess was
--     wrong, gap geometry (gap_start/gap_end/effective_gap_start) was computed
--     for the wrong track while items landed on the real target track,
--     producing exactly the reported symptom: gap not filled on the left,
--     anchor track reported as different from the track actually pasted into.
--   • FIX: get_anchor_track() removed entirely. Replaced with
--     probe_paste_destination(): a real throwaway paste+undo run before the
--     undo block opens (same pattern as clipboard_has_items()) that reads
--     back, via reaper.GetMediaItemTrack() on the probe-pasted items, exactly
--     which track(s) REAPER itself chose as the paste destination. The anchor
--     track is now that observed topmost destination track — ground truth,
--     not a heuristic — so it can never diverge from where the real paste
--     lands afterward. This also subsumes the empty-clipboard check for the
--     non-Razor path (previously only the Razor path checked upfront).
--   3.12-debug (2026-07-18)
--   • DEBUG: added a DEBUG toggle (near FILL_SECONDARY_LEFT_EDGE) that prints
--     a step-by-step trace of the bounded-gap-fill path to the ReaScript
--     console: anchor track, cursor/gap geometry, effective_gap_start, the
--     pre-paste per-track gap snapshot, raw pasted item positions, the
--     sync-preserving move delta, and every per-track decision inside
--     apply_per_track_gap_fill (kept/deleted, right-stretch result,
--     left-adjust check, final item position/length vs. that track's gap).
--     Purely diagnostic; not a behavior change. Reported bug: single-track
--     gap-fill still not expanding to fill the gap even after 3.10/3.11 —
--     this build is meant to be run once against a failing case so the
--     console output pinpoints exactly which computed value is wrong.
--   3.11 (2026-07-18)
--   • FIX: apply_per_track_gap_fill()'s left-edge correction (FILL_SECONDARY_LEFT_EDGE
--     path) only pulled a secondary track's left edge BACK when that track's own
--     gap_start was earlier than the anchor's. It never corrected the opposite,
--     equally common case: a secondary track whose gap_start falls LATER than the
--     anchor's (its preceding item simply ends later). Left uncorrected, that
--     track's pasted item kept the anchor-aligned left position, overlapping its
--     own preceding item and ending up oversized relative to that track's real
--     gap — "right track, wrong sizing" on multi-track pastes with uneven gaps.
--     Fix: the left edge is now always synced to the track's own gap_start
--     whenever it differs from the item's current position, in either direction;
--     set_track_items_left() already handled both directions correctly, the
--     bug was purely in the one-sided calling condition.
--   3.10 (2026-07-18)
--   • FIX: get_anchor_track() no longer scans all tracks looking for "any track
--     with a gap at the cursor" as a fallback. That heuristic was unreliable:
--     virtually any track without an item exactly at the cursor position
--     technically "has a gap" there, so with no mouse hover and no explicit
--     track selection it would silently lock onto an arbitrary earlier track
--     (e.g. track 1) instead of the track the user was actually editing —
--     producing gap-fill results computed against the wrong track's geometry.
--   • CHANGE: anchor track no longer depends on track *selection* at all.
--     New priority order:
--       1. Mouse hover context (BR_GetMouseCursorContext_Track) — wins
--          unconditionally, same as before.
--       2. GetLastTouchedTrack() — the track last clicked/interacted with,
--          independent of current selection highlighting. This is the track
--          "the edit cursor belongs to" in normal keyboard-driven workflows.
--       3. Selected item's track — last-resort fallback only, same as before.
--     The edit-cursor-position gap-validation scan against selected/all
--     tracks has been removed accordingly; get_anchor_track() no longer
--     takes a cursor parameter.
--   3.9 (2026-04-28)
--   • FIX: apply_per_track_gap_fill() now receives a pre-paste gap snapshot
--     (track_gaps table) instead of re-detecting gaps after the paste. Previously,
--     get_gap_around_time_on_track() was called after pasted items already occupied
--     the gap, causing it to return nil and delete the just-pasted items, producing
--     a silent no-op with a misleading "[N track(s) skipped: no gap]" undo label.
--     Gap snapshot is also reused for the right-neighbor locking loop, eliminating
--     a redundant second scan of all tracks.
--   3.8 (2026-04-28)
--   • FIX: get_anchor_track() now accepts the edit cursor position as a parameter
--     and validates candidates against it, fixing consistent failures when the
--     script is invoked via keyboard shortcut with no mouse hover context.
--     Previously the function fell through to GetSelectedTrack / GetLastTouchedTrack
--     heuristics which had no relationship to the edit cursor's position, causing
--     gap detection to run on the wrong track and the script to fall through to
--     plain paste at cursor.
--     New priority order:
--       1. Mouse hover context (BR_GetMouseCursorContext_Track) — wins unconditionally,
--          preserves mouse-driven behavior unchanged.
--       2. First selected track that has a gap at the edit cursor position.
--       3. First track (by index) that has a gap at the edit cursor position — covers
--          the common keyboard case where no track is selected.
--       4. GetLastTouchedTrack / selected item track — last-resort fallbacks only,
--          same as before.
--   3.7 (2026-03-31)
--   • FIX: Bounded gap path now locks right neighbor items on ALL tracks before
--     the native paste call. When a clipboard item is longer than a track's gap,
--     REAPER's paste would previously delete or damage the right neighbor before
--     the script could resize the pasted item. The lock prevents any collateral
--     damage; lock states are restored immediately after the paste, before resize.
--     This applies across all tracks (anchor and secondary) since both are equally
--     exposed to the collateral deletion risk.
--   3.6 (2026-03-31)
--   • FIX/FEATURE: Gap-fill path (bounded gap, no Razor) now operates per-track
--     rather than treating all pasted items as a single block.
--     - Right-edge stretch: each track's rightmost pasted item is stretched to
--       that track's own gap_end (detected independently at the cursor position).
--     - Left-edge behavior on secondary tracks is controlled by the new
--       FILL_SECONDARY_LEFT_EDGE toggle (see below).
--     - Secondary tracks with no detectable gap at the cursor have their pasted
--       items deleted (nothing unintended lands on a gapless track).
--     - Secondary tracks where the pasted item falls entirely outside that
--       track's gap are also deleted (same rule, FILL_SECONDARY_LEFT_EDGE=true path).
--     - Neighbor fade clearing now uses each track's own gap_start/gap_end.
--     - Undo label reports skipped track count when secondary tracks are removed.
--   • NEW: FILL_SECONDARY_LEFT_EDGE toggle constant (near top of file).
--       true  = each secondary track's pasted item is pulled back to its own
--               gap_start, filling the full gap width independently.
--       false = all pasted items share the anchor track's gap_start (strict
--               inter-item sync; may leave a hole on the left of wider secondary gaps).
--   3.5 (2026-03-19)
--   • FIX (#1): clipboard_has_items() now runs before Undo_BeginBlock() and before
--     any state mutation, eliminating undo-block corruption from the probe paste/undo.
--   • FIX (#2): clipboard_has_items() now delegates to diff_new_items() rather than
--     re-implementing the GUID diff inline; removes code duplication and drift risk.
--   • FIX (#3): Left-fill skipped-track counter now tracks unique track pointers in a
--     set rather than incrementing per item, so multi-item pastes report correctly.
--   • CLARIFY (#4): cleanup_end() ordering before ShowMessageBox() now commented to
--     explain that the undo block is intentionally sealed before the dialog appears.
--   • FIX (#5): get_gap_around_time_on_track() now explicitly returns nil,nil for
--     zero-width gaps (flush adjacent items), making the contract self-documenting
--     rather than relying on downstream guards.
--   • CLARIFY (#6): trim_items_in_range() now comments why reverse iteration is
--     load-bearing when SplitMediaItem inserts new items into the list.
--   • CLARIFY (#7): move_items() inner epsilon renamed MOVE_EPS with a comment
--     explaining why it differs from EPS.
--   • CLARIFY (#8): MIN_ITEM_LEN named constant introduced to replace the magic
--     0.0001 used in set_block_right() and the left-fill expand.
--   • CLARIFY (#9): redundant `saved` alias of `cursor` removed from the Razor path;
--     `cursor` used directly throughout for consistency.
--   3.4 (2026-03-19)
--   • FIX: set_block_right now stretches only the rightmost item's right edge,
--     preserving internal spacing when pasting multi-item clipboard blocks.
--   • FIX: Razor path now checks for an empty clipboard BEFORE trimming items,
--     preventing a destructive no-op (items deleted, nothing pasted).
--   • FIX: EPS widened from 1e-6 to 1e-4 (0.1 ms) to tolerate floating-point
--     accumulation at high sample rates and after repeated edits.
--   • FIX: diff_new_items now snapshots item GUIDs for identity, removing
--     dependence on pointer stability after a paste operation.
--   • FIX: Left-fill path now reports in the undo label when some tracks were
--     skipped due to mismatched gap geometry at the cursor.
--   • CLARIFY: D_STARTOFFS comment in left-fill block corrected to reflect
--     actual behavior (source offset is preserved relative to item origin,
--     not absolute playback position).
--   • NOTE: trim_items_in_range double-split ordering added a clarifying comment.
--   3.3
--   • Razor present: trim/remove items inside the Razor range on tracks with item Razors,
--     paste to fill that range, preserve the Razor, and move the edit cursor to Razor start.
--   • No Razor:
--       - If the cursor is over an item body on the anchor track → simple paste at cursor
--         (select pasted only), and clear any boundary fades on adjacent neighbors we abut.
--       - Else paste to fill the gap around the cursor. If flush with a neighbor's edge,
--         only fill the empty side.
--         LEFT-FILL ONLY (cursor flush with right item's left edge): paste at the cursor,
--         expand left per-track to each track's gap start, temporarily lock any right
--         neighbor(s) at the cursor on ALL tracks. D_STARTOFFS is NOT modified (source
--         offset is preserved relative to item origin, not absolute playback position).
--     Cursor moves to the pasted start.
--   • Never ripples: snapshot ripple, force OFF for the op, then restore exactly.
--   • No collateral edits: temporarily disable "Auto-crossfade" and
--     "Trim content behind media items" during paste.
--   • Arrange view preserved: screen never scrolls; original view restored at end.
--   • No new fades on pasted; boundary fades on touched neighbors cleared.
--   • Razor policy: if a Razor existed at start, preserve it; otherwise, clear all Razors at end.
-- @about
--   Smart context-sensitive paste for REAPER. Fills gaps, Razor ranges, or pastes
--   at cursor depending on context. See changelog for full behavior description.
local reaper = reaper
-- EPS: tolerance for timeline position comparisons.
-- 1e-4 s (0.1 ms) absorbs floating-point drift at high sample rates and after
-- repeated edits without being so wide that it misidentifies distinct positions.
local EPS = 1e-4
-- MOVE_EPS: threshold below which a position delta is treated as zero and skipped.
-- Kept much tighter than EPS — we want to skip only genuinely zero moves, not
-- moves that are merely "close" to a neighbor boundary.
local MOVE_EPS = 1e-12
-- MIN_ITEM_LEN: floor applied whenever we set an item length directly, matching
-- REAPER's own minimum to avoid zero- or negative-length items.
local MIN_ITEM_LEN = 0.0001
-- FILL_SECONDARY_LEFT_EDGE: controls left-edge behavior for secondary tracks
-- in the bounded gap-fill path (no Razor, cursor in a gap).
--
--   true  = each secondary track's pasted item is pulled back to its own gap_start,
--            filling the full gap on each track independently. Recommended when
--            secondary tracks have wider gaps starting earlier than the anchor track.
--
--   false = all pasted items share the anchor track's gap_start as their left edge
--           (strict inter-item sync preservation). May leave a hole on the left side
--           of secondary track gaps that start earlier than the anchor's gap_start.
local FILL_SECONDARY_LEFT_EDGE = true
-- DEBUG: when true, prints a step-by-step trace of the bounded-gap-fill path
-- to the ReaScript console (View > Show console output, or it pops up
-- automatically). Purely diagnostic — safe to leave on temporarily while
-- tracking down a specific bug, then flip off.
local DEBUG = false
local function dbg(fmt, ...)
  if not DEBUG then return end
  reaper.ShowConsoleMsg(string.format(fmt, ...) .. "\n")
end
local function trname(tr)
  if not tr then return "<nil>" end
  local ok, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  if ok and nm ~= "" then return nm end
  local idx = reaper.CSurf_TrackToID and reaper.CSurf_TrackToID(tr, false) or nil
  return idx and ("Track " .. idx) or tostring(tr)
end
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
-- ========= Item helpers =========
-- Snapshot GUIDs of all current items for stable identity comparison after paste.
-- Pointer identity alone is fragile if REAPER reorders its internal item list.
local function collect_all_items_guid_set()
  local set = {}
  for i = 0, reaper.CountMediaItems(0)-1 do
    local it = reaper.GetMediaItem(0, i)
    local ok, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if ok and guid ~= "" then set[guid] = it end
  end
  return set
end
local function diff_new_items(before_guid_set)
  local out = {}
  for i = 0, reaper.CountMediaItems(0)-1 do
    local it = reaper.GetMediaItem(0, i)
    local ok, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if ok and guid ~= "" and not before_guid_set[guid] then
      out[#out+1] = it
    end
  end
  return out
end
-- ========= Clipboard empty check =========
-- MUST be called before Undo_BeginBlock() and before any state mutation.
-- Does a probe paste + immediate undo to detect an empty clipboard without
-- touching any option state or an open undo block. Delegates to diff_new_items()
-- so the detection logic stays in sync with the real paste paths.
local function clipboard_has_items()
  local saved_pos = reaper.GetCursorPosition()
  local before    = collect_all_items_guid_set()
  reaper.Main_OnCommand(40058, 0)          -- Paste items/tracks (probe)
  local has = #diff_new_items(before) > 0
  reaper.Main_OnCommand(40029, 0)          -- Edit: Undo (rolls back probe)
  reaper.SetEditCurPos(saved_pos, false, false)
  return has
end
-- MUST be called before Undo_BeginBlock() and before any state mutation, for
-- the same reason as clipboard_has_items(): it does its own throwaway
-- paste+undo cycle.
--
-- Does a real probe paste at the current cursor and reads back which track(s)
-- reaper.Main_OnCommand(40058, ...) actually put the items on, then undoes it.
-- This replaces every previous heuristic for picking an "anchor track"
-- (mouse hover / GetLastTouchedTrack / selection / scanning tracks for a gap):
-- none of those are guaranteed to agree with wherever REAPER's own paste
-- command actually decides to drop the items, and when they disagree the
-- script computes gap geometry for the wrong track while the real paste
-- lands somewhere else entirely — exactly the "different anchor track than
-- the track I'm pasting into" bug. Asking REAPER directly removes the
-- guesswork: nothing between this probe and the real paste later in main()
-- changes track selection or last-touched-track state, so the destination
-- observed here is guaranteed to match the real paste.
-- Returns: has_items (bool), dest_tracks (array of MediaTrack, ordered by
-- project track index so dest_tracks[1] is the topmost / anchor track).
local function probe_paste_destination()
  local saved_pos = reaper.GetCursorPosition()
  local before     = collect_all_items_guid_set()
  reaper.Main_OnCommand(40058, 0)           -- Paste items/tracks (probe)
  local probe_items = diff_new_items(before)
  local dest_tracks, seen = {}, {}
  for _, it in ipairs(probe_items) do
    local tr = reaper.GetMediaItemTrack(it)
    if tr and not seen[tr] then
      seen[tr] = true
      dest_tracks[#dest_tracks+1] = tr
    end
  end
  table.sort(dest_tracks, function(a, b)
    return reaper.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER")
         < reaper.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER")
  end)
  reaper.Main_OnCommand(40029, 0)           -- Edit: Undo (rolls back probe)
  reaper.SetEditCurPos(saved_pos, false, false)
  return #probe_items > 0, dest_tracks
end
local function get_block_bounds(items)
  if #items == 0 then return nil, nil end
  local smin, emax
  for _, it in ipairs(items) do
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if not smin or s < smin then smin = s end
    if not emax or e > emax then emax = e end
  end
  return smin, emax
end
local function move_items(items, delta)
  -- MOVE_EPS is intentionally much tighter than EPS: skip only genuinely zero
  -- deltas, not moves that happen to be close to a neighbor boundary.
  if math.abs(delta) < MOVE_EPS then return end
  for _, it in ipairs(items) do
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    reaper.SetMediaItemInfo_Value(it, "D_POSITION", p + delta)
  end
end
-- Stretch only the rightmost item's right edge to new_right, preserving
-- internal spacing between items in a multi-item clipboard block.
local function set_block_right(items, new_right)
  if #items == 0 then return end
  local rightmost_it, rightmost_end
  for _, it in ipairs(items) do
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if not rightmost_end or e > rightmost_end then
      rightmost_end = e
      rightmost_it  = it
    end
  end
  if not rightmost_it then return end
  local delta = new_right - rightmost_end
  if math.abs(delta) < MOVE_EPS then return end
  local L = reaper.GetMediaItemInfo_Value(rightmost_it, "D_LENGTH")
  reaper.SetMediaItemInfo_Value(rightmost_it, "D_LENGTH", math.max(MIN_ITEM_LEN, L + delta))
end
-- Stretch only the rightmost item on a given list to new_right.
-- Used by per-track gap fill so each track's items are stretched independently.
local function set_track_items_right(track_items, new_right)
  if #track_items == 0 then return end
  local rightmost_it, rightmost_end
  for _, it in ipairs(track_items) do
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if not rightmost_end or e > rightmost_end then
      rightmost_end = e
      rightmost_it  = it
    end
  end
  if not rightmost_it then return end
  local delta = new_right - rightmost_end
  if math.abs(delta) < MOVE_EPS then return end
  local L = reaper.GetMediaItemInfo_Value(rightmost_it, "D_LENGTH")
  reaper.SetMediaItemInfo_Value(rightmost_it, "D_LENGTH", math.max(MIN_ITEM_LEN, L + delta))
end
-- Pull the leftmost item on a given list back to new_left by adjusting D_POSITION
-- and D_LENGTH. D_STARTOFFS is intentionally NOT modified: source offset is
-- preserved relative to the item's internal origin.
local function set_track_items_left(track_items, new_left)
  if #track_items == 0 then return end
  local leftmost_it, leftmost_start
  for _, it in ipairs(track_items) do
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if not leftmost_start or s < leftmost_start then
      leftmost_start = s
      leftmost_it    = it
    end
  end
  if not leftmost_it then return end
  local delta = leftmost_start - new_left   -- positive = item is to the right of new_left
  if math.abs(delta) < MOVE_EPS then return end
  local L = reaper.GetMediaItemInfo_Value(leftmost_it, "D_LENGTH")
  reaper.SetMediaItemInfo_Value(leftmost_it, "D_POSITION", new_left)
  reaper.SetMediaItemInfo_Value(leftmost_it, "D_LENGTH", math.max(MIN_ITEM_LEN, L + delta))
end
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
-- ========= Gap detection =========
-- Returns the gap boundaries [prev_item_end, next_item_start] around time t on
-- the given track, or nil, nil if:
--   • t is inside an item body, or
--   • the gap is zero-width (adjacent items exactly flush with each other).
-- Explicitly rejecting zero-width gaps here makes the contract self-documenting
-- rather than relying on downstream edge-flag guards to silently absorb the
-- degenerate case.
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
-- ========= Anchor track selection =========
-- Anchor track selection no longer lives here as a standalone heuristic.
-- See probe_paste_destination() (Clipboard empty check section, above):
-- the anchor track is now the topmost track that a real probe paste actually
-- lands on, observed directly rather than guessed at via mouse/selection/
-- last-touched-track heuristics.
local function cursor_over_item_body(track, t)
  if not track then return false end
  local n = reaper.CountTrackMediaItems(track)
  for i = 0, n-1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local s  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e  = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if (t > s + EPS) and (t < e - EPS) then return true end
  end
  return false
end
local function find_left_neighbor_at_time(track, time_s)
  local n = reaper.CountTrackMediaItems(track)
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if math.abs(e - time_s) <= EPS then return it end
  end
  return nil
end
local function find_right_neighbor_at_time(track, time_s)
  local n = reaper.CountTrackMediaItems(track)
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if math.abs(s - time_s) <= EPS then return it end
  end
  return nil
end
-- ========= Razor helpers =========
local function parse_track_razor(track)
  local ok, str = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
  local areas = {}
  if ok and str ~= "" then
    for s1, s2, guid in string.gmatch(str, "([%d%.]+)%s+([%d%.]+)%s+([^%s]+)") do
      local s = tonumber(s1)
      local e = tonumber(s2)
      local isEnv = (guid ~= '""') and (guid ~= "")
      areas[#areas+1] = {start=s, finish=e, isEnvelope=isEnv}
    end
  end
  return areas
end
local function any_razor_exists()
  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    local ok, str = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if ok and str ~= "" then return true end
  end
  return false
end
local function snapshot_razors()
  local snap = {}
  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    local ok, str = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if ok then snap[tr] = str end
  end
  return snap
end
local function restore_razors(snap)
  for tr, str in pairs(snap) do
    reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", str or "", true)
  end
end
local function clear_all_razors()
  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", true)
  end
end
local function get_overall_razor_range()
  local Rmin, Rmax, tracks = nil, nil, {}
  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    local areas = parse_track_razor(tr)
    local hasItem = false
    for _, a in ipairs(areas) do
      if not a.isEnvelope then
        hasItem = true
        Rmin = (Rmin and math.min(Rmin, a.start)) or a.start
        Rmax = (Rmax and math.max(Rmax, a.finish)) or a.finish
      end
    end
    if hasItem then tracks[#tracks+1] = tr end
  end
  return Rmin, Rmax, tracks
end
local function trim_items_in_range(tracks, A, B)
  for _, tr in ipairs(tracks) do
    -- Iterate in REVERSE so that SplitMediaItem — which inserts the right
    -- segment at a higher index — does not shift unvisited items and cause
    -- the loop to skip or double-visit entries.
    local n = reaper.CountTrackMediaItems(tr)
    for i = n - 1, 0, -1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if e > A + EPS and s < B - EPS then
        if s >= A - EPS and e <= B + EPS then
          reaper.DeleteTrackMediaItem(tr, it)
        elseif s < A and e > B then
          -- Item spans the entire range [A, B].
          -- Split at B first → 'it' remains [s, B], 'right' is [B, e].
          -- Split 'it' at A  → 'it' remains [s, A], 'mid'   is [A, B].
          -- Delete 'mid'. REAPER guarantees SplitMediaItem returns the right
          -- segment and keeps the original pointer as the left segment.
          local right = reaper.SplitMediaItem(it, B)
          local mid   = reaper.SplitMediaItem(it, A)
          if mid   then reaper.DeleteTrackMediaItem(reaper.GetMediaItemTrack(mid),   mid)   end
          if it    then zero_fade_on_right_edge(it)   end
          if right then zero_fade_on_left_edge(right) end
        elseif s < A and e > A and e <= B then
          local right = reaper.SplitMediaItem(it, A)
          if right then reaper.DeleteTrackMediaItem(reaper.GetMediaItemTrack(right), right) end
          zero_fade_on_right_edge(it)
        elseif s >= A and s < B and e > B then
          local right = reaper.SplitMediaItem(it, B)
          if right then
            reaper.DeleteTrackMediaItem(reaper.GetMediaItemTrack(it), it)
            zero_fade_on_left_edge(right)
          end
        end
      end
    end
  end
end
-- ========= Helpers specific to the multi-track left-fill =========
local function collect_items_starting_at_time_on_all_tracks(t)
  local items = {}
  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    local n  = reaper.CountTrackMediaItems(tr)
    for j = 0, n-1 do
      local it = reaper.GetTrackMediaItem(tr, j)
      local s  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      if math.abs(s - t) <= EPS then
        items[#items+1] = it
      end
    end
  end
  return items
end
local function lock_items(items, lock_value)
  for _, it in ipairs(items) do
    reaper.SetMediaItemInfo_Value(it, "C_LOCK", lock_value and 1 or 0)
  end
end
-- ========= Per-track gap fill (bounded gap, no Razor) =========
-- Groups pasted items by track, then for each track:
--   1. Detect that track's own gap at the cursor.
--   2. If no gap → delete those items (skip this track).
--   3. Stretch right edge to that track's gap_end.
--   4. If FILL_SECONDARY_LEFT_EDGE=true, pull left edge back to that track's gap_start
--      (only when that gap_start is earlier than the item's current position AND the
--      item actually falls inside that gap). If the item falls outside the gap, delete.
--   5. Clear neighbor fades using that track's own gap boundaries.
-- The anchor track is treated identically to secondary tracks here so the logic
-- is uniform; caller is responsible for having already moved all items to anchor gap_start.
-- Returns: items_kept (flat list), n_skipped_tracks (integer).
local function apply_per_track_gap_fill(pasted, anchor_gap_start, track_gaps)
  -- Group pasted items by track
  local by_track = {}
  local track_order = {}
  for _, it in ipairs(pasted) do
    local tr = reaper.GetMediaItemTrack(it)
    if not by_track[tr] then
      by_track[tr] = {}
      track_order[#track_order+1] = tr
    end
    by_track[tr][#by_track[tr]+1] = it
  end
  local kept = {}
  local skipped_track_set = {}
  dbg("[gap-fill] anchor_gap_start=%.6f  tracks_with_pasted_items=%d", anchor_gap_start, #track_order)
  for _, tr in ipairs(track_order) do
    local tr_items = by_track[tr]
    -- Use the pre-paste gap snapshot. Re-detecting here would return nil because
    -- the pasted items are already sitting inside the gap at this point.
    local gap = track_gaps[tr]
    local gs = gap and gap.gs
    local ge = gap and gap.ge
    dbg("[gap-fill] track=%s  items=%d  gs=%s  ge=%s", trname(tr), #tr_items,
      gs and string.format("%.6f", gs) or "nil", ge and string.format("%.6f", ge) or "nil")
    for _, it in ipairs(tr_items) do
      dbg("[gap-fill]   pre  item pos=%.6f len=%.6f",
        reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
        reaper.GetMediaItemInfo_Value(it, "D_LENGTH"))
    end
    -- No gap on this track at the cursor → delete all pasted items on it.
    if not gs or not ge then
      dbg("[gap-fill]   -> DELETED (no gap snapshot for this track)")
      for _, it in ipairs(tr_items) do
        reaper.DeleteTrackMediaItem(tr, it)
      end
      skipped_track_set[tr] = true
    else
      -- Determine effective left edge for this track's items.
      local effective_left
      if FILL_SECONDARY_LEFT_EDGE then
        effective_left = gs   -- pull back to this track's own gap_start
      else
        effective_left = anchor_gap_start  -- all tracks share anchor left edge
      end
      -- When FILL_SECONDARY_LEFT_EDGE=true, check that the items (after the
      -- sync-preserving move that already happened) actually fall inside this
      -- track's gap. If the leftmost item landed at or past ge, the item is
      -- entirely outside this track's gap → delete.
      if FILL_SECONDARY_LEFT_EDGE then
        local leftmost_pos
        for _, it in ipairs(tr_items) do
          local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          if not leftmost_pos or s < leftmost_pos then leftmost_pos = s end
        end
        dbg("[gap-fill]   outside-gap check: leftmost_pos=%.6f  ge-EPS=%.6f",
          leftmost_pos or -1, ge - EPS)
        if leftmost_pos and leftmost_pos >= ge - EPS then
          dbg("[gap-fill]   -> DELETED (leftmost_pos >= ge, entirely outside this track's gap)")
          for _, it in ipairs(tr_items) do
            reaper.DeleteTrackMediaItem(tr, it)
          end
          skipped_track_set[tr] = true
          goto continue
        end
      end
      -- Stretch right edge to this track's gap_end.
      set_track_items_right(tr_items, ge)
      for _, it in ipairs(tr_items) do
        dbg("[gap-fill]   after right-stretch to ge=%.6f: pos=%.6f len=%.6f", ge,
          reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
          reaper.GetMediaItemInfo_Value(it, "D_LENGTH"))
      end
      -- Adjust left edge: always sync to this track's own gap_start when it
      -- differs from the item's current left position, in EITHER direction.
      -- A secondary track's gap_start can land later than the anchor's just
      -- as easily as earlier (its preceding item simply ends later) — only
      -- correcting the "expand backward" direction left items on tracks whose
      -- local gap starts later than the anchor's gap_start overlapping their
      -- own preceding item and sized against the wrong left edge. This was
      -- the source of the "right track, wrong sizing" bug in multi-track
      -- pastes where per-track gaps don't share the same left boundary.
      -- set_track_items_left() already handles both directions correctly
      -- (grow-left and shrink-from-left) via its delta math; the fix is
      -- simply calling it whenever gs and leftmost_pos disagree at all.
      if FILL_SECONDARY_LEFT_EDGE then
        local leftmost_pos
        for _, it in ipairs(tr_items) do
          local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          if not leftmost_pos or s < leftmost_pos then leftmost_pos = s end
        end
        dbg("[gap-fill]   left-adjust check: gs=%.6f  leftmost_pos=%.6f  |diff|=%.9f",
          gs, leftmost_pos or -1, math.abs(gs - (leftmost_pos or gs)))
        if leftmost_pos and math.abs(gs - leftmost_pos) > EPS then
          set_track_items_left(tr_items, gs)
        end
      end
      -- (when FILL_SECONDARY_LEFT_EDGE=false, left edge is already correct
      -- from the earlier move_items() call anchored to anchor_gap_start)
      -- Clear fades on pasted items and their neighbors.
      for _, it in ipairs(tr_items) do
        dbg("[gap-fill]   FINAL item pos=%.6f len=%.6f (gap was [%.6f, %.6f])",
          reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
          reaper.GetMediaItemInfo_Value(it, "D_LENGTH"), gs, ge)
        zero_fades_item_both_edges(it)
        kept[#kept+1] = it
      end
      local L = find_left_neighbor_at_time(tr, gs)
      local R = find_right_neighbor_at_time(tr, ge)
      if L then zero_fade_on_right_edge(L) end
      if R then zero_fade_on_left_edge(R) end
    end
    ::continue::
  end
  local n_skipped = 0
  for _ in pairs(skipped_track_set) do n_skipped = n_skipped + 1 end
  return kept, n_skipped
end
-- ========= Main =========
local function main()
  local cursor          = reaper.GetCursorPosition()
  local hadRazorAtStart = any_razor_exists()
  -- *** The clipboard probe MUST run before Undo_BeginBlock() and before any
  --     option state is mutated. clipboard_has_items() does its own paste+undo
  --     cycle; running it inside an open undo block would corrupt REAPER's undo
  --     history. We only guard the Razor path because it is the only path that
  --     performs destructive edits (item trimming) before the paste. ***
  if hadRazorAtStart then
    local Rmin_pre, Rmax_pre
    for i = 0, reaper.CountTracks(0)-1 do
      local tr = reaper.GetTrack(0, i)
      for _, a in ipairs(parse_track_razor(tr)) do
        if not a.isEnvelope then
          Rmin_pre = (Rmin_pre and math.min(Rmin_pre, a.start)) or a.start
          Rmax_pre = (Rmax_pre and math.max(Rmax_pre, a.finish)) or a.finish
        end
      end
    end
    if Rmin_pre and Rmax_pre and Rmax_pre > Rmin_pre then
      if not clipboard_has_items() then
        -- Bail before opening any undo block — nothing has been modified.
        reaper.ShowMessageBox("Clipboard is empty. No items were modified.", "Special Paste", 0)
        return
      end
    end
  end
  -- Non-Razor path: probe which track(s) a real paste will land on BEFORE
  -- opening the undo block (same constraint as clipboard_has_items() above —
  -- this does its own paste+undo cycle). This is also our empty-clipboard
  -- check for the non-Razor path, so it doubles as that guard.
  local probe_has_items, probe_dest_tracks
  if not hadRazorAtStart then
    probe_has_items, probe_dest_tracks = probe_paste_destination()
    dbg("[probe] has_items=%s  dest_tracks=%d", tostring(probe_has_items), #probe_dest_tracks)
    for _, tr in ipairs(probe_dest_tracks) do dbg("[probe]   -> %s", trname(tr)) end
    if not probe_has_items then
      reaper.ShowMessageBox("Clipboard is empty. No items were modified.", "Special Paste", 0)
      return
    end
  end
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  local view_snap   = snapshot_arrange_view()
  local ripple_snap = snapshot_and_force_ripple_off()
  local edit_snap   = snapshot_and_disable_edit_collateral()
  local razor_snap  = hadRazorAtStart and snapshot_razors() or nil
  local function cleanup_end(msg)
    if hadRazorAtStart then
      if razor_snap then restore_razors(razor_snap) end
    else
      clear_all_razors()
    end
    restore_edit_collateral(edit_snap)
    restore_ripple_mode(ripple_snap)
    restore_arrange_view(view_snap)
    reaper.UpdateArrange()
    reaper.PreventUIRefresh(-1)
    -- Undo block is sealed here. Any ShowMessageBox call after cleanup_end()
    -- therefore describes an already-committed (or already-cancelled) operation,
    -- which is intentional: the dialog is informational, not a confirmation gate.
    reaper.Undo_EndBlock(msg or "Special Paste", -1)
  end
  if hadRazorAtStart then
    local Rmin, Rmax, razor_tracks = get_overall_razor_range()
    if not (Rmin and Rmax) or Rmax <= Rmin then
      cleanup_end("Special Paste: invalid Razor range"); return
    end
    -- Clipboard was already verified non-empty above (before undo block opened).
    trim_items_in_range(razor_tracks, Rmin, Rmax)
    reaper.SetEditCurPos(Rmin, false, false)
    local before = collect_all_items_guid_set()
    reaper.Main_OnCommand(40058, 0)
    local pasted = diff_new_items(before)
    reaper.SetEditCurPos(cursor, false, false)
    if #pasted == 0 then cleanup_end("Special Paste (Razor): nothing pasted"); return end
    local block_start = select(1, get_block_bounds(pasted))
    move_items(pasted, Rmin - block_start)
    set_block_right(pasted, Rmax)
    for _, it in ipairs(pasted) do zero_fades_item_both_edges(it) end
    for _, tr in ipairs(razor_tracks) do
      local L = find_left_neighbor_at_time(tr, Rmin)
      local R = find_right_neighbor_at_time(tr, Rmax)
      if L then zero_fade_on_right_edge(L) end
      if R then zero_fade_on_left_edge(R) end
    end
    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(pasted) do reaper.SetMediaItemSelected(it, true) end
    reaper.SetEditCurPos(Rmin, false, false)
    cleanup_end("Special Paste (fill Razor; cursor to start; overlap-safe)")
    return
  end
  -- No Razor at start → over-body vs gap.
  -- Anchor track = the topmost track the pre-flight probe (above, before the
  -- undo block opened) observed a real paste actually landing on. This is
  -- ground truth, not a guess, so it can't diverge from where the real paste
  -- below will land.
  local anchor_tr = probe_dest_tracks[1]
  if not anchor_tr then
    -- Seal the undo block first (cleanup_end), then show the dialog.
    cleanup_end("Special Paste: no anchor track")
    reaper.ShowMessageBox("No anchor track found (hover/select a track, or select an item).", "Special Paste", 0)
    return
  end
  dbg("[anchor] using %s as anchor track (probe result)", trname(anchor_tr))
  local over_body = cursor_over_item_body(anchor_tr, cursor)
  local gap_start, gap_end = get_gap_around_time_on_track(anchor_tr, cursor)
  dbg("=== Special Paste run ===")
  dbg("cursor=%.6f  anchor_tr=%s  over_body=%s  gap_start=%s  gap_end=%s",
    cursor, trname(anchor_tr), tostring(over_body),
    gap_start and string.format("%.6f", gap_start) or "nil",
    gap_end and string.format("%.6f", gap_end) or "nil")
  -- Edge flags (relative to anchor track).
  -- gap_start/gap_end are nil for zero-width gaps, so both flags correctly
  -- remain false in that case without needing additional downstream guards.
  local on_left_edge, on_right_edge = false, false
  if gap_start and gap_end then
    on_left_edge  = math.abs(gap_start - cursor) <= EPS
    on_right_edge = math.abs(gap_end   - cursor) <= EPS
  end
  if over_body then
    reaper.SetEditCurPos(cursor, false, false)
    local before = collect_all_items_guid_set()
    reaper.Main_OnCommand(40058, 0)
    local pasted = diff_new_items(before)
    if #pasted == 0 then cleanup_end("Special Paste: nothing pasted"); return end
    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(pasted) do reaper.SetMediaItemSelected(it, true); zero_fades_item_both_edges(it) end
    -- Clear boundary fades on neighbors we abut
    for _, it in ipairs(pasted) do
      local tr = reaper.GetMediaItemTrack(it)
      local s  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local e  = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local Ls = find_left_neighbor_at_time(tr, s)
      local Rs = find_right_neighbor_at_time(tr, s)
      local Le = find_left_neighbor_at_time(tr, e)
      local Re = find_right_neighbor_at_time(tr, e)
      if Ls then zero_fade_on_right_edge(Ls) end
      if Rs then zero_fade_on_left_edge(Rs) end
      if Le then zero_fade_on_right_edge(Le) end
      if Re then zero_fade_on_left_edge(Re) end
    end
    local start = select(1, get_block_bounds(pasted))
    if start then reaper.SetEditCurPos(start, false, false) end
    cleanup_end("Special Paste (over item body; select pasted only; neighbor fades cleared)")
    return
  end
  -- LEFT-FILL ONLY (based on anchor track): cursor flush with right neighbor's LEFT edge
  if gap_start and gap_end and on_right_edge and not on_left_edge then
    -- Lock ALL items on ALL tracks that start at the cursor to prevent displacement
    local items_to_lock = collect_items_starting_at_time_on_all_tracks(cursor)
    local previous_locks = {}
    for _, it in ipairs(items_to_lock) do
      previous_locks[it] = reaper.GetMediaItemInfo_Value(it, "C_LOCK")
    end
    lock_items(items_to_lock, true)
    reaper.SetEditCurPos(cursor, false, false)
    local before = collect_all_items_guid_set()
    reaper.Main_OnCommand(40058, 0)
    local pasted = diff_new_items(before)
    if #pasted == 0 then
      for it, was in pairs(previous_locks) do reaper.SetMediaItemInfo_Value(it, "C_LOCK", was or 0) end
      cleanup_end("Special Paste: nothing pasted"); return
    end
    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(pasted) do reaper.SetMediaItemSelected(it, true); zero_fades_item_both_edges(it) end
    -- For each pasted item, expand LEFT to that track's own gap start.
    -- NOTE: D_STARTOFFS is not modified. Source material offset is preserved
    -- relative to the item's internal origin, not its absolute playback position.
    -- Tracks whose gap geometry doesn't match the cursor are collected into a
    -- set keyed by track pointer so each skipped track is counted exactly once,
    -- regardless of how many items were pasted onto it.
    local skipped_track_set = {}
    for _, it in ipairs(pasted) do
      local tr = reaper.GetMediaItemTrack(it)
      local gs, ge = get_gap_around_time_on_track(tr, cursor)
      if gs and ge and math.abs(ge - cursor) <= EPS and gs <= cursor - EPS then
        reaper.SetMediaItemInfo_Value(it, "D_POSITION", gs)
        reaper.SetMediaItemInfo_Value(it, "D_LENGTH", math.max(MIN_ITEM_LEN, cursor - gs))
        local L = find_left_neighbor_at_time(tr, gs)
        local R = find_right_neighbor_at_time(tr, cursor)
        if L then zero_fade_on_right_edge(L) end
        if R then zero_fade_on_left_edge(R) end
      else
        skipped_track_set[tr] = true
      end
    end
    -- Restore locks
    for it, was in pairs(previous_locks) do
      reaper.SetMediaItemInfo_Value(it, "C_LOCK", was or 0)
    end
    local start = select(1, get_block_bounds(pasted))
    if start then reaper.SetEditCurPos(start, false, false) end
    local n_skipped = 0
    for _ in pairs(skipped_track_set) do n_skipped = n_skipped + 1 end
    local label = "Special Paste (left-fill multi-track; neighbors locked; source start preserved)"
    if n_skipped > 0 then
      label = label .. string.format(" [%d track(s) skipped: gap mismatch]", n_skipped)
    end
    cleanup_end(label)
    return
  end
  -- Bounded gap (fit to gap on anchor track; if on left edge only, fill right side).
  -- Per-track gap fill: each track's pasted items are stretched to fill that track's
  -- own gap. Secondary tracks with no gap at the cursor have their items deleted.
  if gap_start and gap_end and gap_end > gap_start then
    dbg("[bounded-gap] entering per-track gap-fill branch. on_left_edge=%s on_right_edge=%s",
      tostring(on_left_edge), tostring(on_right_edge))
    local effective_gap_start = gap_start
    if on_left_edge and not on_right_edge then effective_gap_start = cursor end
    dbg("[bounded-gap] effective_gap_start=%.6f", effective_gap_start)
    -- Snapshot each track's gap BEFORE the paste. apply_per_track_gap_fill() must
    -- use this snapshot rather than re-detecting after the paste, because the pasted
    -- items occupy the gap at that point and get_gap_around_time_on_track() would
    -- return nil, causing the items to be incorrectly treated as skipped and deleted.
    local track_gaps = {}
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      local gs, ge = get_gap_around_time_on_track(tr, cursor)
      if gs and ge then
        track_gaps[tr] = {gs = gs, ge = ge}
        dbg("[bounded-gap] pre-paste snapshot track=%s gs=%.6f ge=%.6f", trname(tr), gs, ge)
      end
    end
    -- Lock right neighbors on ALL tracks before pasting. If the clipboard item is
    -- longer than a track's gap, REAPER's native paste would delete or damage the
    -- right neighbor. Locking prevents that; the pasted item is resized to gap_end
    -- afterward by apply_per_track_gap_fill(). We lock across all tracks (not just
    -- the anchor) because secondary tracks are subject to the same collateral risk.
    local right_neighbor_locks = {}
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      local gap = track_gaps[tr]
      if gap then
        local rn = find_right_neighbor_at_time(tr, gap.ge)
        if rn and not right_neighbor_locks[rn] then
          right_neighbor_locks[rn] = reaper.GetMediaItemInfo_Value(rn, "C_LOCK")
          reaper.SetMediaItemInfo_Value(rn, "C_LOCK", 1)
        end
      end
    end
    reaper.SetEditCurPos(effective_gap_start, false, false)
    local before = collect_all_items_guid_set()
    reaper.Main_OnCommand(40058, 0)
    -- Restore right neighbor locks immediately after paste, before any resizing.
    for rn, was in pairs(right_neighbor_locks) do
      reaper.SetMediaItemInfo_Value(rn, "C_LOCK", was)
    end
    local pasted = diff_new_items(before)
    reaper.SetEditCurPos(cursor, false, false)
    if #pasted == 0 then cleanup_end("Special Paste: nothing pasted"); return end
    dbg("[bounded-gap] pasted %d item(s) from native paste", #pasted)
    for _, it in ipairs(pasted) do
      dbg("[bounded-gap]   raw pasted item track=%s pos=%.6f len=%.6f", trname(reaper.GetMediaItemTrack(it)),
        reaper.GetMediaItemInfo_Value(it, "D_POSITION"), reaper.GetMediaItemInfo_Value(it, "D_LENGTH"))
    end
    -- Sync-preserving move: shift all pasted items so the block's leftmost edge
    -- aligns to the anchor track's effective gap_start. This preserves the
    -- relative timeline offsets between all items (inter-item sync).
    local block_start = select(1, get_block_bounds(pasted))
    dbg("[bounded-gap] block_start=%.6f  move delta=%.6f", block_start, effective_gap_start - block_start)
    move_items(pasted, effective_gap_start - block_start)
    -- Per-track right/left edge fill. Neighbor fades are cleared inside this call.
    local kept, n_skipped = apply_per_track_gap_fill(pasted, effective_gap_start, track_gaps)
    reaper.SelectAllMediaItems(0, false)
    for _, it in ipairs(kept) do reaper.SetMediaItemSelected(it, true) end
    local start = select(1, get_block_bounds(kept))
    if start then reaper.SetEditCurPos(start, false, false) end
    local left_mode = FILL_SECONDARY_LEFT_EDGE and "per-track left" or "anchor left"
    local label = string.format(
      "Special Paste (fit gap per-track; %s; inter-item sync preserved)", left_mode)
    if n_skipped > 0 then
      label = label .. string.format(" [%d track(s) skipped: no gap]", n_skipped)
    end
    cleanup_end(label)
    return
  end
  -- No bounded gap: paste at cursor as-is
  reaper.SetEditCurPos(cursor, false, false)
  local before = collect_all_items_guid_set()
  reaper.Main_OnCommand(40058, 0)
  local pasted = diff_new_items(before)
  if #pasted == 0 then cleanup_end("Special Paste: nothing pasted"); return end
  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(pasted) do reaper.SetMediaItemSelected(it, true); zero_fades_item_both_edges(it) end
  local start = select(1, get_block_bounds(pasted))
  if start then reaper.SetEditCurPos(start, false, false) end
  cleanup_end("Special Paste (no bounded gap; cursor to pasted start; source start preserved)")
end
main()
