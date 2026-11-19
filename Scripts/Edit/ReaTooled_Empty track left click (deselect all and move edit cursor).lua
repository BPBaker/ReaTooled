-- @description ReaTooled - Empty track left click (deselect all and move edit cursor)
-- @version 1.0
-- @date 2026.11.19
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # A plain left click on empty track space, for ReaTooled's tools
--   Clears all razor areas, unselects all tracks, items and envelope points, removes the time
--   selection, and moves the edit cursor to the mouse (snapping as REAPER's own click does).
--   With Link Timeline and Edit Selection on, the loop points are cleared too, since they're
--   the edit selection; off, they're left alone.
--   Set as the plain empty-track click by the Smart, Move, Selector and Trim tools (it replaces
--   REAPER's "Deselect all items and move edit cursor", which left razor areas, the time
--   selection and the loop points behind).
-- @changelog
--   v1.0 (2026.11.19) First version

local reaper = reaper

-- A Shuffle mode drag just ended (REAPER can call the click on its release): the Shuffle move
-- script has done the selection and the undo step
do
  local t = tonumber(reaper.GetExtState("ReaTooled", "ShuffleDragTime"))
  if t and reaper.time_precise() - t < 0.5 then
    reaper.defer(function() end)   -- (no undo point)
    return
  end
end

local CMD_RAZOR_CLEAR    = 42406   -- Razor edit: Clear all areas
local CMD_UNSELECT_ALL   = 40769   -- Unselect (clear selection of) all tracks/items/envelope points
local CMD_CURSOR_TO_MOUSE = 40513  -- View: Move edit cursor to mouse cursor

-- Link Timeline and Edit Selection, found by its file (as the Select Tool does)
local LINK_TOGGLE_SCRIPT = "Toggles/ReaTooled_Toggle Link Play Cursor to Edit Cursor.lua"
local function script_cmd(rel)
  local path = reaper.GetResourcePath():gsub("\\", "/") .. "/Scripts/ReaTooled/" .. rel
  if not reaper.file_exists(path) then return 0 end
  return reaper.AddRemoveReaScript(true, 0, path, true) or 0
end
local link_cmd = script_cmd(LINK_TOGGLE_SCRIPT)
local linked = link_cmd ~= 0 and reaper.GetToggleCommandStateEx(0, link_cmd) == 1

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
reaper.Main_OnCommand(CMD_RAZOR_CLEAR, 0)
reaper.Main_OnCommand(CMD_UNSELECT_ALL, 0)
reaper.GetSet_LoopTimeRange2(0, true, false, 0, 0, false)                 -- (time selection: removed)
if linked then reaper.GetSet_LoopTimeRange2(0, true, true, 0, 0, false) end -- (loop points: only when linked)
reaper.Main_OnCommand(CMD_CURSOR_TO_MOUSE, 0)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Deselect all and move edit cursor", -1)
