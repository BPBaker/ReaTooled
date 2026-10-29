-- @description ReaTooled - Spot click (used by Spot mode)
-- @version 1.0
-- @date 2026.10.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Used for item clicks while "ReaTooled_Toggle Spot mode" is on: selects the
--   item the way a Move Tool click does, then opens the Spot dialog for it (or
--   switches the open dialog to it).
-- @changelog
--   v1.0 Initial version

local NS = "ReaTooled"
local RES = reaper.GetResourcePath():gsub("\\", "/") .. "/Scripts/ReaTooled/"
local MOVE_CLICK = RES .. "Edit/ReaTooled_Move Tool Left Click (Select item under mouse cursor, move cursor to start of items).lua"
local _, script_path = reaper.get_action_context()
local DIALOG = (script_path:match("^(.*[/\\])") or "") .. "ReaTooled_Spot dialog.lua"

local function cmd_of(path)
  if not reaper.file_exists(path) then return 0 end
  return reaper.AddRemoveReaScript(true, 0, path, true) or 0
end

local x, y = reaper.GetMousePosition()
local item = reaper.GetItemFromPoint(x, y, true)
if not item then return end

-- Select it like a normal Move Tool click
local move = cmd_of(MOVE_CLICK)
if move ~= 0 then
  reaper.Main_OnCommand(move, 0)
else
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  reaper.UpdateArrange()
end

-- Tell the dialog which item, then open it (unless it's open already)
local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
reaper.SetExtState(NS, "SpotItem", guid, false)
local alive = tonumber(reaper.GetExtState(NS, "SpotDialogAlive")) or 0
if reaper.time_precise() - alive > 1 then
  local dlg = cmd_of(DIALOG)
  if dlg ~= 0 then reaper.Main_OnCommand(dlg, 0) end
end
