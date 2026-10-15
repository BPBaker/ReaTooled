-- @description ReaTooled - Select Tool Left Click (Edit Cursor + Group Aware)
-- @version 1.3
-- @date 2026.10.14
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Select tool left-click behavior.
--   # Moves edit cursor to mouse position and selects item under mouse.
--   # Clears time selection if the Link toggle (Link Play Cursor to Edit Cursor,
--   # ReaTooled's Link Timeline and Edit Selection) is ON.
--   # Respects REAPER's native group selection preference (41156).
--   # Only expands selection to group if "Selecting one grouped item selects group" option is ON.
-- @changelog
--   1.3 (2026.10.14) - Fixed Link toggle lookup: the old hard-coded command ID pointed to a
--                      script that no longer exists, so the time selection was never cleared.
--                      The toggle is now found by file path.
--   1.2 (2025.04.20) - Group expand (40034) now conditional on native group preference (41156),
--                      matching Move Tool behavior. Previously always selected full group.

local reaper = reaper

local CMD_GROUP_SELECT_OPTION = 41156  -- Options: Selecting one grouped item selects group
local CMD_GROUP_EXPAND        = 40034  -- Item grouping: Select all items in group

-- Link toggle that makes a click clear the time selection (matches Move Tool logic)
local LINK_TOGGLE_SCRIPT = "Toggles/ReaTooled_Toggle Link Play Cursor to Edit Cursor.lua"

-- Command ID of a ReaTooled script from its path (relative to Scripts/ReaTooled/).
-- Returns 0 if the file is missing.
local function script_cmd(rel)
  local path = reaper.GetResourcePath():gsub("\\", "/") .. "/Scripts/ReaTooled/" .. rel
  if not reaper.file_exists(path) then return 0 end
  return reaper.AddRemoveReaScript(true, 0, path, true) or 0
end

local function group_pref_on()
  return reaper.GetToggleCommandState(CMD_GROUP_SELECT_OPTION) == 1
end

-- Link toggle state
local link_cmd = script_cmd(LINK_TOGGLE_SCRIPT)
local link_toggle_state = (link_cmd ~= 0) and reaper.GetToggleCommandStateEx(0, link_cmd) or 0

reaper.Undo_BeginBlock()

-- Move edit cursor to mouse position
reaper.BR_GetMouseCursorContext()
local mouse_pos = reaper.BR_GetMouseCursorContext_Position()
if mouse_pos then
  reaper.SetEditCurPos(mouse_pos, false, false)
end

-- Select item under mouse, then expand to group only if native preference is ON
reaper.Main_OnCommand(40528, 0) -- Select item under mouse cursor
if group_pref_on() then
  reaper.Main_OnCommand(CMD_GROUP_EXPAND, 0)
end

-- Clear time selection if the Link toggle is ON
if link_toggle_state == 1 then
  reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
end

reaper.Undo_EndBlock("Select tool - item select + edit cursor", 0)
