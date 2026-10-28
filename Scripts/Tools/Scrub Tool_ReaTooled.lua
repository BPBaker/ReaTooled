-- @description ReaTooled - Scrub Tool
-- @version 1.3
-- @date 2026.10.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- 
--   # This script loads ReaTooled's Scrub Tool
-- # v1.3 Stopping the Trim Tool and the toolbar buttons are shared with the other tools (ReaTooled_Tools lib.lua), which also knows the new Pencil Tool
-- # v1.2 Puts right-drag back to marquee when "Toggle swap left and right drag" had changed it
-- # v1.1 Kill Trim Tool


reaper.Main_OnCommand(42632, 0)

----------------------------------------
-- Finish: Trim Tool off, drag swap, Pencil cleanup, toolbar buttons
-- (shared by every tool: ReaTooled_Tools lib.lua)
----------------------------------------
do
  local dir = ({reaper.get_action_context()})[2]:match("^(.*[/\\])") or ""
  local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
  if ok and type(tools) == "table" then
    tools.finish("scrub")
  else
    reaper.ShowConsoleMsg("ReaTooled: tools library not loaded: " .. tostring(tools) .. "\n")
  end
end
