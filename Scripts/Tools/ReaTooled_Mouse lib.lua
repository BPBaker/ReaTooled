-- @description ReaTooled - Mouse library (shared by the background tools)
-- @version 1.0
-- @date 2026.10.29
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Not an action. Mouse helpers for ReaTooled's background tools (Shuffle move):
--     - clicks read from the arrange view's own mouse-down messages (passed on to
--       REAPER as usual), so no click is missed and clicks on windows floating over
--       the arrange are ignored
--     - the cursor REAPER shows (which tells what REAPER would do at that spot)
--     - timeline time under the mouse, scrolling the arrange while dragging past
--       its left or right side
--   Requires js_ReaScriptAPI.
-- @changelog
--   v1.0 Initial version (taken from the Trim Tool's background worker)

local M = {}

M.ARRANGE = reaper.JS_Window_FindChildByID and reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)

------------------------------------------------------------
-- Clicks
------------------------------------------------------------
local clicksOn, lastClick = false, 0

-- Start reading the arrange view's mouse-down messages. Returns true if it works
-- (another script holding them makes it fail; try again later).
function M.clicks_start()
  if clicksOn then return true end
  if not (M.ARRANGE and reaper.JS_WindowMessage_Intercept and reaper.JS_WindowMessage_Peek) then return false end
  if reaper.JS_WindowMessage_Intercept(M.ARRANGE, "WM_LBUTTONDOWN", true) == 1 then
    clicksOn = true
    local ok, _, t = reaper.JS_WindowMessage_Peek(M.ARRANGE, "WM_LBUTTONDOWN")
    if ok and t then lastClick = t end
  end
  return clicksOn
end

function M.clicks_stop()
  if clicksOn and reaper.JS_WindowMessage_Release then
    pcall(reaper.JS_WindowMessage_Release, M.ARRANGE, "WM_LBUTTONDOWN")
  end
  clicksOn = false
end

function M.clicks_on() return clicksOn end

-- A click in the arrange since the last call: {x, y} in arrange coordinates, or nil
function M.new_click()
  if not clicksOn then return nil end
  local ok, _, t, _, _, x, y = reaper.JS_WindowMessage_Peek(M.ARRANGE, "WM_LBUTTONDOWN")
  if ok and t and t > lastClick then
    lastClick = t
    return { x = x, y = y }
  end
end

------------------------------------------------------------
-- Positions and time
------------------------------------------------------------
-- Mouse position: arrange coordinates and screen coordinates
function M.mouse()
  local mx, my = reaper.GetMousePosition()
  local cx, cy = reaper.JS_Window_ScreenToClient(M.ARRANGE, mx, my)
  return cx, cy, mx, my
end

-- Screen point of a click (arrange coordinates). If the mouse is still down far
-- from it, the conversion is not trusted and the mouse position is used.
function M.click_screen_point(c, mouseDown)
  local mx, my = reaper.GetMousePosition()
  local sx, sy = reaper.JS_Window_ClientToScreen(M.ARRANGE, c.x, c.y)
  if not sx then return mx, my end
  if mouseDown and (math.abs(sx - mx) > 40 or math.abs(sy - my) > 40) then return mx, my end
  return sx, sy
end

local function pps()
  local z = reaper.GetHZoomLevel() or 1
  return (z > 0) and z or 1e-6
end

function M.time_at(cx)
  local vs = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  return vs + cx / pps()
end

function M.px_to_time(px) return px / pps() end

-- Timeline time under the mouse while dragging. Past the left or right of the
-- arrange, scrolls toward the mouse (rate = pixels per frame per pixel past the
-- side) and returns the time at the arrange's side.
function M.drag_time(rate)
  local cx = M.mouse()
  local okW, w = reaper.JS_Window_GetClientSize(M.ARRANGE)
  if type(okW) == "number" and w == nil then w = okW end
  if not cx then return nil end
  if not w or w <= 0 or (cx >= 0 and cx <= w) then return M.time_at(cx) end
  local vs, ve = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  if rate and rate > 0 then
    local over = (cx < 0) and cx or (cx - w)
    local ns = math.max(0, vs + (over * rate) / pps())
    if ns ~= vs then
      reaper.GetSet_ArrangeView2(0, true, 0, 0, ns, ns + (ve - vs))
      vs = ns
    end
  end
  return vs + ((cx < 0) and 0 or w) / pps()
end

-- Item's top and height in arrange coordinates
function M.item_rect(it)
  local tr = reaper.GetMediaItem_Track(it)
  local top = reaper.GetMediaTrackInfo_Value(tr, "I_TCPY") + reaper.GetMediaItemInfo_Value(it, "I_LASTY")
  return top, reaper.GetMediaItemInfo_Value(it, "I_LASTH")
end

------------------------------------------------------------
-- REAPER's cursor
------------------------------------------------------------
function M.cursor_key(h) return h and tostring(h) or nil end

-- Keys of REAPER's cursors, measured in REAPER 7
local function keys(ids)
  local t = {}
  for _, id in ipairs(ids) do
    local h = reaper.JS_Mouse_LoadCursor(id)
    if h then t[M.cursor_key(h)] = true end
  end
  return t
end
-- Edges (417/418 trim, 450 at the edge), snap offset corner (183), fade handles and
-- curves, the volume handle (184, 105, 525, 526, 463), left-right resize (32644)
M.REAPER_HANDLES = keys({ 417, 418, 450, 183, 184, 105, 525, 526, 463, 32644 })

function M.current_cursor()
  return reaper.JS_Mouse_GetCursor and M.cursor_key(reaper.JS_Mouse_GetCursor()) or nil
end

return M
