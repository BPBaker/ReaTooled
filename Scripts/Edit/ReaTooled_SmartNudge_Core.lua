-- @description ReaTooled Smart Nudge Core Logic
-- @version 1.2.0
-- @about
--   Shared logic for smart nudge, direction passed via wrapper script.
--   Adds pairing: when a selected item is exactly covered by a razor edit on the same track,
--   both the razor span and that item nudge together by the same offset.
--   Grid unit mode note: grid division is in beats; see comments in code.

if not DIRECTION then
  reaper.ShowMessageBox("DIRECTION not set in wrapper script!", "Error", 0)
  return
end

local EXT_SECTION = "ReaTooled"
local nudge_val = tonumber(reaper.GetExtState(EXT_SECTION, "nudge_val")) or 0
local unit_index = tonumber(reaper.GetExtState(EXT_SECTION, "nudge_unit")) or 0
if nudge_val == 0 then return end

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
    -- NOTE: Project grid division is in beats (QN), not measures.
    -- If you intend "grid units" in beats: seconds = value * grid_div * (60/tempo)
    local _, grid_division = reaper.GetSetProjectGrid(0, false) -- beats per grid
    local tempo = reaper.Master_GetTempo()
    local seconds = DIRECTION * value * grid_division * (60 / tempo)

    if DEBUG then
      reaper.ShowConsoleMsg("DEBUG: Grid division (beats) = " .. tostring(grid_division) .. "\n")
      reaper.ShowConsoleMsg("DEBUG: Tempo = " .. tostring(tempo) .. "\n")
      reaper.ShowConsoleMsg("DEBUG: Calculated offset in seconds = " .. tostring(seconds) .. "\n")
    end

    return seconds
  elseif unit_index == 4 then
    local _, sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
    sr = tonumber(sr)
    if not sr or sr == 0 then sr = 44100 end
    return DIRECTION * value / sr -- samples
  elseif unit_index == 5 then
    local fps = reaper.TimeMap_curFrameRate(0)
    return DIRECTION * value / fps -- frames
  else
    return 0
  end
end

local function get_measures_beats_offset(val)
  -- Interprets decimal part as FRACTION OF A MEASURE, not 10ths.
  local cur_pos = reaper.GetCursorPosition()
  local cur_qn = reaper.TimeMap2_timeToQN(0, cur_pos)
  local _, num, _ = reaper.TimeMap_GetTimeSigAtTime(0, cur_pos)

  local measures = math.floor(val)
  local frac = val - measures
  local beats = frac * num
  local beat_offset = measures * num + beats
  local qn_offset = DIRECTION * beat_offset

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
      for start, ending, guid in chunk:gmatch("(.-) (.-) (%S+)") do
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
      for start, ending, guid in chunk:gmatch("(.-) (.-) (%S+)") do
        local s = tonumber(start)
        local e = tonumber(ending)

        if s and e then
          s = s + offset
          e = e + offset
          if s < 0 then s = 0 end
          if e < 0 then e = 0 end
          rebuilt = rebuilt .. s .. " " .. e .. " " .. guid .. " "
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
local reaper_units = { [0]=0, [1]=1, [2]=2, [3]=16, [4]=3, [5]=2, [6]=19, [7]=20, [8]=21 }
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
reaper.Undo_EndBlock("Smart Nudge", -1)
