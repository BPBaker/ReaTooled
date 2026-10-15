-- @description ReaTooled - Extend time selection + razor area to next (right) transient or item edge (gap-aware)
-- @version 1.5.2
-- @date 2025.10.11
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Depending on the state of the ReaTooled Toggle Tab to Transient button,
--   # this script creates or extends a time selection + razor area to the next (right) transient or item edge.
--   # It replicates SHIFT+TAB / SHIFT+' behavior from Pro Tools, with gap-aware stepping.
-- CHANGELOG
-- v1.5.2   - FIX: function order (get_target_tracks defined before use) + all locals.
-- v1.5.1   - FIX: order for merge_or_replace_track_area to avoid nil-call; kept fade/crossfade rules.
-- v1.5.0   - ITEM-EDGE RULES: stops at item start, fade-in end, crossfade start/end, fade-out start, item end.
-- v1.4.7   - VIEWFIX: removed EnsureNotCompletelyOffscreen; robust follow using GetSet_ArrangeView2 only.
-- v1.4.6   - VIEWFIX: correct GetSet_ArrangeView2 arg/return usage (read/write).

----------------------------------
-- USER CONFIG
----------------------------------
local MERGE_TRACK_AREAS       = true
local SELECT_ITEMS_WITHIN_TS  = true
local DEBUG_LOG_VIEWCHECK     = false
local EPS                     = 1e-9

----------------------------------
-- Utilities
----------------------------------
local reaper = reaper

-- ========== VIEW HELPERS ==========
local function read_view()
  local s, e = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
  if type(s) == "number" and type(e) == "number" and e > s then
    return s, e, (e - s)
  end
  return nil, nil, nil
end

local function set_view_center(pos, width)
  if type(pos) ~= "number" or pos ~= pos or type(width) ~= "number" or width <= 0 then return end
  local start_t = pos - width * 0.5
  local end_t   = pos + width * 0.5
  if start_t < 0 then end_t = end_t - start_t; start_t = 0 end
  reaper.CSurf_OnScroll(0, 0) -- tiny nudge for smooth refresh
  reaper.GetSet_ArrangeView2(0, true, 0, 0, start_t, end_t)
  reaper.UpdateArrange()
end

local function ensure_time_visible(pos, cached_width, debug_tag)
  if type(pos) ~= "number" or pos ~= pos then return end
  reaper.UpdateArrange()
  local s, e, w = read_view()

  if not (w and w > 0) then
    w = (type(cached_width) == "number" and cached_width > 0) and cached_width or nil
    if not w then
      local _, _, w2 = read_view()
      w = (w2 and w2 > 0) and w2 or 4.0 -- last resort width
    end
  end

  if not (s and e) then s, e = pos - w * 0.5, pos + w * 0.5 end
  local margin = w * 0.05
  local off = (pos < (s + margin) or pos > (e - margin))

  if DEBUG_LOG_VIEWCHECK and debug_tag then
    reaper.ShowConsoleMsg(string.format(
      "[%s] view=[%.9f..%.9f] w=%.9f pos=%.9f offscreen=%s\n",
      debug_tag, s or -1, e or -1, w or -1, pos, off and "YES" or "NO"))
  end

  if off then set_view_center(pos, w) end
end

-- ========== ITEM / FADE HELPERS ==========
local function get_fade_in_len(item)
  local a = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO") or 0
  local m = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN") or 0
  return (a > 0 and a) or m
end

local function get_fade_out_len(item)
  local a = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO") or 0
  local m = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") or 0
  return (a > 0 and a) or m
end

-- ========== BOUNDARY COLLECTION (items, fades, crossfades) ==========
local function collect_boundaries_for_track(track, add_pos)
  local n = reaper.CountTrackMediaItems(track)
  if n == 0 then return end

  local items = {}
  for i = 0, n - 1 do
    local it   = reaper.GetTrackMediaItem(track, i)
    local pos  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local endp = pos + len
    local fi   = get_fade_in_len(it)
    local fo   = get_fade_out_len(it)
    items[#items+1] = {
      pos = pos, endpos = endp,
      fi_end = pos + fi, fo_start = endp - fo,
      has_fi = fi > 0, has_fo = fo > 0
    }
  end

  table.sort(items, function(a, b) return a.pos < b.pos end)
  for _, it in ipairs(items) do
    add_pos(it.pos)                          -- item start
    if it.has_fi then add_pos(it.fi_end) end -- fade-in end
    if it.has_fo then add_pos(it.fo_start) end -- fade-out start
    add_pos(it.endpos)                       -- item end
  end

  -- Crossfades (overlap start/end)
  for i = 1, #items - 1 do
    local A, B = items[i], items[i + 1]
    local overlap_start = math.max(A.pos, B.pos)
    local overlap_end   = math.min(A.endpos, B.endpos)
    if overlap_end > overlap_start then
      add_pos(overlap_start) -- crossfade start
      add_pos(overlap_end)   -- crossfade end
    end
  end
end

local function collect_boundaries_for_tracks(tracks)
  local positions, seen = {}, {}
  local function add_pos(p)
    local key = string.format("%.12f", p)
    if not seen[key] then seen[key] = true; positions[#positions+1] = p end
  end
  for _, tr in ipairs(tracks) do collect_boundaries_for_track(tr, add_pos) end
  table.sort(positions)
  return positions
end

local function find_next_boundary(sorted_positions, refPos)
  for _, p in ipairs(sorted_positions) do
    if p > refPos + EPS then return p end
  end
  return nil
end

-- ========== RAZOR HELPERS ==========
local function parse_razor_triplets(s)
  local out = {}
  if not s or s == "" then return out end
  local tok = {}
  for w in s:gmatch("%S+") do tok[#tok+1] = w end
  local i = 1
  while i + 2 <= #tok do
    local a = tonumber(tok[i]); local b = tonumber(tok[i+1]); local c = tok[i+2] or ""
    if a and b then out[#out+1] = {a=a, b=b, tag=c} end
    i = i + 3
  end
  return out
end

local function is_track_area_tag(tag)
  return tag == nil or tag == "" or tag == '""'
end

local function triplets_to_string(trips)
  local parts = {}
  for _, t in ipairs(trips) do
    local tag = t.tag or ""
    parts[#parts+1] = string.format("%0.17f %0.17f %s", t.a, t.b, tag)
  end
  return table.concat(parts, " ")
end

-- ✅ ensure this is defined BEFORE write_razor_to_targets / get_global_razor_bounds
local function get_target_tracks()
  local tracks = {}
  local sel = reaper.CountSelectedTracks(0)
  if sel > 0 then
    for i = 0, sel-1 do tracks[#tracks+1] = reaper.GetSelectedTrack(0, i) end
  else
    local n = reaper.CountTracks(0)
    for i = 0, n-1 do tracks[#tracks+1] = reaper.GetTrack(0, i) end
  end
  return tracks
end

local function merge_or_replace_track_area(trips, ns, ne, do_merge)
  local non_track, track_areas = {}, {}
  for _, t in ipairs(trips) do
    if is_track_area_tag(t.tag) then
      track_areas[#track_areas+1] = {a=t.a, b=t.b, tag='""'}
    else
      non_track[#non_track+1] = t
    end
  end

  if not do_merge then
    local out = { {a=ns, b=ne, tag='""'} }
    for _, t in ipairs(non_track) do out[#out+1] = t end
    return out
  end

  track_areas[#track_areas+1] = {a=ns, b=ne, tag='""'}
  table.sort(track_areas, function(x,y) return x.a < y.a end)
  local merged = {}
  for _, seg in ipairs(track_areas) do
    if #merged == 0 then
      merged[1] = {a=seg.a, b=seg.b, tag='""'}
    else
      local last = merged[#merged]
      if seg.a <= last.b + EPS then
        if seg.b > last.b then last.b = seg.b end
      else
        merged[#merged+1] = {a=seg.a, b=seg.b, tag='""'}
      end
    end
  end

  local out = {}
  for _, t in ipairs(merged) do out[#out+1] = t end
  for _, t in ipairs(non_track) do out[#out+1] = t end
  return out
end

local function write_razor_to_targets(tsA, tsB)
  local tracks = get_target_tracks()
  for _, tr in ipairs(tracks) do
    local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    local trips = parse_razor_triplets(ok and s or "")
    local new_trips = merge_or_replace_track_area(trips, tsA, tsB, MERGE_TRACK_AREAS)
    reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", triplets_to_string(new_trips), true)
  end
end

local function get_global_razor_bounds()
  local tracks = get_target_tracks()
  local gA, gB = math.huge, -math.huge
  for _, tr in ipairs(tracks) do
    local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if ok and s and s ~= "" then
      for _, tri in ipairs(parse_razor_triplets(s)) do
        if is_track_area_tag(tri.tag) then
          if tri.a < gA then gA = tri.a end
          if tri.b > gB then gB = tri.b end
        end
      end
    end
  end
  if gB > gA and gA < math.huge then return gA, gB end
  return nil, nil
end

local function sync_ts_to_razor_if_needed()
  local tsA, tsB = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local rA, rB = get_global_razor_bounds()
  if not rA or not rB then return end
  local ts_empty = not (tsB > tsA)
  local ts_diff  = (math.abs((tsA or 0) - rA) > EPS) or (math.abs((tsB or 0) - rB) > EPS)
  if ts_empty or ts_diff then
    reaper.GetSet_LoopTimeRange(true, false, rA, rB, false)
  end
end

----------------------------------
-- Main
----------------------------------
local function main()
  local _, _, init_w = read_view()

  -- Link: loop points linked to time selection?
  local LINK_CMD = 40041
  local link_is_on = (reaper.GetToggleCommandStateEx(0, LINK_CMD) == 1)
  local lp0A, lp0B = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  sync_ts_to_razor_if_needed()

  local tracks = get_target_tracks()
  local curpos = reaper.GetCursorPosition()
  local tsA, tsB = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local had_ts   = (tsB > tsA)
  local anchorA  = had_ts and tsA or curpos
  local refPos   = had_ts and tsB or curpos

  local toggle_cmd = reaper.NamedCommandLookup("_RSf475a3ed46e25a1ef9d2a8b4ad6aab87c94102a1")
  local transient  = (toggle_cmd ~= 0) and (reaper.GetToggleCommandStateEx(0, toggle_cmd) == 1) or false

  local undo_label  = ""

  if transient then
    -- TRANSIENT PATH
    reaper.SetEditCurPos2(0, refPos, false, false)

    -- Select context items overlapping refPos
    reaper.Main_OnCommand(40289, 0)
    for _, tr in ipairs(tracks) do
      local n = reaper.CountTrackMediaItems(tr)
      for i=0,n-1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        local s  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local e  = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if s - EPS <= refPos and e > refPos + EPS then reaper.SetMediaItemSelected(it, true) end
      end
    end
    if not had_ts then
      reaper.GetSet_LoopTimeRange(true, false, anchorA, anchorA, false)
    end

    local preA, preB = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    reaper.Main_OnCommand(40802, 0) -- extend to next transient

    reaper.Main_OnCommand(40289, 0) -- clear selection

    local postA, postB = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if (postB > postA) and (postB > preB + EPS) then
      tsA, tsB = postA, postB
      undo_label = "Extend TS/Razor to next transient (right)"
    else
      -- Fallback to items/fades/crossfades rules
      local positions = collect_boundaries_for_tracks(tracks)
      local boundary  = find_next_boundary(positions, refPos)
      if boundary then
        tsA = had_ts and tsA or anchorA
        tsB = boundary
        reaper.GetSet_LoopTimeRange(true, false, tsA, tsB, false)
        undo_label = "Extend TS/Razor to next edge (fallback)"
      else
        undo_label = "Create rightward TS/Razor (no-op: no next boundary)"
      end
    end

  else
    -- ITEMS / FADES / CROSSFADES RULES (unified)
    local positions = collect_boundaries_for_tracks(tracks)
    local boundary  = find_next_boundary(positions, had_ts and tsB or curpos)

    if boundary then
      tsA = had_ts and tsA or curpos
      tsB = boundary
      reaper.GetSet_LoopTimeRange(true, false, tsA, tsB, false)
      undo_label = "Extend TS/Razor to next edge"
    else
      undo_label = "Create rightward TS/Razor (no-op: no next boundary)"
    end
  end

  -- If TS is empty, finish
  local fA, fB = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if not (fB > fA) then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(undo_label, -1)
    return
  end

  -- Write Razor to targets
  write_razor_to_targets(fA, fB)

  -- Final item selection behavior
  if SELECT_ITEMS_WITHIN_TS then
    reaper.Main_OnCommand(40718, 0)
  end

  -- Restore loop points if link was off; clear time selection
  if not link_is_on then
    reaper.GetSet_LoopTimeRange(true, true, lp0A or 0, lp0B or 0, false)
  end
  reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(undo_label, -1)

  -- Follow the final Razor right edge if off-screen (purely visual)
  local rA2, rB2 = get_global_razor_bounds()
  local follow_pos = rB2 or fB or reaper.GetCursorPosition()
  ensure_time_visible(follow_pos, init_w, "final-check")
  reaper.UpdateArrange()
end

main()
