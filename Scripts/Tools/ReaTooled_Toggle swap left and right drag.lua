-- @description ReaTooled - Toggle swap left and right drag
-- @version 1.1
-- @date 2026.10.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Multi tool: swap razor and marquee between left-drag and right-drag
--   For people who are used to REAPER. With it on, in the Multi tool:
--     - right-drag in the arrange selects a razor area (instead of marquee)
--     - left-drag in empty track space is marquee (instead of razor)
--   The other tools aren't affected: right-drag is always the selection their
--   left-drag isn't (Move Tool: razor; Selector, Zoom, Trim, Scrub: marquee).
--   Off by default; your choice is kept when REAPER restarts. Takes effect right
--   away if the Multi tool is selected.
-- @changelog
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

-- Re-apply the Multi tool if it's selected, so the change takes effect right away
local MULTI_ID, MULTI_FILE = "_RS5e85a066efd01fde2482832bf4a3502dce0427b6", "Default Multi Tool (Smart)_ReaTooled.lua"
local cmd = reaper.NamedCommandLookup(MULTI_ID)
if cmd == 0 and reaper.file_exists(dir .. MULTI_FILE) then
  cmd = reaper.AddRemoveReaScript(true, 0, dir .. MULTI_FILE, true) or 0
end
if cmd ~= 0 and reaper.GetToggleCommandState(cmd) == 1 then reaper.Main_OnCommand(cmd, 0) end

reaper.defer(function() end)   -- no undo point
