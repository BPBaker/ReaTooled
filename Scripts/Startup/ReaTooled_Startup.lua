--[[
-- @description ReaTooled - Startup
-- @version 2.2
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
    # Runs ReaTooled's startup scripts when REAPER launches
    Called from a marked block in Scripts/__startup.lua, which the
    ReaTooled installer adds. Edit the SCRIPTS list below to change
    what runs at startup; ReaPack updates this file like any other.
    CHANGELOG
    v 2.2 - On the first start after setup, also has ReaPack download the rest of ReaTooled.
    v 2.1 - Finishes "Set up ReaTooled": loads the ReaTooled screenset once,
            and restarts the setup helper if it didn't get to run.
    v 2.0 - Moved out of __startup.lua into its own ReaPack-managed script.
            Scripts are found by path instead of hard-coded command IDs.
    v 1.7 - Removed ReaTooled_Link loop points and razor areas.lua (now part of
            Recall ReaTooled Button States), temporarily removed
            ReaTooled_Synch razor areas on grouped items.lua
    v 1.6 - Added ReaTooled_Link loop points and razor areas.lua and
            ReaTooled_Synch razor areas on grouped items.lua
    v 1.5 - Added ReaTooled_Link razor area and item selection.lua
    v 1.4 - Ripple options actually turn on
    v 1.3 - Revised ripple option logic
    v 1.2 - Added ripple edit options
    v 1.1 - Recall ReaTooled ExtStates
--]]

-- Paths are relative to Scripts/ReaTooled/. Runs in this order.
local SCRIPTS = {
  "Toggles/ReaTooled_Recall ReaTooled Button States.lua",
  -- "Toggles/ReaTooled_Synch razor areas on grouped items.lua",  -- temporarily disabled since v1.7
  "Helpers/ReaTooled_Link razor area and item selection.lua",
  "Toggles/ReaTooled_At loop end, move cursor to loop end and clear selection (only when loop button is off).lua",
  "Tools/Default Multi Tool (Smart)_ReaTooled.lua",
  "Edit/ReaTooled_Grid and Nudge Settings.lua",
}

-- Set to true to print missing scripts to the console while testing
local DEBUG = false

local base = reaper.GetResourcePath():gsub("\\", "/") .. "/Scripts/ReaTooled/"

for _, rel in ipairs(SCRIPTS) do
  local path = base .. rel
  if reaper.file_exists(path) then
    -- Returns the script's command ID (registering it first if needed),
    -- so this keeps working without hard-coded _RS... IDs.
    local id = reaper.AddRemoveReaScript(true, 0, path, true)
    if id and id ~= 0 then
      reaper.Main_OnCommand(id, 0)
    elseif DEBUG then
      reaper.ShowConsoleMsg("ReaTooled startup: could not register " .. rel .. "\n")
    end
  elseif DEBUG then
    reaper.ShowConsoleMsg("ReaTooled startup: missing " .. rel .. "\n")
  end
end

------------------------------------------------------------
-- After "Set up ReaTooled"
------------------------------------------------------------

local RES = reaper.GetResourcePath():gsub("\\", "/")
local PENDING = RES .. "/Data/ReaTooled/Pending"
local SETUP = RES .. "/Scripts/ReaTooled/Startup/ReaTooled_Set up ReaTooled.lua"

if reaper.file_exists(PENDING .. "/copy.txt") or reaper.file_exists(PENDING .. "/merge.txt") then
  -- Set up prepared files, but the helper that writes them when REAPER quits
  -- never ran (e.g. REAPER crashed or the computer restarted). Start it again.
  if reaper.file_exists(SETUP) then
    _G.REATOOLED_RELAUNCH_HELPER = true
    pcall(dofile, SETUP)
    _G.REATOOLED_RELAUNCH_HELPER = nil
  end
  reaper.ShowMessageBox("ReaTooled's setup isn't finished yet.\n\n" ..
    "Quit REAPER (File > Quit) and open it again to finish.", "ReaTooled", 0)
else
  -- First start after setup: download the rest of ReaTooled
  if reaper.GetExtState("ReaTooled", "SyncOnce") == "1" then
    reaper.DeleteExtState("ReaTooled", "SyncOnce", true)
    local sync = reaper.NamedCommandLookup("_REAPACK_SYNC")
    if sync ~= 0 then reaper.Main_OnCommand(sync, 0) end
  end
end
if not (reaper.file_exists(PENDING .. "/copy.txt") or reaper.file_exists(PENDING .. "/merge.txt"))
   and reaper.GetExtState("ReaTooled", "LoadScreensetOnce") == "1" then
  -- First start after setup: show the ReaTooled window layout (screenset 1)
  reaper.DeleteExtState("ReaTooled", "LoadScreensetOnce", true)
  local name = "Screenset: Load window set #01"
  local id = (reaper.kbd_getTextFromCmd(40454, 0) == name) and 40454 or nil
  if not id then
    for i = 1, 65535 do
      if reaper.kbd_getTextFromCmd(i, 0) == name then id = i; break end
    end
  end
  if id then reaper.Main_OnCommand(id, 0) end
end
