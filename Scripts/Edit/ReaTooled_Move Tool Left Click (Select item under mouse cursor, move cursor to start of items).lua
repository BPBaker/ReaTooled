-- @description ReaTooled - Move Tool Left Click (Select Under Mouse + Cursor to Item/Group Start) [no-flicker + loop-if-linked]
-- @version 5.8
-- @author Brendan Baker
-- @about
--   Replaces selection with the item under the mouse (no 40529), expands to group via 40034 only if
--   the user’s 41156 option is ON, then moves the edit cursor to the earliest start of the current selection.
--   If the link script (_RSed328eb507619b18c1154efa1b048d816cfc2d0c) is ON, also sets loop points to the full span
--   of the selected items. UI stays frozen until the end; view is preserved.

local reaper = reaper
local CMD_GROUP_SELECT_OPTION = 41156      -- Options: Selecting one grouped item selects group
local CMD_GROUP_EXPAND        = 40034      -- Item grouping: Select all items in group
local LINK_CMD_GUID           = "_RSed328eb507619b18c1154efa1b048d816cfc2d0c"

local function item_under_mouse(allow_locked)
  local x,y = reaper.GetMousePosition()
  return reaper.GetItemFromPoint(x,y, allow_locked and true or false)
end

local function group_pref_on()
  return reaper.GetToggleCommandState(CMD_GROUP_SELECT_OPTION) == 1
end

local function link_toggle_is_on()
  local cmd = reaper.NamedCommandLookup(LINK_CMD_GUID)
  if cmd == 0 then return false end
  local st = reaper.GetToggleCommandStateEx(0, cmd)
  if st == 1 then return true end
  local st2 = reaper.GetToggleCommandState(cmd)
  return (st2 or 0) > 0
end

local function selection_span()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return nil, nil end
  local min_s, max_e = math.huge, -math.huge
  for i=0,n-1 do
    local it = reaper.GetSelectedMediaItem(0,i)
    if it then
      local s = reaper.GetMediaItemInfo_Value(it,"D_POSITION")
      local e = s + reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
      if s < min_s then min_s = s end
      if e > max_e then max_e = e end
    end
  end
  if min_s == math.huge or max_e == -math.huge then return nil,nil end
  return min_s, max_e
end

-- MAIN
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- snapshot view
local vstart,vend = reaper.GetSet_ArrangeView2(0,false,0,0)

-- selection step (no native click)
local it = item_under_mouse(true)  -- set false to ignore locked items
if it then
  reaper.SelectAllMediaItems(0,false)
  reaper.SetMediaItemSelected(it,true)
  if group_pref_on() then
    reaper.Main_OnCommand(CMD_GROUP_EXPAND,0)
  end
end

-- cursor + loop (UI still frozen)
--local s,e = selection_span()
--if s then
--  reaper.SetEditCurPos(s,false,false)
--  if link_toggle_is_on() and e and e > s then
--    reaper.GetSet_LoopTimeRange(true,true, s, e, false)
--  end
--end

-- restore view & unfreeze
reaper.GetSet_ArrangeView2(0,true,0,0, vstart,vend)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Select under mouse + cursor to item/group start (loop if linked)",0)
