--[[
@description ReaTooled - Link Track and Item and Razor Selection (Main Function)
@version 2.24
@date 2026-11-05
@author Brendan Baker
@about
 Models and builds upon "Link track and clip selection" from PT.

CHANGELOG
v2.24
  - Less flicker in other windows (Track Manager, mixer, Project Bay): only the tracks whose
    selection actually changes are touched (it used to deselect every track and select
    again), and the track lists are refreshed and the mixer scrolled only when the
    selection really changed
v2.23
  - Lighter on CPU: with the mouse buttons up, the razor areas and selected items are read
    again only when the project, the track selection or the item selection has changed
    (or 4 times a second, to be safe), instead of every frame
v2.22
  - STRICT track-only selection:
    • Blocks all envelope/automation lanes via BR_GetMouseCursorContext_Envelope
    • Blocks env_point/env_segment/env_edge explicitly
    • Blocks track_divider and unknown detail zones
    • Rejects zero-height (folder compact) tracks
  - Removed unused GetTrackStateChunk() call
--]]

-- USER CONFIG ----------------------------
local scroll_mixer_to_first_selected = true
-- ----------------------------------------

-- =========================================================
-- Startup guard: js_ReaScriptAPI required
-- =========================================================

if not reaper.JS_Mouse_GetState then
  reaper.ShowMessageBox(
    "ReaTooled requires the js_ReaScriptAPI extension.\n\nInstall via ReaPack.",
    "Missing Dependency",
    0
  )
  return
end

-- =========================================================
-- State
-- =========================================================

local sel_items, sel_tracks, sel_razor = {}, {}, {}
local firstselitemtrack = reaper.GetSelectedTrack(0, 0)
local prev_mouse_state = 0

reaper.SetExtState("ReaTooled", "LinkTrackItemState", "1", false)

-- =========================================================
-- Utilities
-- =========================================================

local function shallow_equal(t1, t2)
  if #t1 ~= #t2 then return false end
  for i, v in ipairs(t1) do if v ~= t2[i] then return false end end
  return true
end

local function MouseJustPressed(mask)
  local state = reaper.JS_Mouse_GetState(0xFF)
  return (state & mask == mask) and (prev_mouse_state & mask == 0)
end

-- Exactly these tracks selected, changing only the ones that differ (every selection change
-- makes other windows redraw). Returns true if anything changed.
local function SelectOnlyTracks(list)
  local want = {}
  for _, t in ipairs(list) do want[t] = true end
  local changed = false
  for i = 0, reaper.CountTracks(0) - 1 do
    local t = reaper.GetTrack(0, i)
    local on = want[t] == true
    if reaper.IsTrackSelected(t) ~= on then
      reaper.SetTrackSelected(t, on)
      changed = true
    end
  end
  return changed
end

-- =========================================================
-- Razor helpers
-- =========================================================

local function GetRazorTracks()
  local tracks = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, str = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if str ~= "" then tracks[#tracks + 1] = track end
  end
  return tracks
end

local function ProcessTracks(tracks)
  if #tracks == 0 then return false end
  reaper.PreventUIRefresh(1)
  local changed = SelectOnlyTracks(tracks)
  if changed then reaper.TrackList_AdjustWindows(false) end
  reaper.PreventUIRefresh(-1)
  return changed
end

-- =========================================================
-- Track click handling (STRICT)
-- =========================================================

local function HandleTrackClick()
  local state = reaper.JS_Mouse_GetState(0xFF)

  if not MouseJustPressed(1) then
    prev_mouse_state = state
    return
  end

  -- STRICT CONTEXT GATE
  if reaper.BR_GetMouseCursorContext then
    local context, subcontext, details = reaper.BR_GetMouseCursorContext()

    if context ~= "arrange" or subcontext ~= "track" then
      prev_mouse_state = state
      return
    end

    -- Block ALL envelope interaction
    local env = reaper.BR_GetMouseCursorContext_Envelope()
    if env then
      prev_mouse_state = state
      return
    end

    -- Explicit envelope detail safety
    if details == "env_point"
    or details == "env_segment"
    or details == "env_edge" then
      prev_mouse_state = state
      return
    end

    -- Block divider / ghost zones
    if details == "track_divider"
    or details == "unknown" then
      prev_mouse_state = state
      return
    end
  end

  -- GEOMETRY TEST
  local x, y = reaper.GetMousePosition()
  local track = reaper.GetTrackFromPoint(x, y)

  if not track then
    prev_mouse_state = state
    return
  end

  -- Reject hidden / zero-height tracks (folder compact case)
  local tcp_h = reaper.GetMediaTrackInfo_Value(track, "I_TCPH")
  if tcp_h <= 0 then
    prev_mouse_state = state
    return
  end

  -- Modifier keys
  local is_osx = reaper.GetOS():match("OSX")
  local shift = state & 8 == 8
  local cmd   = state & (is_osx and 256 or 4) == (is_osx and 256 or 4)

  -- Prevent redundant selection
  if not shift and not cmd
     and reaper.IsTrackSelected(track)
     and reaper.CountSelectedTracks(0) == 1
  then
    prev_mouse_state = state
    return
  end

  if shift then
    local last = reaper.GetSelectedTrack(0, reaper.CountSelectedTracks(0) - 1)
    if last then
      local a = reaper.GetMediaTrackInfo_Value(last,  "IP_TRACKNUMBER")
      local b = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
      local range = {}
      for i = math.min(a, b) - 1, math.max(a, b) - 1 do
        local t = reaper.GetTrack(0, i)
        if t then range[#range + 1] = t end
      end
      SelectOnlyTracks(range)
    end

  elseif cmd then
    reaper.SetTrackSelected(track, not reaper.IsTrackSelected(track))

  else
    SelectOnlyTracks({ track })
  end

  prev_mouse_state = state
end

-- =========================================================
-- Main loop
-- =========================================================

-- Nothing changed since the last full look? (cheap: counts, the first and last selected
-- track and item, and REAPER's project change counter)
local quiet_sig, quiet_check, quiet_seen = nil, 0, 0
local QUIET_RECHECK = 0.25   -- seconds
local function nothing_changed()
  local now = reaper.time_precise()
  if reaper.JS_Mouse_GetState(3) ~= 0 then quiet_sig = nil; return false end   -- (a button is down)
  local nt, ni = reaper.CountSelectedTracks(0), reaper.CountSelectedMediaItems(0)
  local sig = table.concat({
    tostring(reaper.EnumProjects(-1)), reaper.GetProjectStateChangeCount(0), nt, ni,
    tostring(nt > 0 and reaper.GetSelectedTrack(0, 0)), tostring(nt > 0 and reaper.GetSelectedTrack(0, nt - 1)),
    tostring(ni > 0 and reaper.GetSelectedMediaItem(0, 0)), tostring(ni > 0 and reaper.GetSelectedMediaItem(0, ni - 1)),
  }, "|")
  -- (skipped once the same state has been looked at twice in a row: the main loop
  -- sometimes needs a second frame to act on a change it has just noted)
  if sig == quiet_sig then
    quiet_seen = quiet_seen + 1
    if quiet_seen >= 2 and now - quiet_check < QUIET_RECHECK then return true end
    if quiet_seen >= 2 then quiet_check = now end
    return false
  end
  quiet_sig, quiet_seen, quiet_check = sig, 0, now
  return false
end

local function Main()
  HandleTrackClick()
  if nothing_changed() then reaper.defer(Main) return end

  local cur_tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    cur_tracks[#cur_tracks + 1] = reaper.GetSelectedTrack(0, i)
  end

  if shallow_equal(sel_tracks, cur_tracks) then
    local r = GetRazorTracks()

    if not shallow_equal(sel_razor, r) then
      sel_razor = r
      ProcessTracks(r)

    elseif #r == 0 then
      local num_items = reaper.CountSelectedMediaItems(0)

      if num_items > 0 then
        local items = {}
        for i = 0, num_items - 1 do
          items[#items + 1] = reaper.GetSelectedMediaItem(0, i)
        end

        local newtrack = reaper.GetMediaItem_Track(items[1])

        if not shallow_equal(sel_items, items) or firstselitemtrack ~= newtrack then
          sel_items = items
          firstselitemtrack = newtrack

          local tracks = {}
          for _, it in ipairs(items) do
            tracks[#tracks + 1] = reaper.GetMediaItem_Track(it)
          end

          if ProcessTracks(tracks) and scroll_mixer_to_first_selected then
            reaper.SetMixerScroll(reaper.GetSelectedTrack(0, 0))
          end
        end
      else
        firstselitemtrack = nil
      end
    end
  else
    sel_tracks = cur_tracks
  end

  reaper.defer(Main)
end

Main()
