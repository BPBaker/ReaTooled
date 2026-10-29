-- @description ReaTooled - Toggle Spot mode
-- @version 1.1
-- @date 2026.10.29
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Like Pro Tools' Spot mode
--   While on, clicking an item with the Move Tool (Grabber), or with the lower
--   half of an item in the Multi tool, selects it and opens the Spot dialog.
--   Other tools aren't affected. Off again when REAPER restarts.
--   Turning Spot mode on turns Shuffle mode off (back to Slip), like Pro Tools.
--   The Spot dialog can also be opened any time with "ReaTooled_Spot dialog".
-- @changelog
--   v1.1 Turns Shuffle mode off (Spot and Shuffle are exclusive)
--   v1.0 Initial version

local _, script_path, section, cmd_id = reaper.get_action_context()
local dir = script_path:match("^(.*[/\\])") or ""

local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
if not ok or type(tools) ~= "table" then
  reaper.ShowMessageBox("ReaTooled_Tools lib.lua is missing from:\n" .. dir ..
    "\n\nUpdate ReaTooled in ReaPack (Extensions > ReaPack > Synchronize packages).", "ReaTooled", 0)
  return
end

local on = not tools.spot_on()
tools.set_spot(on)

-- Spot and Shuffle are exclusive: Spot on = Shuffle off, back to Slip (ripple off).
-- The Shuffle button's own watcher sees this and turns its button off.
if on and tools.shuffle_on() then
  tools.set_shuffle(false)
  reaper.Main_OnCommand(40309, 0)   -- Options: Set ripple editing off
end
reaper.SetToggleCommandState(section, cmd_id, on and 1 or 0)
reaper.RefreshToolbar2(section, cmd_id)

-- Re-apply the current tool if Spot mode changes what its clicks do
tools.reapply_tool()

local x, y = reaper.GetMousePosition()
reaper.TrackCtl_SetToolTip("Spot mode " .. (on and "on" or "off"), x + 12, y + 12, true)

reaper.defer(function() end)   -- no undo point
