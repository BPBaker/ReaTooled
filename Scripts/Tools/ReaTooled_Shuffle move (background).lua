-- @description ReaTooled - Shuffle move (background, started in Shuffle mode)
-- @version 2.7
-- @date 2026.10.30
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
--   half (where it moves items); edges, fades and handles stay REAPER's.
--   Option/Alt-drag copies: the copy goes in at the drop point and pushes what follows
--   along, and the original stays. Other modifier drags stay REAPER's own. A plain click still selects
--   the item. Dragged to another track, the item leaves its track (which closes
--   up) and goes in at an item edge on the new track (on an empty track, at its
--   time). Tracks with locked items aren't shuffled.
-- @changelog
--   v2.6.1 Option/Alt-dragging a razor area in Shuffle copies it with or without Separation
--          Mode (the Selector too, and the Multi tool's upper half over a razor area); no
--          error when an undo removes items during a drag
--   v2.6 Option/Alt-drag copies, like Pro Tools' Option-drag in Shuffle: a copy goes in at
--        the drop point and pushes what follows along (items, grouped and selected
--        tracks, another track, all tracks, and razor areas with Separation Mode, where
--        the copy is trimmed to the area). Razor areas are re-read only when the project
--        changes. Drags switched off over a razor area are kept on disk and put back if
--        the script stops before it can. A tip when razor areas on other tracks cover a
--        different range (every track moves the clicked track's range)
--   v2.5 Multi tool in Shuffle: its upper half works again (drag makes a razor area, as
--        without Shuffle): while the mouse is over an item's upper half, the tool's own
--        drag there is put back; the lower half shuffles
--   v2.4.3 Separation: the placeholders for empty space are shaded like the track's
--          background and never shown selected
--   v2.4.2 Separation: while the mouse is over a razor area, the tool's own plain drags
--          on items and empty track space are off (no new razor area or marquee is
--          started under the Shuffle drag, e.g. with the Selector); back when it leaves
--   v2.4.1 Separation: the razor area is read from just before the press (REAPER can
--          clear it as the button goes down) and put back, so it can be dragged
--   v2.4 Separation mode: dragging a razor area shuffles what's in it (like Pro Tools'
--        Separation Grabber in Shuffle). Once the drag starts, items on the tracks with
--        that razor area are split at its edges and empty space in it is held by
--        temporary empty items; the pieces then shuffle like selected items (crossfades,
--        gaps, other tracks, grouped tracks, all tracks). Back home or cancelled,
--        everything is as it was; dropped, the empty space comes back, the razor area
--        is cleared and the pieces stay selected
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
    local valid = reaper.ValidatePtr2(0, A, "MediaItem*") and reaper.ValidatePtr2(0, B, "MediaItem*")
      and pos[A] and pos[B]                       -- (an undo during the drag can remove items)
    if valid and G.nextOf[A] ~= B then
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
local razor_drag, wrap_restore_fwd, wrap_commit_fwd   -- (Separation, below)
local hover_razor_fwd                                   -- (Separation, below)
local delete_copies_fwd                                 -- (copying, below)
local upper_half_fwd                                    -- (Multi tool upper half, below)

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
    for _, sg in ipairs(F.blk) do
      if sg.item then list[#list + 1] = sg.item end
      for _, m in ipairs(sg.members or {}) do list[#list + 1] = m.item end   -- (copies)
    end
  end
  for _, it in ipairs(G.allMoving or {}) do list[#list + 1] = it end
  if G.wrap and G.wrap.tempSet then   -- Separation's placeholders for empty space: never shown selected
    local keep = {}
    for _, it in ipairs(list) do if not G.wrap.tempSet[it] then keep[#keep + 1] = it end end
    list = keep
  end
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
  if G.copies then delete_copies_fwd() end      -- copying: the copies go
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  if G.wrap then wrap_restore_fwd(G.wrap) end   -- Separation: splits undone
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

------------------------------------------------------------
-- Copy (Option/Alt-drag, like Pro Tools' Option-drag in Shuffle): a copy goes in at
-- the drop point and pushes what follows along; the original stays where it is.
------------------------------------------------------------
local function strip_guids(chunk)
  if type(chunk) ~= "string" then return chunk end
  return (chunk:gsub("\n[ \t]*I?GUID [^\n]*", ""):gsub("\n[ \t]*POOLEDEVTS [^\n]*", ""))
end

-- A copy of an item on its own track (trimmed to a..b when they're given)
local function copy_item(it, a, b)
  local tr = reaper.GetMediaItem_Track(it)
  local ok, chunk = reaper.GetItemStateChunk(it, "", false)
  if not ok then return nil end
  local new = reaper.AddMediaItemToTrack(tr)
  if not new then return nil end
  reaper.SetItemStateChunk(new, strip_guids(chunk), false)
  reaper.SetMediaItemSelected(new, false)
  if a then
    local p = reaper.GetMediaItemInfo_Value(new, "D_POSITION")
    local e = p + reaper.GetMediaItemInfo_Value(new, "D_LENGTH")
    local s2, e2 = math.max(p, a), math.min(e, b)
    if e2 <= s2 + TOL then reaper.DeleteTrackMediaItem(tr, new) return nil end
    local cut = s2 - p
    if cut > 0 then
      for k = 0, reaper.CountTakes(new) - 1 do
        local tk = reaper.GetTake(new, k)
        if tk then
          reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
            + cut * reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"))
        end
      end
      reaper.SetMediaItemInfo_Value(new, "D_FADEINLEN", math.max(0, reaper.GetMediaItemInfo_Value(new, "D_FADEINLEN") - cut))
    end
    if e2 < e - TOL then
      reaper.SetMediaItemInfo_Value(new, "D_FADEOUTLEN", math.max(0, reaper.GetMediaItemInfo_Value(new, "D_FADEOUTLEN") - (e - e2)))
    end
    reaper.SetMediaItemInfo_Value(new, "D_POSITION", s2)
    reaper.SetMediaItemInfo_Value(new, "D_LENGTH", e2 - s2)
  end
  return new
end

local function delete_copies()
  for _, c in ipairs(G.copies or {}) do
    if reaper.ValidatePtr2(0, c, "MediaItem*") then reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(c), c) end
  end
  G.copies = nil
end

local function copy_dup(it, a, b)
  local c = copy_item(it, a, b)
  if c then
    G.copies[#G.copies + 1] = c
    G.copyHome[c] = reaper.GetMediaItemInfo_Value(c, "D_POSITION")
    snap_fades({ { it = c, len = reaper.GetMediaItemInfo_Value(c, "D_LENGTH") } })
  end
  return c
end

-- All tracks: copies of the stretch on the other tracks, and drop points where no
-- locked item would have to move
-- Copying: the original's own start is two drop points. Right there it's home (no
-- copy); a step to the left of it, the copy goes in at that same start and the
-- original and what follows shuffle along (as copying it anywhere else would).
local function add_copy_at_start(bounds, R, a)
  local out = {}
  for _, bd in ipairs(bounds) do
    if bd.k == -1 or bd.split or math.abs(bd.t - a) > TOL then out[#out + 1] = bd end
  end
  local ins = cut_at(R, a)   -- (nil inside an item: a razor area starting mid-item)
  if ins then ins.ins = true; out[#out + 1] = ins end
  return out
end

-- Where the mouse picks it: halfway to the next drop point on the left (at most
-- half the copy's length to the left of the start)
local function copy_at_start_pick(bounds, a, len)
  local ins, prev = nil, nil
  for _, bd in ipairs(bounds) do
    if bd.ins then ins = bd
    elseif bd.t < a - TOL and (not prev or bd.t > prev) then prev = bd.t end
  end
  if not ins then return end
  local half = a - len / 2
  ins.pick = prev and math.max((prev + a) / 2, half) or half
end

local function copy_all_setup(bounds)
  G.allCopies = {}
  for _, o in ipairs(G.others) do
    if not o.locked and o.pos < G.a + G.len - TOL and o.pos + o.len > G.a + TOL then
      local c = copy_dup(o.it, G.a, G.a + G.len)
      if c then G.allCopies[#G.allCopies + 1] = { it = c, off = reaper.GetMediaItemInfo_Value(c, "D_POSITION") - G.a } end
    end
  end
  local ok = {}
  for _, bd in ipairs(bounds) do
    local free = math.abs(bd.t - G.a) <= TOL and not bd.split and not bd.ins
    if not free then
      free = true
      for _, o in ipairs(G.others) do
        if o.locked and o.pos + o.len > bd.t + TOL then free = false break end
      end
    end
    if free then ok[#ok + 1] = bd end
  end
  return ok
end

local function copy_follower_filter(bounds)
  if #G.followers == 0 then return bounds end
  local ok = {}
  for _, bd in ipairs(bounds) do
    local free = math.abs(bd.t - G.a) <= TOL and not bd.split and not bd.ins
    if not free then
      free = true
      for _, F in ipairs(G.followers) do if not cut_at(F.R, bd.t) then free = false break end end
    end
    if free then ok[#ok + 1] = bd end
  end
  return ok
end

-- An item drag becomes a copy once it's picked up: copies of what moves, and every
-- track's row stays whole
local function make_copy()
  G.copies, G.copyHome = {}, {}
  local members, set = {}, {}
  for _, m in ipairs(G.Dslot.members) do
    local c = copy_dup(m.item)
    if c then
      members[#members + 1] = { item = c, off = m.off }
      set[c] = true
      if m.item == G.D then G.D = c end
    end
  end
  G.Dslot = { members = members, pos0 = G.a, len = G.len }
  G.memberSet = set
  G.src.R = build_row(G.src.list)
  for _, F in ipairs(G.followers) do
    F.R = build_row(F.list)
    local fm = {}
    for _, sg in ipairs(F.blk) do
      if sg.item then
        local c = copy_dup(sg.item)
        if c then fm[#fm + 1] = { item = c, off = reaper.GetMediaItemInfo_Value(sg.item, "D_POSITION") - G.a } end
      end
    end
    F.blk = { { members = fm, len = G.len } }
  end
  local bounds = row_bounds(G.src.R, G.a)
  bounds[#bounds + 1] = { k = -1, t = G.a }   -- back home: no copy
  bounds = add_copy_at_start(bounds, G.src.R, G.a)
  bounds = copy_follower_filter(bounds)
  if G.all then bounds = copy_all_setup(bounds) end
  copy_at_start_pick(bounds, G.a, G.len)
  G.src.bounds = bounds
  G.rows = { [G.src.tr] = G.src }
end

-- All tracks, copying: the other tracks open up at T and take the copies there
local function all_apply_copy(T)
  local cur = {}
  for _, o in ipairs(G.others) do if not o.locked then cur[#cur + 1] = o.it end end
  for i = 1, #cur do
    local right = split_at(cur[i], T)
    if right then cur[#cur + 1] = right end
  end
  for _, it in ipairs(cur) do
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if p >= T - TOL then reaper.SetMediaItemInfo_Value(it, "D_POSITION", p + G.len) end
  end
  G.allMoving = {}
  for _, c in ipairs(G.allCopies or {}) do
    reaper.SetMediaItemInfo_Value(c.it, "D_POSITION", T + c.off)
    G.allMoving[#G.allMoving + 1] = c.it
  end
  for _, m in ipairs(G.markSnap or {}) do
    local s1 = (m.pos >= T - TOL) and (m.pos + G.len) or m.pos
    local e1 = m.isrgn and ((m.rend >= T + TOL) and (m.rend + G.len) or m.rend) or m.rend
    set_marker(m, s1, e1)
  end
end

delete_copies_fwd = delete_copies

local function copy_home()
  if G.copyHome then apply_positions(G.copyHome) end
end

local function nearest_bound(bounds, desired)
  local best, bestD = nil, math.huge
  for _, b in ipairs(bounds) do
    local d = math.abs((b.pick or b.t) - desired)
    if d < bestD then best, bestD = b, d end
  end
  return best
end

local function at_start(tr, b)
  return tr == G.src.tr and b and not b.split and not b.ins and math.abs(b.t - G.a) <= TOL
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
    if G.copy then copy_home() end
  elseif tr == G.src.tr then
    put_D_on(tr)
    local F1 = insert(G.src.R, b, { G.Dslot })
    local pos = layout(F1); apply_positions(pos); crossfades_for(F1, pos)
    for _, F in ipairs(G.followers) do
      local fb = cut_at(F.R, b.t)
      local FF = insert(F.R, fb, F.blk)
      local fpos = layout(FF); apply_positions(fpos); crossfades_for(FF, fpos)
    end
    if G.all then
      if G.copy then all_apply_copy(b.t) else all_apply(b.t) end
    end
  else
    if G.copy then                                                                       -- copying: source stays
      restore_list(G.src.list)
    else
      local spos = layout(G.src.R); apply_positions(spos); crossfades_for(G.src.R, spos) -- source closes up
    end
    local row = G.rows[tr]
    put_D_on(tr)
    local F1 = insert(row.R, b, { G.Dslot })
    local pos = layout(F1); apply_positions(pos); crossfades_for(F1, pos)              -- target opens a slot
  end
  -- (a razor area dragged back home: its pieces stay selected, not what was selected
  -- before, which may be the whole item it was cut from)
  if home and not (G.razorClear or G.wrap) then restore_selection() else show_moving() end
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
    if G.copy and not G.copies then
      reaper.PreventUIRefresh(1); make_copy(); reaper.PreventUIRefresh(-1)
    end
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

-- Copying: the stretch a..a+len copied in at T (this track or dst); what's at or
-- after T moves along
local function automation_copy(srcTr, dstTr, a, len, T)
  local srcPts = {}
  for _, env in ipairs(envelopes(srcTr)) do
    if env_has_points(env) then
      anchors(env, { a, a + len - ANCHOR })
      local pts = {}
      for i = 0, reaper.CountEnvelopePoints(env) - 1 do
        local ok, t, v, sh, te = reaper.GetEnvelopePoint(env, i)
        if ok and t >= a and t < a + len then pts[#pts + 1] = { t = t, v = v, sh = sh, te = te } end
      end
      srcPts[env_name(env)] = pts
    end
  end
  for _, env in ipairs(envelopes(dstTr)) do
    local pts = srcPts[env_name(env)]
    if pts or env_has_points(env) then
      anchors(env, { T - ANCHOR, T })
      remap(env, function(t) return (t >= T) and (t + len) or t end)
      for _, m in ipairs(pts or {}) do
        reaper.InsertEnvelopePoint(env, T + (m.t - a), m.v, m.sh, m.te, false, true)
      end
      reaper.Envelope_SortPoints(env)
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
  if G.copy then
    if G.all then
      for t = -1, reaper.CountTracks(0) - 1 do
        local atr = (t < 0) and reaper.GetMasterTrack(0) or reaper.GetTrack(0, t)
        if atr then automation_copy(atr, atr, a, len, T) end
      end
    elseif tr == G.src.tr then
      automation_copy(G.src.tr, G.src.tr, a, len, T)
      for _, F in ipairs(G.followers) do automation_copy(F.tr, F.tr, a, len, T) end
    else
      automation_copy(G.src.tr, tr, a, len, T)
    end
    return
  end
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

------------------------------------------------------------
-- Separation (ReaTooled_Toggle Separation mode) in Shuffle: dragging a razor area
-- shuffles what's in it, like Pro Tools' Separation Grabber. Once the drag starts,
-- the items on the tracks with that razor area are split at its edges (plain splits,
-- as REAPER's razor edits make them) and empty space inside it on the clicked track
-- is filled with temporary empty items; the pieces are selected, and the drag then
-- runs as a Shuffle drag of selected items. Dropped back home or cancelled,
-- everything is put back as it was; dropped, the temporary items go (empty space
-- again), the razor area is cleared and the moved pieces stay selected.
------------------------------------------------------------
local function separation_on() return reaper.GetExtState(NS, "SeparationMode") == "1" end

-- Track-level razor areas of a track: { {s, e}, ... }, and the whole string
local function razor_areas(tr)
  local _, str = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  local list = {}
  for s, e, guid in (str or ""):gmatch('(%S+)%s+(%S+)%s+"([^"]*)"') do
    if guid == "" then list[#list + 1] = { tonumber(s), tonumber(e) } end
  end
  return list, str or ""
end

local function razor_at(tr, t)
  for _, ar in ipairs((razor_areas(tr))) do
    if ar[1] and ar[2] and t >= ar[1] - TOL and t <= ar[2] + TOL then return ar[1], ar[2] end
  end
end

-- Split items, fill the empty space and select the pieces; returns the undo record
-- and the piece to drag (nil and a reason if it can't be done)
local function razor_prepare(tr, a, b, pressTime)
  local W = { created = {}, chunks = {}, temps = {}, razorSnap = {}, selSnap = {} }
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do W.selSnap[#W.selSnap + 1] = reaper.GetSelectedMediaItem(0, i) end
  -- The tracks with this razor area
  -- (all of them move this track's range, so the tracks stay in sync, as with a
  -- Pro Tools selection; a different range on another track is said in a tip)
  local tracks, differs = { tr }, false
  for t = 0, reaper.CountTracks(0) - 1 do
    local t2 = reaper.GetTrack(0, t)
    if t2 ~= tr then
      for _, ar in ipairs((razor_areas(t2))) do
        if ar[1] < b - TOL and ar[2] > a + TOL then
          tracks[#tracks + 1] = t2
          if math.abs(ar[1] - a) > TOL or math.abs(ar[2] - b) > TOL then differs = true end
          break
        end
      end
    end
  end
  W.differs = differs
  -- Locked items at the edges can't be split
  for _, t2 in ipairs(tracks) do
    for i = 0, reaper.CountTrackMediaItems(t2) - 1 do
      local it = reaper.GetTrackMediaItem(t2, i)
      local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if (reaper.GetMediaItemInfo_Value(it, "C_LOCK") or 0) ~= 0 and p < b - TOL and e > a + TOL then
        return nil, nil, "a locked item is in the razor area"
      end
    end
  end
  for _, t2 in ipairs(tracks) do W.razorSnap[t2] = select(2, razor_areas(t2)) end
  -- Split at the edges
  for _, t2 in ipairs(tracks) do
    for _, cut in ipairs({ a, b }) do
      local list = {}
      for i = 0, reaper.CountTrackMediaItems(t2) - 1 do list[#list + 1] = reaper.GetTrackMediaItem(t2, i) end
      for _, it in ipairs(list) do
        local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if p < cut - TOL and e > cut + TOL then
          if not W.created[it] and not W.chunks[it] then
            local ok, chunk = reaper.GetItemStateChunk(it, "", false)
            if ok then W.chunks[it] = chunk end
          end
          local right = reaper.SplitMediaItem(it, cut)
          if right then W.created[right] = true end
        end
      end
    end
  end
  -- Empty space inside the area on the clicked track: temporary empty items
  local inside = {}
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if p >= a - TOL and p < b - TOL then
      inside[#inside + 1] = { p, p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH") }
    end
  end
  table.sort(inside, function(x, y) return x[1] < y[1] end)
  local gaps, t0 = {}, a
  for _, r in ipairs(inside) do
    if r[1] > t0 + TOL then gaps[#gaps + 1] = { t0, r[1] } end
    t0 = math.max(t0, r[2])
  end
  if b > t0 + TOL then gaps[#gaps + 1] = { t0, b } end
  -- (shaded like the track's background, so they look like the empty space they hold)
  local bg
  if reaper.GetThemeColor then
    local n = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 1
    bg = reaper.GetThemeColor((n % 2 == 1) and "col_tr1_bg" or "col_tr2_bg", 0)
    if not bg or bg < 0 then bg = reaper.GetThemeColor("col_arrangebg", 0) end
  end
  W.tempSet = {}
  for _, g in ipairs(gaps) do
    local it = reaper.AddMediaItemToTrack(tr)
    if it then
      reaper.SetMediaItemInfo_Value(it, "D_POSITION", g[1])
      reaper.SetMediaItemInfo_Value(it, "D_LENGTH", g[2] - g[1])
      if bg and bg >= 0 then reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", bg | 0x1000000) end
      W.temps[#W.temps + 1] = it
      W.tempSet[it] = true
    end
  end
  -- Select the pieces; the one under the mouse (or nearest) is dragged
  reaper.SelectAllMediaItems(0, false)
  local D, bestD = nil, math.huge
  for _, t2 in ipairs(tracks) do
    for i = 0, reaper.CountTrackMediaItems(t2) - 1 do
      local it = reaper.GetTrackMediaItem(t2, i)
      local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if p >= a - TOL and p < b - TOL then
        reaper.SetMediaItemSelected(it, true)
        if t2 == tr then
          local d = (pressTime >= p and pressTime <= e) and 0 or math.min(math.abs(pressTime - p), math.abs(pressTime - e))
          if d < bestD then D, bestD = it, d end
        end
      end
    end
  end
  return W, D
end

-- Everything as it was before the split
local function wrap_restore(W)
  reaper.PreventUIRefresh(1)
  for _, it in ipairs(W.temps) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(it), it) end
  end
  for it in pairs(W.created) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(it), it) end
  end
  for it, chunk in pairs(W.chunks) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then reaper.SetItemStateChunk(it, chunk, false) end
  end
  for tr, str in pairs(W.razorSnap) do
    if reaper.ValidatePtr2(0, tr, "MediaTrack*") then reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", str, true) end
  end
  select_only(W.selSnap)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

-- Dropped: the temporary items go (empty space again), the razor area is cleared
local function wrap_commit(W)
  for _, it in ipairs(W.temps) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(it), it) end
  end
  for tr in pairs(W.razorSnap) do
    if reaper.ValidatePtr2(0, tr, "MediaTrack*") then reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", true) end
  end
end

wrap_restore_fwd, wrap_commit_fwd = wrap_restore, wrap_commit

-- The razor areas as they were before the press (REAPER may clear them as the button
-- goes down, before this script sees the click)
local razorCache = nil
local razorStamp = nil   -- the project's change count when they were read

local function cache_razors()
  -- Read every pass while the button is up (razor edits don't always count as a
  -- project change, so a newly drawn area could be missed)
  local c = {}
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    local _, str = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if str and str ~= "" then c[tr] = str end
  end
  razorCache = c
end

-- REAPER clears the razor areas as the button goes down on one, and adds a "Clear
-- razor edits" undo point for it. The areas are put back (below) and the drag makes
-- its own undo point, so that one is taken back off: undone right away, before
-- anything else changes. (Only one REAPER added since the button was last up.)
local upUndo, upCount = nil, nil
local upSel = nil   -- time selection and loop points, last seen with the button up
local function note_undo_top()
  upUndo = reaper.Undo_CanUndo2(0)
  local u = {}
  u.ls, u.le = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
  u.ts, u.te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  upSel = u
  upCount = reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0)
end
local function drop_razor_clear()
  local top = reaper.Undo_CanUndo2(0)
  if not top or top == upUndo then return end
  local low = top:lower()
  if low:find("razor", 1, true) and low:find("clear", 1, true) then
    reaper.Undo_DoUndo2(0)
  end
  upUndo = reaper.Undo_CanUndo2(0)
end

-- Is there a razor area under the press, in the areas as they were before it?
local function razor_cached_at(tr, t)
  local str = razorCache and razorCache[tr]
  if not str then return false end
  for s1, e1, guid in str:gmatch('(%S+)%s+(%S+)%s+"([^"]*)"') do
    s1, e1 = tonumber(s1), tonumber(e1)
    if guid == "" and s1 and e1 and t >= s1 - TOL and t <= e1 + TOL then return true end
  end
  return false
end

-- The razor area under the press, from the areas as they were before it; puts them
-- back if REAPER cleared them
local function razor_press_area(tr, t)
  if not razorCache then return nil end
  local str = razorCache[tr]
  if not str then return nil end
  local a, b
  for s1, e1, guid in str:gmatch('(%S+)%s+(%S+)%s+"([^"]*)"') do
    s1, e1 = tonumber(s1), tonumber(e1)
    if guid == "" and s1 and e1 and t >= s1 - TOL and t <= e1 + TOL then a, b = s1, e1 break end
  end
  if not a then return nil end
  for t2, s2 in pairs(razorCache) do
    if reaper.ValidatePtr2(0, t2, "MediaTrack*") then
      local _, now = reaper.GetSetMediaTrackInfo_String(t2, "P_RAZOREDITS", "", false)
      if now ~= s2 then reaper.GetSetMediaTrackInfo_String(t2, "P_RAZOREDITS", s2, true) end
    end
  end
  return a, b
end

-- While the mouse is over a razor area (button up), the tool's own plain drags on
-- items and empty track space are turned off, so a press there doesn't start
-- REAPER's drag (a new razor area, a marquee) under the Shuffle drag. They're put
-- back as soon as the mouse leaves the area (and when this script stops).
-- (The lower half's "0" is set explicitly: "-1" leaves its entry blank, which REAPER
-- doesn't treat as passing through to the item context)
local HOVER_OFF = { { "MM_CTX_ITEM", 0, "0" }, { "MM_CTX_ITEMLOWER", 0, "0" }, { "MM_CTX_TRACK", 0, "0" },
                    { "MM_CTX_ITEM", 4, "0" }, { "MM_CTX_ITEMLOWER", 4, "0" }, { "MM_CTX_TRACK", 4, "0" } }
local hoverSaved = nil
-- Kept on disk while switched, so they can be put back even if this script (or
-- REAPER) stops before it can: ReaTooled_Tools lib.lua repair_hover()
local HOVER_KEY = "ShuffleHoverSaved"

local function save_hover()
  if not hoverSaved then reaper.DeleteExtState(NS, HOVER_KEY, true) return end
  local out = {}
  for _, o in ipairs(hoverSaved) do out[#out + 1] = table.concat({ o[1], o[2], o[3], o[4] or "" }, "|") end
  reaper.SetExtState(NS, HOVER_KEY, table.concat(out, ";"), true)
end

local function hover_razor(on)
  if on and not hoverSaved then
    if not reaper.GetMouseModifier then return end
    hoverSaved = {}
    local plain = separation_on()   -- (without Separation Mode only Option/Alt-drags are ours)
    for _, h in ipairs(HOVER_OFF) do
      if h[2] ~= 0 or plain then
      local v = reaper.GetMouseModifier(h[1], h[2])
      if v == nil or v == "" then v = "-1" end
      reaper.SetMouseModifier(h[1], h[2], h[3])
      hoverSaved[#hoverSaved + 1] = { h[1], h[2], v, reaper.GetMouseModifier(h[1], h[2]) }
      end
    end
    save_hover()
  elseif not on and hoverSaved then
    -- (only where it's still ours: a tool chosen meanwhile has set its own)
    for _, o in ipairs(hoverSaved) do
      if reaper.GetMouseModifier(o[1], o[2]) == o[4] then reaper.SetMouseModifier(o[1], o[2], o[3]) end
    end
    hoverSaved = nil
    save_hover()
  end
end

local function mouse_over_razor()
  if not razorCache or not next(razorCache) then return false end
  local mx, my = reaper.GetMousePosition()
  local tr, info = reaper.GetTrackFromPoint(mx, my)
  if not tr or (info or 0) ~= 0 or not razorCache[tr] then return false end
  local cx = reaper.JS_Window_ScreenToClient(mouse.ARRANGE, mx, my)
  if not cx then return false end
  local t = mouse.time_at(cx)
  for s1, e1, guid in razorCache[tr]:gmatch('(%S+)%s+(%S+)%s+"([^"]*)"') do
    s1, e1 = tonumber(s1), tonumber(e1)
    if guid == "" and s1 and e1 and t >= s1 and t <= e1 then return true end
  end
  return false
end

hover_razor_fwd = hover_razor

-- Multi tool in Shuffle: its plain item drag is off (the lower half passes through to
-- it, and the lower half shuffles). While the mouse is over an item's upper half, the
-- tool's own upper-half drag (razor area) is put back, and taken off again elsewhere.
local upperApplied = nil   -- { [flag] = the value we set }, while they're the tool's own
local UPPER_FLAGS = { 0, 4 }   -- plain and Option/Alt drags

local function upper_half_value(flag)
  for line in (reaper.GetExtState(NS, "ModeOverrides") or ""):gmatch("[^;]+") do
    local g, c, f, v = line:match("^(.-)|(.-)|(%-?%d+)|(.*)$")
    if g == "shuffle" and c == "MM_CTX_ITEM" and tonumber(f) == flag then return v end
  end
end

local function mouse_upper_half()
  local mx, my = reaper.GetMousePosition()
  local it = reaper.GetItemFromPoint(mx, my, false)
  if not it then return false end
  local _, cy = reaper.JS_Window_ScreenToClient(mouse.ARRANGE, mx, my)
  local top, h = mouse.item_rect(it)
  return cy and h > 0 and cy < top + h / 2
end

-- allow: { [flag] = true } for the drags to put back now (nil/false: none)
local function multi_upper_half(allow)
  if wanted_tool() ~= "smart" or not reaper.GetMouseModifier then allow = nil end
  upperApplied = upperApplied or {}
  for _, f in ipairs(UPPER_FLAGS) do
    local want = allow and allow[f]
    if want and not upperApplied[f] then
      local v = upper_half_value(f)
      if v and v ~= "" then
        reaper.SetMouseModifier("MM_CTX_ITEM", f, v)
        upperApplied[f] = reaper.GetMouseModifier("MM_CTX_ITEM", f)
      end
    elseif not want and upperApplied[f] then
      if reaper.GetMouseModifier("MM_CTX_ITEM", f) == upperApplied[f] then
        reaper.SetMouseModifier("MM_CTX_ITEM", f, "0")   -- back to Shuffle's (No action)
      end
      upperApplied[f] = nil
    end
  end
end
upper_half_fwd = multi_upper_half

-- Pressed on a razor area: nothing happens until the mouse moves far enough
local function start_razor_press(tr, a, b, pressTime, copy)
  local x, y = mouse.mouse()
  G = { pendingRazor = { tr = tr, a = a, b = b, t = pressTime, copy = copy }, pressX = x, pressY = y }
end

-- Option/Alt-drag on a razor area: a copy of what's in it goes in at the drop point
-- (nothing is split: the copies are trimmed to the area; empty space in it comes along)
local function razor_copy_begin(P, px, py)
  local tr, a, b = P.tr, P.a, P.b
  local len = b - a
  local list = lane_items(tr, 0)
  if not list then tip("this track has locked items") return end
  local sel = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = reaper.GetSelectedMediaItem(0, i) end
  local all = reaper.GetToggleCommandState(RIPPLE_ALL) == 1
  local razorTracks = { tr }
  for t = 0, reaper.CountTracks(0) - 1 do
    local t2 = reaper.GetTrack(0, t)
    if t2 ~= tr then
      for _, ar in ipairs((razor_areas(t2))) do
        if ar[1] < b - TOL and ar[2] > a + TOL then razorTracks[#razorTracks + 1] = t2 break end
      end
    end
  end
  G = { fadeSnap = {}, offsSnap = {}, nextOf = {}, envSnap = {}, copy = true, copies = {}, copyHome = {} }
  G.a, G.len = a, len
  snap_fades(list); note_neighbors(list)
  local members, set = {}, {}
  for _, r in ipairs(list) do
    if r.pos < b - TOL and r.pos + r.len > a + TOL then
      local c = copy_dup(r.it, a, b)
      if c then members[#members + 1] = { item = c, off = reaper.GetMediaItemInfo_Value(c, "D_POSITION") - a }; set[c] = true end
    end
  end
  G.followers = {}
  if not all then
    for i = 2, #razorTracks do
      local ftr = razorTracks[i]
      local flist = lane_items(ftr, 0)
      if not flist then delete_copies() G = nil tip("a track with the razor area has locked items") return end
      snap_fades(flist); note_neighbors(flist)
      local fm = {}
      for _, r in ipairs(flist) do
        if r.pos < b - TOL and r.pos + r.len > a + TOL then
          local c = copy_dup(r.it, a, b)
          if c then fm[#fm + 1] = { item = c, off = reaper.GetMediaItemInfo_Value(c, "D_POSITION") - a } end
        end
      end
      G.followers[#G.followers + 1] = { tr = ftr, list = flist, R = build_row(flist), blk = { { members = fm, len = len } }, a = a, b = b }
    end
  end
  local R = build_row(list)
  local bounds = row_bounds(R, a)
  bounds[#bounds + 1] = { k = -1, t = a }   -- back home: no copy
  bounds = add_copy_at_start(bounds, R, a)
  G.Dslot = { members = members, pos0 = a, len = len }
  G.memberSet, G.lane = set, 0
  G.src = { tr = tr, list = list, R = R, bounds = bounds }
  G.rows = { [tr] = G.src }
  G.D = members[1] and members[1].item or nil
  bounds = copy_follower_filter(bounds)
  if all then
    G.others = other_items(tr, list)
    G.all, G.splits, G.cutFade = true, {}, default_fade()
    if MOVE_MARKERS then G.markSnap = snap_markers() end
    bounds = copy_all_setup(bounds)
  end
  copy_at_start_pick(bounds, a, len)
  G.src.bounds = bounds
  G.track, G.b, G.grab, G.active = tr, nil, P.t - a, true
  G.pressX, G.pressY = px, py
  G.wasSelected = false
  G.selSnap = sel
  G.razorClear = razorTracks
end

function razor_drag()
  local P = G.pendingRazor
  if P then
    drop_razor_clear()   -- (in case REAPER added it after the press was seen)
    local cx, cy = mouse.mouse()
    if not cx or (math.abs(cx - G.pressX) < DEADBAND_PX and math.abs(cy - G.pressY) < DEADBAND_PX) then return end
    local px, py = G.pressX, G.pressY
    local top0 = reaper.Undo_CanUndo2(0)   -- (to find REAPER's own step at the drop)
    local preSel = upSel   -- (as they were before the press)
    if P.copy then
      G = nil
      reaper.PreventUIRefresh(1)
      razor_copy_begin(P, px, py)
      reaper.PreventUIRefresh(-1)
      if G then G.undoTop = top0; G.preSel = preSel; drag() end
      return
    end
    reaper.PreventUIRefresh(1)
    local W, D, why = razor_prepare(P.tr, P.a, P.b, P.t)
    reaper.PreventUIRefresh(-1)
    G = nil
    if not W then tip(why or "can't move this razor area") return end
    if not D then wrap_restore(W) return end
    start_drag(D, P.t)
    if not G then wrap_restore(W) return end      -- (start_drag said why)
    G.undoTop = top0
    G.preSel = preSel
    G.wrap = W
    G.selSnap = W.selSnap
    if W.differs then tip("every track moves this track's razor range") end
    for _, it in ipairs(W.temps) do reaper.SetMediaItemSelected(it, false) end
    G.pressX, G.pressY = px, py
    -- the razor area hides while dragging (it's cleared on the drop, back if cancelled)
    for t2 in pairs(W.razorSnap) do reaper.GetSetMediaTrackInfo_String(t2, "P_RAZOREDITS", "", true) end
  end
  drag()
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

-- A razor drag: REAPER records its own "Clear razor edits" step when the button
-- comes up (it cleared the areas as the button went down), ahead of the drop's.
-- (In the Selector's lower half REAPER may record something else as well, so any
-- step it added since the drag began counts.)
local function reaper_clear_on_top()
  if not G.undoTop then return false end
  local top = reaper.Undo_CanUndo2(0)
  return top ~= nil and top ~= G.undoTop
end
-- Undoes the steps REAPER added since the drag began (a few at most)
local function undo_reaper_steps(top0)
  for _ = 1, 4 do
    local top = reaper.Undo_CanUndo2(0)
    if not top or top == top0 then return end
    reaper.Undo_DoUndo2(0)
  end
end

-- The project as the drop left it (tracks, markers, razor areas, edit cursor, loop)
local function snapshot_result()
  local S = { tracks = {}, marks = {} }
  local function add(tr)
    local _, chunk = reaper.GetTrackStateChunk(tr, "", false)
    local _, raz = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    S.tracks[#S.tracks + 1] = { guid = reaper.GetTrackGUID(tr), chunk = chunk, razor = raz or "" }
  end
  add(reaper.GetMasterTrack(0))
  for t = 0, reaper.CountTracks(0) - 1 do add(reaper.GetTrack(0, t)) end
  local i = 0
  while true do
    local ok, isrgn, pos, rend, name, num, color = reaper.EnumProjectMarkers3(0, i)
    if ok == 0 then break end
    S.marks[#S.marks + 1] = { isrgn, pos, rend, name, num, color }
    i = i + 1
  end
  S.cursor = reaper.GetCursorPosition()
  S.ls, S.le = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)    -- loop points
  S.ts, S.te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)   -- time selection
  return S
end

local function marks_key(list)
  local o = {}
  for _, m in ipairs(list) do o[#o + 1] = table.concat({ tostring(m[1]), m[2], m[3], m[4], m[5], m[6] }, "|") end
  return table.concat(o, "\n")
end

-- Puts that result back after REAPER's step has been undone, as one undo step
local function apply_snapshot(S)
  local byGuid = { [reaper.GetTrackGUID(reaper.GetMasterTrack(0))] = reaper.GetMasterTrack(0) }
  for t = 0, reaper.CountTracks(0) - 1 do local tr = reaper.GetTrack(0, t); byGuid[reaper.GetTrackGUID(tr)] = tr end
  for _, T in ipairs(S.tracks) do
    local tr = byGuid[T.guid]
    if tr then
      local _, now = reaper.GetTrackStateChunk(tr, "", false)
      if now ~= T.chunk then reaper.SetTrackStateChunk(tr, T.chunk, false) end
      local _, raz = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
      if (raz or "") ~= T.razor then reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", T.razor, true) end
    end
  end
  local cur = {}
  local i = 0
  while true do
    local ok, isrgn, pos, rend, name, num, color = reaper.EnumProjectMarkers3(0, i)
    if ok == 0 then break end
    cur[#cur + 1] = { isrgn, pos, rend, name, num, color }
    i = i + 1
  end
  if marks_key(cur) ~= marks_key(S.marks) then
    for j = #cur - 1, 0, -1 do reaper.DeleteProjectMarkerByIndex(0, j) end
    for _, m in ipairs(S.marks) do reaper.AddProjectMarker2(0, m[1], m[2], m[3], m[4], m[5], m[6]) end
  end
  reaper.SetEditCurPos(S.cursor, false, false)
  reaper.GetSet_LoopTimeRange(true, true, S.ls, S.le, false)
  reaper.GetSet_LoopTimeRange(true, false, S.ts, S.te, false)
end

local function release()
  if G.active then   -- REAPER runs the item click on this release: tell it to skip
    reaper.SetExtState(NS, DRAG_STAMP, tostring(reaper.time_precise()), false)
  end
  if G.active and G.b and not at_start(G.track, G.b) and (G.D == nil or reaper.ValidatePtr2(0, G.D, "MediaItem*")) then
    local what = G.copy and "Shuffle copy" or "Shuffle"
    local name = (G.wrap or G.razorClear) and (what .. " razor area" .. (G.all and " (all tracks)" or ""))
      or (G.copy and (what .. (G.all and " (all tracks)" or "")))
      or (G.all and "Shuffle (all tracks)")
      or ((#G.Dslot.members > 1 or #G.followers > 0) and "Shuffle items" or "Shuffle item")
    if reaper_clear_on_top() then
      -- One step for the whole drag: the result is noted, REAPER's step undone (back to
      -- before the press), and the result put back as this script's step
      reaper.PreventUIRefresh(1)
      select_and_place_cursor(G.D)
      if G.wrap then wrap_commit_fwd(G.wrap) end
      if G.razorClear then
        for _, t2 in ipairs(G.razorClear) do reaper.GetSetMediaTrackInfo_String(t2, "P_RAZOREDITS", "", true) end
      end
      local S = snapshot_result()
      local top0, pre = G.undoTop, G.preSel
      G = nil   -- (its items may not survive the undo)
      undo_reaper_steps(top0)
      -- (the undo puts back the time selection and loop of the last undo point,
      -- which may be older than what you had: back to what they were at the press)
      if pre then
        reaper.GetSet_LoopTimeRange(true, true, pre.ls, pre.le, false)
        reaper.GetSet_LoopTimeRange(true, false, pre.ts, pre.te, false)
      end
      reaper.Undo_BeginBlock()
      apply_snapshot(S)
      reaper.Undo_EndBlock(name, -1)
      reaper.PreventUIRefresh(-1)
      reaper.UpdateArrange()
      return
    end
    -- The drag made no undo points, so this block captures the whole move
    reaper.Undo_BeginBlock()   -- (the automation was already moved while dragging)
    select_and_place_cursor(G.D)
    if G.wrap then wrap_commit_fwd(G.wrap) end
    if G.razorClear then
      for _, t2 in ipairs(G.razorClear) do reaper.GetSetMediaTrackInfo_String(t2, "P_RAZOREDITS", "", true) end
    end
    reaper.Undo_EndBlock(name, -1)
  else
    restore_selection()
    if G.copies then delete_copies_fwd() end    -- back home: no copy
    if G.wrap then wrap_restore_fwd(G.wrap) end -- back home: splits undone
    -- (nothing changed: REAPER's own "Clear razor edits" step is taken off too)
    if reaper_clear_on_top() then
      local pre = G.preSel
      undo_reaper_steps(G.undoTop)
      if pre then
        reaper.GetSet_LoopTimeRange(true, true, pre.ls, pre.le, false)
        reaper.GetSet_LoopTimeRange(true, false, pre.ts, pre.te, false)
      end
    end
  end
  G = nil
  reaper.UpdateArrange()
end

------------------------------------------------------------
-- Press: is this drag ours?
------------------------------------------------------------
local hoverCursor = nil   -- REAPER's cursor, last seen with the button up

local ALT = 16   -- JS_Mouse_GetState: Option (macOS) / Alt (Windows)

-- Option/Alt over a razor area (and while copying it): REAPER's "copy areas" cursor,
-- in place of the No action cursor REAPER shows there in Shuffle
local COPY_CURSOR_ID = 182   -- arrow with a plus (REAPER's own razor "copy areas" cursor can't be loaded by ID)
local copyCursor = nil
do
  local id = COPY_CURSOR_ID
  if id == 0 then id = tonumber(reaper.GetExtState(NS, "RazorCopyCursor")) or 0 end
  if id ~= 0 and reaper.JS_Mouse_LoadCursor then copyCursor = reaper.JS_Mouse_LoadCursor(id) end
end
local copyCursorShown = false
-- While ours shows, REAPER's own cursor changes are held back (it would flicker)
local function hold_cursor(on)
  if not (mouse.ARRANGE and reaper.JS_WindowMessage_Intercept) then return end
  if on then reaper.JS_WindowMessage_Intercept(mouse.ARRANGE, "WM_SETCURSOR", false)
  else reaper.JS_WindowMessage_Release(mouse.ARRANGE, "WM_SETCURSOR") end
end
local function show_copy_cursor(on)
  if on and copyCursor and reaper.JS_Mouse_SetCursor then
    if not copyCursorShown then hold_cursor(true) end
    reaper.JS_Mouse_SetCursor(copyCursor); copyCursorShown = true
  elseif not on and copyCursorShown then
    copyCursorShown = false
    hold_cursor(false)
    local arrow = reaper.JS_Mouse_LoadCursor and reaper.JS_Mouse_LoadCursor(32512)
    if arrow then reaper.JS_Mouse_SetCursor(arrow) end
  end
end

-- Ours, and is it a copy (Option/Alt-drag)? Other modifier drags stay REAPER's own.
local function our_press(it, sx, sy, mods)
  mods = mods or 0
  if not it or (mods ~= 0 and mods ~= ALT) then return false end
  local copy = mods == ALT
  local tool = wanted_tool()
  if tool == "grabber" then return true, copy end        -- edges and fades are locked there
  if tool == "smart" then
    if hoverCursor and mouse.REAPER_HANDLES[hoverCursor] then return false end
    local _, cy = reaper.JS_Window_ScreenToClient(mouse.ARRANGE, sx, sy)
    local top, h = mouse.item_rect(it)
    return (cy and h > 0 and cy >= top + h / 2) or false, copy   -- lower half moves items
  end
  return false
end

------------------------------------------------------------
-- Main loop
------------------------------------------------------------
local prevDown, lastTry = false, 0

local function stop()
  if G then restore() G = nil end
  -- (only while Shuffle still has the Multi tool: otherwise its settings were just put back)
  if upper_half_fwd and tools.shuffle_on() and wanted_tool() == "smart" then upper_half_fwd(nil) end
  if hover_razor_fwd then hover_razor_fwd(false) end
  show_copy_cursor(false)
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
  if not down and not G then
    hoverCursor = mouse.current_cursor()
    cache_razors()   -- (Option-drag copies razor areas even without Separation Mode)
    note_undo_top()
    local overRazor = razorCache ~= nil and mouse_over_razor()
    -- Multi tool's upper half: its own drags, except where a razor area takes them
    -- (Option/Alt-drags always over a razor area; plain ones with Separation Mode)
    local upper = mouse_upper_half()
    multi_upper_half(upper and { [0] = not (overRazor and separation_on()), [4] = not overRazor } or nil)
    hover_razor(overRazor)
    show_copy_cursor(overRazor and mods == ALT)
  elseif G then
    show_copy_cursor(G.copy or (G.pendingRazor and G.pendingRazor.copy) or false)
  end

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
      -- Separation: a plain press on a razor area shuffles what's in it
      local rtr, rinfo = reaper.GetTrackFromPoint(sx, sy)
      local ra, rb
      if ((separation_on() and (mods or 0) == 0) or mods == ALT) and rtr and (rinfo or 0) == 0 then
        local cx = reaper.JS_Window_ScreenToClient(mouse.ARRANGE, sx, sy)
        local pt = mouse.time_at(cx)
        if razor_cached_at(rtr, pt) then drop_razor_clear() end
        ra, rb = razor_press_area(rtr, pt)
        if ra then start_razor_press(rtr, ra, rb, pt, mods == ALT) end
      end
      if ra then
        -- (taken by Separation)
      else
        local mine, copy = our_press(it, sx, sy, mods)
        if mine then
          local cx = reaper.JS_Window_ScreenToClient(mouse.ARRANGE, sx, sy)
          start_drag(it, mouse.time_at(cx))
          if G and copy then G.copy = true end
        end
      end
    end
  elseif down then
    if G.pendingRazor then razor_drag() else drag() end
  else
    if G.pendingRazor then G = nil else release() end
  end

  prevDown = down
  reaper.defer(loop)
end

-- Started again while running (each time a tool is applied): REAPER stops this copy
-- and runs the new one, so an updated script always takes over
if reaper.set_action_options then reaper.set_action_options(1 | 2) end
if tools.repair_hover then tools.repair_hover() end   -- left switched by a copy that didn't stop cleanly
reaper.atexit(stop)
mouse.clicks_start()
loop()
