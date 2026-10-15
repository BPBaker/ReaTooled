-- @description ReaTooled - Toggle Link loop points and razor areas (with ▶ management & last-known play pos)
-- @version 1.5
-- @date 2025.08.21
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about


local reaper = reaper

-- ========= ▶ Play Marker helpers (ID 0 forced) =========
local PM_SECTION = "Play-Stop with memory"
local PM_NAME    = "▶"
local PM_COLOR   = reaper.ColorToNative(255,255,255) | 0x1000000
local EPS        = 1e-6

-- Delete ALL ▶ markers (by NAME ONLY)
local function PM_DeleteAll()
  local _, nm, nr = reaper.CountProjectMarkers(0)
  local total = (nm or 0) + (nr or 0)
  for i = total - 1, 0, -1 do
    local _, isrgn, _, _, name = reaper.EnumProjectMarkers3(0, i)
    if (not isrgn) and (name == PM_NAME) then
      reaper.DeleteProjectMarkerByIndex(0, i)
    end
  end
  reaper.UpdateTimeline()
end

-- Delete all ▶ except the one that currently owns ID 0 (by NAME ONLY)
local function PM_DeleteOtherPlayMarkersKeepID0()
  local _, nm, nr = reaper.CountProjectMarkers(0)
  local total = (nm or 0) + (nr or 0)
  for i = total - 1, 0, -1 do
    local _, isrgn, _, _, name, id = reaper.EnumProjectMarkers3(0, i)
    if (not isrgn) and (name == PM_NAME) and id ~= 0 then
      reaper.DeleteProjectMarkerByIndex(0, i)
    end
  end
end

local function PM_ForceID0At(pos)
  if type(pos) ~= "number" then return end
  local prev = tonumber(reaper.GetExtState(PM_SECTION, "CurrentMarkerPosition") or "")
  local place_pos = (prev and math.abs(prev - pos) < EPS) and (pos + 1e-4) or pos

  reaper.PreventUIRefresh(1)

  local _, nm, nr = reaper.CountProjectMarkers(0)
  local total = (nm or 0) + (nr or 0)
  local id0_isrgn, id0_pos, id0_rgnend, id0_name, id0_color, id0_found = nil,nil,nil,nil,nil,false
  for i = 0, total - 1 do
    local _, isrgn, pos0, rgnend0, name0, id0, color0 = reaper.EnumProjectMarkers3(0, i)
    if id0 == 0 then
      id0_isrgn, id0_pos, id0_rgnend, id0_name, id0_color, id0_found =
        isrgn, pos0, rgnend0, name0, color0, true
      break
    end
  end

  if id0_found then
    if (not id0_isrgn) and (id0_name == PM_NAME) then
      reaper.SetProjectMarker3(0, 0, false, place_pos, 0.0, PM_NAME, PM_COLOR)
    else
      if id0_isrgn then
        reaper.AddProjectMarker2(0, true,  id0_pos, id0_rgnend, id0_name or "", -1, id0_color or 0)
        reaper.DeleteProjectMarker(0, 0, true)
      else
        reaper.AddProjectMarker2(0, false, id0_pos, 0.0,       id0_name or "", -1, id0_color or 0)
        reaper.DeleteProjectMarker(0, 0, false)
      end
      reaper.AddProjectMarker2(0, false, place_pos, 0.0, PM_NAME, 0, PM_COLOR)
    end
  else
    reaper.AddProjectMarker2(0, false, place_pos, 0.0, PM_NAME, 0, PM_COLOR)
  end

  PM_DeleteOtherPlayMarkersKeepID0()
  reaper.SetExtState(PM_SECTION, "CurrentMarkerPosition", tostring(place_pos), false)
  reaper.UpdateTimeline()
  reaper.PreventUIRefresh(-1)
end
-- ========= end ▶ helpers =========


-- ========= ExtState helpers (read “last known play”) =========
local ESKEY = "Play-Stop with memory"
local function getESnum(key)
  local v = reaper.GetExtState(ESKEY, key)
  if v == nil or v == "" then return nil end
  local n = tonumber(v)
  if n ~= n then return nil end -- NaN guard
  return n
end

-- Returns best “last known play position”, or nil if none
local function get_last_known_play_pos()
  return getESnum("PrevPlayPosition")
      or getESnum("CurrentPlayPosition")
      or getESnum("StartPosAtPlay")
      or getESnum("CurrentMarkerPosition")
end
-- ========= end ExtState helpers =========


-- Get the toggle script's own command ID
local _, _, sectionID, cmdID = reaper.get_action_context()
local toggleScriptCmdID = cmdID

-- Command ID of the BACKGROUND LINK script
local mainScriptCmdID = reaper.NamedCommandLookup("_RS048404ce084ffe20d301c9941d3e096d2ee1d8f6")

-- ExtState for LP+EC toggle
local extstateKey = "ReaTooled"
local extstateVar = "LinkLoopRazor" -- LP+EC state key
local extstate = reaper.GetExtState(extstateKey, extstateVar)
if extstate == "" then extstate = "0" end  -- Default to OFF

local function RunMainScript()
  if mainScriptCmdID > 0 then
    reaper.Main_OnCommandEx(mainScriptCmdID, 0, 0)
  else
    reaper.ShowConsoleMsg("Error: Main linking script command ID not found.\n")
  end
end

local function KillMainScript()
  if mainScriptCmdID > 0 then
    reaper.Main_OnCommandEx(mainScriptCmdID, 0, 1)
  else
    reaper.ShowConsoleMsg("Error: Main linking script command ID not found.\n")
  end
end

-- Helpers to read loop points
local function GetLoopPoints()
  local s, e = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
  return s, e, (e > s)
end

-- ===== Toggle logic (LP+EC) =====
if extstate == "1" then
  -- LP+EC was ON → turn OFF
  reaper.SetExtState(extstateKey, extstateVar, "0", true)
  reaper.SetToggleCommandState(sectionID, toggleScriptCmdID, 0)
  reaper.RefreshToolbar2(sectionID, toggleScriptCmdID)

  KillMainScript()

  -- LP+EC just turned OFF → place ▶ at last known play, else fallback to edit cursor
  local pos = get_last_known_play_pos()
  if not pos then
    -- Optional: prefer loop start if exists
    -- local ls, le, has_lp = GetLoopPoints()
    -- pos = has_lp and ls or reaper.GetCursorPosition()
    pos = reaper.GetCursorPosition()
  end
  PM_ForceID0At(pos)

else
  -- LP+EC was OFF → turn ON
  reaper.SetExtState(extstateKey, extstateVar, "1", true)
  reaper.SetToggleCommandState(sectionID, toggleScriptCmdID, 1)
  reaper.RefreshToolbar2(sectionID, toggleScriptCmdID)

  RunMainScript()

  -- LP+EC just turned ON → remove ▶
  PM_DeleteAll()
end

function NoUndoPoint() end
reaper.defer(NoUndoPoint)
