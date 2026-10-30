-- @description ReaTooled - Toggle pre-roll (playback and recording)
-- @version 1.5
-- @date 2026.10.30
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Like Pro Tools' Pre/Post-Roll switch (Cmd+K): turns REAPER's pre-roll on
--   playback and pre-roll on recording on or off together. If either is off, both
--   go on; if both are on, both go off. The toolbar button is lit while it's on.
--   While pre-roll is on, a white "Pre-roll" marker shows where playback will
--   really start: the pre-roll length before the play start, moved back to the bar
--   line at or before it when REAPER's "Start pre-roll at start of measure" is
--   checked (a point just before a bar line counts as that bar, within a 16th note,
--   as REAPER does). The play start is worked out
--   like ReaTooled's Play-Stop does it (the loop points if there are any, else the
--   ▶ play marker when Link Timeline and Edit Selection is off, else the edit
--   cursor). It follows as those move, hides while playing or recording (like ▶),
--   and is removed when pre-roll goes off.
--   Drag the marker to change the pre-roll length, like Pro Tools' pre-roll flag:
--   with "Start pre-roll at start of measure" checked it snaps to whole bars (REAPER
--   only starts on a bar line then), unchecked to quarter bars. Needs SWS.
--   Option+click the toolbar button (or Option+run it) to open REAPER's
--   Metronome/pre-roll settings (pre-roll length, etc.) without switching anything.
--   REAPER's own separate toggles still work: turning both off there ends this too.
-- @changelog
--   v1.5 At startup (Recall ReaTooled Button States), the marker and button come back if
--        REAPER's pre-roll is on, without switching anything
--   v1.4 Follows REAPER's "Start pre-roll at start of measure": checked, pre-roll
--        starts on a bar line (drags snap to whole bars); unchecked, exactly the
--        pre-roll length before the play start (drags snap to quarter bars)
--   v1.3 Matches REAPER with fractional pre-roll too (measured: back the pre-roll
--        length, then to the bar line at or before). Dragging the marker is applied
--        when the mouse is let go (no more jumping under the mouse) and snaps to whole
--        bars, since REAPER only starts pre-roll on a bar line
--   v1.2 Drag the Pre-roll marker to set the pre-roll length (fractions of a bar
--        too), like Pro Tools' pre-roll flag
--   v1.1.3 A play start just before a bar line counts as that bar, as in REAPER
--   v1.1.2 The marker matches REAPER: pre-roll starts on a bar line, the pre-roll's
--          measures before the start of the bar playback starts in
--   v1.1.1 Fix: toolbar button state (SetToggleCommandState)
--   v1.1 White "Pre-roll" marker at the real playback start while pre-roll is on
--   v1.0 Initial version

local PREROLL_PLAY   = 41818   -- Pre-roll: Toggle pre-roll on play
local PREROLL_RECORD = 41819   -- Pre-roll: Toggle pre-roll on record
local SETTINGS       = 40363   -- Options: Metronome/pre-roll settings...
local ALT            = 16      -- JS_Mouse_GetState: Option (macOS) / Alt (Windows)
local LINK_GUID      = "_RSed328eb507619b18c1154efa1b048d816cfc2d0c"   -- Link Timeline and Edit Selection

local MARKER_NAME  = "Pre-roll"
local MARKER_ID    = 1000       -- REAPER numbers every marker: a high one, clear of numbered markers
local MARKER_COLOR = reaper.ColorToNative(255, 255, 255) | 0x1000000
local PLAY_MARKER  = "▶"         -- ReaTooled Play-Stop's play marker
local POLL_SEC     = 0.1
local DIAG         = false      -- console report at each play start (temporary)

local _, _, section, cmd_id = reaper.get_action_context()

local function on(id) return reaper.GetToggleCommandState(id) == 1 end
local function active() return on(PREROLL_PLAY) or on(PREROLL_RECORD) end

local function light(state)
  if reaper.set_action_options then reaper.set_action_options(1 | 2 | (state and 4 or 8)) end
  reaper.SetToggleCommandState(section, cmd_id, state and 1 or 0)
  reaper.RefreshToolbar2(section, cmd_id)
end

-- Markers --------------------------------------------------------------------
local function find_marker(name)
  local _, nm, nr = reaper.CountProjectMarkers(0)
  for i = 0, (nm or 0) + (nr or 0) - 1 do
    local _, isrgn, pos, _, nm2, num = reaper.EnumProjectMarkers3(0, i)
    if not isrgn and nm2 == name then return pos, num end
  end
end

local function remove_marker()
  local _, num = find_marker(MARKER_NAME)
  while num do
    reaper.DeleteProjectMarker(0, num, false)
    _, num = find_marker(MARKER_NAME)
  end
end

local function place_marker(pos)
  local cur, num = find_marker(MARKER_NAME)
  if num then
    if math.abs(cur - pos) <= 1e-6 then return false end
    reaper.SetProjectMarker3(0, num, false, pos, 0, MARKER_NAME, MARKER_COLOR)
  else
    reaper.AddProjectMarker2(0, false, pos, 0, MARKER_NAME, MARKER_ID, MARKER_COLOR)
  end
  return true
end

-- Where playback will start (as Play-Stop decides), and one pre-roll before it
local link_cmd = reaper.NamedCommandLookup(LINK_GUID)

local function play_start()
  local s, e = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
  if e > s then return s end
  local linked = link_cmd ~= 0 and reaper.GetToggleCommandStateEx(0, link_cmd) == 1
  if not linked then
    local pm = find_marker(PLAY_MARKER)
    if pm then return pm end
  end
  return reaper.GetCursorPosition()
end

local function preroll_measures()
  local v
  if reaper.get_config_var_string then
    local ok, s = reaper.get_config_var_string("prerollmeas")
    if ok then v = tonumber(s) end
  end
  return v or 1
end

-- Where REAPER starts pre-roll (measured): the pre-roll length (fractions of a bar
-- too) back from the play start, then back to the bar line at or before that. A
-- point just before a bar line counts as that bar (REAPER does this within 0.1-0.2 s
-- at 120 bpm; a 16th note is assumed).
local BAR_LOOKAHEAD_QN = 0.25

local function bar_at(t)   -- 0-based bar index, with the lookahead
  local ahead = reaper.TimeMap2_QNToTime(0, reaper.TimeMap2_timeToQN(0, t) + BAR_LOOKAHEAD_QN)
  local _, bar = reaper.TimeMap2_timeToBeats(0, ahead)
  return bar
end

local function back_measures(t, n)   -- t moved n measures earlier
  local num, den = reaper.TimeMap_GetTimeSigAtTime(0, t)
  local qn = reaper.TimeMap2_timeToQN(0, t) - n * (num or 4) * 4 / (den or 4)
  return reaper.TimeMap2_QNToTime(0, qn)
end

-- REAPER's "Start pre-roll at start of measure" (config "preroll" &4: 0 = checked)
local DRAG_STEP_OFF = 0.25   -- measures a drag snaps to when that's unchecked

local function bar_snap()
  local v
  if reaper.get_config_var_string then
    local ok, s = reaper.get_config_var_string("preroll")
    if ok then v = tonumber(s) end
  end
  return ((math.floor(v or 0)) & 4) == 0
end

local function preroll_start(t)
  local x = back_measures(t, preroll_measures())
  if bar_snap() then x = reaper.TimeMap2_beatsToTime(0, 0, bar_at(x)) end
  return math.max(0, x)
end

local function set_preroll_measures(n)
  if reaper.SNM_SetDoubleConfigVar then return reaper.SNM_SetDoubleConfigVar("prerollmeas", n) end
  return false
end

local function tip(msg)
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(msg, x + 12, y + 12, true)
end

-- Run ------------------------------------------------------------------------
local want
local recall = reaper.GetExtState("ReaTooled", "PrerollRecall") == "1"
reaper.DeleteExtState("ReaTooled", "PrerollRecall", false)
if recall then
  want = active()                          -- startup: as REAPER has it, nothing switched
elseif reaper.JS_Mouse_GetState and (reaper.JS_Mouse_GetState(ALT) & ALT) ~= 0 then
  reaper.Main_OnCommand(SETTINGS, 0)       -- Option: settings only, nothing switched
  want = active()
else
  want = not (on(PREROLL_PLAY) and on(PREROLL_RECORD))
  if on(PREROLL_PLAY) ~= want then reaper.Main_OnCommand(PREROLL_PLAY, 0) end
  if on(PREROLL_RECORD) ~= want then reaper.Main_OnCommand(PREROLL_RECORD, 0) end
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip("Pre-roll " .. (want and "on" or "off") .. " (playback and recording)", x + 12, y + 12, true)
end

if not want then
  remove_marker()
  light(false)
  reaper.UpdateTimeline()
  reaper.defer(function() end)   -- no undo point
  return
end

light(true)
reaper.atexit(function()
  remove_marker()
  light(false)
  reaper.UpdateTimeline()
end)

local last, lastPlaced = 0, nil
local wasPlaying, predicted, diagBase, diagEdit, diagPM, diagFrames, diagMin = false, nil, nil, nil, nil, 0, nil
local function log(...) reaper.ShowConsoleMsg(string.format(...) .. "\n") end
local function loop()
  if not active() then return end          -- switched off elsewhere: atexit cleans up
  local now = reaper.time_precise()
  if DIAG then
    local playing = (reaper.GetPlayState() & 5) ~= 0
    if playing and not wasPlaying then diagFrames, diagMin = 0, math.huge end
    if playing and diagFrames and diagFrames < 6 then
      diagFrames = diagFrames + 1
      diagMin = math.min(diagMin, reaper.GetPlayPosition())
      if diagFrames == 6 then
        local okE, en = false, ""
        if reaper.get_config_var_string then okE, en = reaper.get_config_var_string("projmetroen") end
        local exact = back_measures(diagBase or 0, preroll_measures())
        log("Pre-roll: marker %.3f | REAPER started at %.3f (diff %+.3f) | exact-length start %.3f (diff %+.3f) | play start %.3f, measures %.2f, projmetroen %s",
          predicted or -1, diagMin, diagMin - (predicted or 0), exact, diagMin - exact, diagBase or -1,
          preroll_measures(), okE and en or "?")
      end
    end
    if not playing then
      diagBase, diagEdit, diagPM = play_start(), reaper.GetCursorPosition(), find_marker(PLAY_MARKER)
    end
    wasPlaying = playing
  end
  local mouseDown = reaper.JS_Mouse_GetState and (reaper.JS_Mouse_GetState(1) & 1) == 1
  if not mouseDown and now - last >= POLL_SEC then
    last = now
    if (reaper.GetPlayState() & 5) ~= 0 then  -- playing or recording: hidden, like ▶
      if find_marker(MARKER_NAME) then remove_marker(); reaper.UpdateTimeline() end
      lastPlaced = nil
    else
      -- The marker was dragged (applied when the mouse is let go, never under it).
      -- "Start pre-roll at start of measure" checked: REAPER only starts on a bar line,
      -- so it snaps to whole bars; unchecked: to quarter bars (DRAG_STEP_OFF)
      local pos = find_marker(MARKER_NAME)
      if pos and lastPlaced and math.abs(pos - lastPlaced) > 1e-6 then
        local start = play_start()
        local snap = bar_snap()
        local n
        if snap then
          local beats, m, cml = reaper.TimeMap2_timeToBeats(0, pos)
          local nearest = m + (((cml or 0) > 0 and beats / cml >= 0.5) and 1 or 0)
          n = bar_at(start) - nearest
        else
          local num, den = reaper.TimeMap_GetTimeSigAtTime(0, start)
          local mqn = (num or 4) * 4 / (den or 4)
          local raw = (reaper.TimeMap2_timeToQN(0, start) - reaper.TimeMap2_timeToQN(0, pos)) / mqn
          n = math.floor(raw / DRAG_STEP_OFF + 0.5) * DRAG_STEP_OFF
        end
        local minimum = snap and 1 or DRAG_STEP_OFF
        if n < minimum - 1e-9 then
          tip(snap and "Pre-roll: at least one bar" or "Pre-roll: at least a quarter bar")
        elseif math.abs(n - preroll_measures()) > 1e-6 then
          local label = (string.format("%.2f", n):gsub("%.?0+$", ""))
          if set_preroll_measures(n) then tip("Pre-roll: " .. label .. (math.abs(n - 1) < 1e-9 and " bar" or " bars"))
          else tip("Pre-roll: dragging the marker needs the SWS extension") end
        end
      end
      predicted = preroll_start(play_start())
      if place_marker(predicted) then reaper.UpdateTimeline() end
      lastPlaced = predicted
    end
  end
  reaper.defer(loop)
end
loop()
