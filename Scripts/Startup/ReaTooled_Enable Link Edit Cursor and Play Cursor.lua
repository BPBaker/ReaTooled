-- @description ReaTooled - Link Loop Points and Razor Areas
-- @version 2.4.5
-- @date 2026.04.13
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # This script synchronizes loop points and razor edit areas.
--   # When razor edits are created, loop points are updated to match their bounds.
--   # When loop points are created manually via the Ruler, razor areas are generated across all tracks.
--   # Clears existing loop and razor edits on mouse down before creating new ones.
--   # Includes realtime updates when adjusting loop points, with minimal flickering.
--   # Ignores scripted changes or repeat toggle.
--   # Also clears loop points when user left-clicks on an item (arrange only).
-- @changelog
--   v2.4.5 - Fix: removed razor area clearing from clear_loop_if_click_on_item(); REAPER clears
--            razor areas natively on plain left click, making manual clearing redundant and
--            causing conflicts with external razor-area scripts that run on mouse modifier clicks

local reaper = reaper

local last_loop_start, last_loop_end = -1, -1
local mouse_down = false
local mouse_down_in_ruler = false
local last_update_time = 0
local DEBOUNCE_INTERVAL = 0.05 -- seconds
local was_loop_set_before_mouse_down = false

local function clear_all_razor_areas_and_loop()
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', true)
  end
  reaper.GetSet_LoopTimeRange2(0, true, true, 0, 0, false)
end

local function set_razor_areas_from_loop_range(loop_start, loop_end)
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local area = string.format("%f %f \"reatooled\"", loop_start, loop_end)
    reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', area, true)
  end
end

local function get_razor_bounds()
  local min_pos = math.huge
  local max_pos = -math.huge
  local found = false

  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, areas = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
    for start, stop in string.gmatch(areas, '(%-?%d+%.?%d*) (%-?%d+%.?%d*)') do
      start = tonumber(start)
      stop = tonumber(stop)
      if start and stop then
        if start < min_pos then min_pos = start end
        if stop > max_pos then max_pos = stop end
        found = true
      end
    end
  end

  if found then
    return true, min_pos, max_pos
  end
  return false
end

-- Only clear loop on left-click of an item in the arrange view.
-- Razor areas are intentionally not cleared here — REAPER handles that natively
-- on plain left click, and manual clearing conflicts with external razor scripts.
-- Track clicks are intentionally excluded: REAPER reports envelope point/segment
-- clicks as ctx="arrange" seg="track" with a valid track handle, making them
-- indistinguishable from plain empty-track clicks via any available SWS API.
local function clear_loop_if_click_on_item()
  local is_mouse_down = reaper.JS_Mouse_GetState(1) ~= 0
  if is_mouse_down and not mouse_down then
    local context = reaper.BR_GetMouseCursorContext()
    if context == "arrange" then
      local x, y = reaper.GetMousePosition()
      local item = reaper.GetItemFromPoint(x, y, true)
      if item then
        local loop_start, loop_end = reaper.GetSet_LoopTimeRange2(0, false, true, 0, 0, false)
        if loop_end > loop_start then
          reaper.GetSet_LoopTimeRange2(0, true, true, 0, 0, false)
          last_loop_start = 0
          last_loop_end = 0
        end
      end
    end
  end
end

local function main()
  clear_loop_if_click_on_item()

  local loop_start, loop_end = reaper.GetSet_LoopTimeRange2(0, false, true, 0, 0, false)
  local loop_set = loop_end > loop_start and (loop_end - loop_start > 0.01)

  local is_mouse_down = reaper.JS_Mouse_GetState(1) ~= 0
  local now = reaper.time_precise()

  if is_mouse_down and not mouse_down then
    local context = reaper.BR_GetMouseCursorContext()
    mouse_down_in_ruler = context == "ruler"

    was_loop_set_before_mouse_down = loop_set

    if mouse_down_in_ruler and not loop_set then
      clear_all_razor_areas_and_loop()
    end

    mouse_down = true

  elseif not is_mouse_down and mouse_down then
    if loop_set and mouse_down_in_ruler and not was_loop_set_before_mouse_down then
      set_razor_areas_from_loop_range(loop_start, loop_end)
      last_loop_start = loop_start
      last_loop_end = loop_end
    end
    mouse_down = false
    mouse_down_in_ruler = false
    was_loop_set_before_mouse_down = false

  elseif is_mouse_down and loop_set and mouse_down_in_ruler then
    if (loop_start ~= last_loop_start or loop_end ~= last_loop_end)
      and (now - last_update_time > DEBOUNCE_INTERVAL) then
      set_razor_areas_from_loop_range(loop_start, loop_end)
      last_loop_start = loop_start
      last_loop_end = loop_end
      last_update_time = now
    end

  else
    local razor_ok, min_pos, max_pos = get_razor_bounds()
    if razor_ok and (min_pos ~= last_loop_start or max_pos ~= last_loop_end) then
      reaper.GetSet_LoopTimeRange2(0, true, true, min_pos, max_pos, false)
      last_loop_start = min_pos
      last_loop_end = max_pos
    end
  end

  reaper.defer(main)
end

main()
