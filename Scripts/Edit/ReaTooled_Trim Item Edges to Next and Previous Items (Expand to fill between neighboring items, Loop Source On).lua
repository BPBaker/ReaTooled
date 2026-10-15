-- @description ReaTooled_Trim Item Edges to Next and Previous Items (Expand to fill, Loop Source ON + SWS Loop Section BEFORE resize, only if missing, preserve sync)
-- @version 1.4
-- @date 2025.09.08
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Trims both edges of selected item(s) to the nearest neighboring items on the same track.
--   # Loop Source is forced ON. If missing, a Loop Section is created to the item's *current* bounds BEFORE resizing (SWS).
--   # PRESERVES SYNC: when the LEFT edge moves, adjusts take start offset modulo the pre-resize loop-section length (rate-aware).
--   # Removes fades. Works only within the same track.

local reaper = reaper
local EPS = 1e-12

-- Actions we *do* use
local CMD_REMOVE_FADEIN  = 41191 -- Item: Remove fade in
local CMD_REMOVE_FADEOUT = 41193 -- Item: Remove fade out

-- SWS action that creates/enables loop section from time selection for selected item(s)
local SWS_LOOPITEMSECTION = reaper.NamedCommandLookup("_SWS_LOOPITEMSECTION") -- 0 if SWS missing

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

local function save_state()
  local sel = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n - 1 do sel[#sel + 1] = reaper.GetSelectedMediaItem(0, i) end
  local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  return sel, ts, te
end

local function restore_state(sel, ts, te)
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  for _, it in ipairs(sel) do
    if reaper.ValidatePtr(it, "MediaItem*") then reaper.SetMediaItemSelected(it, true) end
  end
  reaper.GetSet_LoopTimeRange(true, false, ts or 0, te or 0, false)
end

-- Detect if active take already uses a loop SECTION
local function take_has_section(take)
  if not take then return false end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return false end
  local ok = reaper.PCM_Source_GetSectionInfo(src)
  return ok and true or false
end

-- If the active take has NO loop section, set one to the item's CURRENT bounds using SWS (before resize)
local function maybe_set_loop_section_pre(item)
  if SWS_LOOPITEMSECTION == 0 then return end -- SWS not installed; skip quietly
  local take = reaper.GetActiveTake(item)
  if not take or take_has_section(take) then return end

  local sel, ts, te = save_state()

  local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local pend = pos + len

  -- Time selection = item bounds; solo-select item; apply SWS loop-section action
  reaper.GetSet_LoopTimeRange(true, false, pos, pend, false)
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  reaper.SetMediaItemSelected(item, true)
  reaper.UpdateArrange()
  reaper.Main_OnCommand(SWS_LOOPITEMSECTION, 0)

  restore_state(sel, ts, te)
end

-- Positive modulo for floats
local function pos_mod(a, b)
  if b <= 0 then return 0 end
  local m = a % b
  if m < 0 then m = m + b end
  return m
end

-- Adjust take start offset so content phase is preserved when LEFT edge moves,
-- wrapping inside the *pre-resize* loop-section length (rate-aware).
local function adjust_start_offset_for_left_move_looping(item, old_start, new_start, pre_len_proj)
  local delta_proj = new_start - old_start
  if math.abs(delta_proj) < EPS then return end

  local take = reaper.GetActiveTake(item)
  if not take then return end

  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  if rate <= 0 then rate = 1.0 end

  local off_src = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0

  -- Section length in *source* seconds, based on pre-resize item length and rate
  local section_len_src = (pre_len_proj or 0) * rate
  if section_len_src > EPS then
    -- Wrap within the section to keep loop phase aligned
    local new_off = pos_mod(off_src + (delta_proj * rate), section_len_src)
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_off)
  else
    -- No meaningful section length (shouldn't happen if we just set it), fall back to linear shift
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", off_src + (delta_proj * rate))
  end
end

-- ---------- main ----------
local function main()
  -- snapshot selection
  local items = {}
  local num = reaper.CountSelectedMediaItems(0)
  for i = 0, num - 1 do items[#items + 1] = reaper.GetSelectedMediaItem(0, i) end

  for _, item in ipairs(items) do
    if item then
      local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local item_end   = item_start + item_len

      -- Loop Source ON + remove fades
      reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
      reaper.Main_OnCommand(CMD_REMOVE_FADEIN,  0)
      reaper.Main_OnCommand(CMD_REMOVE_FADEOUT, 0)

      -- Set loop section to current bounds BEFORE resizing (only if missing)
      maybe_set_loop_section_pre(item)

      -- Compute neighbors
      local prev_end, next_start = get_neighbors(item)
      local new_start = prev_end or item_start
      local new_end   = next_start or item_end

      if new_end > new_start then
        -- If LEFT edge changes, adjust take start offset modulo the pre-resize section length
        if math.abs(new_start - item_start) >= EPS then
          adjust_start_offset_for_left_move_looping(item, item_start, new_start, item_len)
        end

        -- Apply geometry
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

reaper.Undo_EndBlock("Trim to neighbors + Loop Source ON + Enable Loop Section", -1)
