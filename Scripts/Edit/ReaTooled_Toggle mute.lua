--[[
@description ReaTooled - Toggle mute (razor areas, items or tracks)
@version 1.0
@author Brendan Baker
@website https://brendanpatrickbaker.com/reatooled/
@about
  Based on TJF Toggle Mute by Tim Farrell.
  # Toggle mute
  Mutes or unmutes, like Pro Tools' Cmd+M. What it acts on, in order:
    1. Razor areas: the items are split at the area edges and only the parts inside
       the areas are muted (or unmuted). Locked items are left alone.
    2. Selected items.
    3. Selected tracks (the master too).
  If anything it acts on is unmuted, everything is muted; if everything is already
  muted, everything is unmuted.
  Item mutes are written to each item, so item grouping doesn't spread them.
@changelog
  v1.0 First version: razor areas mute just the part inside them.
--]]

local EPS = 1e-9

local function locked(it)
  return (math.floor(reaper.GetMediaItemInfo_Value(it, "C_LOCK")) & 1) == 1
end

-- Track-level razor areas (not envelope lanes): { {track, start, end}, ... }
local function razor_areas()
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if s ~= "" then
      local t = {}
      for w in s:gmatch("%S+") do t[#t + 1] = w end
      for j = 1, #t - 2, 3 do
        local a, b, guid = tonumber(t[j]), tonumber(t[j + 1]), t[j + 2]
        if guid == '""' and a and b and b > a then out[#out + 1] = { tr, a, b } end
      end
    end
  end
  return out
end

-- The parts of the unlocked items inside [a, b] on a track, split off at a and b
local function split_parts(tr, a, b, into)
  local hit = {}
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if p < b - EPS and e > a + EPS and not locked(it) then hit[#hit + 1] = { it, p, e } end
  end
  for _, h in ipairs(hit) do
    local it, p, e = h[1], h[2], h[3]
    if p < a - EPS then it = reaper.SplitMediaItem(it, a) or it end
    if it and e > b + EPS then reaper.SplitMediaItem(it, b) end   -- (it stays the left part)
    if it then into[#into + 1] = it end
  end
end

local function main()
  local kind, targets = nil, {}

  local areas = razor_areas()
  if #areas > 0 then
    kind = "items"
    for _, ar in ipairs(areas) do split_parts(ar[1], ar[2], ar[3], targets) end
    if #targets == 0 then return end           -- razor areas with no items in them: nothing to do
  elseif reaper.CountSelectedMediaItems(0) > 0 then
    kind = "items"
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do targets[#targets + 1] = reaper.GetSelectedMediaItem(0, i) end
  elseif reaper.CountSelectedTracks2(0, true) > 0 then
    kind = "tracks"
    for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do targets[#targets + 1] = reaper.GetSelectedTrack2(0, i, true) end
  else
    return
  end

  local get = kind == "items" and reaper.GetMediaItemInfo_Value or reaper.GetMediaTrackInfo_Value
  local set = kind == "items" and reaper.SetMediaItemInfo_Value or reaper.SetMediaTrackInfo_Value
  local mute = 0
  for _, o in ipairs(targets) do
    if get(o, "B_MUTE") < 0.5 then mute = 1; break end
  end
  for _, o in ipairs(targets) do set(o, "B_MUTE", mute) end

  return (mute == 1 and "Mute " or "Unmute ") .. kind
end

reaper.PreventUIRefresh(1)
reaper.Undo_BeginBlock()
local what = main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
if what then
  reaper.Undo_EndBlock(what, -1)
else
  reaper.Undo_EndBlock("Toggle mute (nothing to do)", -1)
end
