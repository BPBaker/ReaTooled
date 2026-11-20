--[[
@description ReaTooled - Loop item source section (razor area or time selection)
@version 1.0
@author Brendan Baker
@website https://brendanpatrickbaker.com/reatooled/
@about
  Based on Rodilab's "Loop section of audio/midi item source within time selection, if any".
  # Loop item source section
  Turns part of an item into a loop: the item is cut to the selection (padded with
  silence if it's shorter) and set to loop just that section of its source, so
  extending its edge repeats it.
  What it works on, in order:
    1. Razor areas: the items in each area, split at the area edges. The parts outside
       the areas stay as they are.
    2. Selected items, within the time selection if it touches them (split at its
       edges in the same way).
    3. Selected items, whole.
  The processed items end up selected. Razor areas and the time selection are kept.
  Locked items are left alone.
@changelog
  v1.0 ReaTooled's own version, replacing Rodilab's script: razor areas first, and
       the parts of an item outside the selection are kept instead of deleted.
--]]

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

local function only_select(it)
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(it, true)
end

local function is_midi(take)
  return take and reaper.TakeIsMIDI(take)
end

-- Make one item loop the section from a to b of itself
local function loop_section(it, a, b)
  local take = reaper.GetActiveTake(it)
  if not take then return end
  only_select(it)

  local p, e = span(it)
  if math.abs(p - a) > EPS or math.abs(e - b) > EPS then
    -- shorter than the area: extend it to the area, padded with silence
    reaper.GetSet_LoopTimeRange2(0, true, false, a, b, false)
    reaper.Main_OnCommand(41385, 0)   -- Item: Fit items to time selection, padding with silence if needed
  end

  if is_midi(take) then
    reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
    reaper.MIDI_SetItemExtents(it, reaper.TimeMap2_timeToQN(0, a), reaper.TimeMap2_timeToQN(0, b))
    reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 1)
  else
    reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 1)
    reaper.GetSet_LoopTimeRange2(0, true, false, a, b, false)
    local src = reaper.GetMediaItemTake_Source(take)
    if reaper.PCM_Source_GetSectionInfo(src) then
      reaper.Main_OnCommand(40547, 0)  -- (already a section: once to take it off...)
    end
    reaper.Main_OnCommand(40547, 0)    -- Item properties: Loop section of audio item source
  end
end

local function main()
  local jobs = {}   -- { item, start, end }
  local razors = {}

  -- 1. Razor areas
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

  -- 2./3. Selected items, within the time selection if it touches them
  if next(razors) == nil then
    local ts, te = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local sel = {}
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = reaper.GetSelectedMediaItem(0, i) end
    for _, it in ipairs(sel) do
      if not locked(it) then
        local p, e = span(it)
        if te - ts > EPS and p < te - EPS and e > ts + EPS then
          local part = inside_part(it, ts, te)
          if part then jobs[#jobs + 1] = { part, ts, te } end
        else
          jobs[#jobs + 1] = { it, p, e }
        end
      end
    end
  end

  if #jobs == 0 then return false end

  -- (the time selection and loop points are borrowed below, then put back)
  local ts, te = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  local ls, le = reaper.GetSet_LoopTimeRange2(0, false, true, 0, 0, false)

  for _, j in ipairs(jobs) do loop_section(j[1], j[2], j[3]) end

  reaper.GetSet_LoopTimeRange2(0, true, false, ts, te, false)
  reaper.GetSet_LoopTimeRange2(0, true, true, ls, le, false)
  reaper.SelectAllMediaItems(0, false)
  for _, j in ipairs(jobs) do
    if reaper.ValidatePtr2(0, j[1], "MediaItem*") then reaper.SetMediaItemSelected(j[1], true) end
  end
  for tr, s in pairs(razors) do reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", s, true) end
  return true
end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()
local done = main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock(done and "Loop item source section" or "Loop item source section (nothing to do)", -1)
