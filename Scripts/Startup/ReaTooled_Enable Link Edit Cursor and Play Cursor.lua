-- @description ReaTooled - Link Loop Points and Razor Areas
-- @version 2.4.11
-- @date 2026.11.19
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
--   v2.4.11 - With ReaTooled Shortcuts off (your own mouse modifiers), a click that leaves an item
--             selected sets the loop points to the selected items too, as the Move Tool's click
--             does with the tools: Link Timeline and Edit Selection works the same without them.
--             A drag also counts when the item pressed on moved or changed length (REAPER can
--             move it by less than 4 px)
--   v2.4.10 - Loop points after an item drag: also after a copy (Option-drag: the copies are what's
--             selected); never with the Pencil, Zoom or Scrub tool
--   v2.4.9 - A click on an item (no drag) never sets the loop points here: 2.4.8 counted a click whose
--            click action changed the project (the Select Tool's, on the Smart tool's top half or
--            with the Selector) as a drag. Only the mouse moving counts
--   v2.4.8 - Loop points changed by dragging in the ruler: the razor areas go exactly to where they
--            ended up (the last move could be missing, and the loop points were pulled back).
--            After dragging an item (moving, copying, trimming), the loop points are set to the
--            selected items, as a click does (LOOP_FOLLOWS_ITEM_DRAG, on); only if the item pressed
--            on is selected and there are no razor areas
--   v2.4.7 - Razor areas on the master track count too: a razor area there sets the loop points,
--            and clearing (a click in the ruler) clears the master's as well. Loop points drawn in
--            the ruler still make razor areas on the regular tracks only, as before
--   v2.4.6 - Lighter on CPU: with the mouse button up, every track's razor areas are read
--            only when the project has changed (or 4 times a second, to be safe), instead
--            of every frame; while a button is down they're followed every frame as before
--   v2.4.5 - Fix: removed razor area clearing from clear_loop_if_click_on_item(); REAPER clears
--            razor areas natively on plain left click, making manual clearing redundant and
--            causing conflicts with external razor-area scripts that run on mouse modifier clicks

local reaper = reaper

-- After dragging an item (moving, copying, trimming it), the loop points are set to the
-- selected items, as a click on one does; with ReaTooled Shortcuts off, after a click too (there's
-- no tool click script then). false: they stay cleared after such a drag
local LOOP_FOLLOWS_ITEM_DRAG = true

local last_loop_start, last_loop_end = -1, -1
local mouse_down = false
local mouse_down_in_ruler = false
local last_update_time = 0
local DEBOUNCE_INTERVAL = 0.05 -- seconds
local was_loop_set_before_mouse_down = false
local razor_key, razor_check = nil, 0   -- (when the razor areas were last read)
local RAZOR_RECHECK = 0.25              -- seconds, with nothing changing
local item_press = nil                  -- { it, x, y, count } while a press on an item is going on
local item_release = nil                -- (that press ended: checked a moment later)
local ITEM_DRAG_PX = 4                  -- (moved this far: a drag, not a click)
local ITEM_SETTLE = 0.05                -- seconds after the release (REAPER finishing the drag)
local loop_at_press_s, loop_at_press_e = 0, 0

-- Every track, the master included (GetTrack leaves the master out: its razor areas were
-- never seen, so a razor area on the master didn't set the loop points)
local function each_track(fn)
  fn(reaper.GetMasterTrack(0))
  for i = 0, reaper.CountTracks(0) - 1 do fn(reaper.GetTrack(0, i)) end
end

local function clear_all_razor_areas_and_loop()
  each_track(function(track) reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', true) end)
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

  each_track(function(track)
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
  end)

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
      -- (not with the tools whose drags on an item aren't edits of it: Pencil draws clip gain or
      -- automation, Zoom zooms, Scrub scrubs)
      -- With ReaTooled Shortcuts off (your own mouse modifiers, no tool), there's no tool click
      -- script to set the loop points after a click on an item, so this does it too
      local own = reaper.GetExtState("ReaTooled", "MouseSetup") == "off"
      local tool = reaper.GetExtState("ReaTooled", "CurrentTool")
      if item and LOOP_FOLLOWS_ITEM_DRAG and (own or (tool ~= "pencil" and tool ~= "zoom" and tool ~= "scrub")) then
        item_press = { it = item, x = x, y = y, n = reaper.CountMediaItems(0), own = own,
                       p = reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
                       l = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") }
      end
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

-- A moment after a drag that began on an item: the loop points over the selected items, if the
-- item pressed on is one of them and there are no razor areas (those set the loop points)
local function loop_after_item_drag(now)
  if not item_release or now - item_release.t < ITEM_SETTLE then return end
  local pr = item_release
  item_release = nil
  if not reaper.ValidatePtr2(0, pr.it, "MediaItem*") then return end
  local mx, my = pr.mx, pr.my
  -- (a drag: the mouse moved, or the item pressed on moved or changed length, which REAPER can do
  -- with a move under this script's 4 px. A click never is, whatever its click action changed:
  -- with the tools, the loop points after a click are the click script's business (the Select
  -- Tool's leaves them cleared). With ReaTooled Shortcuts off there's no click script, so a click
  -- that leaves the item selected sets them here, as the Move Tool's click would)
  local moved = math.abs(mx - pr.x) >= ITEM_DRAG_PX or math.abs(my - pr.y) >= ITEM_DRAG_PX
    or math.abs(reaper.GetMediaItemInfo_Value(pr.it, "D_POSITION") - pr.p) > 1e-9
    or math.abs(reaper.GetMediaItemInfo_Value(pr.it, "D_LENGTH") - pr.l) > 1e-9
  if not moved and not pr.own then return end
  -- (the item pressed on is selected, or the drag made copies, which REAPER selects instead: an
  -- edge or fade drag on an unselected item leaves the loop points alone)
  if not reaper.IsMediaItemSelected(pr.it) and reaper.CountMediaItems(0) <= pr.n then return end
  if get_razor_bounds() then return end
  local s, e = math.huge, -math.huge
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    s = math.min(s, p); e = math.max(e, p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH"))
  end
  if e > s then
    reaper.GetSet_LoopTimeRange2(0, true, true, s, e, false)
    last_loop_start, last_loop_end = s, e
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
    loop_at_press_s, loop_at_press_e = loop_start, loop_end

    if mouse_down_in_ruler and not loop_set then
      clear_all_razor_areas_and_loop()
    end

    mouse_down = true

  elseif not is_mouse_down and mouse_down then
    -- (the loop points made or changed in the ruler: the razor areas to exactly where they ended
    -- up; while dragging they're updated at most every DEBOUNCE_INTERVAL, so the last move could
    -- be missing, and the razor areas then pulled the loop points back)
    local changed = math.abs(loop_start - loop_at_press_s) > 1e-9 or math.abs(loop_end - loop_at_press_e) > 1e-9
    if loop_set and mouse_down_in_ruler and (changed or not was_loop_set_before_mouse_down) then
      set_razor_areas_from_loop_range(loop_start, loop_end)
      last_loop_start = loop_start
      last_loop_end = loop_end
    end
    if item_press then
      local mx, my = reaper.GetMousePosition()
      item_press.t, item_press.mx, item_press.my = now, mx, my
      item_release, item_press = item_press, nil
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
    -- (reading every track's razor areas each frame added up in big sessions: only when
    -- something changed, while a button is down, or every RAZOR_RECHECK seconds)
    local key = tostring(reaper.EnumProjects(-1)) .. "|" .. reaper.GetProjectStateChangeCount(0)
    local look = is_mouse_down or key ~= razor_key or now - razor_check >= RAZOR_RECHECK
    if look then razor_key, razor_check = key, now end
    local razor_ok, min_pos, max_pos = false
    if look then razor_ok, min_pos, max_pos = get_razor_bounds() end
    if razor_ok and (min_pos ~= last_loop_start or max_pos ~= last_loop_end) then
      reaper.GetSet_LoopTimeRange2(0, true, true, min_pos, max_pos, false)
      last_loop_start = min_pos
      last_loop_end = max_pos
    end
  end

  loop_after_item_drag(now)
  reaper.defer(main)
end

main()
