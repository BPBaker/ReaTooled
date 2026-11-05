-- @description ReaTooled Smart Nudge Core Logic
-- @version 1.3.1
-- @about
--   Shared logic for smart nudge, direction passed via wrapper script.
--   NUDGE_LARGER = true in the wrapper: nudges by the next larger of the Grid and Nudge
--   Settings presets than the current nudge value (same unit).
--   Adds pairing: when a selected item is exactly covered by a razor edit on the same track,
--   both the razor span and that item nudge together by the same offset.
--   Measures.beats values use REAPER's notation (1.15 = 1 measure + 1.5 beats), as REAPER's
--   own nudge does, for razor areas, the cursor and envelopes too.
-- @changelog
--   v1.3.1 Fixes: a track with several razor areas keeps them all (only the first was read,
--          the others were dropped); items nudge by samples and frames (they moved by
--          256th notes and by the grid); the sample rate is the project's (it was always
--          44.1 kHz); grid units are the grid's size (they were a quarter of it); measures.
--          beats move razor areas, the cursor and envelopes by the same amount as items;
--          pixels work for razor areas, the cursor and envelopes; razor areas nudged left
--          stop at the project start instead of shrinking
--   v1.3.0 NUDGE_LARGER (the "by next larger setting" scripts)

if not DIRECTION then
  reaper.ShowMessageBox("DIRECTION not set in wrapper script!", "Error", 0)
  return
end

local EXT_SECTION = "ReaTooled"
local nudge_val = tonumber(reaper.GetExtState(EXT_SECTION, "nudge_val")) or 0
local unit_index = tonumber(reaper.GetExtState(EXT_SECTION, "nudge_unit")) or 0
if nudge_val == 0 then return end

-- REAPER's measures.beats notation (1.15 = 1 measure + 1.5 beats) <-> beats of the time
-- signature at the edit cursor
local function timesig_here()
  local num, denom = reaper.TimeMap_GetTimeSigAtTime(0, reaper.GetCursorPosition())
  num = (num and num > 0) and num or 4
  denom = (denom and denom > 0) and denom or 4
  return num, denom
end
local function mb_to_beats(v, num)
  local m = math.floor(v + 1e-9)
  return m * num + (v - m) * 10
end
local function beats_to_mb(b, num)
  local m = math.floor(b / num + 1e-9)
  return m + (b - m * num) / 10
end

-- The project's sample rate (the audio device's when the project doesn't set its own)
local function project_srate()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  local use = reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false)
  if (use == 0 or not sr or sr <= 0) and reaper.GetAudioDeviceInfo then
    local ok, v = reaper.GetAudioDeviceInfo("SRATE", "")
    local n = ok and tonumber(v)
    if n and n > 0 then return n end
  end
  return (sr and sr > 0) and sr or 44100
end

-- "Nudge ... by next larger setting": the smallest of the Grid and Nudge Settings presets
-- for this unit that's larger than the current nudge value (keep these lists in step
-- with unit_presets in ReaTooled_Grid and Nudge Settings.lua). Already at the largest,
-- or a unit without presets (grid units): twice the current value.
local function next_larger(val, unit)
  local fps = reaper.TimeMap_curFrameRate(0)
  local mod = reaper.GetExtState(EXT_SECTION, "nudge_modifier")
  local mul = (mod == "dotted") and 1.5 or (mod == "triplet") and (2/3) or 1.0
  local presets = ({
    [0] = { 1000, 500, 100, 10, 1, 0.1 },                                -- ms
    [1] = { 1.0, 0.5, 0.1, 0.01, 0.001, 0.0001 },                        -- seconds
    [3] = (function()                                                    -- measures.beats
            local num = timesig_here()
            local t = {}
            for _, b in ipairs({ num, 2, 1, 0.5, 0.25, 0.125, 0.0625 }) do t[#t + 1] = beats_to_mb(b * mul, num) end
            return t
          end)(),
    [4] = { 10000, 1000, 100, 10, 2, 1 },                                -- samples
    [5] = { fps, 6, 1, 0.5, 0.25, 1/80 },                                -- frames
    [6] = { 100, 50, 10, 5, 1 },                                         -- pixels
    [7] = { 8, 4, 2, 1, 0.5, 0.25 },                                     -- items
    [8] = { 8, 4, 2, 1, 0.5, 0.25 },                                     -- selection
  })[unit]
  local best = nil
  for _, v in ipairs(presets or {}) do
    if v > val * (1 + 1e-6) + 1e-9 and (not best or v < best) then best = v end
  end
  if best then return best end
  if unit == 3 then local num = timesig_here(); return beats_to_mb(mb_to_beats(val, num) * 2, num) end
  return val * 2
end
if NUDGE_LARGER then nudge_val = next_larger(nudge_val, unit_index) end

local DEBUG = false

-- Pairing toggles (defaults enabled)
local pair_toggle_raw = reaper.GetExtState(EXT_SECTION, "pair_item_with_razor_when_exact")
local PAIR_ENABLED = (pair_toggle_raw == "" or tonumber(pair_toggle_raw) ~= 0)
local EPSILON = tonumber(reaper.GetExtState(EXT_SECTION, "pair_epsilon_seconds")) or 1e-6
local pair_apply_nudge_raw = reaper.GetExtState(EXT_SECTION, "pair_move_uses_apply_nudge")
local PAIR_USE_APPLYNudge = (pair_apply_nudge_raw == "" or tonumber(pair_apply_nudge_raw) ~= 0)

local function get_seconds_from_unit(value, unit_index)
  if unit_index == 0 then
    return DIRECTION * value / 1000 -- milliseconds
  elseif unit_index == 1 then
    return DIRECTION * value -- seconds
  elseif unit_index == 2 then
    -- grid units: the grid's division is in whole notes (0.25 = a quarter note), measured
    -- from the edit cursor along the tempo map
    local _, grid_division = reaper.GetSetProjectGrid(0, false)
    local cur = reaper.GetCursorPosition()
    local qn = reaper.TimeMap2_timeToQN(0, cur)
    local seconds = reaper.TimeMap2_QNToTime(0, qn + DIRECTION * value * grid_division * 4) - cur
    if DEBUG then
      reaper.ShowConsoleMsg("DEBUG: Grid division (whole notes) = " .. tostring(grid_division) ..
        ", offset in seconds = " .. tostring(seconds) .. "\n")
    end
    return seconds
  elseif unit_index == 4 then
    return DIRECTION * value / project_srate() -- samples
  elseif unit_index == 5 then
    local fps = reaper.TimeMap_curFrameRate(0)
    return DIRECTION * value / fps -- frames
  elseif unit_index == 6 then
    local pps = reaper.GetHZoomLevel()
    return (pps and pps > 0) and (DIRECTION * value / pps) or 0 -- pixels at the current zoom
  else
    return 0
  end
end

local function get_measures_beats_offset(val)
  -- REAPER's notation, as its own nudge reads it: 1.15 = 1 measure + 1.5 beats
  local cur_pos = reaper.GetCursorPosition()
  local cur_qn = reaper.TimeMap2_timeToQN(0, cur_pos)
  local num, denom = timesig_here()
  local qn_offset = DIRECTION * mb_to_beats(val, num) * (4 / denom)   -- (beats of the time signature, in quarter notes)
  local new_time = reaper.TimeMap2_QNToTime(0, cur_qn + qn_offset)
  return new_time - cur_pos
end

local function save_and_restore_view(fn)
  local start_time = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local end_time = reaper.GetSet_ArrangeView2(0, false, 1, 0)
  fn()
  reaper.GetSet_ArrangeView2(0, true, 0, 0, start_time, end_time)
end

local function get_razor_edits()
  local list = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, chunk = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if chunk ~= "" then
      for start, ending, guid in chunk:gmatch("(%S+)%s+(%S+)%s+(%S+)") do
        table.insert(list, {
          track = track,
          start_time = tonumber(start),
          end_time   = tonumber(ending),
          guid = guid
        })
      end
    end
  end
  return list
end

local function move_razor_bounds(offset)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, chunk = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if chunk ~= "" then
      local rebuilt = ""
      for start, ending, guid in chunk:gmatch("(%S+)%s+(%S+)%s+(%S+)") do
        local s = tonumber(start)
        local e = tonumber(ending)

        if s and e then
          s = math.max(0, s + offset)   -- (offset is already limited so nothing goes before 0)
          e = math.max(0, e + offset)
          rebuilt = rebuilt .. string.format("%.15g %.15g ", s, e) .. guid .. " "
        else
          if DEBUG then
            reaper.ShowConsoleMsg(
              "WARN: could not parse razor segment: start='" ..
              tostring(start) .. "', end='" .. tostring(ending) .. "'\n"
            )
          end
          -- we just skip malformed segments instead of crashing
        end
      end
      reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", rebuilt, true)
    end
  end
end

local function envelope_with_selected_points()
  local env = reaper.GetSelectedEnvelope(0)
  if not env then return false end
  for i = 0, reaper.CountEnvelopePoints(env) - 1 do
    local _, _, _, _, _, sel = reaper.GetEnvelopePoint(env, i)
    if sel then return true end
  end
  return false
end

local function manually_nudge_envelope_points(offset_sec)
  save_and_restore_view(function()
    local env = reaper.GetSelectedEnvelope(0)
    if not env then return end
    for i = 0, reaper.CountEnvelopePoints(env) - 1 do
      local ok, time, val, shape, tension, sel = reaper.GetEnvelopePoint(env, i)
      if sel then
        reaper.SetEnvelopePoint(env, i, time + offset_sec, val, shape, tension, sel, true)
      end
    end
    reaper.Envelope_SortPoints(env)
  end)
end

local function nudge_items_native(unit, val)
  save_and_restore_view(function()
    reaper.ApplyNudge(0, 0, 0, unit, val, DIRECTION < 0, 0)
    local first = reaper.GetSelectedMediaItem(0, 0)
    if first then
      local new_pos = reaper.GetMediaItemInfo_Value(first, "D_POSITION")
      reaper.SetEditCurPos(new_pos, false, false)
    end
  end)
end

local function nudge_cursor(seconds)
  save_and_restore_view(function()
    local cur = reaper.GetCursorPosition()
    reaper.SetEditCurPos(cur + seconds, false, false)
  end)
end

local function nudge_selected_automation_items(offset)
  save_and_restore_view(function()
    for i = 0, reaper.CountTracks(0) - 1 do
      local track = reaper.GetTrack(0, i)
      for j = 0, reaper.CountTrackEnvelopes(track) - 1 do
        local env = reaper.GetTrackEnvelope(track, j)
        for k = 0, reaper.CountAutomationItems(env) - 1 do
          local sel = reaper.GetSetAutomationItemInfo(env, k, "D_UISEL", 0, false)
          if sel == 1 then
            local pos = reaper.GetSetAutomationItemInfo(env, k, "D_POSITION", 0, false)
            reaper.GetSetAutomationItemInfo(env, k, "D_POSITION", pos + offset, true)
          end
        end
      end
    end
  end)
end

local function has_selected_automation_items()
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    for j = 0, reaper.CountTrackEnvelopes(track) - 1 do
      local env = reaper.GetTrackEnvelope(track, j)
      for k = 0, reaper.CountAutomationItems(env) - 1 do
        local sel = reaper.GetSetAutomationItemInfo(env, k, "D_UISEL", 0, false)
        if sel == 1 then return true end
      end
    end
  end
  return false
end

-- -------- Pairing helpers --------
local function approx_equal(a, b, eps) return math.abs((a or 0) - (b or 0)) <= (eps or 1e-6) end

local function get_selected_items()
  local items = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tr = reaper.GetMediaItem_Track(it)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    table.insert(items, {
      item = it,
      track = tr,
      start_time = pos,
      end_time = pos + len
    })
  end
  return items
end

local function find_razor_item_pairs(razor_list, selected_items, eps)
  local matched = {}
  if not razor_list or #razor_list == 0 then return matched end
  -- Build per-track buckets for faster matching
  local by_track = {}
  for _, rz in ipairs(razor_list) do
    local key = tostring(rz.track)
    by_track[key] = by_track[key] or {}
    table.insert(by_track[key], rz)
  end
  for _, it in ipairs(selected_items) do
    local bucket = by_track[tostring(it.track)]
    if bucket then
      for _, rz in ipairs(bucket) do
        if approx_equal(rz.start_time, it.start_time, eps) and approx_equal(rz.end_time, it.end_time, eps) then
          table.insert(matched, it.item)
          break
        end
      end
    end
  end
  return matched
end

local function save_item_selection()
  local sel = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    sel[#sel+1] = reaper.GetSelectedMediaItem(0, i)
  end
  return sel
end

local function restore_item_selection(sel)
  -- clear
  for i = reaper.CountSelectedMediaItems(0)-1, 0, -1 do
    reaper.SetMediaItemSelected(reaper.GetSelectedMediaItem(0, i), false)
  end
  -- restore
  for _, it in ipairs(sel or {}) do
    if it then reaper.SetMediaItemSelected(it, true) end
  end
end

local function select_only(items)
  -- clear all
  for i = reaper.CountSelectedMediaItems(0)-1, 0, -1 do
    reaper.SetMediaItemSelected(reaper.GetSelectedMediaItem(0, i), false)
  end
  for _, it in ipairs(items or {}) do
    reaper.SetMediaItemSelected(it, true)
  end
end

local function nudge_specific_items_by_seconds(items, offset_sec)
  if #items == 0 or offset_sec == 0 then return end
  save_and_restore_view(function()
    local saved = save_item_selection()
    select_only(items)
    if PAIR_USE_APPLYNudge then
      -- Use ApplyNudge in seconds to respect ripple/locking modes.
      local seconds = math.abs(offset_sec)
      local reverse = offset_sec < 0
      reaper.ApplyNudge(0, 0, 0, 1, seconds, reverse, 0) -- unit=1 (seconds)
    else
      -- Direct position set (fast, ignores ripple)
      for _, it in ipairs(items) do
        local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        reaper.SetMediaItemInfo_Value(it, "D_POSITION", math.max(0, pos + offset_sec))
      end
      reaper.UpdateArrange()
    end
    restore_item_selection(saved)
  end)
end

-- === Execute ===
-- ApplyNudge's units: 0 ms, 1 seconds, 2 grid, 16 measures.beats, 17 samples, 18 frames,
-- 19 pixels, 20 item lengths, 21 item selections
local reaper_units = { [0]=0, [1]=1, [2]=2, [3]=16, [4]=17, [5]=18, [6]=19, [7]=20, [8]=21 }
local is_beats = unit_index == 3
local item_count = reaper.CountSelectedMediaItems(0)
local razor = get_razor_edits()
local env_points = envelope_with_selected_points()

local offset_sec = is_beats and get_measures_beats_offset(nudge_val)
                        or get_seconds_from_unit(nudge_val, unit_index)

if DEBUG then
  reaper.ShowConsoleMsg("Offset in seconds: " .. tostring(offset_sec) .. "\n")
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

if #razor > 0 then
  -- (nudging left stops at the project start: every area keeps its length)
  local first = math.huge
  for _, rz in ipairs(razor) do if rz.start_time and rz.start_time < first then first = rz.start_time end end
  if offset_sec < 0 and first ~= math.huge and first + offset_sec < 0 then offset_sec = -first end
  -- NEW: If pairing is enabled, move matched items together with razor spans.
  if PAIR_ENABLED and item_count > 0 and offset_sec ~= 0 then
    local selected_items = get_selected_items()
    local matched_items = find_razor_item_pairs(razor, selected_items, EPSILON)
    save_and_restore_view(function()
      move_razor_bounds(offset_sec)
      if #matched_items > 0 then
        nudge_specific_items_by_seconds(matched_items, offset_sec)
      end
    end)
  else
    move_razor_bounds(offset_sec)
  end

elseif has_selected_automation_items() then
  nudge_selected_automation_items(offset_sec)

elseif env_points then
  manually_nudge_envelope_points(offset_sec)

elseif item_count > 0 then
  local unit = is_beats and 16 or reaper_units[unit_index]

  if unit_index == 2 and DEBUG then
    local _, grid_division = reaper.GetSetProjectGrid(0, false)
    reaper.ShowConsoleMsg("DEBUG: Grid division (beats) = " .. tostring(grid_division) .. "\n")
    reaper.ShowConsoleMsg("DEBUG: Using raw nudge_val = " .. tostring(nudge_val) .. "\n")
  end

  if unit then
    nudge_items_native(unit, nudge_val)
  end

else
  nudge_cursor(offset_sec)
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock(NUDGE_LARGER and "Smart Nudge (next larger setting)" or "Smart Nudge", -1)
