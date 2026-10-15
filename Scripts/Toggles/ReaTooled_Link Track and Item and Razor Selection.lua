--[[
@description ReaTooled - Link Track and Item and Razor Selection (Main Function)
@version 2.22
@date 2026-04-17
@author Brendan Baker
@about
 Models and builds upon "Link track and clip selection" from PT.

CHANGELOG
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

local function DeselectAllTracks()
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
  end
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
  if #tracks == 0 then return end
  reaper.PreventUIRefresh(1)
  DeselectAllTracks()
  for _, t in ipairs(tracks) do
    reaper.SetTrackSelected(t, true)
  end
  reaper.TrackList_AdjustWindows(false)
  reaper.PreventUIRefresh(-1)
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
      DeselectAllTracks()
      for i = math.min(a, b) - 1, math.max(a, b) - 1 do
        local t = reaper.GetTrack(0, i)
        if t then reaper.SetTrackSelected(t, true) end
      end
    end

  elseif cmd then
    reaper.SetTrackSelected(track, not reaper.IsTrackSelected(track))

  else
    DeselectAllTracks()
    reaper.SetTrackSelected(track, true)
  end

  prev_mouse_state = state
end

-- =========================================================
-- Main loop
-- =========================================================

local function Main()
  HandleTrackClick()

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

          ProcessTracks(tracks)

          if scroll_mixer_to_first_selected then
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
