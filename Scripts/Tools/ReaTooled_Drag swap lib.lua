-- @description ReaTooled - Drag swap library (used by the tool scripts)
-- @version 1.1
-- @date 2026.10.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Not an action. The tool scripts load this after setting their own mouse
--   modifiers. Right-drag in the arrange does the selection the tool's left-drag
--   doesn't:
--     - Move Tool (Grabber): left-drag marquee, right-drag razor area
--     - Selector, Zoom, Trim, Scrub: right-drag marquee
--     - Multi tool: right-drag marquee (left-drag razor), or with
--       "ReaTooled_Toggle swap left and right drag" on, right-drag razor and
--       left-drag in empty track space marquee
-- @changelog
--   v1.1 Right-drag is written in full (all 16 keys) for every tool, instead of
--        read back and restored (that left right-drag on razor and copied razor
--        onto unused keys). The swap applies to the Multi tool only; the Move
--        Tool always has razor on right-drag.
--   v1.0 Initial version

local M = {}

local NS     = "ReaTooled"
local KEY_ON = "DragSwap"   -- "1" = swap on (per user, kept across restarts)

local RDRAG = "MM_CTX_ARRANGE_RMOUSE"   -- Arrange view: right drag
local TRACK = "MM_CTX_TRACK"            -- Track: left drag (empty track space)

-- Arrange view right-drag as ReaTooled ships it, every key written ("-1" =
-- REAPER's default; plain right-drag's default is marquee select items)
local RIGHT_MARQUEE = {
  [0] = "-1",    [1] = "28 m",  [2] = "26 m",  [3] = "-1",
  [4] = "11 m",  [5] = "30 m",  [6] = "-1",    [7] = "-1",
  [8] = "10 m",  [9] = "12 m",  [10] = "-1",   [11] = "-1",
  [12] = "11 m", [13] = "13 m", [14] = "-1",   [15] = "-1",
}
-- The same, with plain right-drag selecting a razor area
local RIGHT_RAZOR = {}
for i, v in pairs(RIGHT_MARQUEE) do RIGHT_RAZOR[i] = v end
RIGHT_RAZOR[0] = "24 m"

-- Multi tool with the swap on: left-drag in empty track space is marquee
local TRACK_MARQUEE = {
  [0] = "9 m",    -- plain: marquee select items
  [1] = "13 m",   -- Shift: marquee add to item selection
}

function M.is_on()
  return reaper.GetExtState(NS, KEY_ON) == "1"
end

function M.set_on(on)
  reaper.SetExtState(NS, KEY_ON, on and "1" or "0", true)
end

local function set(context, values)
  for i = 0, 15 do
    if values[i] then reaper.SetMouseModifier(context, i, values[i]) end
  end
end

-- Right-drag: all 16 keys written, so the result is always exactly one layout
local function set_right_drag(values)
  set(RDRAG, values)
end

-- Called by every tool script after it sets its own modifiers.
-- tool: "smart", "grabber", "selector", "zoom", "trim" or "scrub"
function M.apply(tool)
  if tool == "grabber" then
    set_right_drag(RIGHT_RAZOR)
  elseif tool == "smart" and M.is_on() then
    set_right_drag(RIGHT_RAZOR)
    set(TRACK, TRACK_MARQUEE)
  else
    set_right_drag(RIGHT_MARQUEE)
  end
  reaper.DeleteExtState(NS, "DragSwapRightDragPlain", true)   -- left by v1.0
end

return M
