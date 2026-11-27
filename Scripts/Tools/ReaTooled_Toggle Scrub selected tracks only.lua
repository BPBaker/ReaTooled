-- @description ReaTooled - Toggle Scrub selected tracks only (Scrub tool option)
-- @version 1.0
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   An option of the Scrub tool (Cmd+click or Option+click on its button). On (the default):
--   while the Scrub tool is chosen, REAPER's "Only play selected tracks when scrubbing/jogging"
--   is on, so you hear only the selected tracks. Choosing another tool puts REAPER's setting
--   back as it was. Kept when REAPER restarts.
-- @changelog
--   v1.0 Initial version

local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])") or ""
local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
if not (ok and type(tools) == "table" and tools.set_scrub_selected) then
  reaper.ShowMessageBox("ReaTooled_Tools lib.lua is missing from:\n" .. dir, "ReaTooled", 0)
  return
end
tools.set_scrub_selected(not tools.scrub_selected_on())
-- (the Scrub tool chosen now: REAPER's setting follows straight away)
if tools.current_tool and tools.current_tool() == "scrub" then tools.apply_scrub_option("scrub") end
reaper.defer(function() end)   -- no undo point
