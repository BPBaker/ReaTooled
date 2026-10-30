-- @description ReaTooled - Shuffle move (background, started in Shuffle mode)
-- @version 2.2
-- @date 2026.10.29
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Runs while Shuffle mode is on and the Move Tool (or the Multi tool) is selected;
--   stops by itself otherwise. Like Pro Tools' Shuffle: dragging an item reorders it
--   among the items on its track.
--     - The item leaves its place, and what comes after it closes up by its length.
--     - It goes back in at the item edge nearest where you drop it, pushing what
--       comes after that edge along by its length.
--     - Crossfades are kept: the edit point is the crossfade's centre, items keep the
--       audio that reaches past it, and crossfades form again where that audio meets
--       a new neighbor. Butted items stay butted (no crossfade is ever added).
--     - Gaps between items are kept, like empty items: they move along, and the item
--       can be dropped on either side of a gap. In a gap with room, it can also go
--       one item-length right or left of where it was (nothing else moves).
--     - The track shows the result while you drag, with what moves selected (it stays
--       selected after the drop); letting go makes one undo step.
--   Dragging a selected item moves the selected items on its track (and lane) as one
--   block, keeping their spacing; unselected items between them come along.
--   Tracks that follow the clicked track's group (media editing), other items in the
--   clicked item's group, and (if it's selected) selected items on other tracks
--   shuffle together: each of those tracks takes out the same time range and puts it
--   back at the same place, so they stay in sync. Drop points are item edges on any of
--   those tracks that aren't inside an item on another (empty space is fine; nothing
--   is ever split); if an item there crosses the start or end of what's moving, the
--   shuffle doesn't start.
--   With ripple editing all tracks, every track moves the same stretch of time (a
--   razor move of the whole project): items crossing it, or the drop point, are split
--   there with short fades, and markers and regions go along. Locked items never
--   move or split.
--   With "Move envelope points with media items" on, the tracks' automation follows:
--   the moved stretch's points go with it (to the envelope of the same name on
--   another track), the rest closes up or moves along like the items, and points are
--   added at the edit boundaries so the values stay exact around each edit. It moves
--   live while you drag.
--   Automation items aren't moved.
--   Move Tool: any plain drag on an item. Multi tool: plain drags on an item's lower
--   half (where it moves items); edges, fades and handles stay REAPER's. Drags with
--   modifier keys stay REAPER's own (copy and so on). A plain click still selects
--   the item. Dragged to another track, the item leaves its track (which closes
--   up) and goes in at an item edge on the new track (on an empty track, at its
--   time). Tracks with locked items aren't shuffled.
-- @changelog
--   v2.2 What moves is selected while dragging (on every track it moves on, with the
--        split pieces in all-tracks mode), so its bounds show; it stays selected
--        after the drop. Back home or cancelled, the selection is as it was.
--   v2.1 With ripple editing all tracks: every track moves the same stretch of time,
--        like a razor move of the whole project. Items on other tracks crossing its
--        start or end, or the drop point, are split there with short fades (REAPER's
--        default fade length); markers and regions go along (MOVE_MARKERS); all
--        tracks' automation follows (not the tempo map). Drop points come from the
--        clicked track only. Locked items never move or split: drop points that would
--        need that aren't offered.
--   v2.0 Crossfades are preserved: a crossfade's edit point is its centre, so what
--        moves runs from edit point to edit point and every track shifts by the same
--        amount. Neighbors that close up meet in a crossfade made of their own
--        extensions; an item with extensions keeps them where it lands (crossfades
--        form there, fades set to the overlap). Butted items stay butted. Grouped
--        crossfaded edits (drums) can now be shuffled.
--   v1.9 Automation follows live while dragging (not only on release)
--   v1.8 Restarts whenever a tool is applied, so an updated script always takes over
--   v1.7 Track automation follows (with "Move envelope points with media items" on):
--        the moved stretch's points go with it, the rest closes up or moves along,
--        and points are added at the edit boundaries so values stay exact
--   v1.6 Tracks shuffling together: an item edge on any of them is a drop point, as long
--        as it isn't inside an item on another (empty space is fine), so the moving
--        items can go where some tracks have edges and others have empty space
--   v1.5 Grouped tracks, item groups and selections across tracks shuffle together:
--        each of those tracks takes out the same time range and puts it back at the
--        same place. Only drop points that aren't inside an item on any of them.
--   v1.4 Dragging a selected item moves the selected items on its track as one block
--        (keeping their spacing; items between them come along)
--   v1.3 Items can be moved to another track: the track they leave closes up, and
--        they go in at an item edge on the new one (an empty track: at their time).
--        Tracks with locked items can't take them.
--   v1.2 An item sitting in a gap can also be dropped one item-length to the right or
--        left of where it was (its start where its end was, or its end where its start
--        was) when the gap has room; nothing else moves. One undo step with Link
--        Timeline on (the Move Tool's click no longer runs after a Shuffle drag).
--   v1.1 The item's starting place is always one it can be dropped back at (it
--        couldn't when it was the first item on its track with a gap after it)
--   v1.0 Initial version: one item, on its own track

local NS          = "ReaTooled"
local TOOL_KEY    = "ShuffleMoveTool"    -- "grabber" / "smart" while wanted (set by the Tools library)
local HEARTBEAT   = "ShuffleMoveAlive"
local LINK_CMD_GUID = "_RSed328eb507619b18c1154efa1b048d816cfc2d0c"   -- Link Timeline and Edit Selection

local DEADBAND_PX     = 4      -- the mouse must move this far before the item is picked up
local DRAG_STAMP      = "ShuffleDragTime"   -- read by the Move Tool click: skip the click after a drag
local AUTOSCROLL_RATE = 0.5    -- pixels scrolled per frame, per pixel past the arrange's side
local MOVE_MARKERS    = true   -- ripple editing all tracks: markers and regions move along
local RIPPLE_ALL      = 40311  -- Options: Set ripple editing all tracks

local _, script_path = reaper.get_action_context()
local dir = script_path:match("^(.*[/\\])") or ""

if not (reaper.JS_Mouse_GetState and reaper.JS_Window_FindChildByID) then
  reaper.ShowMessageBox("Shuffle mode's item moves need js_ReaScriptAPI (install it with ReaPack).", "ReaTooled", 0)
  return
end
local okM, mouse = pcall(dofile, dir .. "ReaTooled_Mouse lib.lua")
local okT, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
if not (okM and type(mouse) == "table" and okT and type(tools) == "table") then
  reaper.ShowMessageBox("ReaTooled_Mouse lib.lua or ReaTooled_Tools lib.lua is missing from:\n" .. dir ..
    "\n\nUpdate ReaTooled in ReaPack (Extensions > ReaPack > Synchronize packages).", "ReaTooled", 0)
  return
end

local function wanted_tool() return reaper.GetExtState(NS, TOOL_KEY) end

local G = nil   -- the drag in progress

------------------------------------------------------------
-- A track as a row of segments: items and the gaps between them
--
-- A crossfade's edit point is its centre: the two items' segments meet there, and
-- each item reaches past it by half the overlap (its extension, like Pro Tools'
-- handles under a crossfade). Moving a stretch takes out the segments between two
-- edit points, so every track shifts by exactly the same amount, and items keep
-- their extensions wherever they go: crossfades are preserved (and form again where
-- an item with an extension meets a new neighbor). Butted items stay butted.
------------------------------------------------------------
local TOL = 1e-6

-- Items of one lane of a track (all items on a track without fixed lanes), sorted.
-- nil if one of them is locked.
local function lane_items(tr, lane)
  local fixed = (reaper.GetMediaTrackInfo_Value(tr, "I_FIXEDLANES") or 0) > 0
  local list = {}
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if (not fixed) or reaper.GetMediaItemInfo_Value(it, "I_FIXEDLANE") == lane then
      if (reaper.GetMediaItemInfo_Value(it, "C_LOCK") or 0) ~= 0 then return nil end
      list[#list + 1] = { it = it, pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
                                   len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH") }
    end
  end
  table.sort(list, function(a, b) return a.pos < b.pos end)
  return list
end

-- Segments from time 0: { item=, len=, off=, pos0= } (the item sits at segment start
-- + off; off < 0 when it reaches into the previous segment) or { gap=true, len= }.
-- skip: items left out (the ones being dragged, on another track).
local function build_row(list, skip)
  local items = {}
  for _, r in ipairs(list) do if not (skip and skip[r.it]) then items[#items + 1] = r end end
  local segs, t = {}, 0
  for i, r in ipairs(items) do
    local s, e = r.pos, r.pos + r.len
    local left, right = s, e
    local p = items[i - 1]
    if p and p.pos + p.len > s + TOL then left = (s + math.min(p.pos + p.len, e)) / 2 end
    local n = items[i + 1]
    if n and e > n.pos + TOL then right = (math.max(n.pos, s) + e) / 2 end
    left = math.max(left, t)
    right = math.max(right, left)
    if left > t + TOL then segs[#segs + 1] = { gap = true, len = left - t } end
    segs[#segs + 1] = { item = r.it, len = right - left, off = s - left, pos0 = s }
    t = right
  end
  return segs
end

local function seg_starts(segs)
  local st, t = {}, 0
  for j, s in ipairs(segs) do st[j] = t; t = t + s.len end
  return st, t
end

-- Positions of the items in a row of segments
local function layout(segs)
  local t, pos = 0, {}
  for _, s in ipairs(segs) do
    if s.item then pos[s.item] = t + s.off end
    if s.members then for _, m in ipairs(s.members) do pos[m.item] = t + m.off end end
    t = t + s.len
  end
  return pos
end

-- The items of a row of segments, in order
local function row_order(segs)
  local list = {}
  for _, s in ipairs(segs) do
    if s.item then list[#list + 1] = s.item end
    if s.members then for _, m in ipairs(s.members) do list[#list + 1] = m.item end end
  end
  return list
end

-- Where time T falls in a row: a drop point { k = segments before it, t = T,
-- split = offset into a gap } or nil when it's inside an item's segment
local function cut_at(R, T)
  local st, total = seg_starts(R)
  for j, sl in ipairs(R) do
    if math.abs(T - st[j]) <= TOL then return { k = j - 1, t = st[j] } end
    if T > st[j] and T < st[j] + sl.len then
      if sl.gap then return { k = j - 1, t = T, split = T - st[j] } end
      return nil
    end
  end
  if T >= total - TOL then
    if T > total + TOL then return { k = #R, t = T, tail = T - total } end   -- past the end
    return { k = #R, t = total }
  end
  return nil
end

-- R with the segments in blk inserted at drop point b
local function insert(R, b, blk)
  local F, after = {}, b.k + 1
  for i = 1, b.k do F[#F + 1] = R[i] end
  if b.split then
    local g = R[b.k + 1]
    F[#F + 1] = { gap = true, len = b.split }
    for _, s in ipairs(blk) do F[#F + 1] = s end
    F[#F + 1] = { gap = true, len = g.len - b.split }
    after = b.k + 2
  else
    if b.tail then F[#F + 1] = { gap = true, len = b.tail } end
    for _, s in ipairs(blk) do F[#F + 1] = s end
  end
  for i = after, #R do F[#F + 1] = R[i] end
  return F
end

-- Take the stretch a..b out of a row: the rest (gaps cut at a and b) and the
-- stretch's own segments. nil if a or b falls inside an item's segment.
local function extract(segs, a, b)
  local st = seg_starts(segs)
  local R, blk = {}, {}
  for j, s in ipairs(segs) do
    local s0, s1 = st[j], st[j] + s.len
    if s1 <= a + TOL or s0 >= b - TOL then
      if s.len > TOL or not s.gap then R[#R + 1] = s end
    elseif s0 >= a - TOL and s1 <= b + TOL then
      blk[#blk + 1] = s
    elseif s.gap then
      if s0 < a then R[#R + 1] = { gap = true, len = a - s0 } end
      blk[#blk + 1] = { gap = true, len = math.min(s1, b) - math.max(s0, a) }
      if s1 > b then R[#R + 1] = { gap = true, len = s1 - b } end
    else
      return nil
    end
  end
  return R, blk
end

-- Drop points of a row: every segment boundary, not before a gap at the very start
-- of the track (that would put the moving stretch at the project start)
local function row_bounds(R, keepT)
  local bounds, t = {}, 0
  for k = 0, #R do
    local okk = not (k == 0 and R[1] and R[1].gap)
    if okk or (keepT and math.abs(t - keepT) <= TOL) then bounds[#bounds + 1] = { k = k, t = t } end
    if R[k + 1] then t = t + R[k + 1].len end
  end
  return bounds
end

------------------------------------------------------------
-- Fades: crossfades follow the items
------------------------------------------------------------
local FADE_KEYS = { "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINLEN_AUTO", "D_FADEOUTLEN_AUTO" }

-- (with the length and take offsets: an item can be trimmed at the project start)
local function snap_fades(list)
  for _, r in ipairs(list) do
    if not G.fadeSnap[r.it] then
      local f = { D_LENGTH = r.len }
      for _, k in ipairs(FADE_KEYS) do f[k] = reaper.GetMediaItemInfo_Value(r.it, k) end
      G.fadeSnap[r.it] = f
      local offs = {}
      for t = 0, reaper.CountTakes(r.it) - 1 do
        local tk = reaper.GetTake(r.it, t)
        if tk then offs[tk] = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") end
      end
      G.offsSnap[r.it] = offs
    end
  end
end

local function restore_fades()
  for it, f in pairs(G.fadeSnap) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      for k, v in pairs(f) do
        if math.abs(reaper.GetMediaItemInfo_Value(it, k) - v) > 1e-12 then reaper.SetMediaItemInfo_Value(it, k, v) end
      end
      for tk, v in pairs(G.offsSnap[it] or {}) do
        if reaper.ValidatePtr2(0, tk, "MediaItem_Take*")
           and math.abs(reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") - v) > 1e-12 then
          reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", v)
        end
      end
    end
  end
end

-- Items that are next to each other now but weren't at the click: where they overlap,
-- that's a crossfade (from an item's extension), so both fades are set to the overlap
local function crossfades_for(segs, pos)
  local order = row_order(segs)
  for i = 1, #order - 1 do
    local A, B = order[i], order[i + 1]
    if G.nextOf[A] ~= B then
      local aEnd = pos[A] + reaper.GetMediaItemInfo_Value(A, "D_LENGTH")
      local ov = aEnd - pos[B]
      if ov > TOL then
        reaper.SetMediaItemInfo_Value(A, "D_FADEOUTLEN", ov)
        reaper.SetMediaItemInfo_Value(B, "D_FADEINLEN", ov)
        if reaper.GetMediaItemInfo_Value(A, "D_FADEOUTLEN_AUTO") >= 0 then reaper.SetMediaItemInfo_Value(A, "D_FADEOUTLEN_AUTO", ov) end
        if reaper.GetMediaItemInfo_Value(B, "D_FADEINLEN_AUTO") >= 0 then reaper.SetMediaItemInfo_Value(B, "D_FADEINLEN_AUTO", ov) end
      end
    end
  end
end

local function note_neighbors(list)
  for i = 1, #list - 1 do G.nextOf[list[i].it] = list[i + 1].it end
end

------------------------------------------------------------
-- Ripple editing all tracks: every track moves the same stretch of time, like a
-- razor move of the whole project. Items crossing its start or end, or the drop
-- point, are split there (with short fades); markers and regions go along.
------------------------------------------------------------
local function default_fade()
  local v
  if reaper.get_config_var_string then
    local ok, s = reaper.get_config_var_string("deffadelen")
    if ok then v = tonumber(s) end
  end
  return (v and v > 0) and v or 0.01
end

-- Time T with the stretch a..a+len taken out, as a time on the timeline before the edit
local function orig_time(a, len, T) return (T <= a + TOL) and T or (T + len) end

-- The range a drop at T changes on the other tracks
local function touched(a, len, T)
  local u = orig_time(a, len, T)
  return math.min(a, u), math.max(a + len, u)
end

-- Where something at time p (before the edit) goes: the stretch to T, the rest closes up
-- and opens again at T
local function outside_map(p, T)
  local r = (p >= G.a + G.len - TOL) and (p - G.len) or p
  return (r >= T - TOL) and (r + G.len) or r
end
local function all_map(p, T)
  if p >= G.a - TOL and p < G.a + G.len - TOL then return T + (p - G.a) end
  return outside_map(p, T)
end
local function all_map_end(e, T)   -- a region's end
  if e > G.a + TOL and e <= G.a + G.len + TOL then return T + (e - G.a) end
  return outside_map(e, T)
end

-- Items on every other track (and on the clicked track's other lanes)
local function other_items(srcTr, srcList)
  local mine = {}
  for _, r in ipairs(srcList) do mine[r.it] = true end
  local list = {}
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      if not mine[it] then
        list[#list + 1] = { it = it, pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION"),
                            len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH"),
                            locked = (reaper.GetMediaItemInfo_Value(it, "C_LOCK") or 0) ~= 0 }
      end
    end
  end
  return list
end

local function snap_markers()
  local list = {}
  local _, nm, nr = reaper.CountProjectMarkers(0)
  for i = 0, (nm or 0) + (nr or 0) - 1 do
    local ok, isrgn, pos, rend, name, num, color = reaper.EnumProjectMarkers3(0, i)
    if ok then list[#list + 1] = { isrgn = isrgn, pos = pos, rend = rend, name = name, num = num, color = color } end
  end
  return list
end

local function set_marker(m, pos, rend)
  reaper.SetProjectMarker3(0, m.num, m.isrgn, pos, rend, m.name, m.color)
end

-- Split an item at t (the cut gets short fades); remembered so it can be undone
local function split_at(it, t)
  local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  if not (pos + TOL < t and pos + len - TOL > t) then return nil end
  local rec = { left = it, len = len,
                fout = reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN"),
                foutA = reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO"),
                foutS = reaper.GetMediaItemInfo_Value(it, "C_FADEOUTSHAPE") }
  local right = reaper.SplitMediaItem(it, t)
  if not right then return nil end
  rec.right = right
  G.splits[#G.splits + 1] = rec
  -- exactly at t, whatever REAPER's split preferences add (overlaps on split)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", t - pos)
  local rpos = reaper.GetMediaItemInfo_Value(right, "D_POSITION")
  if math.abs(rpos - t) > 1e-9 then
    for k = 0, reaper.CountTakes(right) - 1 do
      local tk = reaper.GetTake(right, k)
      if tk then
        reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
          + (t - rpos) * reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"))
      end
    end
    reaper.SetMediaItemInfo_Value(right, "D_POSITION", t)
  end
  reaper.SetMediaItemInfo_Value(right, "D_LENGTH", pos + len - t)
  local f = G.cutFade
  local fl, fr = math.min(f, (t - pos) / 2), math.min(f, (pos + len - t) / 2)
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", fl)
  if reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO") >= 0 then reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", fl) end
  reaper.SetMediaItemInfo_Value(right, "D_FADEINLEN", fr)
  if reaper.GetMediaItemInfo_Value(right, "D_FADEINLEN_AUTO") >= 0 then reaper.SetMediaItemInfo_Value(right, "D_FADEINLEN_AUTO", fr) end
  return right
end

-- Every other track back as it was at the click
local function all_restore()
  for _, o in ipairs(G.others) do
    if reaper.ValidatePtr2(0, o.it, "MediaItem*")
       and math.abs(reaper.GetMediaItemInfo_Value(o.it, "D_POSITION") - o.pos) > 1e-9 then
      reaper.SetMediaItemInfo_Value(o.it, "D_POSITION", o.pos)
    end
  end
  for i = #G.splits, 1, -1 do
    local s = G.splits[i]
    if reaper.ValidatePtr2(0, s.right, "MediaItem*") then
      reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(s.right), s.right)
    end
    if reaper.ValidatePtr2(0, s.left, "MediaItem*") then
      reaper.SetMediaItemInfo_Value(s.left, "D_LENGTH", s.len)
      reaper.SetMediaItemInfo_Value(s.left, "D_FADEOUTLEN", s.fout)
      reaper.SetMediaItemInfo_Value(s.left, "D_FADEOUTLEN_AUTO", s.foutA)
      reaper.SetMediaItemInfo_Value(s.left, "C_FADEOUTSHAPE", s.foutS)
    end
  end
  G.splits = {}
  G.allMoving = nil
  for _, m in ipairs(G.markSnap or {}) do set_marker(m, m.pos, m.rend) end
end

-- Every other track with the stretch moved to T (T: time with the stretch taken out)
local function all_apply(T)
  local cur = {}
  for _, o in ipairs(G.others) do if not o.locked then cur[#cur + 1] = o.it end end
  for _, t in ipairs({ G.a, G.a + G.len, orig_time(G.a, G.len, T) }) do
    for i = 1, #cur do
      local right = split_at(cur[i], t)
      if right then cur[#cur + 1] = right end
    end
  end
  local pos = {}
  G.allMoving = {}
  for _, it in ipairs(cur) do
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if p >= G.a - TOL and p < G.a + G.len - TOL then G.allMoving[#G.allMoving + 1] = it end
    pos[it] = all_map(p, T)
  end
  for it, p in pairs(pos) do
    if math.abs(reaper.GetMediaItemInfo_Value(it, "D_POSITION") - p) > 1e-9 then
      reaper.SetMediaItemInfo_Value(it, "D_POSITION", p)
    end
  end
  for _, m in ipairs(G.markSnap or {}) do
    if m.isrgn then
      local s, e = all_map(m.pos, T), all_map_end(m.rend, T)
      if e > s + TOL then set_marker(m, s, e) end
    else
      set_marker(m, all_map(m.pos, T), m.rend)
    end
  end
end

------------------------------------------------------------
-- Tracks that shuffle along (groups, selection on other tracks)
------------------------------------------------------------
local function tg(id) return reaper.GetToggleCommandState(id) == 1 end

local function group_masks(tr, name)
  local lo, hi = 0, 0
  if reaper.GetSetTrackGroupMembershipEx then
    lo = reaper.GetSetTrackGroupMembershipEx(tr, name, 0, 0, 0) or 0
    hi = reaper.GetSetTrackGroupMembershipEx(tr, name, 32, 0, 0) or 0
  elseif reaper.GetSetTrackGroupMembership then
    lo = reaper.GetSetTrackGroupMembership(tr, name, 0, 0) or 0
  end
  return math.floor(lo) & 0xFFFFFFFF, math.floor(hi) & 0xFFFFFFFF
end

-- Other tracks that move with D: tracks following a group D's track leads (media
-- editing), tracks with items in D's item group, and tracks with selected items
-- (when D is selected)
local function follower_tracks(D, srcTr)
  local set = {}
  if reaper.IsMediaItemSelected(D) then
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
      local tr = reaper.GetMediaItem_Track(reaper.GetSelectedMediaItem(0, i))
      if tr ~= srcTr then set[tr] = true end
    end
  end
  if tg(1156) then   -- item grouping on
    local gid = reaper.GetMediaItemInfo_Value(D, "I_GROUPID") or 0
    if gid > 0 then
      for i = 0, reaper.CountMediaItems(0) - 1 do
        local it = reaper.GetMediaItem(0, i)
        if reaper.GetMediaItemInfo_Value(it, "I_GROUPID") == gid then
          local tr = reaper.GetMediaItem_Track(it)
          if tr ~= srcTr then set[tr] = true end
        end
      end
    end
    if tg(40771) then  -- track grouping
      local lLo, lHi = group_masks(srcTr, "MEDIA_EDIT_LEAD")
      if lLo ~= 0 or lHi ~= 0 then
        for t = 0, reaper.CountTracks(0) - 1 do
          local tr = reaper.GetTrack(0, t)
          if tr ~= srcTr then
            local fLo, fHi = group_masks(tr, "MEDIA_EDIT_FOLLOW")
            if (fLo & lLo) ~= 0 or (fHi & lHi) ~= 0 then set[tr] = true end
          end
        end
      end
    end
  end
  return set
end

------------------------------------------------------------
-- The drag
------------------------------------------------------------
local automation_apply, restore_envs   -- (defined with the automation below)

-- An item's crossfade audio can't go before the project start: it is trimmed there
-- (the timing of everything stays the same)
local function trim_at_start(it, cut)
  local f = G.fadeSnap[it]
  local len = (f and f.D_LENGTH) or reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  cut = math.min(cut, len - TOL)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", len - cut)
  for t = 0, reaper.CountTakes(it) - 1 do
    local tk = reaper.GetTake(it, t)
    if tk then
      local o = (G.offsSnap[it] and G.offsSnap[it][tk]) or reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
      reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", o + cut * reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"))
    end
  end
  local fin = reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN")
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN", math.max(0, fin - cut))
  local fa = reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO")
  if fa > 0 then reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", math.max(0, fa - cut)) end
end

local function apply_positions(pos)
  for it, p in pairs(pos) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      if p < -TOL then trim_at_start(it, -p); p = 0 end
      if math.abs(reaper.GetMediaItemInfo_Value(it, "D_POSITION") - p) > 1e-9 then
        reaper.SetMediaItemInfo_Value(it, "D_POSITION", p)
      end
    end
  end
end

-- Put a track's items back where they were at the click
local function restore_list(list)
  local pos = {}
  for _, r in ipairs(list) do pos[r.it] = r.pos end
  apply_positions(pos)
end

-- The dragged item(s) onto a track
local function put_D_on(tr)
  for _, m in ipairs(G.Dslot.members) do
    if reaper.ValidatePtr2(0, m.item, "MediaItem*") and reaper.GetMediaItem_Track(m.item) ~= tr then
      reaper.MoveMediaItemToTrack(m.item, tr)
    end
  end
end

-- While dragging, what moves is selected (on every track it moves on), so its
-- bounds show; back home or cancelled, the selection is as it was at the click
local function select_only(list)
  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(list) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then reaper.SetMediaItemSelected(it, true) end
  end
end

local function show_moving()
  local list = {}
  for _, m in ipairs(G.Dslot.members) do list[#list + 1] = m.item end
  for _, F in ipairs(G.followers or {}) do
    for _, sg in ipairs(F.blk) do if sg.item then list[#list + 1] = sg.item end end
  end
  for _, it in ipairs(G.allMoving or {}) do list[#list + 1] = it end
  select_only(list)
end

local function restore_selection()
  if G.selSnap then select_only(G.selSnap) end
end

-- Everything back as it was at the click
local function restore()
  if not G then return end
  reaper.PreventUIRefresh(1)
  put_D_on(G.src.tr)
  for _, row in pairs(G.rows) do if row then restore_list(row.list) end end
  for _, F in ipairs(G.followers or {}) do restore_list(F.list) end
  if G.all then all_restore() end
  restore_fades()
  restore_envs()
  restore_selection()
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

-- Another track D could go to: its row without D (nil if it has locked items)
local function target_row(tr)
  if G.rows[tr] ~= nil then return G.rows[tr] or nil end
  local list = lane_items(tr, G.lane)
  if not list then G.rows[tr] = false return nil end
  snap_fades(list); note_neighbors(list)
  local R = build_row(list, G.memberSet)
  local bounds = row_bounds(R, nil)
  if #R == 0 then                                -- empty track: D keeps its time
    R = { { gap = true, len = G.a } }
    bounds = { { k = 1, t = G.a } }
  end
  G.rows[tr] = { tr = tr, list = list, R = R, bounds = bounds }
  return G.rows[tr]
end

local function tip(msg)
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip("Shuffle: " .. msg, x + 12, y + 12, true)
end

local function start_drag(D, pressTime)
  local tr = reaper.GetMediaItem_Track(D)
  local lane = reaper.GetMediaItemInfo_Value(D, "I_FIXEDLANE")
  local list = lane_items(tr, lane)
  if not list then tip("this track has locked items") return end
  local segs = build_row(list)
  -- What moves: D, or, if D is selected, the selected items on its track and lane
  -- (and whatever lies between them), as one block: from the edit point before the
  -- first to the edit point after the last
  local i1, i2
  for i, s in ipairs(segs) do
    if s.item and (s.item == D or (reaper.IsMediaItemSelected(D) and reaper.IsMediaItemSelected(s.item))) then
      i1 = i1 or i; i2 = i
    end
  end
  if not i1 then return end
  local st = seg_starts(segs)
  local a = st[i1]
  local block = { members = {}, pos0 = a, len = 0 }
  local memberSet = {}
  for i = i1, i2 do
    local sl = segs[i]
    if sl.item then
      block.members[#block.members + 1] = { item = sl.item, off = (st[i] + sl.off) - a }
      memberSet[sl.item] = true
    end
    block.len = block.len + sl.len
  end
  local len = block.len
  local R = {}
  for i = 1, i1 - 1 do R[#R + 1] = segs[i] end
  for i = i2 + 1, #segs do R[#R + 1] = segs[i] end
  local bounds = row_bounds(R, a)
  -- Its own edges, when it sits in a gap with room: one length right (its start where
  -- its end was) or left (its end where its start was). The gap is split, so nothing
  -- else moves.
  for _, T in ipairs({ a + len, a - len }) do
    local b = cut_at(R, T)
    if b and b.split then bounds[#bounds + 1] = b end
  end

  G = { fadeSnap = {}, offsSnap = {}, nextOf = {}, envSnap = {} }   -- (filled below; needed by the helpers)
  snap_fades(list); note_neighbors(list)

  local all = reaper.GetToggleCommandState(RIPPLE_ALL) == 1
  if all then
    -- Every track moves: only drop points where no locked item would have to move
    -- or be split
    G.others = other_items(tr, list)
    local ok = {}
    for _, b in ipairs(bounds) do
      local free = math.abs(b.t - a) <= TOL and not b.split
      if not free then
        local lo, hi = touched(a, len, b.t)
        free = true
        for _, o in ipairs(G.others) do
          if o.locked and o.pos + o.len > lo + TOL and o.pos < hi - TOL then free = false break end
        end
      end
      if free then ok[#ok + 1] = b end
    end
    if #ok < #bounds and #ok <= 1 then tip("locked items on other tracks are in the way") end
    bounds = ok
    G.all, G.splits, G.cutFade = true, {}, default_fade()
    if MOVE_MARKERS then G.markSnap = snap_markers() end
  end

  -- Tracks that shuffle along: the same stretch out, the same place back in
  local followers = {}
  for ftr in pairs(all and {} or follower_tracks(D, tr)) do
    local flist = lane_items(ftr, lane)
    if not flist then G = nil tip("a grouped track has locked items") return end
    local FR, fblk = extract(build_row(flist), a, a + len)
    if not FR then G = nil tip("an item on a grouped track crosses the start or end of what's moving") return end
    snap_fades(flist); note_neighbors(flist)
    followers[#followers + 1] = { tr = ftr, list = flist, R = FR, blk = fblk, a = a, b = a + len }
  end
  if #followers > 0 then
    -- Drop points: the clicked track's own, plus every edit point on the other tracks,
    -- where all of them have an edit point or empty space (nothing is ever split)
    local seen = {}
    for _, b in ipairs(bounds) do seen[string.format("%.6f", b.t)] = true end
    for _, F in ipairs(followers) do
      local fst, ftotal = seg_starts(F.R)
      local times = { ftotal }
      for j = 1, #F.R do times[#times + 1] = fst[j] end
      for _, T in ipairs(times) do
        local key = string.format("%.6f", T)
        if T >= 0 and not seen[key] then
          seen[key] = true
          local b = cut_at(R, T)
          if b and not b.tail then bounds[#bounds + 1] = b end
        end
      end
    end
    local ok = {}
    for _, b in ipairs(bounds) do
      local free = math.abs(b.t - a) <= TOL and not b.split
      if not free then
        free = true
        for _, F in ipairs(followers) do if not cut_at(F.R, b.t) then free = false break end end
      end
      if free then ok[#ok + 1] = b end
    end
    bounds = ok
  end
  local src = { tr = tr, list = list, R = R, bounds = bounds }
  G.D, G.Dslot, G.memberSet, G.lane, G.src, G.rows = D, block, memberSet, lane, src, { [tr] = src }
  G.followers, G.a, G.len = followers, a, len
  G.track, G.b, G.grab, G.active = tr, nil, pressTime - a, false
  G.pressX, G.pressY = mouse.mouse()
  G.wasSelected = reaper.IsMediaItemSelected(D)
  G.selSnap = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do G.selSnap[#G.selSnap + 1] = reaper.GetSelectedMediaItem(0, i) end
end

local function nearest_bound(bounds, desired)
  local best, bestD = nil, math.huge
  for _, b in ipairs(bounds) do
    local d = math.abs(b.t - desired)
    if d < bestD then best, bestD = b, d end
  end
  return best
end

local function at_start(tr, b)
  return tr == G.src.tr and b and not b.split and math.abs(b.t - G.a) <= TOL
end

-- Show D at drop point b of track tr (and the source track closed up)
local function place(tr, b)
  reaper.PreventUIRefresh(1)
  if G.all then all_restore() end
  restore_fades()
  for t2, row in pairs(G.rows) do
    if row and t2 ~= tr and t2 ~= G.src.tr then restore_list(row.list) end   -- tracks left behind
  end
  local home = at_start(tr, b)
  automation_apply(tr, (not home) and b or nil)
  if home then
    put_D_on(G.src.tr)
    restore_list(G.src.list)
    for _, F in ipairs(G.followers) do restore_list(F.list) end
  elseif tr == G.src.tr then
    put_D_on(tr)
    local F1 = insert(G.src.R, b, { G.Dslot })
    local pos = layout(F1); apply_positions(pos); crossfades_for(F1, pos)
    for _, F in ipairs(G.followers) do
      local fb = cut_at(F.R, b.t)
      local FF = insert(F.R, fb, F.blk)
      local fpos = layout(FF); apply_positions(fpos); crossfades_for(FF, fpos)
    end
    if G.all then all_apply(b.t) end
  else
    local spos = layout(G.src.R); apply_positions(spos); crossfades_for(G.src.R, spos)   -- source closes up
    local row = G.rows[tr]
    put_D_on(tr)
    local F1 = insert(row.R, b, { G.Dslot })
    local pos = layout(F1); apply_positions(pos); crossfades_for(F1, pos)              -- target opens a slot
  end
  if home then restore_selection() else show_moving() end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

-- The track D is over: the track under the mouse if it can take D, else the last one
local function track_under_mouse()
  if #G.followers > 0 or G.all then return G.src.tr end   -- grouped or all tracks: stays on its track
  local mx, my = reaper.GetMousePosition()
  local tr, info = reaper.GetTrackFromPoint(mx, my)
  if not tr or (info or 0) ~= 0 then return G.track end   -- envelope lanes, FX: stay
  if tr == G.src.tr or target_row(tr) then return tr end
  return G.track                                          -- locked items there
end

local function drag()
  local cx, cy = mouse.mouse()
  if not G.active then   -- picked up once the mouse moves far enough, in any direction
    if not cx or (math.abs(cx - G.pressX) < DEADBAND_PX and math.abs(cy - G.pressY) < DEADBAND_PX) then return end
    G.active = true
  end
  reaper.SetExtState(NS, DRAG_STAMP, tostring(reaper.time_precise()), false)
  local t = mouse.drag_time(AUTOSCROLL_RATE)
  if not t then return end
  local tr = track_under_mouse()
  local row = G.rows[tr]
  local b = nearest_bound(row.bounds, t - G.grab)
  if b and (b ~= G.b or tr ~= G.track) then
    G.track, G.b = tr, b
    place(tr, b)
  end
end

------------------------------------------------------------
-- Automation follows (track envelopes, when "Move envelope points with media items"
-- is on). Each track's edit is: the range a..a+len taken out and/or put back at T.
------------------------------------------------------------
local ANCHOR = 1e-6   -- how far apart the two points at an edit boundary are

local function env_has_points(env) return reaper.CountEnvelopePoints(env) > 0 end

local function env_value(env, t)
  local _, v = reaper.Envelope_Evaluate(env, t, 0, 0)
  return v
end

-- Points at these times with the envelope's values there (keeps the shape around
-- an edit). All values are read before any point is added.
local function anchors(env, times)
  local vals = {}
  for i, t in ipairs(times) do vals[i] = env_value(env, t) end
  for i, t in ipairs(times) do
    if t >= 0 then reaper.InsertEnvelopePoint(env, t, vals[i], 0, 0, false, true) end
  end
  reaper.Envelope_SortPoints(env)
end

-- Move every point by fn(t); nil from fn = delete
local function remap(env, fn)
  for i = reaper.CountEnvelopePoints(env) - 1, 0, -1 do
    local ok, t, v, sh, te, sel = reaper.GetEnvelopePoint(env, i)
    if ok then
      local nt = fn(t)
      if nt then reaper.SetEnvelopePoint(env, i, nt, v, sh, te, sel, true)
      else reaper.DeleteEnvelopePointEx(env, -1, i) end
    end
  end
  reaper.Envelope_SortPoints(env)
end

local function envelopes(tr)
  local list = {}
  for e = 0, reaper.CountTrackEnvelopes(tr) - 1 do
    local env = reaper.GetTrackEnvelope(tr, e)
    local _, name = reaper.GetEnvelopeName(env)
    if name ~= "Tempo map" then list[#list + 1] = env end   -- tempo stays where it is
  end
  return list
end

local function env_name(env)
  local _, name = reaper.GetEnvelopeName(env)
  return name
end

-- Same track: range a..a+len taken out and put back at T (T in the time with the
-- range taken out)
local function automation_shuffle(tr, a, len, T)
  local b = a + len
  local u = (T < a) and T or (T + len)           -- the drop point, before the edit
  for _, env in ipairs(envelopes(tr)) do
    if env_has_points(env) then
      anchors(env, { a - ANCHOR, a, b - ANCHOR, b, u - ANCHOR, u })
      remap(env, function(t)
        if t >= a and t < b then return T + (t - a) end
        local r = (t >= b) and (t - len) or t
        return (r >= T) and (r + len) or r
      end)
    end
  end
end

-- Another track: range a..a+len taken out of src, put in at T on dst
local function automation_move(srcTr, dstTr, a, len, T)
  local b = a + len
  local dstEnvs = {}
  for _, env in ipairs(envelopes(dstTr)) do dstEnvs[env_name(env)] = env end
  -- The destination opens up at T
  for _, env in pairs(dstEnvs) do
    if env_has_points(env) then
      anchors(env, { T - ANCHOR, T })
      remap(env, function(t) return (t >= T) and (t + len) or t end)
    end
  end
  for _, env in ipairs(envelopes(srcTr)) do
    if env_has_points(env) then
      anchors(env, { a - ANCHOR, a, b - ANCHOR, b })
      -- the stretch's points go to the envelope of the same name there
      local dst = dstEnvs[env_name(env)]
      local moved = {}
      for i = 0, reaper.CountEnvelopePoints(env) - 1 do
        local ok, t, v, sh, te = reaper.GetEnvelopePoint(env, i)
        if ok and t >= a and t < b then moved[#moved + 1] = { t = t, v = v, sh = sh, te = te } end
      end
      remap(env, function(t)
        if t >= a and t < b then return nil end
        return (t >= b) and (t - len) or t
      end)
      if dst then
        for _, m in ipairs(moved) do
          reaper.InsertEnvelopePoint(dst, T + (m.t - a), m.v, m.sh, m.te, false, true)
        end
        reaper.Envelope_SortPoints(dst)
      end
    end
  end
end

-- Live while dragging: the envelopes as they were at the click are kept, put back
-- before each new drop point is shown, and the edit applied again from them
local function snap_track_envs(tr)
  for _, env in ipairs(envelopes(tr)) do
    if not G.envSnap[env] then
      local pts = {}
      for i = 0, reaper.CountEnvelopePoints(env) - 1 do
        local ok, t, v, sh, te, sel = reaper.GetEnvelopePoint(env, i)
        if ok then pts[#pts + 1] = { t, v, sh, te, sel } end
      end
      G.envSnap[env] = pts
    end
  end
end

function restore_envs()
  for env, pts in pairs(G.envSnap or {}) do
    if reaper.ValidatePtr2(0, env, "TrackEnvelope*") then
      reaper.DeleteEnvelopePointRange(env, -1e10, 1e10)
      for _, p in ipairs(pts) do reaper.InsertEnvelopePoint(env, p[1], p[2], p[3], p[4], p[5], true) end
      reaper.Envelope_SortPoints(env)
    end
  end
end

-- Show the automation for D at drop point b of track tr (nil b: as at the click)
function automation_apply(tr, b)
  if reaper.GetToggleCommandState(40070) ~= 1 then return end   -- Move envelope points with media items
  snap_track_envs(G.src.tr)
  for _, F in ipairs(G.followers) do snap_track_envs(F.tr) end
  if G.all then
    for t = -1, reaper.CountTracks(0) - 1 do
      local atr = (t < 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, t)
      if atr then snap_track_envs(atr) end
    end
  end
  if tr then snap_track_envs(tr) end
  restore_envs()
  if not b then return end
  local a, len, T = G.a, G.len, b.t
  if G.all then
    for t = -1, reaper.CountTracks(0) - 1 do
      local atr = (t < 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, t)
      if atr then automation_shuffle(atr, a, len, T) end
    end
  elseif tr == G.src.tr then
    automation_shuffle(G.src.tr, a, len, T)
    for _, F in ipairs(G.followers) do automation_shuffle(F.tr, F.a, F.b - F.a, T) end
  else
    automation_move(G.src.tr, tr, a, len, T)
  end
end

-- Like the Move Tool's click: what moved is selected (on every track it moved on),
-- the edit cursor goes to the selection's start, and with Link Timeline and Edit
-- Selection on the loop points span it
local function select_and_place_cursor(D)
  show_moving()   -- what moved stays selected, on every track
  local s, e = math.huge, -math.huge
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    s = math.min(s, p)
    e = math.max(e, p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH"))
  end
  if s == math.huge then return end
  reaper.SetEditCurPos(s, false, false)
  local cmd = reaper.NamedCommandLookup(LINK_CMD_GUID)
  if cmd ~= 0 and reaper.GetToggleCommandStateEx(0, cmd) == 1 and e > s then
    reaper.GetSet_LoopTimeRange(true, true, s, e, false)
  end
end

local function release()
  if G.active then   -- REAPER runs the item click on this release: tell it to skip
    reaper.SetExtState(NS, DRAG_STAMP, tostring(reaper.time_precise()), false)
  end
  if G.active and G.b and not at_start(G.track, G.b) and reaper.ValidatePtr2(0, G.D, "MediaItem*") then
    -- The drag made no undo points, so this block captures the whole move
    reaper.Undo_BeginBlock()   -- (the automation was already moved while dragging)
    select_and_place_cursor(G.D)
    reaper.Undo_EndBlock(G.all and "Shuffle (all tracks)"
      or ((#G.Dslot.members > 1 or #G.followers > 0) and "Shuffle items" or "Shuffle item"), -1)
  end
  G = nil
  reaper.UpdateArrange()
end

------------------------------------------------------------
-- Press: is this drag ours?
------------------------------------------------------------
local hoverCursor = nil   -- REAPER's cursor, last seen with the button up

local function our_press(it, sx, sy, mods)
  if not it or (mods or 0) ~= 0 then return false end   -- modifier drags: REAPER's own
  local tool = wanted_tool()
  if tool == "grabber" then return true end              -- edges and fades are locked there
  if tool == "smart" then
    if hoverCursor and mouse.REAPER_HANDLES[hoverCursor] then return false end
    local _, cy = reaper.JS_Window_ScreenToClient(mouse.ARRANGE, sx, sy)
    local top, h = mouse.item_rect(it)
    return cy and h > 0 and cy >= top + h / 2              -- lower half moves items
  end
  return false
end

------------------------------------------------------------
-- Main loop
------------------------------------------------------------
local prevDown, lastTry = false, 0

local function stop()
  if G then restore() G = nil end
  mouse.clicks_stop()
  reaper.DeleteExtState(NS, HEARTBEAT, false)
end

local function loop()
  if wanted_tool() == "" or not tools.shuffle_on() then stop() return end
  local now = reaper.time_precise()
  reaper.SetExtState(NS, HEARTBEAT, tostring(now), false)
  if not mouse.clicks_on() and now - lastTry > 1 then lastTry = now; mouse.clicks_start() end

  local down = reaper.JS_Mouse_GetState(1) == 1
  local mods = reaper.JS_Mouse_GetState(4 | 8 | 16 | 32)
  local cursorBefore = hoverCursor
  if not down and not G then hoverCursor = mouse.current_cursor() end

  if not G then
    local c = mouse.new_click()
    local sx, sy
    if c then
      sx, sy = mouse.click_screen_point(c, down)
    elseif not mouse.clicks_on() and down and not prevDown then
      sx, sy = reaper.GetMousePosition()
    end
    if sx and down then   -- a click already released can't be a drag
      local it = reaper.GetItemFromPoint(sx, sy, false)
      hoverCursor = cursorBefore or hoverCursor
      if our_press(it, sx, sy, mods) then
        local cx = reaper.JS_Window_ScreenToClient(mouse.ARRANGE, sx, sy)
        start_drag(it, mouse.time_at(cx))
      end
    end
  elseif down then
    drag()
  else
    release()
  end

  prevDown = down
  reaper.defer(loop)
end

-- Started again while running (each time a tool is applied): REAPER stops this copy
-- and runs the new one, so an updated script always takes over
if reaper.set_action_options then reaper.set_action_options(1 | 2) end
reaper.atexit(stop)
mouse.clicks_start()
loop()
