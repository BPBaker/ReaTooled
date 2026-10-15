-- @description ReaTooled_Trim Item Edges to Next and Previous Items (Expand to fill between neighboring items, preserve sync)
-- @version 1.2
-- @date 2025.09.08
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Trims both edges of selected item(s) to the nearest neighboring items on the same track.
--   # Preserves source sync by adjusting take start offset when the LEFT edge moves.
--   # Removes fades. Loop Source state is LEFT UNCHANGED. Works only within the same track.

local reaper = reaper
local EPS = 1e-12

-- ---------- helpers ----------
local function get_neighbors(item)
  local track      = reaper.GetMediaItem_Track(item)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_end   = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_count = reaper.CountTrackMediaItems(track)

  local prev_end, next_start
  for i = 0, item_count - 1 do
    local other = reaper.GetTrackMediaItem(track, i)
    if other ~= item then
      local os = reaper.GetMediaItemInfo_Value(other, "D_POSITION")
      local oe = os + reaper.GetMediaItemInfo_Value(other, "D_LENGTH")

      if oe <= item_start then
        if not prev_end or oe > prev_end then prev_end = oe end
      end
      if os >= item_end then
        if not next_start or os < next_start then next_start = os end
      end
    end
  end
  return prev_end, next_start
end

-- Adjust take start offset so content stays in sync when the LEFT edge moves
local function adjust_start_offset_for_left_move(item, old_start, new_start)
  local delta = new_start - old_start
  if math.abs(delta) < EPS then return end

  local take = reaper.GetActiveTake(item)
  if not take then return end

  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  if rate <= 0 then rate = 1.0 end

  local off  = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
  -- Project seconds → source seconds (rate-aware)
  local new_off = off + (delta * rate)

  -- For non-looping behavior, clamp to >= 0 so extending left can't go negative
  if new_off < 0 then new_off = 0 end

  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_off)
end

-- ---------- main ----------
local function main()
  local items = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n - 1 do
    items[#items+1] = reaper.GetSelectedMediaItem(0, i)
  end

  for _, item in ipairs(items) do
    if item then
      local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local item_end   = item_start + item_len

      -- Leave B_LOOPSRC unchanged; just remove fades
      reaper.Main_OnCommand(41191, 0) -- Remove fade in
      reaper.Main_OnCommand(41193, 0) -- Remove fade out

      local prev_end, next_start = get_neighbors(item)
      local new_start = prev_end or item_start
      local new_end   = next_start or item_end

      if new_end > new_start then
        -- If LEFT edge is changing, adjust take start offset to preserve sync
        if math.abs(new_start - item_start) >= EPS then
          adjust_start_offset_for_left_move(item, item_start, new_start)
        end
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_start)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH",   new_end - new_start)
      end
    end
  end

  reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)

reaper.Undo_EndBlock("Trim Item Edges to Next and Previous Items (Expand to fill between neighboring items)", -1)
