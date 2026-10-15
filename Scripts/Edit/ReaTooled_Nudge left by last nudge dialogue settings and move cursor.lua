-- @description ReaTooled_Nudge Items Left via Last Nudge Settings + Move Cursor to First Item
-- @version 1.1
-- @date 2024.04.16
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- Nudges selected items to the left using REAPER's last-used nudge dialog settings.
-- Moves the edit cursor to the first selected item without affecting arrange view.

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Nudge left using REAPER's built-in "Nudge left by last nudge dialog settings"
reaper.Main_OnCommand(41250, 0)

-- Move cursor to start of first selected item
local item = reaper.GetSelectedMediaItem(0, 0)
if item then
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.SetEditCurPos(pos, false, false) -- don't move view, don't seek
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Nudge Left", -1)
reaper.UpdateArrange()

