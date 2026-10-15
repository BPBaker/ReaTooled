-- @description ReaTooled_Trim Item Right Edge to Next Item (with Loop Item Source Off)
-- @version 1.1
-- @date 2025.04.23
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Trims the right edge of selected item(s) to the next item on the same track.
--   # Disables loop item source and removes fade-out per item.
--   # Works only within the same track (ignores items on other tracks).

local function trim_to_next_on_same_track(item)
  if not item then return end

  local item_end = reaper.GetMediaItemInfo_Value(item, "D_POSITION") + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local track = reaper.GetMediaItem_Track(item)
  local target_pos = nil

  local item_count = reaper.CountTrackMediaItems(track)
  for i = 0, item_count - 1 do
    local other = reaper.GetTrackMediaItem(track, i)
    if other ~= item then
      local other_pos = reaper.GetMediaItemInfo_Value(other, "D_POSITION")
      if other_pos > item_end then
        if not target_pos or other_pos < target_pos then
          target_pos = other_pos
        end
      end
    end
  end

  if target_pos then
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", target_pos - item_start)
  end
end

function main()
  local selected_items = {}
  local num_items = reaper.CountSelectedMediaItems(0)
  for i = 0, num_items - 1 do
    selected_items[i + 1] = reaper.GetSelectedMediaItem(0, i)
  end

  for i = 1, #selected_items do
    local item = selected_items[i]
    if item then
      -- Temporarily select only this item
      reaper.Main_OnCommand(40289, 0) -- Unselect all
      reaper.SetMediaItemSelected(item, true)

      -- Remove fade out
      reaper.Main_OnCommand(41193, 0)

      ---- Turn loop item source off
      --reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)

      -- Trim to next item on the same track
      trim_to_next_on_same_track(item)
    end
  end

  -- Restore original selection
  for _, item in ipairs(selected_items) do
    reaper.SetMediaItemSelected(item, true)
  end

  reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Trim Item Right Edge to Next Item (with Loop Item Source Off)", -1)

