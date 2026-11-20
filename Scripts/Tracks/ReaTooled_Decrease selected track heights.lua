--[[
@description ReaTooled - Decrease selected track heights
@version 1.0
@author Brendan Baker
@website https://brendanpatrickbaker.com/reatooled/
@about
  Based on TJF Decrease Selected Track Heights by Tim Farrell.
  # Decrease selected track heights
  Makes tracks shorter in steps, like Pro Tools' Ctrl+Down.
  The steps are in STEPS below (pixels). All the tracks go to the same step: the
  next one below the first track's height.
  Which tracks, in order: the selected tracks; else the tracks with razor areas;
  else the tracks of the selected items; else the track under the mouse.
  Tracks whose height is locked are left alone. No undo point (it's a view change).
@changelog
  v1.0 First version:
       uses the track's own height (not counting envelope lanes), gives folder
       tracks their own minimum correctly, and works
       without a track selection.
--]]

------------------------------------------------------------
-- Settings
------------------------------------------------------------
local STEPS = { 64, 150, 300, 600, 900 }   -- track heights in pixels, smallest first
local MIN_TRACK  = 15                      -- the smallest height (REAPER keeps it at least the theme's minimum)
local MIN_FOLDER = 25                      -- the smallest height for folder tracks
------------------------------------------------------------

local function add(list, seen, tr)
  if tr and not seen[tr] then seen[tr] = true; list[#list + 1] = tr end
end

local function targets()
  local list, seen = {}, {}
  for i = 0, reaper.CountSelectedTracks2(0, true) - 1 do add(list, seen, reaper.GetSelectedTrack2(0, i, true)) end
  if #list > 0 then return list, true end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if s ~= "" then add(list, seen, tr) end
  end
  if #list > 0 then return list end
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    add(list, seen, reaper.GetMediaItem_Track(reaper.GetSelectedMediaItem(0, i)))
  end
  if #list > 0 then return list end
  local x, y = reaper.GetMousePosition()
  add(list, seen, (reaper.GetTrackFromPoint(x, y)))
  return list
end

local function height_of(tr)
  local h = reaper.GetMediaTrackInfo_Value(tr, "I_TCPH")
  if not h or h <= 0 then h = reaper.GetMediaTrackInfo_Value(tr, "I_WNDH") end
  return h
end

local function main()
  local list, selected = targets()
  if #list == 0 then return end
  local h = height_of(list[1])
  local new_h = MIN_TRACK
  for i = #STEPS, 1, -1 do
    if STEPS[i] < h - 1 then new_h = STEPS[i]; break end   -- (-1: the theme can round a height by a pixel)
  end
  local changed = false
  for _, tr in ipairs(list) do
    if reaper.GetMediaTrackInfo_Value(tr, "B_HEIGHTLOCK") < 0.5 then
      local t = new_h
      if t == MIN_TRACK and reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 then t = MIN_FOLDER end
      reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", t)
      changed = true
    end
  end
  if not changed then return end
  reaper.TrackList_AdjustWindows(false)
  if selected then reaper.Main_OnCommand(40913, 0) end   -- Track: Vertical scroll selected tracks into view
end

main()
reaper.defer(function() end)   -- no undo point
