-- @description ReaTooled - Smart Remove
-- @version 1.8
-- @date 2025.05.07
-- @author Brendan Baker - but really modified from Smart remove by Rodrigo Diaz (aka Rodilab)
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   If time selection is set and last focus on items, then cut selected area of items. ReaTooled Added: also clear time selection and loop points
--   ReaTooled Added: Else if time selection is not set and last focus is on items, remove item and move edit cursor to left edge of item
--   Else, remove items/tracks/envelope points (depending on focus)
--   ## v1.4 change "cut" to "remove"
--   ## v1.5 Disable move cursor to item (PT-like cursor movement is handled via Mouse Modifiers)
--   ## v1.6 Revise edit cursor behavior to move edit cursor to item's former start position if item was selected
--   ## v1.7 Replaced scroll-causing command with direct cursor move
--   ## v1.8 Let REAPER handle Razor Edit deletion naturally but explicitly move cursor to Razor Edit start if needed

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local function GetFirstRazorStart()
  local first_start = nil
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local ret, razor_str = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if razor_str ~= "" then
      for start_s, end_s in string.gmatch(razor_str, "(%S+) (%S+)") do
        local start = tonumber(start_s)
        if not first_start or start < first_start then
          first_start = start
        end
        break -- only look at the first area per track
      end
    end
  end
  return first_start
end

local function HasRazorEdits()
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local ret, razor = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if razor ~= "" then return true end
  end
  return false
end

local time_sel_start, time_sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
local focus = reaper.GetCursorContext2(true)
local window, segment, details = reaper.BR_GetMouseCursorContext()

if HasRazorEdits() and focus == 1 then
  local razor_start = GetFirstRazorStart()
  if razor_start then
    reaper.SetEditCurPos(razor_start, false, false)
  end
  reaper.Main_OnCommand(40312, 0) -- Remove content of time selection (items only)
  reaper.Main_OnCommand(40020, 0) -- Remove time selection and loop points

elseif time_sel_end - time_sel_start == 0 and focus == 1 then
  local item = reaper.GetSelectedMediaItem(0, 0)
  if item then
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.SetEditCurPos(pos, false, false)
  end
  reaper.Main_OnCommand(40697, 0) -- Remove items/tracks/envelope points (depending on focus)

else
  if window == "tcp" and segment == "envelope" then
    reaper.Main_OnCommand(40065, 0) -- Remove envelope
  else
    reaper.Main_OnCommand(40697, 0) -- Remove items/tracks/envelope points
  end
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Smart remove", 0)
reaper.UpdateArrange()

