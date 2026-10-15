--@description ReaTooled: Delete Item Under Mouse (Suspend Groups)
--@version 1.0
--@changelog
--  v1.0 - Initial public release
--@author Brendan Baker (ReaTooled)
--@website https://brendanpatrickbaker.com/reatooled/
--@about
--  Temporarily suspends item grouping, selects the item under the mouse cursor,
--  deletes it, restores grouping, and restores the previous item selection
--  (minus the deleted item). Designed for key bindings.

---------------------------------------------------------------
-- Safety: require SWS
---------------------------------------------------------------
if not reaper.BR_GetMouseCursorContext_Item then return end

---------------------------------------------------------------
-- Get item under mouse (SWS = no click required)
---------------------------------------------------------------
reaper.BR_GetMouseCursorContext()
local target_item = reaper.BR_GetMouseCursorContext_Item()
if not target_item then return end

---------------------------------------------------------------
-- Save current item selection
---------------------------------------------------------------
local selected_items = {}
local sel_count = reaper.CountSelectedMediaItems(0)

for i = 0, sel_count - 1 do
  selected_items[i+1] = reaper.GetSelectedMediaItem(0, i)
end

---------------------------------------------------------------
-- Begin undo block
---------------------------------------------------------------
reaper.Undo_BeginBlock()

---------------------------------------------------------------
-- Suspend item grouping
---------------------------------------------------------------
reaper.Main_OnCommand(1156, 0) -- Options: Toggle item grouping override

---------------------------------------------------------------
-- Select ONLY the target item
---------------------------------------------------------------
reaper.SelectAllMediaItems(0, false)
reaper.SetMediaItemSelected(target_item, true)
reaper.UpdateArrange()

---------------------------------------------------------------
-- Delete selected item (safe: grouping suspended)
---------------------------------------------------------------
reaper.Main_OnCommand(40006, 0) -- Item: Remove items

---------------------------------------------------------------
-- Restore item grouping
---------------------------------------------------------------
reaper.Main_OnCommand(1156, 0) -- Options: Toggle item grouping override

---------------------------------------------------------------
-- Restore previous selection (minus deleted item)
---------------------------------------------------------------
reaper.SelectAllMediaItems(0, false)

for _, item in ipairs(selected_items) do
  if reaper.ValidatePtr(item, "MediaItem*") then
    reaper.SetMediaItemSelected(item, true)
  end
end

---------------------------------------------------------------
-- Finalize
---------------------------------------------------------------
reaper.UpdateArrange()

reaper.Undo_EndBlock(
  "ReaTooled: Delete Item Under Mouse (Suspend Groups)",
  -1
)
