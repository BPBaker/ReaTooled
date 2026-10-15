-- @description ReaTooled_Trim Item Left Edge to Previous Item (Loop Source ON + SWS Loop Section BEFORE resize, only if missing, preserve sync)
-- @version 1.4
-- @date 2025.09.08
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Trims the left edge of selected item(s) to the previous item on the same track.
--   # Loop Source is forced ON. If missing, a Loop Section is created to the item's *current* bounds BEFORE resizing (SWS).
--   # PRESERVES SYNC: when the LEFT edge moves, adjusts take start offset modulo the pre-resize loop-section length (rate-aware).
--   # Removes fade-in. Works only within the same track.

local reaper = reaper
local EPS = 1e-12

-- Actions
local CMD_REMOVE_FADEIN      = 41191 -- Item: Remove fade in
local SWS_LOOPITEMSECTION    = reaper.NamedCommandLookup("_SWS_LOOPITEMSECTION") -- 0 if SWS missing

-- ---------- helpers ----------
local function get_previous_end(item)
  local track = reaper.GetMediaItem_Track(item)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_count = reaper.CountTrackMediaItems(track)
  local prev_end = nil
  for i = 0, item_count - 1 do
    local other = reaper.GetTrackMediaItem(track, i)
    if other ~= item then
      local other_start = reaper.GetMediaItemInfo_Value(other, "D_POSITION")
      local other_end   = other_start + reaper.GetMediaItemInfo_Value(other, "D_LENGTH")
      if other_end <= item_start then
        if not prev_end or other_end > prev_end then prev_end = other_end end
      end
    end
  end
  return prev_end
end

-- Detect if active take already uses a loop SECTION
local function take_has_section(take)
  if not take then return false end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return false end
  local ok = reaper.PCM_Source_GetSectionInfo(src)
  return ok and true or false
end

local function save_state()
  local sel = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n - 1 do sel[#sel+1] = reaper.GetSelectedMediaItem(0, i) end
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

-- If the active take has NO loop section, set one to the item's CURRENT bounds using SWS (before resize)
local function maybe_set_loop_section_pre(item)
  if SWS_LOOPITEMSECTION == 0 then return end -- SWS not installed; skip quietly
  local take = reaper.GetActiveTake(item)
  if not take or take_has_section(take) then return end

  local sel, ts, te = save_state()

  local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local pend = pos + len

  -- Time selection = item bounds; select only this item; apply SWS loop-section action
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
  local section_len_src = (pre_len_proj or 0) * rate

  if section_len_src > EPS then
    local new_off = pos_mod(off_src + (delta_proj * rate), section_len_src)
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_off)
  else
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", off_src + (delta_proj * rate))
  end
end

-- ---------- main ----------
local function main()
  local selected_items = {}
  local num_items = reaper.CountSelectedMediaItems(0)
  for i = 0, num_items - 1 do
    selected_items[#selected_items+1] = reaper.GetSelectedMediaItem(0, i)
  end

  for _, item in ipairs(selected_items) do
    if item then
      local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len   = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

      -- Force Loop Source ON and remove fade-in
      reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
      reaper.Main_OnCommand(CMD_REMOVE_FADEIN, 0)

      -- If missing, create loop section to current bounds BEFORE trimming (SWS)
      maybe_set_loop_section_pre(item)

      -- Trim left edge to previous item end (same track), preserving loop phase
      local prev_end = get_previous_end(item)
      if prev_end and prev_end < item_start - EPS then
        -- adjust offset first (modulo pre-resize section length)
        adjust_start_offset_for_left_move_looping(item, item_start, prev_end, item_len)
        local new_len = (item_start + item_len) - prev_end
        if new_len < 0 then new_len = 0 end
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", prev_end)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH",   new_len)
      end
    end
  end

  reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)

reaper.Undo_EndBlock("Trim Item Left Edge to Previous Item (Loop Source ON + Loop Section ON)", -1)
