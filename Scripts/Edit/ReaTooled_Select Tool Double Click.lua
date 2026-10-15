-- @description ReaTooled - Select Tool Double Click
-- @version 1.1
-- @date 2025.04.22
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Double-click selection tool for Reaper.
--   # Selects the item under the mouse, creates a razor area around it (and any grouped items), and moves the edit cursor to the item's start.
--   # Designed for focused item selection without affecting adjacent groups or view positions.
-- @changelog
--   v1.1 - Added group-aware logic for razor and selection
--   v1.0 - Initial implementation

reaper.Undo_BeginBlock()

-- Unselect all items
reaper.Main_OnCommand(40289, 0)

-- Select item under mouse cursor
reaper.Main_OnCommand(40528, 0)
local item = reaper.GetSelectedMediaItem(0, 0)

if item then
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_start + item_len
    local item_track = reaper.GetMediaItem_Track(item)
    local groupID = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")

    -- Clear razor edits on all tracks
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        reaper.GetSetMediaTrackInfo_String(tr, 'P_RAZOREDITS', '', true)
    end

    -- Store view
    local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)

    if groupID > 0 then
        local itemCount = reaper.CountMediaItems(0)
        for i = 0, itemCount - 1 do
            local it = reaper.GetMediaItem(0, i)
            if reaper.GetMediaItemInfo_Value(it, "I_GROUPID") == groupID then
                local it_start = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local it_len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                local it_end = it_start + it_len
                local it_track = reaper.GetMediaItem_Track(it)

                local area = string.format("%f %f \"reatooled\"", it_start, it_end)
                local _, current = reaper.GetSetMediaTrackInfo_String(it_track, 'P_RAZOREDITS', '', false)
                reaper.GetSetMediaTrackInfo_String(it_track, 'P_RAZOREDITS', current .. area .. ' ', true)

                reaper.SetMediaItemSelected(it, true)
            end
        end
    else
        local area = string.format("%f %f \"reatooled\"", item_start, item_end)
        reaper.GetSetMediaTrackInfo_String(item_track, 'P_RAZOREDITS', area, true)
        reaper.SetMediaItemSelected(item, true)
    end

    -- Move edit cursor without changing arrange view
    reaper.SetEditCurPos(item_start, false, false)
    reaper.GetSet_ArrangeView2(0, true, 0, 0, view_start, view_end)
end

reaper.Undo_EndBlock("Select item and razor on double click (group-aware)", 0)

