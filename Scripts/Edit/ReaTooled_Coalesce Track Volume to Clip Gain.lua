--[[
-- @description ReaTooled - Coalesce Track Volume to Clip Gain
-- @version 1.0
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Like Pro Tools' "Coalesce Volume Automation to Clip Gain"
    For each selected item, moves the track's volume automation under the item
    into the item's take volume envelope (combined with any clip gain already
    there), and sets the track automation to 0 dB across the item.
    Uses the Pre-FX volume envelope by default. Creates the take volume
    envelope if needed. Short glides at the item edges keep the automation
    outside the item as it was.
    Known limit: two selected items overlapping on the same track can give
    unexpected results. Envelopes with automation items are skipped.
-- CHANGELOG
-- v1.0 Initial version (replaces TJF Coalesce Track Volume to Take Volume)
--]]

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local USE_PREFX   = false   -- true = Volume (Pre-FX) envelope, false = Volume
local GLIDE       = 0.01   -- seconds of glide at each item edge
local SHOW_RESULT = true   -- show the take volume envelope afterwards

-- (not used in this direction)
local INCLUDE_TAKE_VOLUME, INCLUDE_ITEM_VOLUME = false, false

local DIRECTION = "track_to_clip"
local TITLE     = "Coalesce Track Volume to Clip Gain"

------------------------------------------------------------
-- (No need to edit below this line)
------------------------------------------------------------

local SRATE = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
local EPS   = 1e-9

-- Native actions, found by exact name (command numbers are only a first guess)
local function find_cmd(name, guess)
  if guess and reaper.kbd_getTextFromCmd(guess, 0) == name then return guess end
  for id = 1, 65535 do
    if reaper.kbd_getTextFromCmd(id, 0) == name then return id end
  end
  return nil
end

local TRACK_ENV_ACTION = USE_PREFX and "Track: Toggle track pre-FX volume envelope visible"
                                    or "Track: Toggle track volume envelope visible"
local TAKE_ENV_ACTION  = "Take: Toggle take volume envelope"

------------------------------------------------------------
-- Envelope helpers
------------------------------------------------------------

local function mode(env) return reaper.GetEnvelopeScalingMode(env) end

-- Gain (amplitude, 1 = 0 dB) of an envelope at an envelope-local time
local function gain_at(env, t)
  local _, v = reaper.Envelope_Evaluate(env, t, SRATE, 0)
  return reaper.ScaleFromEnvelopeMode(mode(env), v)
end

local function raw_at(env, t)
  local _, v = reaper.Envelope_Evaluate(env, t, SRATE, 0)
  return v
end

local function to_raw(env, gain) return reaper.ScaleToEnvelopeMode(mode(env), gain) end

local function is_active(env)
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  return not (ok and chunk:match("\nACT 0"))
end

-- Turn an envelope on (un-bypass) and optionally show it
local function activate(env, show)
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok then return end
  local new = chunk:gsub("\nACT 0", "\nACT 1")
  if show then new = new:gsub("\nVIS 0", "\nVIS 1") end
  if new ~= chunk then reaper.SetEnvelopeStateChunk(env, new, false) end
end

local function track_env(track)
  return reaper.GetTrackEnvelopeByChunkName(track, USE_PREFX and "<VOLENV" or "<VOLENV2")
end

local function take_env(take)
  return reaper.GetTakeEnvelopeByName(take, "Volume")
end

-- Run an action on one track / one item only, then put the selection back
local function with_only_track(track, fn)
  local sel = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do sel[#sel + 1] = reaper.GetSelectedTrack(0, i) end
  reaper.SetOnlyTrackSelected(track)
  fn()
  for i = 0, reaper.CountTracks(0) - 1 do reaper.SetTrackSelected(reaper.GetTrack(0, i), false) end
  for _, t in ipairs(sel) do reaper.SetTrackSelected(t, true) end
end

local function with_only_item(item, fn)
  local sel = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = reaper.GetSelectedMediaItem(0, i) end
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  fn()
  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(sel) do reaper.SetMediaItemSelected(it, true) end
end

local function get_or_create_track_env(track)
  local env = track_env(track)
  if env then return env end
  local cmd = find_cmd(TRACK_ENV_ACTION)
  if not cmd then return nil end
  with_only_track(track, function() reaper.Main_OnCommand(cmd, 0) end)
  return track_env(track)
end

local function get_or_create_take_env(item, take)
  local env = take_env(take)
  if env then return env end
  local cmd = find_cmd(TAKE_ENV_ACTION, 40693)
  if not cmd then return nil end
  with_only_item(item, function() reaper.Main_OnCommand(cmd, 0) end)
  return take_env(take)
end

local function has_automation_items(env, s, e)
  for i = 0, reaper.CountAutomationItems(env) - 1 do
    local p = reaper.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
    local l = reaper.GetSetAutomationItemInfo(env, i, "D_LENGTH", 0, false)
    if p < e and p + l > s then return true end
  end
  return false
end

-- Sorted unique list of times
local function unique_sorted(list)
  table.sort(list)
  local out = {}
  for _, t in ipairs(list) do
    if #out == 0 or t - out[#out] > EPS then out[#out + 1] = t end
  end
  return out
end

-- Envelope point times inside [s, e] (project time), for a take envelope
-- converted from take time (take envelope time = item time x playrate)
local function point_times(env, s, e, item_start, rate)
  local out = {}
  for i = 0, reaper.CountEnvelopePoints(env) - 1 do
    local _, t = reaper.GetEnvelopePoint(env, i)
    if item_start then t = item_start + t / rate end
    if t >= s - EPS and t <= e + EPS then out[#out + 1] = t end
  end
  return out
end

------------------------------------------------------------
-- The two directions
------------------------------------------------------------

local skipped, done = {}, 0

-- Clip gain (take volume envelope, take volume, item volume) -> track volume
local function clip_to_track(item)
  local take = reaper.GetActiveTake(item)
  if not take then return end
  local s     = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local e     = s + len
  local rate  = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local track = reaper.GetMediaItem_Track(item)

  local tkenv  = take_env(take)
  local tk_on  = tkenv and is_active(tkenv)
  local take_vol = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
  local item_vol = reaper.GetMediaItemInfo_Value(item, "D_VOL")
  local static = 1
  if INCLUDE_TAKE_VOLUME then static = static * math.abs(take_vol) end
  if INCLUDE_ITEM_VOLUME then static = static * item_vol end

  if not tk_on and math.abs(static - 1) < EPS then return end   -- no clip gain here

  local env = get_or_create_track_env(track)
  if not env then skipped[#skipped + 1] = "could not create the track envelope"; return end
  if has_automation_items(env, s - GLIDE, e + GLIDE) then
    skipped[#skipped + 1] = "automation items on the track envelope at " ..
      reaper.format_timestr_pos(s, "", -1)
    return
  end

  local function clip_gain(t)
    local g = static
    if tk_on then g = g * gain_at(tkenv, (t - s) * rate) end
    return g
  end

  -- Work out every new value before changing anything
  local times = { s, e }
  for _, t in ipairs(point_times(env, s, e)) do times[#times + 1] = t end
  if tk_on then
    for _, t in ipairs(point_times(tkenv, s, e, s, rate)) do times[#times + 1] = t end
  end
  times = unique_sorted(times)

  local pts = {}
  for _, t in ipairs(times) do
    pts[#pts + 1] = { t, to_raw(env, gain_at(env, t) * clip_gain(t)) }
  end
  local before = raw_at(env, s - GLIDE)
  local after  = raw_at(env, e + GLIDE)

  -- Write the track envelope
  reaper.DeleteEnvelopePointRange(env, s - GLIDE - EPS, e + GLIDE + EPS)
  if s - GLIDE >= 0 then reaper.InsertEnvelopePoint(env, s - GLIDE, before, 0, 0, false, true) end
  for _, p in ipairs(pts) do reaper.InsertEnvelopePoint(env, p[1], p[2], 0, 0, false, true) end
  reaper.InsertEnvelopePoint(env, e + GLIDE, after, 0, 0, false, true)
  reaper.Envelope_SortPoints(env)
  activate(env, SHOW_RESULT)

  -- Reset clip gain to 0 dB
  if tkenv then
    reaper.DeleteEnvelopePointRange(tkenv, -1, len * rate + 1)
    reaper.InsertEnvelopePoint(tkenv, 0, to_raw(tkenv, 1), 0, 0, false, true)
    reaper.Envelope_SortPoints(tkenv)
  end
  if INCLUDE_TAKE_VOLUME then
    reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", take_vol < 0 and -1 or 1)   -- keeps polarity
  end
  if INCLUDE_ITEM_VOLUME then reaper.SetMediaItemInfo_Value(item, "D_VOL", 1) end
  done = done + 1
end

-- Track volume -> clip gain (take volume envelope)
local function track_to_clip(item)
  local take = reaper.GetActiveTake(item)
  if not take then return end
  local s     = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local e     = s + len
  local rate  = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local track = reaper.GetMediaItem_Track(item)

  local env = track_env(track)
  if not env or not is_active(env) then return end   -- no track volume automation
  if has_automation_items(env, s - GLIDE, e + GLIDE) then
    skipped[#skipped + 1] = "automation items on the track envelope at " ..
      reaper.format_timestr_pos(s, "", -1)
    return
  end

  local tkenv = get_or_create_take_env(item, take)
  if not tkenv then skipped[#skipped + 1] = "could not create the take volume envelope"; return end
  local tk_on = is_active(tkenv)

  -- Work out every new value before changing anything
  local times = { s, e }
  for _, t in ipairs(point_times(env, s, e)) do times[#times + 1] = t end
  for _, t in ipairs(point_times(tkenv, s, e, s, rate)) do times[#times + 1] = t end
  times = unique_sorted(times)

  local pts = {}
  for _, t in ipairs(times) do
    local g = gain_at(env, t)
    if tk_on then g = g * gain_at(tkenv, (t - s) * rate) end
    pts[#pts + 1] = { (t - s) * rate, to_raw(tkenv, g) }
  end
  local before = raw_at(env, s - GLIDE)
  local after  = raw_at(env, e + GLIDE)

  -- Write the take envelope
  reaper.DeleteEnvelopePointRange(tkenv, -1, len * rate + 1)
  for _, p in ipairs(pts) do reaper.InsertEnvelopePoint(tkenv, p[1], p[2], 0, 0, false, true) end
  reaper.Envelope_SortPoints(tkenv)
  activate(tkenv, SHOW_RESULT)

  -- Track envelope: 0 dB across the item, gliding back to the old values outside it
  local unity = to_raw(env, 1)
  reaper.DeleteEnvelopePointRange(env, s - GLIDE - EPS, e + GLIDE + EPS)
  if s - GLIDE >= 0 then reaper.InsertEnvelopePoint(env, s - GLIDE, before, 0, 0, false, true) end
  reaper.InsertEnvelopePoint(env, s, unity, 0, 0, false, true)
  reaper.InsertEnvelopePoint(env, e, unity, 0, 0, false, true)
  reaper.InsertEnvelopePoint(env, e + GLIDE, after, 0, 0, false, true)
  reaper.Envelope_SortPoints(env)
  done = done + 1
end

------------------------------------------------------------
-- Main
------------------------------------------------------------

local items = {}
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do items[#items + 1] = reaper.GetSelectedMediaItem(0, i) end
if #items == 0 then
  reaper.ShowMessageBox("Select one or more items first.", TITLE, 0)
  return
end

-- Left to right, track by track
table.sort(items, function(a, b)
  local ta = reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(a), "IP_TRACKNUMBER")
  local tb = reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(b), "IP_TRACKNUMBER")
  if ta ~= tb then return ta < tb end
  return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
end)

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
for _, item in ipairs(items) do
  if DIRECTION == "clip_to_track" then clip_to_track(item) else track_to_clip(item) end
end
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock(TITLE, -1)

if #skipped > 0 then
  reaper.ShowMessageBox("Some items were skipped:\n\n" .. table.concat(skipped, "\n"), TITLE, 0)
end
