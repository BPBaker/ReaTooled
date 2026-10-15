--[[
@description ReaTooled - TAB honoring fades/crossfades (SelectionSet restore + only-if-offscreen centering)
@version 1.17
@author Brendan Baker (enhanced by The Reaper Script Wizard)
@about
  Pro Tools-like TAB using ReaTooled "Toggle Tab to Transient".
  - Transient mode (toggle ON):
      * Uses REAPER’s native transient navigation.
      * Temporarily saves/restores item selection using Selection Set #01.
      * Respects user track/item selection context (tracks > all items).
  - Item-edge mode (toggle OFF):
      * Moves between fades, crossfades, item edges on relevant tracks.
      * No selection changes.
  - View centers on edit cursor only if it moves off-screen (margin configurable).
  - No defer; Undo suppressed (-1).

  v1.17:
    * Added VIEW_MARGIN user setting (default 5%).
    * Optional follow behavior during playback (FOLLOW_DURING_PLAY).
    * Slightly smoother viewport updates.
--]]

--------------------------------------
-- USER SETTINGS
--------------------------------------
local DIRECTION          = "prev"  -- "next" or "prev"
local VIEW_MARGIN        = 0.05    -- fraction of view width (0.0..0.5 recommended)
local FOLLOW_DURING_PLAY = false   -- if false, no auto-centering while playing

--------------------------------------
-- COMMAND IDS
--------------------------------------
local CMD_SAVE_SELSET1        = 41229 -- Selection set: Save set #01
local CMD_LOAD_SELSET1        = 41239 -- Selection set: Load set #01
local CMD_NEXT_TRANSIENT      = 40375
local CMD_PREV_TRANSIENT      = 40376
local CMD_EDGE_RIGHT          = 40319
local CMD_EDGE_LEFT           = 40318
local REATOOG_TTT_CMDID_STR   = "_RSf475a3ed46e25a1ef9d2a8b4ad6aab87c94102a1"

--------------------------------------
-- HELPERS
--------------------------------------
local function any_item_selected()
  return reaper.CountSelectedMediaItems(0) > 0
end

local function get_selected_tracks()
  local t = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    t[#t+1] = reaper.GetSelectedTrack(0, i)
  end
  return t
end

local function get_tracks_from_selected_items()
  local seen, t = {}, {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tr = it and reaper.GetMediaItem_Track(it)
    if tr and not seen[tr] then seen[tr] = true; t[#t+1] = tr end
  end
  return t
end

local function get_all_tracks()
  local t = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    t[#t+1] = reaper.GetTrack(0, i)
  end
  return t
end

local function get_fade_in_len(item)
  local a = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO") or 0
  local m = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN") or 0
  return (a > 0 and a) or m
end

local function get_fade_out_len(item)
  local a = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO") or 0
  local m = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") or 0
  return (a > 0 and a) or m
end

--------------------------------------
-- Collect fade/crossfade boundaries
--------------------------------------
local function collect_boundaries_for_track(track, add_pos)
  local n = reaper.CountTrackMediaItems(track)
  if n == 0 then return end

  local items = {}
  for i = 0, n - 1 do
    local it   = reaper.GetTrackMediaItem(track, i)
    local pos  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local endp = pos + len
    local fi   = get_fade_in_len(it)
    local fo   = get_fade_out_len(it)
    items[#items+1] = {
      pos = pos, endpos = endp,
      fi_end = pos + fi, fo_start = endp - fo,
      has_fi = fi > 0, has_fo = fo > 0
    }
  end

  table.sort(items, function(a, b) return a.pos < b.pos end)
  for _, it in ipairs(items) do
    add_pos(it.pos)
    if it.has_fi then add_pos(it.fi_end) end
    if it.has_fo then add_pos(it.fo_start) end
    add_pos(it.endpos)
  end

  for i = 1, #items - 1 do
    local A, B = items[i], items[i + 1]
    local overlap_start = math.max(A.pos, B.pos)
    local overlap_end   = math.min(A.endpos, B.endpos)
    if overlap_end > overlap_start then
      add_pos(overlap_start)
      add_pos(overlap_end)
    end
  end
end

local function collect_boundaries_for_tracks(tracks)
  local positions, seen = {}, {}
  local function add_pos(p)
    local key = string.format("%.12f", p)
    if not seen[key] then seen[key] = true; positions[#positions+1] = p end
  end
  for _, tr in ipairs(tracks) do collect_boundaries_for_track(tr, add_pos) end
  table.sort(positions)
  return positions
end

local function find_next_prev(sorted_positions, cursor, dir)
  local eps = 1e-9
  if dir == "next" then
    for _, p in ipairs(sorted_positions) do
      if p > cursor + eps then return p end
    end
  else
    for i = #sorted_positions, 1, -1 do
      local p = sorted_positions[i]
      if p < cursor - eps then return p end
    end
  end
end

--------------------------------------
-- Arrange view helpers
--------------------------------------
local function get_arr_view()
  -- read full arrange view (requires both screen_x args)
  local s, e = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
  return s, e
end

local function set_arr_view(start_t, end_t)
  -- smoother visual update hint
  reaper.CSurf_OnScroll(0, 0)
  reaper.GetSet_ArrangeView2(0, true, 0, 0, start_t, end_t)
  reaper.UpdateArrange()
end

-- View centering only if off-screen
local function center_if_offscreen(pos)
  -- optional: don’t fight playback scroll unless allowed
  if not FOLLOW_DURING_PLAY then
    local playing = (reaper.GetPlayState() & 1) == 1
    if playing then return end
  end

  local view_start, view_end = get_arr_view()
  if not view_start or not view_end then
    reaper.Main_OnCommand(40913, 0) -- fallback: center edit cursor
    return
  end

  local width = view_end - view_start
  if width <= 0 then
    reaper.Main_OnCommand(40913, 0)
    return
  end

  -- only center if truly off-screen with adjustable margin
  local margin = math.max(0, VIEW_MARGIN or 0) * width
  if pos >= (view_start + margin) and pos <= (view_end - margin) then
    return -- already visible
  end

  -- center and clamp to project range
  local new_start = pos - (width * 0.5)
  local new_end   = pos + (width * 0.5)

  local proj_len = reaper.GetProjectLength(0) or 0
  if new_start < 0 then
    new_end = new_end - new_start
    new_start = 0
  end
  if proj_len > 0 and new_end > proj_len then
    local overshoot = new_end - proj_len
    new_start = math.max(0, new_start - overshoot)
    new_end   = proj_len
  end

  set_arr_view(new_start, new_end)
end

--------------------------------------
-- MAIN
--------------------------------------
local function main()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local dir = (DIRECTION or "next"):lower()
  local ttt_cmd = reaper.NamedCommandLookup(REATOOG_TTT_CMDID_STR)
  local transient_on = (ttt_cmd ~= 0) and (reaper.GetToggleCommandStateEx(0, ttt_cmd) == 1)

  local moved_to = nil

  if transient_on then
    -- === TRANSIENT MODE (with SelectionSet Save/Restore) ===
    reaper.Main_OnCommand(CMD_SAVE_SELSET1, 0)

    if not any_item_selected() then
      local sel_tracks = get_selected_tracks()
      if #sel_tracks == 0 then
        reaper.SelectAllMediaItems(0, true) -- fallback: all items
      else
        reaper.SelectAllMediaItems(0, false)
        for i = 0, reaper.CountMediaItems(0)-1 do
          local it = reaper.GetMediaItem(0, i)
          local tr = it and reaper.GetMediaItem_Track(it)
          for _, t in ipairs(sel_tracks) do
            if tr == t then reaper.SetMediaItemSelected(it, true) break end
          end
        end
      end
    end

    if dir == "prev" then reaper.Main_OnCommand(CMD_PREV_TRANSIENT, 0)
    else reaper.Main_OnCommand(CMD_NEXT_TRANSIENT, 0) end

    moved_to = reaper.GetCursorPosition()
    reaper.Main_OnCommand(CMD_LOAD_SELSET1, 0)

  else
    -- === ITEM-EDGE MODE ===
    local cursor = reaper.GetCursorPosition()
    local tracks = {}
    local from_items = get_tracks_from_selected_items()
    if #from_items > 0 then
      tracks = from_items
    else
      local sel_tracks = get_selected_tracks()
      if #sel_tracks > 0 then tracks = sel_tracks else tracks = get_all_tracks() end
    end

    local positions = collect_boundaries_for_tracks(tracks)
    local target_pos = find_next_prev(positions, cursor, dir)

    if target_pos then
      reaper.SetEditCurPos(target_pos, false, false)
      moved_to = target_pos
    else
      if dir == "prev" then reaper.Main_OnCommand(CMD_EDGE_LEFT, 0) else reaper.Main_OnCommand(CMD_EDGE_RIGHT, 0) end
      moved_to = reaper.GetCursorPosition()
    end
  end

  reaper.PreventUIRefresh(-1)

  if moved_to then
    center_if_offscreen(moved_to)
  end

  reaper.Undo_EndBlock("ReaTooled TAB (no undo)", -1)
end

main()
