-- @description ReaTooled - Extend Razor Areas Upward or Create From Items/TS (track-aware)
-- @version 1.4.1
-- @date 2025.09.01
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Behavior priority:
--     1) If any Razor Edit(s) exist on any track:
--          - Extend those exact track-area Razor segments (guid == "") to the track(s) directly above
--            the tracks that have them. (Optionally propagate env/item GUID segments if enabled.)
--     2) Else, if items are selected:
--          - Create Razor segments that match each selected item (per-item, per-track),
--            and also apply those segments to the track(s) directly above.
--     3) Else, if a time selection exists and it intersects selected items:
--          - For each selected item, create a Razor segment from the intersection of
--            the item bounds and the time selection, then mirror to the track(s) above.
--   Finish rules (family-consistent):
--     • Always clear the Time Selection at the end.
--     • If LINK is OFF, restore Loop Points to their original position (Razor edits remain).
--     • If LINK is ON, clearing TS will also clear LP (we do not toggle LINK).
-- @changelog
--   v1.4.1 - Ported 1.3.8 robustness:
--            • Track-area–only semantics by default; safe GUID handling (configurable).
--            • Hardened Razor parsing; per-track track-area MERGE/UNION with EPS tolerance; preserve non-track triplets.
--            • De-dupe & accumulate per-destination when multiple carriers target the same track.
--            • Selection hygiene for TS∩selected-items (no selection-set slots).
--            • Family finish: clear TS; restore LP if LINK is OFF.
--   v1.4 - Implemented three-stage logic: (1) extend existing Razor(s) upward, (2) else create per-item Razor(s) upward,
--          (3) else create intersection-of-TS-and-selected-items Razor(s) upward. Works with or without selected tracks.
--   v1.3 - Properly extends when Razor Edits already exist: parses existing RE segments and applies them vertically.
--   v1.2 - Extends razor edit area to the track(s) above the selected track(s). If no time selection or razor area exists, creates from selected items.

local reaper = reaper

----------------------------------
-- CONFIG
----------------------------------
local APPEND_ON_DEST            = true        -- true: append to destination tracks (with merge); false: replace track-areas (preserve non-track)
local MERGE_TRACK_AREAS         = true        -- union overlapping/adjacent track-area segments
local COPY_ENV_ITEM_SEGMENTS    = false       -- false: only propagate track-area (guid == ""); true: also copy env/item GUID segments verbatim
local EPS                       = 1e-9

----------------------------------
-- Helpers
----------------------------------
local function split_tokens(s)
  local t = {}
  for tok in string.gmatch(s or "", "%S+") do t[#t+1] = tok end
  return t
end

-- Triplet shape: {a=number, b=number, tag=string}
local function parse_razor_triplets(s)
  local out = {}
  if not s or s == "" then return out end
  local tok = split_tokens(s)
  local i = 1
  while i + 2 <= #tok do
    local a = tonumber(tok[i]); local b = tonumber(tok[i+1]); local tag = tok[i+2] or ""
    if a and b then out[#out+1] = {a=a, b=b, tag=tag} end
    i = i + 3
  end
  return out
end

local function triplets_to_string(trips)
  local parts = {}
  for _, t in ipairs(trips) do
    parts[#parts+1] = string.format("%0.17f %0.17f %s", t.a, t.b, t.tag or '""')
  end
  return table.concat(parts, " ")
end

local function is_track_area_tag(tag)
  return tag == nil or tag == "" or tag == '""'
end

local function get_track_triplets(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  return parse_razor_triplets(ok and s or "")
end

-- Merge/union track-area segments (non-track segments are preserved as-is)
local function merge_track_area_segments(existing_trips, added_area_trips, do_merge)
  -- separate
  local non_track, areas = {}, {}
  for _, t in ipairs(existing_trips or {}) do
    if is_track_area_tag(t.tag) then areas[#areas+1] = {a=t.a, b=t.b, tag='""'} else non_track[#non_track+1] = t end
  end
  for _, t in ipairs(added_area_trips or {}) do
    if is_track_area_tag(t.tag) then areas[#areas+1] = {a=t.a, b=t.b, tag='""'} end
  end

  if not do_merge then
    -- Replace track-areas entirely with added_area_trips; keep non-track
    local out = {}
    for _, t in ipairs(added_area_trips or {}) do out[#out+1] = {a=t.a, b=t.b, tag='""'} end
    for _, t in ipairs(non_track) do out[#out+1] = t end
    return out
  end

  table.sort(areas, function(x,y) return x.a < y.a end)
  local merged = {}
  for _, seg in ipairs(areas) do
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

local function append_or_replace_triplets(dest_tr, added_area_trips, append_mode, do_merge, maybe_copy_guid_trips)
  -- Build the final set to write:
  --   - Start from existing trips
  --   - If APPEND: union track-areas with added_area_trips (merge option)
  --   - If REPLACE: replace track-areas with added_area_trips; preserve existing non-track
  --   - Optionally append GUID trips verbatim (no merging with track-areas)
  local existing = get_track_triplets(dest_tr)
  local final = {}

  -- Separate GUID trips to optionally copy
  local guid_trips = {}
  if maybe_copy_guid_trips and #maybe_copy_guid_trips > 0 and COPY_ENV_ITEM_SEGMENTS then
    for _, t in ipairs(maybe_copy_guid_trips) do
      if not is_track_area_tag(t.tag) then guid_trips[#guid_trips+1] = t end
    end
  end

  if append_mode then
    final = merge_track_area_segments(existing, added_area_trips, do_merge)
  else
    -- replace track-areas, preserve existing non-track
    final = merge_track_area_segments(existing, added_area_trips, false)
  end

  -- Append GUID trips verbatim (no de-dup beyond exact triplet text)
  for _, t in ipairs(guid_trips) do final[#final+1] = t end

  reaper.GetSetMediaTrackInfo_String(dest_tr, "P_RAZOREDITS", triplets_to_string(final), true)
end

local function count_tracks()
  return reaper.CountTracks(0)
end

local function get_track_by_idx1(idx1)
  if idx1 < 1 then return nil end
  return reaper.GetTrack(0, idx1 - 1)
end

local function get_idx1(tr)
  return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
end

-- Collect all tracks that currently have any Razor segments
local function collect_tracks_with_razors()
  local tracks = {}
  for i = 0, count_tracks() - 1 do
    local tr = reaper.GetTrack(0, i)
    local trips = get_track_triplets(tr)
    if #trips > 0 then
      tracks[#tracks+1] = {track=tr, trips=trips}
    end
  end
  return tracks
end

-- Items
local function collect_selected_items_grouped_by_track()
  local by_track = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tr = reaper.GetMediaItem_Track(it)
    if tr then
      by_track[tr] = by_track[tr] or {}
      by_track[tr][#by_track[tr] + 1] = it
    end
  end
  return by_track
end

local function seg_from_bounds(a, b) if b > a + EPS then return {a=a, b=b, tag='""'} end end

local function segments_from_items(items)
  local segs = {}
  for _, it in ipairs(items) do
    local a = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local b = a + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local seg = seg_from_bounds(a, b)
    if seg then segs[#segs+1] = seg end
  end
  return segs
end

local function segments_from_ts_item_intersections(items, ts_a, ts_b)
  local segs = {}
  if not (ts_b > ts_a) then return segs end
  for _, it in ipairs(items) do
    local ia = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local ib = ia + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local a = math.max(ts_a, ia)
    local b = math.min(ts_b, ib)
    local seg = seg_from_bounds(a, b)
    if seg then segs[#segs+1] = seg end
  end
  return segs
end

local function any_segments_exist()
  for i = 0, count_tracks() - 1 do
    local tr = reaper.GetTrack(0, i)
    local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if ok and s ~= "" then return true end
  end
  return false
end

----------------------------------
-- Main
----------------------------------
local function main()
  -- Finish-state bookkeeping (family-consistent)
  local LINK_CMD = 40041
  local link_is_on = (reaper.GetToggleCommandStateEx(0, LINK_CMD) == 1)
  local lp0A, lp0B = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local did_anything = false

  local ts_a, ts_b = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local have_ts = (ts_b > ts_a)

  if any_segments_exist() then
    -- Case 1: Extend existing Razor(s) upward (track-area only by default)
    local carriers = collect_tracks_with_razors()
    -- Accumulate per destination to avoid multiple writes & allow de-dupe/merge
    local dest_add = {}          -- map<track* -> {area_trips={}, guid_trips={}}>
    local function ensure_dest(tr)
      if not dest_add[tr] then dest_add[tr] = {area={}, guid={}} end
      return dest_add[tr]
    end

    for _, entry in ipairs(carriers) do
      local tr = entry.track
      local trips = entry.trips
      local idx1 = get_idx1(tr)
      if idx1 > 1 then
        local above = get_track_by_idx1(idx1 - 1)
        if above then
          local bucket = ensure_dest(above)
          for _, t in ipairs(trips) do
            if is_track_area_tag(t.tag) then
              bucket.area[#bucket.area+1] = {a=t.a, b=t.b, tag='""'}
            elseif COPY_ENV_ITEM_SEGMENTS then
              bucket.guid[#bucket.guid+1] = t
            end
          end
          did_anything = true
        end
      end
    end

    -- Apply to each destination (append/replace semantics; merge track-areas; preserve non-track)
    for dest_tr, packs in pairs(dest_add) do
      append_or_replace_triplets(dest_tr, packs.area, APPEND_ON_DEST, MERGE_TRACK_AREAS, packs.guid)
    end

  else
    -- Case 2: selected items → per-item segments (mirror up)
    local by_track = collect_selected_items_grouped_by_track()
    local total_items = 0
    for _, items in pairs(by_track) do total_items = total_items + #items end

    if total_items > 0 then
      for tr, items in pairs(by_track) do
        local segs = segments_from_items(items)
        if #segs > 0 then
          -- Apply to source (always append+merge for source)
          append_or_replace_triplets(tr, segs, true, MERGE_TRACK_AREAS, nil)
          -- Apply to track above
          local idx1 = get_idx1(tr)
          if idx1 > 1 then
            local above = get_track_by_idx1(idx1 - 1)
            if above then append_or_replace_triplets(above, segs, APPEND_ON_DEST, MERGE_TRACK_AREAS, nil) end
          end
          did_anything = true
        end
      end

    elseif have_ts then
      -- Case 3: TS ∩ selected-items (mirror up). Requires selected items by spec.
      -- If no selected items, nothing to do.
      -- We do not auto-select; we intersect TS with currently selected items only.
      local acted = false
      for tr, items in pairs(by_track) do
        if #items > 0 then
          local segs = segments_from_ts_item_intersections(items, ts_a, ts_b)
          if #segs > 0 then
            append_or_replace_triplets(tr, segs, true, MERGE_TRACK_AREAS, nil)
            local idx1 = get_idx1(tr)
            if idx1 > 1 then
              local above = get_track_by_idx1(idx1 - 1)
              if above then append_or_replace_triplets(above, segs, APPEND_ON_DEST, MERGE_TRACK_AREAS, nil) end
            end
            acted = true
          end
        end
      end
      did_anything = did_anything or acted
    end
  end

  -- Finish: clear TS always; restore LP if LINK is OFF (Razor remains)
  if not link_is_on then
    reaper.GetSet_LoopTimeRange(true, true, lp0A or 0, lp0B or 0, false)
  end
  reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(did_anything and "Extend/Create Razor Areas Upward" or "Extend/Create Razor Areas Upward (nothing to do)", -1)
  reaper.UpdateArrange()
end

main()
