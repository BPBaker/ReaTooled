--[[
@description ReaTooled - Reverse (non-destructive)
@version 1.3
@author Brendan Baker
@website https://brendanpatrickbaker.com/reatooled/
@about
  Based on TJF Non Destructive Reverse by Tim Farrell.
  # Reverse (non-destructive)
  Reverses without rendering anything: each item's take is reversed and its fades
  swap ends. What it reverses, in order:
    1. Razor areas: the items in each area (split at its edges), each area on its own.
    2. Selected items.
  The time selection is ignored.
  Selected items are each reversed where they are: nothing moves.
  Razor areas (MIRROR_SELECTION below): on (the default), each area is flipped end to
  end within its own edges, as if the tape were played backwards, so the order of the
  items and the gaps in it reverses too. Off: each item part is reversed where it is.
  The razor areas and the item selection are kept, so running it again on razor areas
  puts everything back.
  Take envelopes flip with the item (REVERSE_TAKE_ENVELOPES below). Track envelopes
  and automation stay where they are. Locked items are left alone.
@changelog
  v1.3 Selected items are reversed in place (they don't move); MIRROR_SELECTION is for
       razor areas only.
  v1.2 Running it again un-reverses: razor areas and the item selection are kept as they
       were, and the items it just reversed flip back within the same edges.
  v1.1 Razor areas first, then selected items; the time selection is ignored (with Link
       Timeline and Edit Selection on, razor areas make one). New MIRROR_SELECTION setting.
  v1.0 First version: each razor area is reversed within its own edges; with a time selection only the
       parts inside it are reversed; take envelopes and snap offsets flip too.
--]]

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local MIRROR_SELECTION       = true   -- razor areas: true flips each area end to end; false reverses each item part in place
local REVERSE_TAKE_ENVELOPES = true   -- flip the active take's envelopes with the item
------------------------------------------------------------

local EPS = 1e-9

local function locked(it)
  return (math.floor(reaper.GetMediaItemInfo_Value(it, "C_LOCK")) & 1) == 1
end

local function span(it)
  local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  return p, p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
end

-- Split `it` at a and b; returns the part inside [a, b] (or nil)
local function inside_part(it, a, b)
  local p, e = span(it)
  if p >= b - EPS or e <= a + EPS then return nil end
  if p < a - EPS then it = reaper.SplitMediaItem(it, a) end
  if it and e > b + EPS then reaper.SplitMediaItem(it, b) end
  return it
end

local function swap(it, k1, k2)
  local v1 = reaper.GetMediaItemInfo_Value(it, k1)
  reaper.SetMediaItemInfo_Value(it, k1, reaper.GetMediaItemInfo_Value(it, k2))
  reaper.SetMediaItemInfo_Value(it, k2, v1)
end

-- A segment's shape seen from the other end
local MIRROR_SHAPE = { [3] = 4, [4] = 3 }   -- fast start <-> fast end; the others look the same

local SR = 48000   -- (Envelope_Evaluate's sample rate; any value works for one value)

local function flip_envelope(env, L)
  local n = reaper.CountEnvelopePoints(env)
  if n == 0 then return end
  local _, v0 = reaper.Envelope_Evaluate(env, 0, SR, 0)
  local _, vL = reaper.Envelope_Evaluate(env, L, SR, 0)
  -- the points inside (0, L), with a point at each end holding the value there
  local first = { t = 0, v = v0, sh = 0, ten = 0, sel = false }
  local pts = { first }
  for i = 0, n - 1 do
    local _, t, v, sh, ten, sel = reaper.GetEnvelopePoint(env, i)
    if t <= EPS then first.sh, first.ten = sh, ten          -- (its shape carries on past 0)
    elseif t < L - EPS then pts[#pts + 1] = { t = t, v = v, sh = sh, ten = ten, sel = sel } end
  end
  pts[#pts + 1] = { t = L, v = vL, sh = 0, ten = 0, sel = false }

  -- Mirrored: the segment from point i-1 to point i now runs from L-t[i] to L-t[i-1],
  -- so it starts at the point for i and takes the shape point i-1 had
  local out = {}
  for i = #pts, 1, -1 do
    local p, before = pts[i], pts[i - 1]
    local t = L - p.t
    if before and before.sh == 1 then
      -- square: the reversed segment must hold before's value from t on. The segment
      -- arriving at t ends on p's value, unless it is a square one too
      local nxt = pts[i + 1]
      if nxt and p.sh ~= 1 then out[#out + 1] = { t = t - 1e-6, v = p.v, sh = 0, ten = 0, sel = p.sel } end
      out[#out + 1] = { t = t, v = before.v, sh = 1, ten = 0, sel = p.sel }
    else
      local sh, ten = 0, 0
      if before then
        sh, ten = before.sh, before.ten
        if sh == 5 then ten = -ten end                      -- bezier: bend the other way
        sh = MIRROR_SHAPE[sh] or sh
      end
      out[#out + 1] = { t = t, v = p.v, sh = sh, ten = ten, sel = p.sel }
    end
  end

  reaper.DeleteEnvelopePointRange(env, -1e9, 1e9)
  for _, p in ipairs(out) do
    if p.t >= -EPS then reaper.InsertEnvelopePoint(env, math.max(0, p.t), p.v, p.sh, p.ten, p.sel or false, true) end
  end
  reaper.Envelope_SortPoints(env)
end

local function reverse_item(it, a, b)
  local p, e = span(it)
  local len = e - p
  if MIRROR_SELECTION then reaper.SetMediaItemInfo_Value(it, "D_POSITION", a + b - e) end

  swap(it, "D_FADEINLEN", "D_FADEOUTLEN")
  swap(it, "D_FADEINLEN_AUTO", "D_FADEOUTLEN_AUTO")
  swap(it, "D_FADEINDIR", "D_FADEOUTDIR")
  swap(it, "C_FADEINSHAPE", "C_FADEOUTSHAPE")

  local snap = reaper.GetMediaItemInfo_Value(it, "D_SNAPOFFSET")
  if snap > 0 and snap < len then reaper.SetMediaItemInfo_Value(it, "D_SNAPOFFSET", len - snap) end

  local take = reaper.GetActiveTake(it)
  if REVERSE_TAKE_ENVELOPES and take then
    local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    for k = 0, reaper.CountTakeEnvelopes(take) - 1 do
      flip_envelope(reaper.GetTakeEnvelope(take, k), len * rate)
    end
  end
end

local function main()
  local jobs = {}   -- { item, start, end }
  local razors = {} -- track -> its razor areas, put back afterwards
  do
    local any_razor = false
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
      if s ~= "" then
        razors[tr] = s
        local w = {}
        for x in s:gmatch("%S+") do w[#w + 1] = x end
        for j = 1, #w - 2, 3 do
          local a, b = tonumber(w[j]), tonumber(w[j + 1])
          if w[j + 2] == '""' and a and b and b > a then
            any_razor = true
            local hit = {}
            for k = 0, reaper.CountTrackMediaItems(tr) - 1 do
              local it = reaper.GetTrackMediaItem(tr, k)
              local p, e = span(it)
              if p < b - EPS and e > a + EPS and not locked(it) then hit[#hit + 1] = it end
            end
            for _, it in ipairs(hit) do
              local part = inside_part(it, a, b)
              if part then jobs[#jobs + 1] = { part, a, b } end
            end
          end
        end
      end
    end

    if not any_razor then   -- selected items: each reversed in place
      for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local it = reaper.GetSelectedMediaItem(0, i)
        if not locked(it) then
          local p, e = span(it)
          jobs[#jobs + 1] = { it, p, e }
        end
      end
    end
  end

  if #jobs == 0 then return false end

  for _, j in ipairs(jobs) do reverse_item(j[1], j[2], j[3]) end

  -- Reverse the takes of exactly these items, then put the item selection and the
  -- razor areas back as they were (so running it again un-reverses)
  local was = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do was[#was + 1] = reaper.GetSelectedMediaItem(0, i) end
  reaper.SelectAllMediaItems(0, false)
  for _, j in ipairs(jobs) do reaper.SetMediaItemSelected(j[1], true) end
  reaper.Main_OnCommand(41051, 0)   -- Item properties: Toggle take reverse
  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(was) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then reaper.SetMediaItemSelected(it, true) end
  end
  for tr, str in pairs(razors) do reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", str, true) end
  return true
end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()
local done = main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock(done and "Reverse" or "Reverse (nothing to do)", -1)
