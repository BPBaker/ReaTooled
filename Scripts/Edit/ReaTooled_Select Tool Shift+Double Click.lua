-- @description ReaTooled - Select Tool Double Click (Add to Selection) [SHIFT+DOUBLE-CLICK]
-- @version 1.2
-- @date 2025.09.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Shift+Double-Click selection tool that PRESERVES selection.
--   # Extends selection to the item under the mouse (group-aware), and appends razor areas on the items' tracks.
--   # Does NOT clear existing razors; simply adds segments for the newly added item(s).
--   # Moves edit cursor to the clicked item start but restores arrange view (no jumping).
-- @changelog
--   v1.2 - New "add-to-selection" behavior; preserve prior selection; append (don’t clear) razors; keep view steady.
--   v1.1 - Added group-aware logic for razor and selection
--   v1.0 - Initial implementation

local reaper = reaper

-- Helpers ------------------------------------------------------------

local function collect_selected_items()
  local set = {}
  local list = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    set[it] = true
    list[#list+1] = it
  end
  return set, list
end

local function restore_selection(set)
  -- Clear all, then reselect those we had
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  for it,_ in pairs(set) do
    if reaper.ValidatePtr(it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end
end

local function append_razor_segment(track, start_pos, end_pos, tag)
  if not track then return end
  local _, cur = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
  local seg = string.format("%f %f \"%s\" ", start_pos, end_pos, tag or "reatooled")
  -- Ensure a trailing space between existing and new segments
  if cur ~= nil and #cur > 0 and cur:sub(-1) ~= " " then
    cur = cur .. " "
  end
  reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', (cur or "") .. seg, true)
end

local function items_in_group(groupID)
  local out = {}
  local cnt = reaper.CountMediaItems(0)
  for i = 0, cnt - 1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "I_GROUPID") == groupID then
      out[#out+1] = it
    end
  end
  return out
end

-- Main ---------------------------------------------------------------

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Save current view before we do anything that might nudge it
local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)

-- Snapshot current selection
local sel_set = select(1, collect_selected_items())

-- Use built-in action to grab item under mouse (may disturb selection, we’ll restore)
reaper.Main_OnCommand(40528, 0) -- Item: Select item under mouse cursor
local mouse_item = reaper.GetSelectedMediaItem(0, 0)

-- Restore previous selection
restore_selection(sel_set)

if mouse_item then
  -- Build the list of items to ADD: group-aware
  local groupID = reaper.GetMediaItemInfo_Value(mouse_item, "I_GROUPID")
  local to_add = {}
  if groupID and groupID > 0 then
    to_add = items_in_group(groupID)
  else
    to_add = { mouse_item }
  end

  -- Add items to selection and append matching razor segments
  local first_item_start = nil

  for _, it in ipairs(to_add) do
    if reaper.ValidatePtr(it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)

      local it_start = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local it_len   = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local it_end   = it_start + it_len
      local tr       = reaper.GetMediaItem_Track(it)

      append_razor_segment(tr, it_start, it_end, "reatooled")

      if not first_item_start or it_start < first_item_start then
        first_item_start = it_start
      end
    end
  end

  -- Move edit cursor to the clicked item's start (use the actual clicked item’s start)
  local clicked_start = reaper.GetMediaItemInfo_Value(mouse_item, "D_POSITION")
  reaper.SetEditCurPos(clicked_start or first_item_start or reaper.GetCursorPosition(), false, false)
end

-- Restore arrange view (no jump)
reaper.GetSet_ArrangeView2(0, true, 0, 0, view_start, view_end)

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("ReaTooled - Add to Selection on Shift+Double-Click (group-aware, append razors)", -1)
