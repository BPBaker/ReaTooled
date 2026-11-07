--[[
-- @description ReaTooled - Shortcut choices
-- @version 1.0
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Change your answers in the shortcut clash window
    When ReaTooled's shortcuts use keys you already use for something else, Set up asks which
    to keep, and updates remember what you chose (so you aren't asked again). This opens the
    same window with every key you were asked about, so you can change your mind either way:
    give a key you kept to ReaTooled, or give a key ReaTooled has back to your own action.
    Your settings are backed up first and REAPER restarts to finish, like an update.
-- CHANGELOG
-- v1.0 First version
--]]

local RES = reaper.GetResourcePath():gsub("\\", "/")
local SETUP = RES .. "/Scripts/ReaTooled/Startup/ReaTooled_Set up ReaTooled.lua"

if not reaper.file_exists(SETUP) then
  reaper.ShowMessageBox("\"Set up ReaTooled\" is missing, so the shortcut choices can't be opened.\n\n" .. SETUP,
    "Shortcut choices", 0)
  return
end
_G.REATOOLED_UPDATE = "choices"
local ok, err = pcall(dofile, SETUP)
_G.REATOOLED_UPDATE = nil
if not ok then reaper.ShowMessageBox("Shortcut choices couldn't open:\n\n" .. tostring(err), "Shortcut choices", 0) end
