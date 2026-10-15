-- @description ReaTooled - Link Razor Area to Item Selection (Context-Aware)
-- @version 4.6
-- @date 2026.04.13
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Background utility script that ensures razor area edits select items intelligently.
--   - Razor areas that exactly match item bounds select only those items (click/script behavior).
--   - Broader or misaligned razor areas select all overlapping items (manual/drag behavior).
--   - Razor areas are preserved (never cleared or rewritten).
--   - Designed for seamless compatibility with ReaTooled Move Tool Left Click.
--   - Continuously tracks edit cursor position to ExtState for use by other ReaTooled scripts.
-- @changelog
--   v4.6 - Added continuous cursor position tracking to ExtState ("ReaTooled", "lastcursor")
--          for use by ReaTooled razor scripts that need pre-click cursor position

function RazorEditSelectionExists()
  for i = 0, reaper.CountTracks(0) - 1 do
    local _, area = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), "P_RAZOREDITS", "", false)
    if area ~= "" then return true end
  end
  return false
end

function GetRazorEdits()
  local areaMap = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    local str = {}
    for j in string.gmatch(area, "%S+") do
      table.insert(str, j)
    end
    local j = 1
    while j <= #str do
      local areaStart = tonumber(str[j])
      local areaEnd = tonumber(str[j+1])
      local GUID = str[j+2] or ""
      local isEnvelope = GUID ~= '""'
      table.insert(areaMap, {
        areaStart = areaStart,
        areaEnd = areaEnd,
        track = track,
        isEnvelope = isEnvelope
      })
      j = j + 3
    end
  end
  return areaMap
end

function DeselectAllMediaItems()
  for i = 0, reaper.CountMediaItems(0) - 1 do
    reaper.SetMediaItemSelected(reaper.GetMediaItem(0, i), false)
  end
end

function SelectItemsInRazorEdits()
  local selections = GetRazorEdits()
  reaper.PreventUIRefresh(1)
  DeselectAllMediaItems()
  for _, areaData in ipairs(selections) do
    if not areaData.isEnvelope then
      local track = areaData.track
      local itemCount = reaper.CountTrackMediaItems(track)
      local clickMatches = {}
      local overlapMatches = {}
      for i = 0, itemCount - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local isExact = math.abs(areaData.areaStart - itemStart) < 0.000001 and math.abs(areaData.areaEnd - itemEnd) < 0.000001
        local isOverlap = not (itemEnd <= areaData.areaStart or itemStart >= areaData.areaEnd)
        if isExact then
          table.insert(clickMatches, item)
        elseif isOverlap then
          table.insert(overlapMatches, item)
        end
      end
      if #clickMatches > 0 then
        for _, item in ipairs(clickMatches) do
          reaper.SetMediaItemSelected(item, true)
        end
      else
        for _, item in ipairs(overlapMatches) do
          reaper.SetMediaItemSelected(item, true)
        end
      end
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

local lastMouseState = reaper.JS_Mouse_GetState(1)

function Main()
  reaper.SetExtState("ReaTooled", "lastcursor", tostring(reaper.GetCursorPosition()), false)

  local currentMouseState = reaper.JS_Mouse_GetState(1)
  if lastMouseState == 1 and currentMouseState == 0 then
    reaper.defer(function()
      if RazorEditSelectionExists() then
        SelectItemsInRazorEdits()
      end
    end)
  end
  lastMouseState = currentMouseState
  reaper.defer(Main)
end

local cmd_id = ({reaper.get_action_context()})[4]
reaper.SetToggleCommandState(0, cmd_id, 1)
reaper.RefreshToolbar2(0, cmd_id)
reaper.atexit(function()
  reaper.SetToggleCommandState(0, cmd_id, 0)
  reaper.RefreshToolbar2(0, cmd_id)
end)
Main()
