-- @description ReaTooled - Toggle swap left and right drag
-- @version 1.2
-- @date 2026.10.30
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Swap razor and marquee between left-drag and right-drag
--   For people who are used to REAPER. With it on, in the Selector and the Multi
--   tool, right-drag selects a razor area and left-drag in empty track space is
--   marquee (swapped from razor left, marquee right).
--   The other tools aren't affected (the Move Tool only ever selects items: left-
--   and right-drag are marquee; Zoom, Trim and Scrub: right-drag is marquee).
--   Off by default; your choice is kept when REAPER restarts. Takes effect right
--   away for the tool that's selected.
-- @changelog
--   v1.2 Applies to the Selector too
--   v1.1 Applies to the Multi tool only
--   v1.0 Initial version

local _, script_path, section, cmd_id = reaper.get_action_context()
local dir = script_path:match("^(.*[/\\])") or ""

local ok, swap = pcall(dofile, dir .. "ReaTooled_Drag swap lib.lua")
if not ok or type(swap) ~= "table" then
  reaper.ShowMessageBox("ReaTooled_Drag swap lib.lua is missing from:\n" .. dir ..
    "\n\nUpdate ReaTooled in ReaPack (Extensions > ReaPack > Synchronize packages).", "ReaTooled", 0)
  return
end

local on = not swap.is_on()
swap.set_on(on)
reaper.SetToggleCommandState(section, cmd_id, on and 1 or 0)
reaper.RefreshToolbar2(section, cmd_id)

-- Re-apply the selected tool if the swap changes it, so it takes effect right away
local okT, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
if okT and type(tools) == "table" then
  local key = tools.current_tool()
  if key == "selector" or key == "smart" then
    local t = tools.find(key)
    local tcmd = t and tools.command_of(t) or 0
    if tcmd ~= 0 then
      reaper.SetExtState("ReaTooled", tools.BUSY_KEY or "ToolOptionsBusy", "1", false)
      reaper.Main_OnCommand(tcmd, 0)
      reaper.DeleteExtState("ReaTooled", tools.BUSY_KEY or "ToolOptionsBusy", false)
    end
  end
end
reaper.defer(function() end)   -- no undo point
