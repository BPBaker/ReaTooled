-- @description ReaTooled - Loop END stop+cursor handler (pref-aware)
--                [LOOP POINTS ONLY, LP+EC-aware, ▶ forced to ID 0]
-- @version 2.8
-- @date 2026.10.27
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   • Follows REAPER's "Stop playback at end of loop if repeat is disabled" (stopendofloop):
--       – ON : REAPER stops at the loop end itself; this script only does the cleanup below,
--              and only when playback really ended at the loop end (not when you press stop).
--       – OFF: playback carries on past the loop end, and this script does nothing
--              (the cursor and loop points stay where they are).
--   • ▶ Play Marker is a singleton and is always forced to **ID 0**:
--       – If ID 0 is occupied (marker or region), it is faithfully recreated at a new auto ID, then removed.
--       – ▶ is then created/moved at ID 0 and any other ▶ by **name** are deleted (no color matching).
--   • LP+EC-aware loop-end cleanup (unchanged semantics, renamed):
--       – Follow OFF + LP+EC OFF: EDIT := loop start; preserve LP & Razor; ▶ mirrors LP start (via watcher).
--       – Follow ON  + LP+EC OFF: ▶ := loop end; clear LP; keep Razor; EDIT stays.
--       – Follow ON  + LP+EC ON : EDIT := loop end; clear LP & Razor.
--   • When LP+EC is OFF and loop points change, ▶ mirrors Loop Start (queued while playing).
-- @changelog
--   v2.8 - With "Stop playback at end of loop if repeat is disabled" off, playback now
--          carries on past the loop end, as in REAPER: the script no longer stops it or
--          moves the cursor. With the preference on, nothing changes.
--   v2.7 - Reads the real preference (stopendofloop, live) instead of a name that doesn't
--          exist (stoploopnomode), which made the script always stop playback itself,
--          slightly before the loop end. With the preference on, REAPER now stops exactly
--          at the loop end, and the cleanup runs only when playback ended there.

local debug = false
local STOP_THRESHOLD = 0.05
local OVERRUN_MARGIN = 0.10
local EPS = 1e-6

local END_WINDOW = 0.15   -- a stop within this many seconds of the loop end counts as "at the loop end"

local triggered_rt_loopstop = false
local triggered_edit_cursor_cleanup = false

-- While playing: where playback was and which loop end applied (to recognise
-- REAPER's own stop at the loop end once playback has stopped)
local was_playing = false
local last_play_pos, last_play_lp_end, last_play_lp_ok = nil, nil, false

-- Persist last-seen loop state across defers (for change detection)
local last_lp_active, last_lp_start, last_lp_end = nil, nil, nil

-- =========================
-- REAPER's "Stop playback at end of loop if repeat is disabled" (read live,
-- so changing it in Preferences takes effect right away)
-- =========================
local function stopAtLoopEndPref()
  local ok, v = reaper.get_config_var_string("stopendofloop")
  return ok and tonumber(v) ~= nil and (tonumber(v) & 1) == 1
end

-- =========================
-- Loop Points helpers (loop-only; no time selection)
-- =========================
local function ClearLoopPoints()
  reaper.GetSet_LoopTimeRange(true, true, 0, 0, false)
end

-- =========================
-- ▶ Play Marker helpers — force ID 0
-- =========================
local PM_NS    = "Play-Stop with memory"
local PM_NAME  = "▶"
local PM_COLOR = reaper.ColorToNative(255,255,255) | 0x1000000 -- used on write only; not for identification

local function PM_WriteTrackedID(id_or_nil)
  reaper.SetExtState(PM_NS, "PM_ID", id_or_nil and tostring(id_or_nil) or "", false)
end

-- Delete all ▶ except the one currently at ID 0 (NAME ONLY)
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

-- Move ▶ to `pos` and ensure it **is** ID 0 (evicting any occupant of ID 0 if needed).
local function PM_ForceID0At(pos)
  if type(pos) ~= "number" then return end
  -- tiny nudge if writing same timestamp (avoids rare hit-test quirk)
  local prev = tonumber(reaper.GetExtState(PM_NS, "CurrentMarkerPosition") or "")
  local place_pos = (prev and math.abs(prev - pos) < EPS) and (pos + 1e-4) or pos

  reaper.PreventUIRefresh(1)

  -- 1) Locate current ID 0 (marker or region), if any
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
    -- If ID 0 is already our ▶ (NAME ONLY), just move it
    if (not id0_isrgn) and (id0_name == PM_NAME) then
      reaper.SetProjectMarker3(0, 0, false, place_pos, 0.0, PM_NAME, PM_COLOR)
    else
      -- 2) Evict ID 0 occupant by recreating at a new auto ID, then delete the original ID 0
      if id0_isrgn then
        reaper.AddProjectMarker2(0, true,  id0_pos, id0_rgnend, id0_name or "", -1, id0_color or 0)
        reaper.DeleteProjectMarker(0, 0, true)
      else
        reaper.AddProjectMarker2(0, false, id0_pos, 0.0,       id0_name or "", -1, id0_color or 0)
        reaper.DeleteProjectMarker(0, 0, false)
      end
      -- 3) Create ▶ at ID 0
      reaper.AddProjectMarker2(0, false, place_pos, 0.0, PM_NAME, 0, PM_COLOR)
    end
  else
    -- No ID 0 exists; create ▶ at ID 0
    reaper.AddProjectMarker2(0, false, place_pos, 0.0, PM_NAME, 0, PM_COLOR)
  end

  -- 4) Cleanup any stray ▶ (by NAME ONLY) that are not ID 0
  PM_DeleteOtherPlayMarkersKeepID0()

  -- 5) Track and store position
  PM_WriteTrackedID(0)
  reaper.SetExtState(PM_NS, "CurrentMarkerPosition", tostring(place_pos), false)

  reaper.UpdateTimeline()
  reaper.PreventUIRefresh(-1)
end

-- =========================
-- MAIN
-- =========================
local function main()
  -- Live toggle states each cycle
  local follow_state = reaper.GetToggleCommandStateEx(
    0, reaper.NamedCommandLookup("_RSe16d9e990f3d5fcec42256f63e00086d75b71288")
  )
  local lp_ec_state = reaper.GetToggleCommandStateEx( -- formerly llr_state
    0, reaper.NamedCommandLookup("_RSed328eb507619b18c1154efa1b048d816cfc2d0c")
  )

  local playStateBits = reaper.GetPlayState()
  local isPlaying = (playStateBits & 1) == 1
  local repeatOn  = (reaper.GetSetRepeat(-1) == 1)

  -- Current loop points (loop-only)
  local lpStart, lpEnd = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
  local lpActive = (lpEnd > lpStart)

  -- === LP change watcher: when LP+EC OFF, keep ▶ synced to LP start ===
  local lp_changed = false
  if last_lp_active ~= nil then
    lp_changed = (lpActive ~= last_lp_active)
                 or (lpActive and (math.abs((last_lp_start or lpStart) - lpStart) > EPS
                                   or math.abs((last_lp_end or lpEnd)   - lpEnd)   > EPS))
  end

  if lp_ec_state == 0 and lpActive and lp_changed then
    if not isPlaying then
      PM_ForceID0At(lpStart)
      if debug then reaper.ShowConsoleMsg("LP changed (LP+EC OFF, stopped): ▶ → LP start (ID 0)\n") end
    else
      -- queue until stopped (keeps ▶ hidden while playing if transport hides it)
      reaper.SetExtState(PM_NS, "PendingMarkerAtLPStart", "1", false)
      reaper.SetExtState(PM_NS, "PendingMarkerPos", tostring(lpStart), false)
      if debug then reaper.ShowConsoleMsg("LP changed (LP+EC OFF, playing): queued ▶ → LP start on stop\n") end
    end
  end

  -- Special-case: when stopped and cursor exactly at LP end, ensure start from LP end
  if not isPlaying and not repeatOn and lpActive then
    local cur = reaper.GetCursorPosition()
    if math.abs(cur - lpEnd) < 0.0001 then
      reaper.SetEditCurPos(lpEnd, false, false)
    end
  end

  local stopPrefEnabled = stopAtLoopEndPref()

  -- Loop-end stop logic only when LP active and repeat OFF
  if lpActive and not repeatOn then
    local playPos = reaper.GetPlayPosition2()
    local dist    = lpEnd - playPos
    local aboutToHit = (dist > 0 and dist <= STOP_THRESHOLD)
    local justPassed = (playPos > lpEnd and playPos - lpEnd < OVERRUN_MARGIN)

    -- Preference OFF: REAPER keeps playing past the loop end, and so does this
    -- script (no stop, no cleanup). Preference ON: REAPER stops by itself (below).
  end

  -- REAPER stopped by itself at the loop end (preference ON): playback was
  -- within END_WINDOW of the loop end when it stopped
  local native_loopstop = false
  if was_playing and not isPlaying and stopPrefEnabled and last_play_lp_ok and last_play_pos then
    native_loopstop = (last_play_pos >= last_play_lp_end - END_WINDOW)
    if debug then
      reaper.ShowConsoleMsg(string.format("Stopped at %.3f (loop end %.3f): %s\n", last_play_pos,
        last_play_lp_end, native_loopstop and "loop-end stop" or "stopped by you"))
    end
  end

  -- Cleanup once after a stop at the loop end (loop-end behaviors)
  if not isPlaying and (triggered_rt_loopstop or native_loopstop) and not triggered_edit_cursor_cleanup then
    if lp_ec_state == 0 then
      -- LP+EC OFF
      if follow_state == 0 then
        -- Follow OFF: EDIT := loop start; preserve LP & Razor
        reaper.SetEditCurPos(lpStart, false, false)
        -- ▶ mirrors LP start via watcher
        if debug then reaper.ShowConsoleMsg("Loop-end: LP+EC OFF + Follow OFF → edit:=LP start; kept LP & Razor\n") end
      else
        -- Follow ON: ▶ := loop end; clear LP; keep Razor; EDIT stays
        PM_ForceID0At(lpEnd)
        ClearLoopPoints()
        if debug then reaper.ShowConsoleMsg("Loop-end: LP+EC OFF + Follow ON → ▶=LP end (ID 0); cleared LP; kept Razor\n") end
      end
    else
      -- LP+EC ON + Follow ON: EDIT := loop end; clear LP & Razor
      if follow_state == 1 then
        reaper.SetEditCurPos(lpEnd, false, false)
        ClearLoopPoints()
        reaper.Main_OnCommand(42406, 0) -- Remove Razor Edit area
        if debug then reaper.ShowConsoleMsg("Loop-end: LP+EC ON + Follow ON → edit:=LP end; cleared LP & Razor\n") end
      end
    end

    triggered_edit_cursor_cleanup = true
  end

  -- Apply any queued “place ▶ at LP start” after stop
  if not isPlaying then
    local pending = reaper.GetExtState(PM_NS, "PendingMarkerAtLPStart")
    if pending == "1" then
      local p = tonumber(reaper.GetExtState(PM_NS, "PendingMarkerPos") or "")
      if p then PM_ForceID0At(p) end
      reaper.SetExtState(PM_NS, "PendingMarkerAtLPStart", "", false)
      reaper.SetExtState(PM_NS, "PendingMarkerPos", "", false)
      if debug then reaper.ShowConsoleMsg("Pending ▶ → LP start applied after stop\n") end
    end
  end

  -- Reset triggers after cleanup
  if not isPlaying and triggered_edit_cursor_cleanup then
    triggered_rt_loopstop = false
    triggered_edit_cursor_cleanup = false
  end

  -- Remember where playback is (for recognising REAPER's own loop-end stop)
  if isPlaying then
    local p1, p2 = reaper.GetPlayPosition(), reaper.GetPlayPosition2()
    last_play_pos = math.max(p1, p2)
    last_play_lp_end = lpEnd
    last_play_lp_ok = lpActive and not repeatOn
  end
  was_playing = isPlaying

  -- Update last-seen loop state
  last_lp_active = lpActive
  last_lp_start  = lpStart
  last_lp_end    = lpEnd

  reaper.defer(main)
end

main()
