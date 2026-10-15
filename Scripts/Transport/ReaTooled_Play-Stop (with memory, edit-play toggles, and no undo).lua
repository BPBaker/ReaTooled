-- @description ReaTooled - Transport (LP-first start, v2.4 stop-cursor behavior, Loop Points only) + v1.2-style Play Marker (LP+EC OFF) [ID 0 forced]
-- @version 2.7.6
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   • Loop Points only (no Time Selection calls).
--   • LP-first start: if Loop Points exist, always start from LP start.
--   • v2.4 stop guard retained (LP+EC ON + Follow ON only snap edit to playhead if user didn’t move edit during playback).
--   • LP+EC OFF (“unlinked” like v1.2), with ▶ singleton:
--       – ▶ is **only visible while stopped** (hidden during playback).
--       – Start (no LP): launch from ▶ if it exists; else from edit; edit is then restored.
--       – Start (LP present): launch from loop start; edit restored.
--       – Stop: Follow OFF → ▶ at last START; Follow ON → ▶ at last STOP.
--       – If stopping with LP present and Follow ON: clear LP *first* so ▶ reflects last play pos.
--   • ▶ Play Marker is forced to **ID 0** (evicts the previous ID 0 marker/region if needed).
--   • When LP+EC turns ON, ▶ is auto-deleted.
--   • Never creates undo points.

-- @changelog
--   v2.7.6
--     - Never creates undo points:
--         • Ends with a no-op reaper.defer() so REAPER skips the automatic
--           script undo point (previously created whenever ▶ was added/moved/deleted,
--           or a marker was evicted from ID 0).
--         • Razor-area clearing now writes P_RAZOREDITS directly instead of running
--           action 42406, which created its own "Remove razor edit areas" undo point.
--     - Rapid re-presses: on REAPER 7.03+, set_action_options(3) terminates and
--       relaunches instead of showing the "script is already running" dialog.
--   v2.7.5
--     - Renamed all references from LLR → LP+EC (Link Play & Edit Cursor).
--     - Updated @about text to reflect LP+EC wording.
--     - No functional changes beyond naming; name-only deletion strategy retained.
--   v2.7.4
--     - Deletion strategy tightened: delete ▶ by **name only** (no color matching).
--     - PM_GetByName now returns ▶ by name only.
--     - Minor: added @link line in header.
--   v2.7.3
--     - Merged 2.7.2’s “▶ visible only while stopped” into the ID-0 version:
--         • On Play: compute start, then delete ▶ so it’s hidden during playback.
--         • On Stop: place ▶ per the LP+EC/Follow matrix.
--     - Re-read loop points *after* stopping to avoid stale loop-state when placing ▶.
--     - Minor robustness: PM_GetByColor now matches by name OR color.
--   v2.7.2
--     - Policy change: display the ▶ Play Marker only when transport is stopped.
--       Deleted on Play start; (re)placed on Stop according to matrix.
--   v2.7.1
--     - Introduced ▶ ID-0 forcing (singleton): evict ID 0 occupant (marker/region), recreate it at auto ID, then claim ID 0 for ▶.
--     - Auto-delete ▶ when LP+EC turns ON.
--     - Fix: PM_GetByColor Lua syntax; small nudge on same-position writes to avoid lane/hit-test quirks.
--     - Special case: LP+EC OFF + Follow ON + LP present → clear LP *before* Stop so ▶ represents last play pos.
--   v2.7.0
--     - Baseline: LP-first start, v2.4 stop-cursor guard, LP+EC-OFF uses ▶ as authoritative start, edit “stays put”.

local reaper = reaper
local EPS = 1e-6

-- Because this script ends with a no-op defer (to suppress undo points), a fast
-- re-press could otherwise trigger the "already running" dialog. REAPER 7.03+:
-- 1 = auto-terminate on relaunch, 2 = then relaunch.
if reaper.set_action_options then reaper.set_action_options(1 | 2) end

-- Command lookups
local CMD_FOLLOW_TGL = reaper.NamedCommandLookup("_RSe16d9e990f3d5fcec42256f63e00086d75b71288")
local CMD_LP_EC_TGL  = reaper.NamedCommandLookup("_RSed328eb507619b18c1154efa1b048d816cfc2d0c")
local RULER_MOUSEMOD = "_9666c9bb52a6499facd6a038b11d0f66"

-- =========================
-- ▶ Play Marker helpers — force ID 0
-- =========================
local PM_SECTION = "Play-Stop with memory"
local PM_NAME    = "▶"
local PM_COLOR   = reaper.ColorToNative(255,255,255) | 0x1000000

-- Name-only predicate: this is considered the definitive identity of ▶
local function PM_IsPlayMarkerByName(isrgn, name)
  return (not isrgn) and (name == PM_NAME)
end

-- Delete ALL ▶ markers (by name only)
local function PM_DeleteAll()
  local _, nm, nr = reaper.CountProjectMarkers(0)
  local total = (nm or 0) + (nr or 0)
  for i = total - 1, 0, -1 do
    local _, isrgn, _, _, name = reaper.EnumProjectMarkers3(0, i)
    if PM_IsPlayMarkerByName(isrgn, name) then
      -- index-safe delete
      reaper.DeleteProjectMarkerByIndex(0, i)
    end
  end
  reaper.UpdateTimeline()
end

-- Delete all ▶ except the one that currently owns ID 0 (name-only)
local function PM_DeleteOtherPlayMarkersKeepID0()
  local _, nm, nr = reaper.CountProjectMarkers(0)
  local total = (nm or 0) + (nr or 0)
  for i = total - 1, 0, -1 do
    local _, isrgn, _, _, name, id = reaper.EnumProjectMarkers3(0, i)
    if PM_IsPlayMarkerByName(isrgn, name) and id ~= 0 then
      reaper.DeleteProjectMarkerByIndex(0, i)
    end
  end
end

-- Force ▶ to be ID 0; if something else is at ID 0, evict it properly
local function PM_ForceID0At(pos)
  if type(pos) ~= "number" then return end
  -- tiny nudge if writing same timestamp (avoids rare hit-test quirk)
  local prev = tonumber(reaper.GetExtState(PM_SECTION, "CurrentMarkerPosition") or "")
  local place_pos = (prev and math.abs(prev - pos) < EPS) and (pos + 1e-4) or pos

  reaper.PreventUIRefresh(1)

  -- Find current ID 0 occupant
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
    if PM_IsPlayMarkerByName(id0_isrgn, id0_name) then
      -- ID 0 already our ▶ → move in place
      reaper.SetProjectMarker3(0, 0, false, place_pos, 0.0, PM_NAME, PM_COLOR)
    else
      -- Evict current ID 0 to a new auto ID, then claim ID 0
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
    -- No ID 0 exists → create ▶ at ID 0
    reaper.AddProjectMarker2(0, false, place_pos, 0.0, PM_NAME, 0, PM_COLOR)
  end

  -- Cleanup any stray ▶ (non-0)
  PM_DeleteOtherPlayMarkersKeepID0()

  -- Track position
  reaper.SetExtState(PM_SECTION, "CurrentMarkerPosition", tostring(place_pos), false)

  reaper.UpdateTimeline()
  reaper.PreventUIRefresh(-1)
end

-- Get ▶ by NAME ONLY (returns position or nil)
local function PM_GetByName()
  local _, nm, nr = reaper.CountProjectMarkers(0)
  local total = (nm or 0) + (nr or 0)
  for i = 0, total - 1 do
    local _, isrgn, pos, _, name = reaper.EnumProjectMarkers3(0, i)
    if PM_IsPlayMarkerByName(isrgn, name) then
      return pos
    end
  end
  return nil
end

-- ============ Small helpers (Loop Points only; no Time Selection)
local function ApplyRulerMouseMod()
  reaper.SetMouseModifier('MM_CTX_RULER_CLK', 0, RULER_MOUSEMOD)
end

-- Clear razor areas via the API (action 42406 would create its own undo point).
-- Clearing P_RAZOREDITS on a track also clears razor areas on its envelopes.
local function ClearRazor()
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local ok, area = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if ok and area ~= "" then
      reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", true)
    end
  end
end

local function ClearLoopPoints()
  reaper.GetSet_LoopTimeRange(true, true, 0, 0, false)
end

local function GetLoopPoints()
  local s, e = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
  return s, e, (e > s)
end

-- Toggle reads
local FOLLOW_ON = (reaper.GetToggleCommandStateEx(0, CMD_FOLLOW_TGL) == 1)
local LP_EC_ON  = (reaper.GetToggleCommandStateEx(0, CMD_LP_EC_TGL)  == 1)

-- Auto-clean: if LP+EC just turned ON, delete Play Marker
do
  local prevLP_EC = reaper.GetExtState(PM_SECTION, "PrevLP_ECState")
  if prevLP_EC == "" then prevLP_EC = nil end
  local prevLP_ECnum = prevLP_EC and tonumber(prevLP_EC) or nil
  if LP_EC_ON and (prevLP_ECnum == nil or prevLP_ECnum == 0) then
    PM_DeleteAll()
  end
  reaper.SetExtState(PM_SECTION, "PrevLP_ECState", (LP_EC_ON and "1" or "0"), false)
end

-- State capture
local playstate   = reaper.GetPlayState()
local edit_pos    = reaper.GetCursorPosition()
local play_pos    = reaper.GetPlayPosition() -- capture BEFORE any stop

-- ExtState helpers
local ESKEY = "Play-Stop with memory"
local function getES(k, fallback)
  local v = reaper.GetExtState(ESKEY, k)
  if v == "" then return fallback end
  return tonumber(v) or fallback
end
local function setES(k, v) reaper.SetExtState(ESKEY, k, tostring(v), false) end

-- Keep BOTH last and previous play positions (unchanged bookkeeping)
local prev_play_pos2 = getES("PrevPlayPosition2", play_pos) -- older previous (two stops ago)
local prev_play_pos  = getES("PrevPlayPosition",  play_pos) -- previous (last stop)
local prev_edit_pos  = getES("PrevEditPosition",  edit_pos)

-- Also track where edit cursor and start pos were at play start (for LP+EC-OFF “edit stays put”)
local edit_pos_at_play_start = reaper.GetExtState(ESKEY, "EditPosAtPlayStart")
local start_pos_at_play      = reaper.GetExtState(ESKEY, "StartPosAtPlay")

-- =============== PLAYING -> STOP (manual) ===============
if playstate > 0 then
  ApplyRulerMouseMod()

  -- Special case:
  -- If LP+EC OFF + Follow ON + loop exists, clear LP *before* we stop
  -- so the post-stop ▶ reflects the last play pos.
  local had_lp_before_stop = false
  local lp_start_before, lp_end_before
  do
    local s, e, has_lp = GetLoopPoints()
    had_lp_before_stop = has_lp
    lp_start_before = s; lp_end_before = e
    if (not LP_EC_ON) and FOLLOW_ON and has_lp then
      ClearLoopPoints()
    end
  end

  reaper.Main_OnCommand(1016, 0) -- Stop

  -- LP+EC ON behavior (v2.4 guard etc.)
  if LP_EC_ON and FOLLOW_ON then
    if math.abs(edit_pos - prev_edit_pos) < EPS then
      reaper.SetEditCurPos2(0, play_pos, false, false)
    end
    ClearLoopPoints()
    ClearRazor()

  elseif LP_EC_ON and not FOLLOW_ON then
    -- edit unchanged; clear nothing

  -- LP+EC OFF behavior
  elseif (not LP_EC_ON) and FOLLOW_ON then
    -- “unlinked”: edit stays put; clear LP only (RA untouched here)
    -- (LP already cleared above if it existed; safe to clear again no-op)
    ClearLoopPoints()

  else
    -- LP+EC OFF, FOLLOW OFF: edit unchanged; clear nothing
  end

  -- Re-check loop points *after* stop for accurate ▶ placement
  local lp_start_after, lp_end_after, has_lp_after = GetLoopPoints()

  -- LP+EC OFF: Place ▶ appropriately and restore edit to pre-play
  if not LP_EC_ON then
    if has_lp_after then
      -- If loop still present after stop → ▶ at loop start
      PM_ForceID0At(lp_start_after)
    else
      -- No loop after stop:
      if FOLLOW_ON then
        PM_ForceID0At(play_pos) -- last stop
      else
        local start_baseline = tonumber(start_pos_at_play) or edit_pos
        PM_ForceID0At(start_baseline) -- last start
      end
    end

    -- Restore edit to the position it had when playback began
    if edit_pos_at_play_start and edit_pos_at_play_start ~= "" then
      local restore_pos = tonumber(edit_pos_at_play_start)
      if restore_pos then
        reaper.SetEditCurPos2(0, restore_pos, false, false)
      end
    end
  else
    -- LP+EC ON: make sure ▶ is not hanging around (policy: only while stopped & only used in LP+EC OFF)
    PM_DeleteAll()
  end

  -- Bookkeeping: shift previous-play stack
  setES("PrevPlayPosition2", prev_play_pos)
  setES("PrevPlayPosition",  play_pos)

  -- Remember where edit WAS when this script started
  setES("PrevEditPosition", edit_pos)
  setES("CurrentPlayPosition", play_pos)

-- =============== STOPPED -> PLAY ===============
else
  ApplyRulerMouseMod()

  local lp_start, lp_end, has_lp = GetLoopPoints()
  local start_pos

  if has_lp then
    -- LP-first start (always)
    start_pos = lp_start
  else
    if not LP_EC_ON then
      -- LP+EC OFF: prefer ▶ if it exists; else edit cursor
      local marker_pos = PM_GetByName()
      if not marker_pos then
        -- fall back to extstate (in case marker was previously deleted but position is known)
        local extp = tonumber(reaper.GetExtState(PM_SECTION, "CurrentMarkerPosition") or "")
        marker_pos = extp
      end
      start_pos = marker_pos or edit_pos
    else
      -- LP+EC ON: v2.4 behavior (start from current edit cursor)
      start_pos = edit_pos
    end
  end

  -- ▶ must be hidden while playing
  PM_DeleteAll()

  -- Start playback, with LP+EC-OFF “edit stays put” trick
  if not LP_EC_ON then
    -- Save pre-play baselines
    setES("EditPosAtPlayStart", edit_pos)
    setES("StartPosAtPlay", start_pos or edit_pos)

    -- Move edit to start and play, then restore edit to pre-play value
    reaper.SetEditCurPos2(0, start_pos or edit_pos, false, false)
    reaper.Main_OnCommand(1007, 0)
    reaper.SetEditCurPos2(0, edit_pos, false, false)
  else
    -- LP+EC ON: standard start
    reaper.SetEditCurPos2(0, start_pos or edit_pos, false, false)
    reaper.Main_OnCommand(1007, 0)
  end

  -- Bookkeeping at launch (capture current baselines)
  setES("PrevEditPosition", edit_pos)
  setES("CurrentPlayPosition", play_pos)
end

-- Suppress REAPER's automatic undo point for this script.
-- A script that has registered a defer callback is not given an undo point on exit.
reaper.defer(function() end)
