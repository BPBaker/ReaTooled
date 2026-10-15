--[[
-- @description ReaTooled - Startup
-- @version 2.0
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
    # Runs ReaTooled's startup scripts when REAPER launches
    Called from a marked block in Scripts/__startup.lua, which the
    ReaTooled installer adds. Edit the SCRIPTS list below to change
    what runs at startup; ReaPack updates this file like any other.
    CHANGELOG
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
