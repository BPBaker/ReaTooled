-- @description ReaTooled - Bottom-half Shift-Click ADD (preserve selection) + Cursor/Loop-if-Linked [single script]
-- @version 6.3
-- @author Brendan Baker
-- @about
--   Single-script solution for Media item bottom-half Shift+Click (no pass-through available).
--   Restores the prior selection from its own cache, adds the item under mouse, optionally expands to full groups
--   when option 41156 is ON, moves the cursor to earliest selected start, and if the link script
--   (_RSed328eb507619b18c1154efa1b048d816cfc2d0c) is ON, sets loop points to [min, max] of selection.
--   UI stays frozen; view is preserved. No SWS required.

local reaper = reaper

-- User/Action constants
local CMD_GROUP_SELECT_OPTION = 41156      -- Options: Selecting one grouped item selects group
local CMD_GROUP_EXPAND        = 40034      -- Item grouping: Select all items in group
local LINK_CMD_GUID           = "_RSed328eb507619b18c1154efa1b048d816cfc2d0c"

-- Cache namespace
local NS, KEY = "ReaTooled_AddSelfCache", "sel_item_guids"

-- === Helpers (native, no SWS) ===

local function get_item_guid_str(it)
  local ok, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
  return ok and guid or nil
end

local function find_item_by_guid_str(gstr)
  -- Scan project items to find matching GUID string (native only)
  local n_tracks = reaper.CountTracks(0)
  for ti = 0, n_tracks - 1 do
    local tr = reaper.GetTrack(0, ti)
    local n_it = reaper.CountTrackMediaItems(tr)
    for ii = 0, n_it - 1 do
      local it = reaper.GetTrackMediaItem(tr, ii)
      local ok, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
      if ok and guid == gstr then return it end
    end
  end
  -- Also check items not on normal tracks (e.g. if needed): project-wide enumerate
  local n_all = reaper.CountMediaItems(0)
  for i = 0, n_all - 1 do
    local it = reaper.GetMediaItem(0, i)
    local ok, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if ok and guid == gstr then return it end
  end
  return nil
end

local function serialize_selection_to_cache()
  local n = reaper.CountSelectedMediaItems(0)
  local parts = {}
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local g = get_item_guid_str(it)
      if g then parts[#parts + 1] = g end
    end
  end
  reaper.SetExtState(NS, KEY, table.concat(parts, ";"), false)
end

local function restore_selection_from_cache()
  local list = reaper.GetExtState(NS, KEY)
  if list == "" then return end
  for g in list:gmatch("[^;]+") do
    local it = find_item_by_guid_str(g)
    if it then reaper.SetMediaItemSelected(it, true) end
  end
end

local function item_under_mouse(allow_locked)
  local x, y = reaper.GetMousePosition()
  return reaper.GetItemFromPoint(x, y, allow_locked and true or false)
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
  local smin, smax = math.huge, -math.huge
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if s < smin then smin = s end
      if e > smax then smax = e end
    end
  end
  if smin == math.huge or smax == -math.huge then return nil, nil end
  return smin, smax
end

-- === MAIN ===

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Snapshot view
local vstart, vend = reaper.GetSet_ArrangeView2(0, false, 0, 0)

-- Start from our cached selection (because bottom-half cleared the real one on mousedown)
reaper.SelectAllMediaItems(0, false)
restore_selection_from_cache()

-- Add clicked item
local it = item_under_mouse(true)  -- set to 'false' if you want to ignore locked items
if it then
  reaper.SetMediaItemSelected(it, true)
end

-- Expand to full groups if the option is ON
if group_pref_on() then
  reaper.Main_OnCommand(CMD_GROUP_EXPAND, 0)
end

-- Cursor to earliest start; loop points if link toggle is ON
local s, e = selection_span()
if s then
  reaper.SetEditCurPos(s, false, false)
  if link_toggle_is_on() and e and e > s then
    reaper.GetSet_LoopTimeRange(true, true, s, e, false)
  end
end

-- Update our cache to reflect the new final selection (so next click can restore it)
serialize_selection_to_cache()

-- Restore view & unfreeze
reaper.GetSet_ArrangeView2(0, true, 0, 0, vstart, vend)
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Bottom-half Shift+Click ADD (preserve) + cursor/loop-if-linked [single]", 0)
