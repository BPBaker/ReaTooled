-- @description ReaTooled - Toggle Separation mode (drag a razor area to move what's in it)
-- @version 1.1
-- @date 2026.10.30
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Like Pro Tools' Separation Grabber: with it on, a plain left-drag on a razor area
--   moves the area and what's in it (REAPER's "Move areas": items are split at the
--   area's edges and the part inside moves). With it off, a plain drag on a razor
--   area does what it did before (ReaTooled ships it as No action).
--   Only that one mouse modifier changes (Razor edit area, left drag, no modifier
--   keys); it's remembered and put back exactly when Separation goes off, so the
--   rest of your mouse modifiers and the tools are never touched. Works with every
--   tool. Kept when REAPER restarts.
--   In Shuffle mode (with the Move Tool or the Multi tool), dragging a razor area
--   shuffles what's in it instead: what follows closes up and it goes back in at an
--   item edge, like Pro Tools' Separation Grabber in Shuffle.
-- @changelog
--   v1.1 Works with Shuffle mode: in Shuffle, dragging a razor area shuffles what's in
--        it (the Shuffle move script does it, so REAPER's own razor drag is turned off
--        there)
--   v1.0 Initial version

local NS        = "ReaTooled"
local KEY       = "SeparationMode"       -- "1" while on (kept)
local SNAP_KEY  = "SeparationOriginal"   -- the modifier as it was before (kept)
local CTX, FLAG = "MM_CTX_AREASEL", 0    -- Razor edit area: left drag, no modifier keys
local MOVE_AREAS = "-1"                  -- REAPER's default for that drag: Move areas

local _, script_path, section, cmd_id = reaper.get_action_context()
local dir = script_path:match("^(.*[/\\])") or ""
local okT, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
if not (okT and type(tools) == "table") then tools = nil end

-- Other modes (Shuffle) may have this modifier changed too: put them back first
if tools and tools.release_mode_overrides then tools.release_mode_overrides() end

local on = reaper.GetExtState(NS, KEY) ~= "1"
if on then
  local orig = reaper.GetMouseModifier and reaper.GetMouseModifier(CTX, FLAG) or ""
  if orig == nil or orig == "" then orig = "-1" end
  if orig ~= MOVE_AREAS then reaper.SetExtState(NS, SNAP_KEY, orig, true) end
  reaper.SetMouseModifier(CTX, FLAG, MOVE_AREAS)
else
  local orig = reaper.GetExtState(NS, SNAP_KEY)
  if orig == "" then orig = "0 m" end            -- ReaTooled's own setting: No action
  reaper.SetMouseModifier(CTX, FLAG, orig)
end
reaper.SetExtState(NS, KEY, on and "1" or "0", true)
if tools and tools.reapply_tool then tools.reapply_tool() end   -- the modes set again

reaper.SetToggleCommandState(section, cmd_id, on and 1 or 0)
reaper.RefreshToolbar2(section, cmd_id)
local x, y = reaper.GetMousePosition()
reaper.TrackCtl_SetToolTip("Separation " .. (on and "on: drag a razor area to move what's in it" or "off"), x + 12, y + 12, true)
reaper.defer(function() end)   -- no undo point
