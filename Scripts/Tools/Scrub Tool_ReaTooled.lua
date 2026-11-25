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


-- Set up ReaTooled hasn't run here: the user's own mouse modifiers haven't been backed up,
-- so this tool leaves them alone (3.04: running a tool before setup had replaced them)
if not reaper.file_exists(reaper.GetResourcePath():gsub("\\", "/") .. "/Data/ReaTooled/Backups/Before ReaTooled/backup_info.txt") then
  reaper.ShowMessageBox("ReaTooled isn't set up yet, so this tool won't change your mouse settings.\n\n" ..
    "Run \"Set up ReaTooled\" from the Actions list first. It backs up your settings before changing anything.",
    "ReaTooled", 0)
  return
end

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
