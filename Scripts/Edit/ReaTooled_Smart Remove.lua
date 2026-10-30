-- @description ReaTooled - Smart Remove
-- @version 1.10
-- @date 2026.10.30
-- @author Brendan Baker - but really modified from Smart remove by Rodrigo Diaz (aka Rodilab)
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Context-aware remove, Pro Tools style.
--   - Razor edits present and focus on items: remove razor areas, move edit cursor to the earliest razor start, clear time selection.
--   - Time selection and focus on items: remove the selected area (gaps included, so ripple closes the whole range). With no items selected, removes across all tracks. Moves edit cursor to selection start and clears the time selection.
--   - No time selection and focus on items: remove selected items and move edit cursor to the item's former start.
--   - Otherwise: remove items/tracks/envelope points depending on focus. With the mouse over a track envelope's control panel, remove that envelope (REAPER asks for confirmation).
--   SWS is optional; without it the envelope-panel check is skipped.
--   ## v1.4 change "cut" to "remove"
--   ## v1.5 Disable move cursor to item (PT-like cursor movement is handled via Mouse Modifiers)
--   ## v1.6 Revise edit cursor behavior to move edit cursor to item's former start position if item was selected
--   ## v1.7 Replaced scroll-causing command with direct cursor move
--   ## v1.8 Let REAPER handle Razor Edit deletion naturally but explicitly move cursor to Razor Edit start if needed
--   ## v1.9 Restore time-selection branch (v1.8 dropped it, so selections spanning gaps deleted whole items and kept the gap)
--   ## v1.10 SWS now optional; single-step undo; updated description

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local function GetFirstRazorStart()
  local first_start = nil
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, razor_str = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if razor_str ~= "" then
      local start = tonumber(razor_str:match("^(%S+)"))
      if start and (not first_start or start < first_start) then
        first_start = start
      end
    end
  end
  return first_start
end

local function HasRazorEdits()
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, razor = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if razor ~= "" then return true end
  end
  return false
end

local time_sel_start, time_sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
local has_time_sel = time_sel_end - time_sel_start > 0
local focus = reaper.GetCursorContext2(true)

-- SWS is optional: only used to detect the mouse over a track envelope's control panel
local window, segment = "", ""
if reaper.BR_GetMouseCursorContext then
  window, segment = reaper.BR_GetMouseCursorContext()
end

if focus == 1 and HasRazorEdits() then
  local razor_start = GetFirstRazorStart()
  if razor_start then
    reaper.SetEditCurPos(razor_start, false, false)
  end
  reaper.Main_OnCommand(40312, 0) -- Remove selected area of items (handles razor areas)
  reaper.Main_OnCommand(40020, 0) -- Remove time selection and loop points

elseif focus == 1 and has_time_sel then
  reaper.SetEditCurPos(time_sel_start, false, false)
  reaper.Main_OnCommand(40312, 0) -- Remove selected area of items (includes gaps)
  reaper.Main_OnCommand(40020, 0) -- Remove time selection and loop points

elseif focus == 1 then
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
reaper.Undo_EndBlock("Smart remove", -1)
reaper.UpdateArrange()
