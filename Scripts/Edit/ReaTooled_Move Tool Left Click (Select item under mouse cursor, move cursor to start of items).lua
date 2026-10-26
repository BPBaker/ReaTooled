-- @description ReaTooled - Move Tool Left Click (Select Under Mouse + Cursor to Item/Group Start) [no-flicker + loop-if-linked]
-- @version 5.9
-- @author Brendan Baker
-- @about
--   Replaces selection with the item under the mouse (no 40529), expands to group via 40034 only if
--   the user's 41156 option is ON, then moves the edit cursor to the earliest start of the current selection.
--   If the link script (_RSed328eb507619b18c1154efa1b048d816cfc2d0c) is ON, also sets loop points to the full span
--   of the selected items. UI stays frozen until the end; view is preserved.
--   Razor mode (set CLICK_MAKES_RAZOR = true below): instead of moving the edit cursor and loop
--   points, the click puts a razor area exactly over the selected item(s), and the Link Timeline
--   and Edit Selection toggle decides whether the loop points follow it. Trade-offs: while the
--   razor area is there, dragging in it does nothing, and with "Razor edits in media item lane
--   affect all track envelopes" on, deleting also deletes the automation under it.
-- @changelog
--   v5.9 Moves the edit cursor to the item/group start again (and sets the loop points when
--        linked): this had been switched off. Keeping a plain item selection means the item can
--        still be dragged (razor-area drag has no action) and deleting it leaves the track's
--        automation alone. Optional razor mode: set CLICK_MAKES_RAZOR = true at the top of
--        the script.

------------------------------------------------------------
-- SETTING
-- false = the click selects the item and moves the edit cursor to its start (default)
-- true  = the click puts a razor area over the item instead (see @about for the trade-offs)
local CLICK_MAKES_RAZOR = false
------------------------------------------------------------

local reaper = reaper
local CMD_GROUP_SELECT_OPTION = 41156      -- Options: Selecting one grouped item selects group
local CMD_GROUP_EXPAND        = 40034      -- Item grouping: Select all items in group
local LINK_CMD_GUID           = "_RSed328eb507619b18c1154efa1b048d816cfc2d0c"

local razor_mode = CLICK_MAKES_RAZOR

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

-- Razor mode: one razor area exactly over each selected item (track lanes only),
-- all other razor areas cleared
local function razor_over_selection()
  local per_track = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tr = reaper.GetMediaItem_Track(it)
    local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    per_track[tr] = per_track[tr] or {}
    table.insert(per_track[tr], { s, e })
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local spans = per_track[tr]
    local str = ""
    if spans then
      table.sort(spans, function(a, b) return a[1] < b[1] end)
      local parts = {}
      for _, sp in ipairs(spans) do parts[#parts + 1] = string.format('%.14f %.14f ""', sp[1], sp[2]) end
      str = table.concat(parts, " ")
    end
    local _, cur = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if cur ~= str then reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", str, true) end
  end
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

if it and razor_mode then
  -- razor area over the selection; the Link toggle decides what the loop points do
  razor_over_selection()
else
  -- cursor + loop (UI still frozen)
  local s,e = selection_span()
  if s then
    reaper.SetEditCurPos(s,false,false)
    if link_toggle_is_on() and e and e > s then
      reaper.GetSet_LoopTimeRange(true,true, s, e, false)
    end
  end
end

-- restore view & unfreeze
reaper.GetSet_ArrangeView2(0,true,0,0, vstart,vend)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock(razor_mode and "Select under mouse + razor area over item/group"
  or "Select under mouse + cursor to item/group start (loop if linked)", 0)
