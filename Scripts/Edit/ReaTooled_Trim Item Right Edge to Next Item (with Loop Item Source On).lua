-- @description ReaTooled_Trim Item Right Edge to Next Item (Loop Source ON + SWS Loop Section BEFORE resize, only if missing)
-- @version 1.3
-- @date 2025.09.08
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Trims the right edge of selected item(s) to the next item on the same track.
--   # Enables Loop Source and (via SWS) sets/enables a Loop Section to each item's *current* bounds BEFORE resizing,
--   # but ONLY if the item does not already have a loop section.
--   # Removes fade-out. Works only within the same track.

local reaper = reaper

-- Actions
local CMD_REMOVE_FADEOUT      = 41193 -- Item: Remove fade out
local SWS_LOOPITEMSECTION     = reaper.NamedCommandLookup("_SWS_LOOPITEMSECTION") -- 0 if SWS missing

-- ---------- helpers ----------
local function get_next_start(item)
  local track      = reaper.GetMediaItem_Track(item)
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_end   = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_count = reaper.CountTrackMediaItems(track)
  local next_start = nil

  for i = 0, item_count - 1 do
    local other = reaper.GetTrackMediaItem(track, i)
    if other ~= item then
      local other_start = reaper.GetMediaItemInfo_Value(other, "D_POSITION")
      if other_start >= item_end then
        if not next_start or other_start < next_start then
          next_start = other_start
        end
      end
    end
  end

  return next_start
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
      local item_end   = item_start + item_len

      -- Enable Loop Source and remove fade-out
      reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
      reaper.Main_OnCommand(CMD_REMOVE_FADEOUT, 0)

      -- IMPORTANT: if the item lacks a loop section, create one to current bounds BEFORE trimming (SWS)
      maybe_set_loop_section_pre(item)

      -- Trim right edge to next item start (same track)
      local next_start = get_next_start(item)
      if next_start and next_start > item_end then
        local new_len = next_start - item_start
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
      end
    end
  end

  reaper.UpdateArrange()
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Trim Item Right Edge to Next Item (Loop Source ON + Loop Section ON)", -1)
