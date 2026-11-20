--[[
@description ReaTooled - Write current value to all envelopes in selection
@version 1.0
@author Brendan Baker
@website https://brendanpatrickbaker.com/reatooled/
@about
  Based on TJF Write Punch ALL envelopes by Tim Farrell.
  # Write current value to all envelopes in selection
  Like Pro Tools' "Write Automation to All Enabled Parameters" (Cmd+Opt+/): every
  envelope in the selection gets one flat value across it, with a short ramp in and
  out (TRANSITION below).
  The value is each envelope's value at the edit cursor (or at the start of the
  selection: USE_EDIT_CURSOR_VALUE below).
  What it writes to, in order:
    1. Time selection: the track envelopes of the selected tracks (all tracks if none
       are selected), and the take envelopes of the selected items in it (all items in
       it on those tracks if none are selected).
    2. Razor areas: envelope lanes in the areas, and the take envelopes of the items in
       the areas.
    3. Selected items: their tracks' envelopes across each item, and their take
       envelopes.
  Only visible envelopes are written (ONLY_VISIBLE), the master track's included; the
  tempo map never is. Automation items in the selection are written too.
  The time selection is never changed.
@changelog
  v1.0 First version: only visible envelopes, the master track included,
       take envelopes follow the take's playrate, and the time selection is left alone.
--]]

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local USE_EDIT_CURSOR_VALUE  = true    -- true: each envelope's value at the edit cursor; false: at the selection start
local ONLY_VISIBLE           = true    -- only write envelopes that are shown
local ONLY_ARMED             = false   -- only write armed envelopes
local TRANSITION             = 0.010   -- seconds of ramp outside the selection, at each end
local ALWAYS_4_POINTS        = false   -- always add the ramp points, even where the value doesn't change
local ALSO_WRITING_ENVELOPES = true    -- with a time selection, also write envelopes that are writing right now
------------------------------------------------------------

local EPS = 1e-9
local SR = 48000   -- (Envelope_Evaluate's sample rate; any value works for one value)

local function eval(env, t)
  local _, v = reaper.Envelope_Evaluate(env, t, SR, 0)
  return v
end

-- An envelope flag ("VISIBLE", "ARM"), read without the state chunk where REAPER allows
local function env_flag(env, key, chunk_key)
  local ok, r, v = pcall(reaper.GetSetEnvelopeInfo_String, env, key, "", false)
  if ok and r and (v == "0" or v == "1") then return v == "1" end
  local okc, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if okc then
    local x = chunk:match("\n" .. chunk_key .. "%s+(%d)")
    if x then return x ~= "0" end
  end
  return true
end

local function env_ok(env, is_take)
  if not env then return false end
  local _, name = reaper.GetEnvelopeName(env)
  if name == "Tempo map" then return false end
  if ONLY_VISIBLE and not env_flag(env, "VISIBLE", "VIS") then return false end
  if ONLY_ARMED and not is_take and not env_flag(env, "ARM", "ARM") then return false end
  return true
end

local function points_in(env, ai, a, b)   -- any point with a <= t < b (a < t <= b if right)
  local n = reaper.CountEnvelopePointsEx(env, ai)
  for i = 0, n - 1 do
    local _, t = reaper.GetEnvelopePointEx(env, ai, i)
    if t >= a - EPS and t <= b + EPS then return true end
  end
  return false
end

-- Write one value across [a, b] of an envelope (times in the envelope's own time:
-- project time for track envelopes, take time for take envelopes). lo/hi: where
-- ramp points may go (0 and the take's length for take envelopes).
local function write_env(env, a, b, cur, lo, hi)
  if b - a <= EPS then return end
  local T = TRANSITION
  local value = USE_EDIT_CURSOR_VALUE and eval(env, cur) or eval(env, a)

  -- Automation items over the range, and the envelope lane itself (-1) unless one
  -- automation item covers the whole range
  local parts, lane = {}, true
  for i = 0, reaper.CountAutomationItems(env) - 1 do
    local s = reaper.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
    local e = s + reaper.GetSetAutomationItemInfo(env, i, "D_LENGTH", 0, false)
    if s < b - EPS and e > a + EPS then
      if s <= a + EPS and e >= b - EPS then lane = false end
      parts[#parts + 1] = { ai = i, a = math.max(a, s), b = math.min(b, e) }
    end
  end
  if lane then table.insert(parts, 1, { ai = -1, a = a, b = b }) end
  local several = #parts > 1

  -- Read everything first, so writing one part doesn't change what the next one reads
  for _, p in ipairs(parts) do
    p.vl, p.vr = eval(env, p.a - T), eval(env, p.b + T)
    p.ramp_l = p.a - T >= lo - EPS
    p.ramp_r = p.b + T <= hi + EPS
    p.had_l = p.ramp_l and points_in(env, p.ai, p.a - T, p.a - EPS)
    p.had_r = p.ramp_r and points_in(env, p.ai, p.b + EPS, p.b + T)
  end

  for _, p in ipairs(parts) do
    local ai = p.ai
    reaper.DeleteEnvelopePointRangeEx(env, ai, p.ramp_l and p.a - T or p.a, (p.ramp_r and p.b + T or p.b) + 1e-7)
    reaper.InsertEnvelopePointEx(env, ai, p.a, value, 0, 0, false, true)
    reaper.InsertEnvelopePointEx(env, ai, p.b, value, 0, 0, false, true)
    if p.ramp_l and (ALWAYS_4_POINTS or several or p.had_l or math.abs(value - p.vl) > EPS) then
      reaper.InsertEnvelopePointEx(env, ai, p.a - T, p.vl, 0, 0, false, true)
    end
    if p.ramp_r and (ALWAYS_4_POINTS or several or p.had_r or math.abs(value - p.vr) > EPS) then
      reaper.InsertEnvelopePointEx(env, ai, p.b + T, p.vr, 0, 0, false, true)
    end
    reaper.Envelope_SortPointsEx(env, ai)
  end
end

local function track_envs(tr, a, b, cur)
  for i = 0, reaper.CountTrackEnvelopes(tr) - 1 do
    local env = reaper.GetTrackEnvelope(tr, i)
    if env_ok(env, false) then write_env(env, a, b, cur, 0, math.huge) end
  end
end

-- Take envelopes of an item, across the part of it within [a, b] (the whole item if nil)
local function take_envs(it, a, b, cur)
  local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local s, e = math.max(a or p, p) - p, math.min(b or p + len, p + len) - p
  if e - s <= EPS then return end
  local c = math.min(math.max(cur - p, 0), len)
  for k = 0, reaper.CountTakes(it) - 1 do
    local take = reaper.GetTake(it, k)
    if take then
      local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
      for j = 0, reaper.CountTakeEnvelopes(take) - 1 do
        local env = reaper.GetTakeEnvelope(take, j)
        if env_ok(env, true) then write_env(env, s * rate, e * rate, c * rate, 0, len * rate) end
      end
    end
  end
end

local function overlaps(it, a, b)
  local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  return p < b - EPS and e > a + EPS
end

local function all_tracks()   -- master first, then the rest
  local list = { reaper.GetMasterTrack(0) }
  for i = 0, reaper.CountTracks(0) - 1 do list[#list + 1] = reaper.GetTrack(0, i) end
  return list
end

local function main()
  local cur = reaper.GetCursorPosition()
  local ts, te = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)

  -- 1. Time selection
  if te - ts > EPS then
    local tracks = {}
    local nsel = reaper.CountSelectedTracks2(0, true)
    if nsel > 0 then
      for i = 0, nsel - 1 do tracks[#tracks + 1] = reaper.GetSelectedTrack2(0, i, true) end
    else
      tracks = all_tracks()
    end
    local items, sel = {}, {}
    for _, tr in ipairs(tracks) do
      track_envs(tr, ts, te, cur)
      for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        if overlaps(it, ts, te) then
          items[#items + 1] = it
          if reaper.IsMediaItemSelected(it) then sel[#sel + 1] = it end
        end
      end
    end
    for _, it in ipairs(#sel > 0 and sel or items) do take_envs(it, ts, te, cur) end
    if ALSO_WRITING_ENVELOPES then
      reaper.Main_OnCommand(42013, 0)   -- Automation: Write current values for actively-writing envelopes to time selection
    end
    return true
  end

  -- 2. Razor areas
  local any = false
  for _, tr in ipairs(all_tracks()) do
    local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if s ~= "" then
      local w = {}
      for x in s:gmatch("%S+") do w[#w + 1] = x end
      for j = 1, #w - 2, 3 do
        local a, b, guid = tonumber(w[j]), tonumber(w[j + 1]), w[j + 2]
        if a and b and b > a then
          any = true
          if guid == '""' then
            for k = 0, reaper.CountTrackMediaItems(tr) - 1 do
              local it = reaper.GetTrackMediaItem(tr, k)
              if overlaps(it, a, b) then take_envs(it, a, b, cur) end
            end
          else
            local env = reaper.GetTrackEnvelopeByChunkName(tr, guid:sub(2, -2))
            if env_ok(env, false) then write_env(env, a, b, cur, 0, math.huge) end
          end
        end
      end
    end
  end
  if any then return true end

  -- 3. Selected items
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return false end
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    track_envs(reaper.GetMediaItem_Track(it), p, e, cur)
    take_envs(it, nil, nil, cur)
  end
  return true
end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()
local done = main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock(done and "Write current value to envelopes" or "Write current value to envelopes (nothing to do)", -1)
