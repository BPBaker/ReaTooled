-- ReaTooled – AGC (dB) → Track Volume (simple & robust)
-- Copies points from the SELECTED envelope (assumed AGC OUT in dB)
-- into the parent TRACK's "Volume" envelope.
-- Minimal dependencies: no optional API calls that vary by build.
-- If your Volume envelope is fader-scaled (dB), leave WRITE_DB_TO_VOLUME = true.
-- Otherwise set to false to write linear gain (10^(dB/20)).

local r = reaper

----------------------------------------------------------------
-- USER SETTINGS
local WRITE_DB_TO_VOLUME = true   -- true = write dB values; false = write linear gain
local SHIFT_MS = 0.0              -- set a positive/negative time shift (ms), e.g. -50 for 50ms advance
----------------------------------------------------------------

local function msg(s) r.ShowMessageBox(s, "AGC → Volume (Simple)", 0) end

-- Safely get a track from an envelope (supports track or take envelopes)
local function get_track_from_envelope(env)
  local tr = r.GetEnvelopeInfo_Value(env, "P_TRACK")
  if tr then
    if r.ValidatePtr2(0, tr, "MediaTrack*") then return tr end
  end
  -- Try via take → item → track
  local tk = r.GetEnvelopeInfo_Value(env, "P_TAKE")
  if tk and r.ValidatePtr2(0, tk, "MediaItem_Take*") then
    local it = r.GetMediaItemTake_Item(tk)
    if it and r.ValidatePtr2(0, it, "MediaItem*") then
      local parent = r.GetMediaItem_Track(it)
      if parent and r.ValidatePtr2(0, parent, "MediaTrack*") then
        return parent
      end
    end
  end
  return nil
end

-- Ensure we can access the track Volume envelope (toggle visible if needed)
local function get_or_create_volume_env(track)
  local env = r.GetTrackEnvelopeByName(track, "Volume")
  if not env then
    r.Main_OnCommand(40406, 0) -- Track: Toggle track volume envelope visible
    env = r.GetTrackEnvelopeByName(track, "Volume")
  end
  return env
end

-- Read points from selected envelope (uses time selection if present)
local function read_points(env)
  local pts = {}
  local ts, te = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  local useTS = (te > ts) and (te - ts) > 1e-9

  local cnt = r.CountEnvelopePoints(env)
  for i = 0, cnt-1 do
    local ok, t, v, shape, tens = r.GetEnvelopePoint(env, i)
    if ok and (not useTS or (t >= ts and t <= te)) then
      pts[#pts+1] = {t=t, v=v, shape=shape or 0, tens=tens or 0}
    end
  end

  local t1, t2
  if #pts > 0 then
    t1, t2 = pts[1].t, pts[#pts].t
  end
  return pts, t1, t2
end

-- Clear target range
local function clear_range(env, t1, t2)
  if not t1 or not t2 then return end
  r.DeleteEnvelopePointRange(env, t1 - 1e-6, t2 + 1e-6)
end

-- Map AGC dB to target value
local function map_value(dB)
  -- clamp to sensible display range
  if dB > 12 then dB = 12 end
  if dB < -150 then dB = -150 end
  if WRITE_DB_TO_VOLUME then
    -- For fader-scaled volume envelopes, storing dB values directly works well.
    return dB
  else
    -- Linear amplitude for non-fader volume envelopes
    return 10^(dB/20)
  end
end

-- Main
local function main()
  local src = r.GetSelectedEnvelope(0)
  if not src then return msg("Select the AGC OUT (dB) envelope first.") end

  -- Optional name sanity check (non-fatal)
  local okn, nm = r.GetEnvelopeName(src, "")
  if okn and nm and (not nm:lower():find("agc")) then
    local b = r.ShowMessageBox(
      "Selected envelope doesn't look like an AGC output.\nContinue anyway?",
      "AGC → Volume", 4)
    if b ~= 6 then return end
  end

  local track = get_track_from_envelope(src)
  if not track then return msg("Couldn't find the parent track for the selected envelope.") end

  local dest = get_or_create_volume_env(track)
  if not dest then return msg("Couldn't access the track Volume envelope.") end

  local pts, t1, t2 = read_points(src)
  if #pts == 0 then return msg("No points found (check time selection).") end

  -- Time shift (ms → sec)
  local shift = (SHIFT_MS or 0) / 1000.0

  -- Clear destination in shifted range
  clear_range(dest, (t1 + shift), (t2 + shift))

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  for i = 1, #pts do
    local p = pts[i]
    local t = p.t + shift
    if t < 0 then t = 0 end
    local dB = p.v          -- source is assumed in dB
    local val = map_value(dB)
    r.InsertEnvelopePoint(dest, t, val, p.shape, p.tens, false, true)
  end

  r.Envelope_SortPoints(dest)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("AGC (dB) → Volume (simple)", -1)

  local note = string.format(
    "Copied %d points → Volume.\nShift: %.3f s (%.2f ms)\nWrote %s.",
    #pts, shift, shift*1000, (WRITE_DB_TO_VOLUME and "dB (fader-scaled)" or "linear gain"))
  msg(note)
end

main()
