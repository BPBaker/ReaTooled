-- @description ReaTooled_Trim Item Left Edge to Previous Item (preserve sync; Loop Source state unchanged)
-- @version 1.2
-- @date 2025.09.08
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Trims the LEFT edge of selected item(s) to the previous item on the same track.
--   # PRESERVES SOURCE SYNC by adjusting the take start offset when the left edge moves.
--   # Removes fade-in per item. Loop Source state is LEFT UNCHANGED (no force ON/OFF).
--   # Works only within the same track (ignores items on other tracks).

local reaper = reaper
local EPS = 1e-12

-- Find the nearest previous item's end on the same track
local function get_previous_end_on_track(item)
  local track = reaper.GetMediaItem_Track(item)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_count = reaper.CountTrackMediaItems(track)
  local target_end = nil

  for i = 0, item_count - 1 do
    local other = reaper.GetTrackMediaItem(track, i)
    if other ~= item then
      local other_start = reaper.GetMediaItemInfo_Value(other, "D_POSITION")
      local other_len   = reaper.GetMediaItemInfo_Value(other, "D_LENGTH")
      local other_end   = other_start + other_len
      if other_end <= item_start then
        if not target_end or other_end > target_end then
          target_end = other_end
        end
      end
    end
  end
  return target_end
end

-- Adjust take start offset so content stays phase-locked when LEFT edge moves
local function adjust_start_offset_for_left_move(item, old_start, new_start)
  local delta = new_start - old_start
  if math.abs(delta) < EPS then return end

  local take = reaper.GetActiveTake(item)
  if not take then return end

  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  if rate <= 0 then rate = 1.0 end
  local off  = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0

  -- Convert project-time delta to source-time delta (rate-aware)
  local new_off = off + (delta * rate)

  -- Non-looping behavior: clamp to >= 0 (do not wrap)
  if new_off < 0 then new_off = 0 end

  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_off)
end

-- Trim this item's left edge to previous item on same track, preserving sync
local function trim_left_preserve_sync(item)
  if not item then return end

  local old_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local old_len   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local prev_end  = get_previous_end_on_track(item)

  if prev_end and prev_end < old_start - EPS then
    -- Adjust offset first, then move geometry
    adjust_start_offset_for_left_move(item, old_start, prev_end)
    local new_len = (old_start + old_len) - prev_end
    if new_len < 0 then new_len = 0 end
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", prev_end)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH",   new_len)
  end
end

local function main()
  -- Capture original selection
  local selected_items = {}
  local num_items = reaper.CountSelectedMediaItems(0)
  for i = 0, num_items - 1 do
    selected_items[#selected_items+1] = reaper.GetSelectedMediaItem(0, i)
  end

  for _, item in ipairs(selected_items) do
    if item then
      -- Solo-select this item for per-item actions
      reaper.Main_OnCommand(40289, 0) -- Unselect all
      reaper.SetMediaItemSelected(item, true)

      -- Remove fade-in (leave Loop Source state UNCHANGED)
      reaper.Main_OnCommand(41191, 0) -- Item: Remove fade in

      -- Trim left to previous, preserving sync
      trim_left_preserve_sync(item)
    end
  end

  -- Restore original selection
  reaper.Main_OnCommand(40289, 0)
  for _, it in ipairs(selected_items) do
    if reaper.ValidatePtr(it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end

  reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)

reaper.Undo_EndBlock("Trim Item Left Edge to Previous Item (with Loop Item Source Off)", -1)

