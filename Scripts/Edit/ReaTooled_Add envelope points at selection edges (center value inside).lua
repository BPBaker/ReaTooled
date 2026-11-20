--[[
@description ReaTooled - Add envelope points at selection edges (center value inside)
@version 1.0
@author Brendan Baker
@website https://brendanpatrickbaker.com/reatooled/
@about
  Based on X-Raym's "Add envelope points at time selection edges from center to center preserving edges".
  # Add envelope points at selection edges (center value inside)
  Sets the envelopes inside the selection to their center value (0 dB for volume,
  center for pan, and so on), with a step at each edge. Outside the selection, the
  envelope keeps its values right up to the edges. Points that were inside the
  selection are replaced; the new points are left selected.
  What it works on, in order:
    1. Razor areas: envelope lanes in the areas, and the envelopes of tracks with
       razor areas, each across its own area.
    2. Time selection: the selected envelope, or else the envelopes of the selected
       tracks (the master too).
  Only visible, armed envelopes are changed (ONLY_VISIBLE_ARMED below). Needs SWS.
@changelog
  v1.0 ReaTooled's own version, replacing X-Raym's script: razor areas first, the
       master track included.
--]]

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local ONLY_VISIBLE_ARMED = true   -- only change envelopes that are shown and armed
------------------------------------------------------------

local EPS = 1e-9
local SR = 48000   -- (Envelope_Evaluate's sample rate; any value works for one value)

if not reaper.BR_EnvAlloc then
  reaper.ShowMessageBox("This script needs the SWS extension.", "ReaTooled", 0)
  return
end

-- The envelope's center value (in its own scale), or nil if it shouldn't be changed
local function center_of(env)
  local br = reaper.BR_EnvAlloc(env, false)
  if not br then return nil end
  local _, visible, armed, _, _, _, _, _, center, _, fader =
    reaper.BR_EnvGetProperties(br, true, true, true, true, 0, 0, 0, 0, 0, 0, true)
  reaper.BR_EnvFree(br, false)
  if ONLY_VISIBLE_ARMED and not (visible and armed) then return nil end
  if fader then center = reaper.ScaleToEnvelopeMode(1, center) end
  return center
end

local function add_points(env, a, b)
  local center = center_of(env)
  if not center then return end

  -- The values at the edges, as seen from outside: a point exactly on the start edge
  -- (the first one there) or the value there; likewise the last point on the end edge
  local n = reaper.CountEnvelopePoints(env)
  local v_start, v_end
  for i = 0, n - 1 do
    local _, t, v = reaper.GetEnvelopePoint(env, i)
    if not v_start and math.abs(t - a) < EPS then v_start = v end
    if math.abs(t - b) < EPS then v_end = v end
  end
  if not v_start then v_start = select(2, reaper.Envelope_Evaluate(env, a, SR, 0)) end
  if not v_end then v_end = select(2, reaper.Envelope_Evaluate(env, b, SR, 0)) end

  -- Only the new points end up selected
  for i = 0, n - 1 do reaper.SetEnvelopePoint(env, i, nil, nil, nil, nil, false, true) end
  reaper.DeleteEnvelopePointRange(env, a - EPS, b + EPS)

  reaper.InsertEnvelopePoint(env, a, v_start, 0, 0, true, true)
  reaper.InsertEnvelopePoint(env, a, center,  0, 0, true, true)
  reaper.InsertEnvelopePoint(env, b, center,  0, 0, true, true)
  reaper.InsertEnvelopePoint(env, b, v_end,   0, 0, true, true)
  reaper.Envelope_SortPoints(env)
end

local function all_tracks()   -- master first, then the rest
  local list = { reaper.GetMasterTrack(0) }
  for i = 0, reaper.CountTracks(0) - 1 do list[#list + 1] = reaper.GetTrack(0, i) end
  return list
end

local function main()
  -- 1. Razor areas
  local jobs, seen = {}, {}
  local function job(env, a, b)
    if not env then return end
    local k = tostring(env) .. string.format(" %.9f %.9f", a, b)
    if not seen[k] then seen[k] = true; jobs[#jobs + 1] = { env, a, b } end
  end
  for _, tr in ipairs(all_tracks()) do
    local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if s ~= "" then
      local w = {}
      for x in s:gmatch("%S+") do w[#w + 1] = x end
      for j = 1, #w - 2, 3 do
        local a, b, guid = tonumber(w[j]), tonumber(w[j + 1]), w[j + 2]
        if a and b and b > a then
          if guid == '""' then
            for k = 0, reaper.CountTrackEnvelopes(tr) - 1 do job(reaper.GetTrackEnvelope(tr, k), a, b) end
          else
            job(reaper.GetTrackEnvelopeByChunkName(tr, guid:sub(2, -2)), a, b)
          end
        end
      end
    end
  end

  -- 2. Time selection
  if #jobs == 0 then
    local a, b = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if b - a <= EPS then return false end
    local env = reaper.GetSelectedEnvelope(0)
    if env then
      job(env, a, b)
    else
      for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do
        local tr = reaper.GetSelectedTrack2(0, i, true)
        for k = 0, reaper.CountTrackEnvelopes(tr) - 1 do job(reaper.GetTrackEnvelope(tr, k), a, b) end
      end
    end
  end

  for _, j in ipairs(jobs) do add_points(j[1], j[2], j[3]) end
  return #jobs > 0
end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()
local done = main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.TrackList_AdjustWindows(false)   -- (the track panels' envelope values)
reaper.Undo_EndBlock(done and "Add envelope points at selection edges" or "Add envelope points (nothing to do)", -1)
