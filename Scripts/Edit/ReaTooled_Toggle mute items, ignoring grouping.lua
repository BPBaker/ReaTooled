--@description ReaTooled: Toggle Item Mute (Ignore Groups, Mouse-Track Scoped, Majority-Based)
--@version 1.2
--@changelog
--  v1.2 - Scope all operations to the track under the mouse cursor; simplified targeting logic.
--  v1.1 - Track-aware filtering for selected/mouse tracks.
--  v1.0 - Initial release.
--@author Brendan Baker (ReaTooled)
--@website https://brendanpatrickbaker.com/reatooled/
--@about
--  Toggles item mute (ignoring groups) based on the track under the mouse cursor.
--  Targeting priority (all scoped to the mouse track):
--    1) If Razor Edit exists on the mouse track: WHOLE items on the mouse track touched by Razor.
--    2) Else if Time Selection exists: WHOLE items on the mouse track that intersect the TS.
--    3) Else if any selected items exist on the mouse track: those items.
--    4) Else: the single item under the mouse cursor.
--
--  Majority rule:
--    - If most targeted items are muted, unmute all; if most are unmuted, mute all.
--    - Tie-breaker: mute all (deterministic).
--
--  Notes:
--    - Ignores grouping by writing item mute flag directly (B_MUTE).
--    - Works with locked items; doesn’t require SWS.

--------------------------------------
-- helpers
--------------------------------------

local function add_item(set, item)
  if item and reaper.ValidatePtr2(0, item, "MediaItem*") then set[item] = true end
end

local function items_intersect_time(item, a, b)
  local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local e    = pos + len
  return (e > a and pos < b)
end

local function get_items_in_range(track, a, b)
  local out = {}
  local cnt = reaper.CountTrackMediaItems(track)
  for i = 0, cnt-1 do
    local it = reaper.GetTrackMediaItem(track, i)
    if items_intersect_time(it, a, b) then out[#out+1] = it end
  end
  return out
end

local function get_mouse_track_and_item()
  local x, y = reaper.GetMousePosition()
  local tr, info = reaper.GetTrackFromPoint(x, y)
  local it = reaper.GetItemFromPoint(x, y, true) -- allow locked
  return tr, it
end

local function razor_exists_on_track(tr)
  if not tr then return false end
  local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if not s or s == "" then return false end
  -- only consider item-areas (GUID == '""') as per spec
  for w in s:gmatch("%S+") do end
  return true
end

local function collect_items_from_razor_on_track(tr)
  local items, set = {}, {}
  local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if s == "" then return items end
  local toks = {}
  for w in s:gmatch("%S+") do toks[#toks+1] = w end
  local j = 1
  while j <= #toks do
    local a   = tonumber(toks[j])
    local b   = tonumber(toks[j+1])
    local guid= toks[j+2]
    if guid == '""' then
      local ranged = get_items_in_range(tr, a, b)
      for _, it in ipairs(ranged) do add_item(set, it) end
    end
    j = j + 3
  end
  for it,_ in pairs(set) do items[#items+1] = it end
  return items
end

local function collect_items_from_timeselection_on_track(tr)
  local a, b = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if a == b or not tr then return {} end
  return get_items_in_range(tr, a, b)
end

local function collect_selected_items_on_track(tr)
  local list = {}
  if not tr then return list end
  local selcnt = reaper.CountSelectedMediaItems(0)
  if selcnt == 0 then return list end
  for i = 0, selcnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if reaper.GetMediaItem_Track(it) == tr then list[#list+1] = it end
  end
  return list
end

local function majority_toggle_state(items)
  local muted, unmuted = 0, 0
  for _, it in ipairs(items) do
    local m = reaper.GetMediaItemInfo_Value(it, "B_MUTE") or 0
    if m >= 0.5 then muted = muted + 1 else unmuted = unmuted + 1 end
  end
  if muted > unmuted then return 0 elseif unmuted > muted then return 1 else return 1 end
end

--------------------------------------
-- main
--------------------------------------

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local mouse_tr, mouse_it = get_mouse_track_and_item()

local targets, mode = {}, "none"

-- 1) Razor on mouse track
if mouse_tr and razor_exists_on_track(mouse_tr) then
  local t = collect_items_from_razor_on_track(mouse_tr)
  if #t > 0 then targets = t; mode = "razor(mouse track)" end
end

-- 2) Time selection on mouse track (if nothing from razor)
if #targets == 0 and mouse_tr then
  local t = collect_items_from_timeselection_on_track(mouse_tr)
  if #t > 0 then targets = t; mode = "timesel(mouse track)" end
end

-- 3) Selected items on mouse track (if nothing yet)
if #targets == 0 and mouse_tr then
  local t = collect_selected_items_on_track(mouse_tr)
  if #t > 0 then targets = t; mode = "selected(mouse track)" end
end

-- 4) Single item under mouse
if #targets == 0 and mouse_it then
  targets = {mouse_it}; mode = "mouse item"
end

-- Fallback: if no mouse track and nothing else, try generic selected items (last resort)
if #targets == 0 then
  local sel = {}
  for i = 0, reaper.CountSelectedMediaItems(0)-1 do sel[#sel+1] = reaper.GetSelectedMediaItem(0, i) end
  if #sel > 0 then targets = sel; mode = "selected(fallback)" end
end

if #targets == 0 then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("ReaTooled: Toggle Item Mute (no targets)", -1)
  return
end

local target_state = majority_toggle_state(targets)
for _, it in ipairs(targets) do
  reaper.SetMediaItemInfo_Value(it, "B_MUTE", target_state) -- ignore groups by writing per item
end

reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("ReaTooled: Toggle Item Mute (Mouse-Track Scoped, "..mode..")", -1)
