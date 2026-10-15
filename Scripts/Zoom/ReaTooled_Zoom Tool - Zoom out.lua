--[[
-- @description ReaTooled - Zoom Tool - Zoom out
-- @version 1.0
-- @date 2026.10.15
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Zooms the arrange view out horizontally, like a Pro Tools Zoomer Option-click.
    Centers on the mouse position (or the play/edit cursor, see SETTINGS).
    Used by the Zoom Tool's Option/Alt-click mouse modifier. Requires SWS for the
    mouse position; falls back to the play/edit cursor without it.
-- CHANGELOG
-- v1.0 Initial version (replaces Archie's View zoom scripts in the Zoom Tool)
--]]

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------
local ZOOM_FACTOR = 2         -- 2 = each click shows twice as much time
local CENTER_ON   = "mouse"   -- "mouse"  = center on where you clicked
                              -- "cursor" = center on play cursor (playing) or edit cursor (stopped)

------------------------------------------------------------

local function center_time()
  if CENTER_ON == "mouse" and reaper.BR_PositionAtMouseCursor then
    local t = reaper.BR_PositionAtMouseCursor(false)
    if t and t >= 0 then return t end
  end
  if reaper.GetPlayState() & 1 == 1 then
    return reaper.GetPlayPosition()
  end
  return reaper.GetCursorPosition()
end

local function main()
  local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local length = (view_end - view_start) * ZOOM_FACTOR

  local new_start = center_time() - length / 2
  if new_start < 0 then new_start = 0 end

  reaper.GetSet_ArrangeView2(0, true, 0, 0, new_start, new_start + length)
end

-- Run deferred so REAPER doesn't add an undo point for a view change
reaper.defer(main)
