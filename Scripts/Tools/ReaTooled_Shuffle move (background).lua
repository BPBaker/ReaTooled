-- @description ReaTooled - Shuffle move (background, started in Shuffle mode)
-- @version 1.2.1
-- @date 2026.11.07
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Pro Tools' Shuffle for REAPER. Runs while Shuffle mode is on and the Move Tool or
--   the Multi tool is selected (it stops by itself otherwise).
--
--   Dragging an item reorders it among the items on its track:
--     - It leaves its place and what follows closes up; it goes back in at the item
--       edge nearest where you drop it, pushing what follows along.
--     - Gaps are kept, like empty items. In a gap with room, it can also go one
--       item-length right or left of where it was (nothing else moves).
--     - Dragged to another track, its own track closes up and it goes in at an item
--       edge there (on an empty track, at its time).
--     - The track shows the result while you drag; letting go makes one undo step and
--       leaves what moved selected. A plain click still just selects the item.
--     - Dragging a selected item moves the selected items on its track as one block
--       (with whatever lies between them).
--     - Option/Alt-drag copies: the copy goes in at the drop point, the original stays.
--
--   Crossfades:
--     - The item moves whole, as REAPER shows it. Pressing it cuts its neighbors where
--       it begins and ends, so its crossfades go (the audio stays in their sources);
--       let go where it started, they come back. Crossfades inside a block stay.
--     - Items crossfaded together stay together: the drop points there are the
--       crossfade's start and end, never its centre.
--     - Zoomed in, the inner edge of a fade is a drop point too (the item is split
--       there; the fade stays whole).
--     - Every new junction gets a crossfade of REAPER's default crossfade length while
--       auto-crossfade is on (Options > Auto-crossfade media items when editing), from
--       the audio past the cut; with it off, butt joints and no fades.
--
--   Razor areas: with Separation Mode on, dragging a razor area shuffles what's in it;
--   Option/Alt-dragging one copies it (with or without Separation Mode). A piece cut
--   out of a razor area keeps a fade only if the whole fade is inside the area; a fade
--   the area cuts through ends at the cut on what's left outside; the cuts get a short
--   safety fade.
--
--   Other tracks:
--     - Tracks grouped with the clicked track (media editing), items grouped with the
--       clicked item, and selected items on other tracks shuffle together, in sync.
--       Drop points are only where none of them would have to be split.
--     - With ripple editing all tracks, every track moves the same stretch of time:
--       items crossing it or the drop point are split there, and markers and regions
--       go along.
--     - With "Move envelope points with media items" on, track automation follows,
--       live (automation items don't move).
--     - Locked items never move or split.
--
--   Move Tool: any plain drag on an item. Multi tool: plain drags on an item's lower
--   half; its upper half, edges, fades and handles stay REAPER's.
-- @changelog
--   v1.2.1 No outline while what's dragged is back where it started
--   v1.2 While dragging, the items being moved have a yellow outline drawn on top, so they
--        can be seen where they overlap other items (Tools library 1.17)
--   v1.1.3 Cmd = all tracks is shared with the Trim Tool (7.10) too
--   v1.1.2 The drags switched off while the mouse is over a razor area are in the shared record
--          too, and are put back even when REAPER reports an item's lower half differently
--   v1.1.1 The click actions switched off for a drag, and REAPER's Cmd drags switched off
--          over a move zone or razor area, are kept in ReaTooled's shared record (Tools
--          library 1.16), so the left-edge ripple script switching some of the same ones off
--          nearby can't leave them off
--   v1.1 Cmd = all tracks: in Shuffle per-track, Cmd+drag on an item's move zone (Move Tool:
--        the whole item; Multi tool: the lower half) or on a razor area (any of the three
--        tools) is a Shuffle all tracks drag, Cmd+Option a copy. While Cmd is held over one,
--        REAPER switches to ripple all tracks (Shuffle shows it, without a tooltip) and back
--        afterwards; REAPER's own Cmd drags there (a new razor area) are off meanwhile
--   v1.0.2 With ripple editing all tracks, the other tracks' new junctions follow the same
--          rule as the dragged track: a crossfade with auto-crossfade on, else a butt joint
--   v1.0.1 Less flicker in other windows (Track Manager, Project Bay) while dragging: the
--          item selection is changed only where it differs
--   v1.0 First release

local NS          = "ReaTooled"
local TOOL_KEY    = "ShuffleMoveTool"    -- "grabber" / "smart" while wanted (set by the Tools library)
local HEARTBEAT   = "ShuffleMoveAlive"
local LINK_CMD_GUID = "_RSed328eb507619b18c1154efa1b048d816cfc2d0c"   -- Link Timeline and Edit Selection

local DEADBAND_PX     = 4      -- the mouse must move this far before the item is picked up
local DRAG_STAMP      = "ShuffleDragTime"   -- read by the Move Tool click: skip the click after a drag
local AUTOSCROLL_RATE = 0.5    -- pixels scrolled per frame, per pixel past the arrange's side
local MOVE_MARKERS    = true   -- ripple editing all tracks: markers and regions move along
local RIPPLE_ALL      = 40311  -- Options: Set ripple editing all tracks
-- Crossfades and cuts (see @about): the dragged item moves whole; its old neighbors are
-- cut where it began and ended. Every new junction between two items: a crossfade of
-- REAPER's default crossfade length while auto-crossfade is on, else a butt joint.
local AUTO_XFADE      = 40041  -- Options: Auto-crossfade media items when editing
local XFADE_SHAPE     = 1      -- fade shape of both sides of those crossfades
local FADE_DROP_PX    = 12     -- a fade's inner edge is a drop point when it's this wide on screen

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
-- each item reaches past it by half the overlap (its extension). Moving a stretch takes
-- out the segments between two edit points, so every track shifts by exactly the same
-- amount. What's dragged is widened to its items' real edges (start_drag: the item moves
-- whole, its old neighbors are cut there); everywhere else, an item that gets a new
-- neighbor is cut at its segment's edge (junctions_for), and new junctions get a
-- crossfade with auto-crossfade on. (Grouped tracks shuffling along keep the centres.)
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
local FADE_KEYS = { "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINLEN_AUTO", "D_FADEOUTLEN_AUTO",
                    "C_FADEINSHAPE", "C_FADEOUTSHAPE" }

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

-- Items whose fades, length or take offsets this drag has changed: only these are put
-- back each time the drop point changes
local function touch(it)
  if G.fadeSnap[it] then
    G.dirty = G.dirty or {}
    G.dirty[it] = true
  end
end

local function restore_fades()
  local dirty = G.dirty or {}
  G.dirty = {}
  for it in pairs(dirty) do
    local f = G.fadeSnap[it]
    if f and reaper.ValidatePtr2(0, it, "MediaItem*") then
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

local clean_junctions_fwd, junction_xfades_fwd, all_xfades_fwd   -- (below)

-- Items that are next to each other now but weren't at the click: where they overlap,
-- that's a crossfade (from an item's extension), so both fades are set to the overlap
-- (the extensions are cut off first, so now they never do)
local function junctions_for(segs)
  clean_junctions_fwd(segs)
  junction_xfades_fwd(segs)
end

local function note_neighbors(list)
  for i = 1, #list - 1 do G.nextOf[list[i].it] = list[i + 1].it end
end

------------------------------------------------------------
-- Ripple editing all tracks: every track moves the same stretch of time, like a
-- razor move of the whole project. Items crossing its start or end, or the drop
-- point, are split there (with short fades); markers and regions go along.
------------------------------------------------------------
-- REAPER's default crossfade length (as "Auto crossfade at edit cursor" reads it)
local function default_xfade()
  local ok, v = reaper.get_config_var_string("defsplitxfadelen")
  local n = ok and tonumber(v) or nil
  if n and n > 0 then return (n > 10) and (n / 1000) or n end
  ok, v = reaper.get_config_var_string("deffadelen")
  n = ok and tonumber(v) or nil
  return (n and n > 0) and n or 0.01
end

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
local function split_at(it, t, store, fade)
  local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  if not (pos + TOL < t and pos + len - TOL > t) then return nil end
  touch(it)
  local rec = { left = it, len = len,
                fout = reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN"),
                foutA = reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO"),
                foutS = reaper.GetMediaItemInfo_Value(it, "C_FADEOUTSHAPE") }
  local right = reaper.SplitMediaItem(it, t)
  if not right then return nil end
  rec.right = right
  store = store or G.splits
  store[#store + 1] = rec
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
  local f = fade or G.cutFade
  local fl, fr = math.min(f, (t - pos) / 2), math.min(f, (pos + len - t) / 2)
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", fl)
  if reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO") >= 0 then reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", fl) end
  reaper.SetMediaItemInfo_Value(right, "D_FADEINLEN", fr)
  if reaper.GetMediaItemInfo_Value(right, "D_FADEINLEN_AUTO") >= 0 then reaper.SetMediaItemInfo_Value(right, "D_FADEINLEN_AUTO", fr) end
  return right
end

-- Every other track back as it was at the click
local function all_restore()
  for i = #(G.allXRec or {}), 1, -1 do   -- (their crossfades undone)
    local r = G.allXRec[i]
    if reaper.ValidatePtr2(0, r.it, "MediaItem*") then
      for _, k in ipairs({ "D_POSITION", "D_LENGTH", "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINLEN_AUTO",
                           "D_FADEOUTLEN_AUTO", "C_FADEINSHAPE", "C_FADEOUTSHAPE" }) do
        reaper.SetMediaItemInfo_Value(r.it, k, r[k])
      end
      for tk, v in pairs(r.offs) do
        if reaper.ValidatePtr2(0, tk, "MediaItem_Take*") then reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", v) end
      end
    end
  end
  G.allXRec, G.allXSeen = nil, nil
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

-- Copying a razor area that starts inside an item: its "copy at the start" drop point
-- splits that item there (plainly, as a razor edit would), on each track that moves.
-- The split is healed as soon as the copy goes anywhere else, back home, or is
-- cancelled; dropped there, it stays.
local function mid_covering(list, T)
  local c = {}
  for _, r in ipairs(list) do
    if r.pos + TOL < T and r.pos + r.len - TOL > T then c[#c + 1] = r end
  end
  return c
end

-- Can this row be split at T? (one item there at most: not inside a crossfade)
local function mid_ok(list, T) return #mid_covering(list, T) <= 1 end

local function heal_mid()
  if not G.midSplits then return end
  for i = #G.midSplits, 1, -1 do
    local s = G.midSplits[i]
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
  G.midSplits, G.midBy = nil, nil
end

-- A row's segments with its items split at the razor area's edges (G.splitTs; each
-- only where it falls inside an item). The splits are made the first time and kept
-- (put back after the fades are restored each time the copy moves)
local function split_row(row)
  local list = {}
  for _, x in ipairs(row.list) do list[#list + 1] = { it = x.it, pos = x.pos, len = x.len } end
  for _, T in ipairs(G.splitTs or {}) do
    local cov = mid_covering(list, T)
    if #cov == 1 then
      local r = cov[1]
      local key = tostring(row.tr) .. "@" .. T
      G.midSplits, G.midBy = G.midSplits or {}, G.midBy or {}
      local rec = G.midBy[key]
      touch(r.it)
      if not rec then
        reaper.SetMediaItemInfo_Value(r.it, "D_POSITION", r.pos)
        reaper.SetMediaItemInfo_Value(r.it, "D_LENGTH", r.len)
        rec = { left = r.it, len = r.len,
                fout = reaper.GetMediaItemInfo_Value(r.it, "D_FADEOUTLEN"),
                foutA = reaper.GetMediaItemInfo_Value(r.it, "D_FADEOUTLEN_AUTO"),
                foutS = reaper.GetMediaItemInfo_Value(r.it, "C_FADEOUTSHAPE") }
        local right = reaper.SplitMediaItem(r.it, T)
        if right then
          rec.right = right
          -- exactly at T, whatever REAPER's split preferences add
          local rpos = reaper.GetMediaItemInfo_Value(right, "D_POSITION")
          if math.abs(rpos - T) > 1e-9 then
            for k = 0, reaper.CountTakes(right) - 1 do
              local tk = reaper.GetTake(right, k)
              if tk then
                reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
                  + (T - rpos) * reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"))
              end
            end
            reaper.SetMediaItemInfo_Value(right, "D_POSITION", T)
          end
          reaper.SetMediaItemInfo_Value(right, "D_LENGTH", r.pos + r.len - T)
          reaper.SetMediaItemInfo_Value(r.it, "D_LENGTH", T - r.pos)
          rec.after = { reaper.GetMediaItemInfo_Value(r.it, "D_FADEOUTLEN"),
                        reaper.GetMediaItemInfo_Value(r.it, "D_FADEOUTLEN_AUTO"),
                        reaper.GetMediaItemInfo_Value(r.it, "C_FADEOUTSHAPE") }
          G.midSplits[#G.midSplits + 1] = rec
          G.midBy[key] = rec
        else
          rec = nil
        end
      else
        -- (the fades were just put back as they were at the click: split again)
        reaper.SetMediaItemInfo_Value(r.it, "D_LENGTH", T - r.pos)
        reaper.SetMediaItemInfo_Value(r.it, "D_FADEOUTLEN", rec.after[1])
        reaper.SetMediaItemInfo_Value(r.it, "D_FADEOUTLEN_AUTO", rec.after[2])
        reaper.SetMediaItemInfo_Value(r.it, "C_FADEOUTSHAPE", rec.after[3])
      end
      if rec then
        local out = {}
        for _, x in ipairs(list) do
          if x.it == r.it then
            out[#out + 1] = { it = r.it, pos = r.pos, len = T - r.pos }
            out[#out + 1] = { it = rec.right, pos = T, len = r.pos + r.len - T }
          else
            out[#out + 1] = x
          end
        end
        list = out
      end
    end
  end
  return build_row(list)
end

------------------------------------------------------------
-- Fade drop points: the inner edge of a fade or crossfade.
-- A fade-in's end or a fade-out's start: the item is split there (the fade stays
-- whole in its piece). A crossfade's end: the next item is trimmed to it (the
-- crossfade stays with the earlier item); its start: the earlier item is trimmed to it
-- (the crossfade stays with the next). Done only while
-- that drop point is used: undone as soon as the drag goes anywhere else.
------------------------------------------------------------
-- (The old neighbors as they are once what moves has left, cut where
-- it began and ended; not when copying, where they stay as they were)
local function claimed(it)
  return G.claimSnap and not G.copy and G.claimSnap[it] or nil
end

local function snap_val(it, k)
  local c = claimed(it)
  if c and c[k] ~= nil then return c[k] end
  local f = G.fadeSnap[it]
  if f and f[k] ~= nil then return f[k] end
  return reaper.GetMediaItemInfo_Value(it, k)
end

local function fade_len(it, which)
  local au = snap_val(it, which == "in" and "D_FADEINLEN_AUTO" or "D_FADEOUTLEN_AUTO")
  if au and au > 0 then return au end
  return snap_val(it, which == "in" and "D_FADEINLEN" or "D_FADEOUTLEN") or 0
end

-- A row's fade drop points { k = -3, t =, fade = "in"/"out", x = crossfade?, w = fade length }
local function fade_bounds(R, list)
  local out = {}
  -- A crossfade's start and end are drop points instead of its
  -- centre (whatever the zoom); what's dropped there goes between the two items, the
  -- one on the other side keeps the whole crossfade's length, the near one is cut
  -- (not with grouped tracks, where the drag uses the crossfades' centres)
  local keepX = G.claim ~= nil
  local skip = {}   -- (copying a razor area: items split at its edges have none)
  if G.splitTs and list then
    for _, T in ipairs(G.splitTs) do
      for _, r in ipairs(mid_covering(list, T)) do skip[r.it] = true end
    end
  end
  local st = seg_starts(R)
  for j, sg in ipairs(R) do
    local Z = sg.item
    if Z and not skip[Z] and reaper.ValidatePtr2(0, Z, "MediaItem*") then
      local s, L = st[j], sg.len
      local p = s + sg.off
      local e = p + snap_val(Z, "D_LENGTH")
      local P, N = R[j - 1], R[j + 1]
      local tin, xin, win, tout, xout, wout
      if P and P.item then
        local pe = st[j - 1] + P.off + snap_val(P.item, "D_LENGTH")
        if pe > p + TOL then
          if keepX then tin, xin, win = pe, true, pe - p else tin = false end
        end
      end
      if tin == nil then
        local f = fade_len(Z, "in")
        if f > TOL then tin, win = p + f, f end
      end
      if N and N.item then
        local np = st[j + 1] + N.off
        if e > np + TOL then
          if keepX then tout, xout, wout = np, true, e - np else tout = false end
        end
      end
      if tout == nil then
        local f = fade_len(Z, "out")
        if f > TOL then tout, wout = e - f, f end
      end
      if tin and tout and tin > tout + TOL then tin, tout = nil, nil end   -- (the fades overlap)
      if tin == false then tin = nil end
      if tout == false then tout = nil end
      if tin and tin > s + TOL and tin < s + L - TOL then
        out[#out + 1] = { k = -3, t = tin, fade = "in", x = xin, w = win }
      end
      if tout and tout > s + TOL and tout < s + L - TOL and not (tin and math.abs(tout - tin) <= TOL) then
        out[#out + 1] = { k = -3, t = tout, fade = "out", x = xout, w = wout }
      end
    end
  end
  return out
end

-- No drop points at the centre of a crossfade (items crossfaded together stay together)
local function drop_xfade_centres(bounds, R)
  if not G.claim then return bounds end
  local st = seg_starts(R)
  local out = {}
  for _, b in ipairs(bounds) do
    local centre = false
    if not (b.fade or b.split or b.tail) and b.k and b.k >= 1 then
      local P, N = R[b.k], R[b.k + 1]
      if P and P.item and N and N.item then
        local c = st[b.k + 1]
        local pe = st[b.k] + P.off + snap_val(P.item, "D_LENGTH")
        centre = pe > c + TOL and (c + N.off) < c - TOL
      end
    end
    if not centre then out[#out + 1] = b end
  end
  return out
end

local function add_fade_bounds(bounds, R, list)
  for _, fb in ipairs(fade_bounds(R, list)) do bounds[#bounds + 1] = fb end
  return bounds
end

local function razor_drag_on() return G.wrap ~= nil or G.razorClear ~= nil end

-- The fade at a cut Shuffle makes: REAPER's default fade length for razor areas, else none
-- (junctions get crossfades instead, with auto-crossfade on)
local function safety_fade()
  if not G.safeFade then
    G.safeFade = razor_drag_on() and default_fade() or 0
  end
  return G.safeFade
end

local function set_fade(it, which, v)
  touch(it)
  local k = which == "in" and "D_FADEINLEN" or "D_FADEOUTLEN"
  reaper.SetMediaItemInfo_Value(it, k, v)
  if reaper.GetMediaItemInfo_Value(it, k .. "_AUTO") >= 0 then reaper.SetMediaItemInfo_Value(it, k .. "_AUTO", v) end
end

-- The start of an item cut off (its audio stays in place)
local function trim_start(it, cut)
  touch(it)
  local len = snap_val(it, "D_LENGTH") - cut
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", len)
  for t = 0, reaper.CountTakes(it) - 1 do
    local tk = reaper.GetTake(it, t)
    if tk then
      local o = (G.offsSnap[it] and G.offsSnap[it][tk]) or reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
      local c = claimed(it)
      reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", o + ((c and c.shift or 0) + cut) * reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"))
    end
  end
  set_fade(it, "in", math.min(safety_fade(), len / 2))
end

local function trim_end(it, keep)
  touch(it)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", keep)
  set_fade(it, "out", math.min(safety_fade(), keep / 2))
end

-- Wherever an item's neighbor (the next segment) isn't the one
-- it had at the click, what reaches past its segment is cut off, with a safety fade
local function clip_item(it, s0, s1, keepL, keepR)
  if not reaper.ValidatePtr2(0, it, "MediaItem*") then return end
  local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local ns = (not keepL and p < s0 - TOL) and s0 or p
  local ne = (not keepR and e > s1 + TOL) and s1 or e
  if (ns == p and ne == e) or ne <= ns + TOL then return end
  touch(it)
  local f = math.min(safety_fade(), (ne - ns) / 2)
  if ns > p then
    for t = 0, reaper.CountTakes(it) - 1 do
      local tk = reaper.GetTake(it, t)
      if tk then
        reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
          + (ns - p) * reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"))
      end
    end
    reaper.SetMediaItemInfo_Value(it, "D_POSITION", ns)
    set_fade(it, "in", f)
  end
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", ne - ns)
  if ne < e then set_fade(it, "out", f) end
end

local function first_last(sg)   -- a segment's first and last item
  if not sg then return nil, nil end
  if sg.item then return sg.item, sg.item end
  if sg.members and #sg.members > 0 then return sg.members[1].item, sg.members[#sg.members].item end
  return nil, nil
end

local function clean_junctions(segs)
  local st = seg_starts(segs)
  for j, sg in ipairs(segs) do
    local s0, s1 = st[j], st[j] + sg.len
    local _, prevLast = first_last(segs[j - 1])
    local nextFirst = first_last(segs[j + 1])
    if sg.item then
      local kl = prevLast ~= nil and G.nextOf[prevLast] == sg.item
      local kr = nextFirst ~= nil and G.nextOf[sg.item] == nextFirst
      if not (kl and kr) then clip_item(sg.item, s0, s1, kl, kr) end   -- (same neighbors: nothing to cut)
    elseif sg.members then
      local n = #sg.members
      for i, m in ipairs(sg.members) do
        local kl = i > 1 or (prevLast ~= nil and G.nextOf[prevLast] == m.item)
        local kr = i < n or (nextFirst ~= nil and G.nextOf[m.item] == nextFirst)
        if not (kl and kr) then clip_item(m.item, s0, s1, kl, kr) end
      end
    end
  end
end
clean_junctions_fwd = clean_junctions

-- Source audio an item has before its start and after its end (seconds)
local function handle_room(it)
  local tk = reaper.GetActiveTake(it)
  if not tk then return 0, 0 end
  if reaper.GetMediaItemInfo_Value(it, "B_LOOPSRC") == 1 then return math.huge, math.huge end
  local src = reaper.GetMediaItemTake_Source(tk)
  if not src then return 0, 0 end
  local srclen, qn = reaper.GetMediaSourceLength(src)
  if qn or not srclen then return 0, 0 end
  local rate = reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
  if rate <= 0 then return 0, 0 end
  local offs = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  return math.max(0, offs / rate), math.max(0, (srclen - offs) / rate - len)
end

-- A crossfade of REAPER's default crossfade length at c, where A ends and B starts (butted):
-- centred when both have audio past the cut, else from the side that has some, else none.
-- before(it): called before an item is changed (to note how it was)
local function xfade_pair(A, B, c, before)
  local aPos, aLen = reaper.GetMediaItemInfo_Value(A, "D_POSITION"), reaper.GetMediaItemInfo_Value(A, "D_LENGTH")
  local bPos, bLen = reaper.GetMediaItemInfo_Value(B, "D_POSITION"), reaper.GetMediaItemInfo_Value(B, "D_LENGTH")
  if math.abs(aPos + aLen - c) > 1e-6 or math.abs(bPos - c) > 1e-6 then return end   -- (not butted there)
  G.xfadeLen = G.xfadeLen or default_xfade()
  local half = G.xfadeLen / 2
  local _, aAfter = handle_room(A)
  local bBefore = handle_room(B)
  local ra = math.max(0, math.min(aAfter, bLen / 2))        -- (A reaches over B's start)
  local rb = math.max(0, math.min(bBefore, aLen / 2, c))    -- (B reaches back over A's end)
  local hA = math.min(half, ra)
  local hB = math.min(half, rb)
  if hA < half then hB = math.min(2 * half - hA, rb) end
  if hB < half then hA = math.min(2 * half - hB, ra) end
  local x = hA + hB
  if x <= 1e-4 then return end
  if before then before(A); before(B) end
  if hA > 0 then reaper.SetMediaItemInfo_Value(A, "D_LENGTH", aLen + hA) end
  set_fade(A, "out", x)
  reaper.SetMediaItemInfo_Value(A, "C_FADEOUTSHAPE", XFADE_SHAPE)
  if hB > 0 then
    for t = 0, reaper.CountTakes(B) - 1 do
      local tk = reaper.GetTake(B, t)
      if tk then
        reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
          - hB * reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"))
      end
    end
    reaper.SetMediaItemInfo_Value(B, "D_POSITION", c - hB)
    reaper.SetMediaItemInfo_Value(B, "D_LENGTH", bLen + hB)
  end
  set_fade(B, "in", x)
  reaper.SetMediaItemInfo_Value(B, "C_FADEINSHAPE", XFADE_SHAPE)
end

-- Auto-crossfade on (not for razor areas): every junction between items that weren't next
-- to each other at the click gets a crossfade of REAPER's default crossfade length, from
-- the audio past the cut (else it stays a butt joint)
local function junction_xfades(segs)
  if razor_drag_on() then return end
  if G.autoX == nil then G.autoX = reaper.GetToggleCommandState(AUTO_XFADE) == 1 end
  if not G.autoX then return end
  local st = seg_starts(segs)
  for j = 1, #segs - 1 do
    local _, A = first_last(segs[j])
    local B = first_last(segs[j + 1])
    if A and B and G.nextOf[A] ~= B and reaper.ValidatePtr2(0, A, "MediaItem*") and reaper.ValidatePtr2(0, B, "MediaItem*") then
      local c = st[j + 1]
      xfade_pair(A, B, st[j + 1])
    end
  end
end
junction_xfades_fwd = junction_xfades

-- Ripple editing all tracks: the other tracks' new junctions (where the moved stretch
-- starts and ends, and where the gap it left closes up) follow the same rule as the
-- dragged track: a crossfade with auto-crossfade on, else a butt joint. How the items
-- were is noted, so all_restore puts them back.
local ALLX_KEYS = { "D_POSITION", "D_LENGTH", "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINLEN_AUTO",
                    "D_FADEOUTLEN_AUTO", "C_FADEINSHAPE", "C_FADEOUTSHAPE" }
local function all_rec(it)
  G.allXSeen = G.allXSeen or {}
  if G.allXSeen[it] then return end
  G.allXSeen[it] = true
  local r = { it = it, offs = {} }
  for _, k in ipairs(ALLX_KEYS) do r[k] = reaper.GetMediaItemInfo_Value(it, k) end
  for t = 0, reaper.CountTakes(it) - 1 do
    local tk = reaper.GetTake(it, t)
    if tk then r.offs[tk] = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") end
  end
  G.allXRec = G.allXRec or {}
  G.allXRec[#G.allXRec + 1] = r
end

local function all_xfades(times)
  if razor_drag_on() then return end
  if G.autoX == nil then G.autoX = reaper.GetToggleCommandState(AUTO_XFADE) == 1 end
  if not G.autoX then return end
  local rows = {}   -- (items by track and lane)
  local function add(it)
    if it and reaper.ValidatePtr2(0, it, "MediaItem*") then
      local key = tostring(reaper.GetMediaItem_Track(it)) .. ":" .. reaper.GetMediaItemInfo_Value(it, "I_FIXEDLANE")
      rows[key] = rows[key] or {}
      rows[key][#rows[key] + 1] = it
    end
  end
  for _, o in ipairs(G.others) do if not o.locked then add(o.it) end end
  for _, sp in ipairs(G.splits) do add(sp.right) end
  for _, c in ipairs(G.allCopies or {}) do add(c.it) end
  for _, list in pairs(rows) do
    for _, J in ipairs(times) do
      local L, R
      for _, it in ipairs(list) do
        local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        if math.abs(p - J) <= 1e-6 then R = it end
        if math.abs(p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH") - J) <= 1e-6 then L = it end
      end
      if L and R and L ~= R then xfade_pair(L, R, J, all_rec) end
    end
  end
end
all_xfades_fwd = all_xfades



local function heal_fade()
  if not (G and G.fadeSplits) then return end
  for i = #G.fadeSplits, 1, -1 do
    local s = G.fadeSplits[i]
    if reaper.ValidatePtr2(0, s.right, "MediaItem*") then
      reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(s.right), s.right)
    end
    -- (the left piece's length and fades are put back with everyone's fades)
  end
  G.fadeSplits = nil
end

-- Row R cut at fade drop point b: the new row and the drop point in it (nil if it can't be)
local function fade_row(R, b)
  local st = seg_starts(R)
  for j, sg in ipairs(R) do
    if sg.item and b.t > st[j] + TOL and b.t < st[j] + sg.len - TOL then
      local Z, s, L, T = sg.item, st[j], sg.len, b.t
      local p = s + sg.off
      local F = {}
      for i = 1, j - 1 do F[i] = R[i] end
      local nb, nextI
      if b.x and b.fade == "in" then          -- crossfade's end: this item starts there
        local P = R[j - 1]
        if not (P and P.item) then return nil end
        trim_start(Z, T - p)
        set_fade(P.item, "out", math.min(safety_fade(), snap_val(P.item, "D_LENGTH") / 2))
        F[j - 1] = { item = P.item, len = P.len + (T - s), off = P.off, pos0 = P.pos0 }
        F[j] = { item = Z, len = s + L - T, off = 0, pos0 = sg.pos0 }
        nb, nextI = { k = j - 1, t = T }, j + 1
      elseif b.x and b.fade == "out" then     -- crossfade's start: this item ends there
        local N = R[j + 1]
        if not (N and N.item) then return nil end
        trim_end(Z, T - p)
        set_fade(N.item, "in", math.min(safety_fade(), snap_val(N.item, "D_LENGTH") / 2))
        F[j] = { item = Z, len = T - s, off = sg.off, pos0 = sg.pos0 }
        local ns = st[j + 1]
        F[j + 1] = { item = N.item, len = ns + N.len - T, off = ns + N.off - T, pos0 = N.pos0 }
        nb, nextI = { k = j, t = T }, j + 2
      else                                    -- a fade's inner edge: split there
        local cur = reaper.GetMediaItemInfo_Value(Z, "D_POSITION")
        G.fadeSplits = G.fadeSplits or {}
        local Y = split_at(Z, cur + (T - p), G.fadeSplits, safety_fade())
        if not Y then return nil end
        G.nextOf[Y] = G.nextOf[Z]
        F[j] = { item = Z, len = T - s, off = sg.off, pos0 = sg.pos0 }
        F[j + 1] = { item = Y, len = s + L - T, off = 0, pos0 = T }
        nb, nextI = { k = j, t = T }, j + 1
      end
      for i = nextI, #R do F[#F + 1] = R[i] end
      return F, nb
    end
  end
  return nil
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
  -- new junctions: the moved stretch's start and end, and where the gap it left closed
  all_xfades_fwd({ T, T + G.len, (G.a >= T - TOL) and (G.a + G.len) or G.a })
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
local razor_starting = false                            -- (start_drag called for a razor area)
local click_actions_off_fwd                                    -- (below)
local delete_copies_fwd                                 -- (copying, below)
local upper_half_fwd                                    -- (Multi tool upper half, below)

-- An item's crossfade audio can't go before the project start: it is trimmed there
-- (the timing of everything stays the same)
local function trim_at_start(it, cut)
  touch(it)
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
-- (only what differs is changed: every selection change makes other windows, such as the
-- Track Manager and Project Bay, redraw)
local function select_only(list)
  local want = {}
  for _, it in ipairs(list) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then want[it] = true end
  end
  local cur = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do cur[#cur + 1] = reaper.GetSelectedMediaItem(0, i) end
  local was = {}
  for _, it in ipairs(cur) do
    was[it] = true
    if not want[it] then reaper.SetMediaItemSelected(it, false) end
  end
  for it in pairs(want) do
    if not was[it] then reaper.SetMediaItemSelected(it, true) end
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
  heal_mid()
  heal_fade()
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
  local bounds = drop_xfade_centres(add_fade_bounds(row_bounds(R, nil), R, list), R)
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
  -- What moves runs from the first item's start to the last one's end (crossfades and all);
  -- the neighbors it was crossfaded with are cut there once it moves
  local all0 = reaper.GetToggleCommandState(RIPPLE_ALL) == 1
  local fset = all0 and {} or follower_tracks(D, tr)
  local claim = nil
  if not razor_starting and next(fset) == nil then
    local first, last = segs[i1], segs[i2]
    local fPos = st[i1] + first.off
    local lEnd = st[i2] + last.off + reaper.GetMediaItemInfo_Value(last.item, "D_LENGTH")
    local bEnd = a + len
    local ns, ne = math.min(a, fPos), math.max(bEnd, lEnd)
    local ok, P, N = true, nil, nil
    if ns < a - TOL then
      P = segs[i1 - 1]
      ok = P and P.item and ns > st[i1 - 1] + TOL and (st[i1 - 1] + P.off) < ns - TOL
    end
    if ok and ne > bEnd + TOL then
      N = segs[i2 + 1]
      local nEnd = N and N.item and (st[i2 + 1] + N.off + reaper.GetMediaItemInfo_Value(N.item, "D_LENGTH"))
      ok = N and N.item and ne < st[i2 + 1] + N.len - TOL and nEnd > ne + TOL
    end
    if ok then
      claim = {}
      local R2 = {}
      for i = 1, i1 - 2 do R2[#R2 + 1] = segs[i] end
      if i1 > 1 then
        local pv = segs[i1 - 1]
        if P then
          R2[#R2 + 1] = { item = pv.item, len = pv.len - (a - ns), off = pv.off, pos0 = pv.pos0 }
          claim.P, claim.pKeep = pv.item, ns - (st[i1 - 1] + pv.off)
        else
          R2[#R2 + 1] = pv
        end
      end
      if i2 < #segs then
        local nx = segs[i2 + 1]
        if N then
          R2[#R2 + 1] = { item = nx.item, len = nx.len - (ne - bEnd), off = 0, pos0 = nx.pos0 }
          claim.N, claim.nCut = nx.item, ne - (st[i2 + 1] + nx.off)
        else
          R2[#R2 + 1] = nx
        end
      end
      for i = i2 + 2, #segs do R2[#R2 + 1] = segs[i] end
      for _, m in ipairs(block.members) do m.off = m.off + (a - ns) end
      a, len = ns, ne - ns
      block.pos0, block.len = a, len
      R = R2
    end
  end
  local bounds = row_bounds(R, a)
  -- Its own edges, when it sits in a gap with room: one length right (its start where
  -- its end was) or left (its end where its start was). The gap is split, so nothing
  -- else moves.
  for _, T in ipairs({ a + len, a - len }) do
    local b = cut_at(R, T)
    if b and b.split then bounds[#bounds + 1] = b end
  end

  G = { fadeSnap = {}, offsSnap = {}, nextOf = {}, envSnap = {} }   -- (filled below; needed by the helpers)
  G.claim = claim
  snap_fades(list); note_neighbors(list)
  if claim and (claim.P or claim.N) then
    G.claimSnap = {}
    local sf = safety_fade()
    local function cs(it, which, len, shift)
      local f = G.fadeSnap[it]
      local k = which == "in" and "D_FADEINLEN" or "D_FADEOUTLEN"
      local c = { D_LENGTH = len, shift = shift or 0, p0 = reaper.GetMediaItemInfo_Value(it, "D_POSITION") }
      c[k] = math.min(sf, len / 2)
      c[k .. "_AUTO"] = (f[k .. "_AUTO"] >= 0) and c[k] or f[k .. "_AUTO"]
      G.claimSnap[it] = c
    end
    if claim.P then cs(claim.P, "out", claim.pKeep) end
    if claim.N then cs(claim.N, "in", G.fadeSnap[claim.N].D_LENGTH - claim.nCut, claim.nCut) end
  end
  add_fade_bounds(bounds, R, list)
  bounds = drop_xfade_centres(bounds, R)

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
    G.all, G.splits, G.cutFade = true, {}, 0   -- (plain cuts)
    if MOVE_MARKERS then G.markSnap = snap_markers() end
  end

  -- Tracks that shuffle along: the same stretch out, the same place back in
  local followers = {}
  for ftr in pairs(fset) do
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
local function add_copy_at_start(bounds, R, a, list)
  local out = {}
  for _, bd in ipairs(bounds) do
    if bd.k == -1 or bd.split or math.abs(bd.t - a) > TOL then out[#out + 1] = bd end
  end
  local ins = cut_at(R, a)
  if ins then ins.ins = true; out[#out + 1] = ins
  elseif list and mid_ok(list, a) then
    -- (a razor area starting inside an item: that item is split there when it's used)
    out[#out + 1] = { k = -2, t = a, ins = true, mid = true }
  end
  return out
end

-- Copying a razor area: its own end is a drop point too (the copy right after the
-- original area, like a duplicate), besides the item edges around it. Inside an item,
-- that item is split there when it's used (healed if the copy moves on).
local function add_copy_at_end(bounds, R, T, list)
  for _, bd in ipairs(bounds) do
    if bd.k ~= -1 and math.abs(bd.t - T) <= TOL then return bounds end   -- (already one)
  end
  local e = cut_at(R, T)
  if e then e.ins, e.endpt = true, true; bounds[#bounds + 1] = e
  elseif list and mid_ok(list, T) then
    bounds[#bounds + 1] = { k = -2, t = T, ins = true, mid = true, endpt = true }
  end
  return bounds
end

-- Where the mouse picks it: halfway to the next drop point on the left (at most
-- half the copy's length to the left of the start)
local function copy_at_start_pick(bounds, a, len)
  local ins, prev = nil, nil
  for _, bd in ipairs(bounds) do
    if bd.ins and not bd.endpt then ins = bd
    elseif not bd.fade and bd.t < a - TOL and (not prev or bd.t > prev) then prev = bd.t end
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
      for _, F in ipairs(G.followers) do
        if bd.mid then
          if not mid_ok(F.list, bd.t) then free = false break end
        elseif not cut_at(F.R, bd.t) then free = false break end
      end
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
  local bounds = drop_xfade_centres(add_fade_bounds(row_bounds(G.src.R, G.a), G.src.R, G.src.list), G.src.R)
  bounds[#bounds + 1] = { k = -1, t = G.a }   -- back home: no copy
  -- (its start may be inside the item before it: no split there)
  bounds = add_copy_at_start(bounds, G.src.R, G.a, (not G.claim) and G.src.list or nil)
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
  -- A razor area copied with every track moving: every track shows the area split out
  -- at its edges, as the lead track does (healed with the rest when it goes back home)
  for _, ts in ipairs(G.splitTs or {}) do
    for i = 1, #cur do
      local right = split_at(cur[i], ts)
      if right then cur[#cur + 1] = right end
    end
  end
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
  all_xfades_fwd({ T, T + G.len })   -- (the copy's start and end)
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
  local zoom = reaper.GetHZoomLevel()   -- (pixels per second)
  for _, b in ipairs(bounds) do
    if not b.dead and (not b.fade or b.x or b.w * zoom >= FADE_DROP_PX) then
      local d = math.abs((b.pick or b.t) - desired)
      if d < bestD then best, bestD = b, d end
    end
  end
  return best
end

local function at_start(tr, b)
  return tr == G.src.tr and b and not b.split and not b.ins and math.abs(b.t - G.a) <= TOL
end

-- The old neighbors cut where what moves began and ended, and its own
-- crossfades gone (from the press on; put back only if it's let go where it started)
local function apply_claim()
  if not G.copy then
    for it, c in pairs(G.claimSnap or {}) do   -- (cut where what moves began and ended)
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        touch(it)
        for k, v in pairs(c) do
          if k ~= "shift" and k ~= "p0" then reaper.SetMediaItemInfo_Value(it, k, v) end
        end
        if c.shift > 0 then
          reaper.SetMediaItemInfo_Value(it, "D_POSITION", c.p0 + c.shift)   -- (its audio stays in place)
          for t = 0, reaper.CountTakes(it) - 1 do
            local tk = reaper.GetTake(it, t)
            if tk and G.offsSnap[it] and G.offsSnap[it][tk] then
              reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", G.offsSnap[it][tk] + c.shift * reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"))
            end
          end
        end
      end
    end
  end
  local ms = G.Dslot.members
  local f1, f2 = ms[1] and ms[1].item, ms[#ms] and ms[#ms].item
  if G.claim.P and f1 and reaper.ValidatePtr2(0, f1, "MediaItem*") then
    set_fade(f1, "in", math.min(safety_fade(), reaper.GetMediaItemInfo_Value(f1, "D_LENGTH") / 2))
  end
  if G.claim.N and f2 and reaper.ValidatePtr2(0, f2, "MediaItem*") then
    set_fade(f2, "out", math.min(safety_fade(), reaper.GetMediaItemInfo_Value(f2, "D_LENGTH") / 2))
  end
end

-- (a fade drop point that can't be used after all: never offered again)
local function fade_failed(b)
  b.dead = true
  G.b = nil
  reaper.PreventUIRefresh(-1)
end

-- Show D at drop point b of track tr (and the source track closed up)
local function place(tr, b)
  reaper.PreventUIRefresh(1)
  local home = at_start(tr, b)
  -- Copying a razor area: once the copy leaves home, the items the area starts or ends
  -- inside are split at its edges (showing what was copied), until it's back home
  local splitting = G.splitTs ~= nil and not home
  if not splitting then heal_mid() end
  heal_fade()
  if G.all then all_restore() end
  restore_fades()
  local claimHome = home and G.claim ~= nil and not G.copy   -- (its crossfades stay gone, even at home)
  if G.claim and (not home or claimHome) then apply_claim() end
  for t2, row in pairs(G.rows) do
    if row and t2 ~= tr and t2 ~= G.src.tr then restore_list(row.list) end   -- tracks left behind
  end
  local SR = splitting and split_row(G.src) or G.src.R
  automation_apply(tr, (not home) and b or nil)
  if home and claimHome then
    put_D_on(G.src.tr)                                  -- (where it was, its old neighbors cut)
    apply_positions(layout(insert(G.src.R, b, { G.Dslot })))
  elseif home then
    put_D_on(G.src.tr)
    restore_list(G.src.list)
    for _, F in ipairs(G.followers) do restore_list(F.list) end
    if G.copy then copy_home() end
  elseif tr == G.src.tr then
    put_D_on(tr)
    local sb = b
    if b.fade then
      SR, sb = fade_row(SR, b)                         -- (a fade's inner edge: cut there)
      if not SR then return fade_failed(b) end
    elseif splitting then sb = cut_at(SR, b.t) or b end   -- (the same drop point in the split row)
    local F1 = insert(SR, sb, { G.Dslot })
    local pos = layout(F1); apply_positions(pos); junctions_for(F1)
    for _, F in ipairs(G.followers) do
      local FR = splitting and split_row(F) or F.R
      local fb = cut_at(FR, b.t)
      local FF = insert(FR, fb, F.blk)
      local fpos = layout(FF); apply_positions(fpos); junctions_for(FF)
    end
    if G.all then
      if G.copy then all_apply_copy(b.t) else all_apply(b.t) end
    end
  else
    if G.copy then                                                                       -- copying: source stays
      restore_list(G.src.list)
      if splitting then apply_positions(layout(SR)) end                                 -- (split, in place)
    else
      local spos = layout(G.src.R); apply_positions(spos); junctions_for(G.src.R) -- source closes up
    end
    local row = G.rows[tr]
    put_D_on(tr)
    local RR, rb = row.R, b
    if b.fade then
      RR, rb = fade_row(row.R, b)
      if not RR then return fade_failed(b) end
    end
    local F1 = insert(RR, rb, { G.Dslot })
    local pos = layout(F1); apply_positions(pos); junctions_for(F1)              -- target opens a slot
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
    if click_actions_off_fwd then click_actions_off_fwd() end
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

-- Split items, fill the empty space and select the pieces; returns the undo record
-- and the piece to drag (nil and a reason if it can't be done)
local function razor_prepare(tr, a, b, pressTime)
  local W = { created = {}, chunks = {}, temps = {}, razorSnap = {}, selSnap = {}, recreate = {} }
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
  local cutIn, cutOut = {}, {}   -- pieces whose start / end is one of those cuts
  local origOf, leftRem, rightRem = {}, {}, {}   -- (the item each piece came from, as it was;
                                                 --  what's left outside the area on each side)
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
          local o = origOf[it] or {
            p = p, e = e,
            fin = math.max(reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN"), reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO")),
            fout = math.max(reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN"), reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO")),
          }
          local right = reaper.SplitMediaItem(it, cut)
          if right then
            W.created[right] = true
            origOf[it], origOf[right] = o, o
            if cut == a then cutIn[right] = true; leftRem[it] = true
            else cutOut[it] = true; rightRem[right] = true end
          end
        end
      end
    end
  end
  -- Fades inside the area: a razor area has no fades of its own, so a piece keeps a fade
  -- (or crossfade) only if the whole of it is inside the area; a fade the area cuts
  -- through, and the cut edges themselves, get only a short safety fade
  do
    local safe = default_fade()
    local function cap(it, key)
      for _, k in ipairs({ key, key .. "_AUTO" }) do
        local v = reaper.GetMediaItemInfo_Value(it, k)
        if v > safe then reaper.SetMediaItemInfo_Value(it, k, safe) end
      end
    end
    for _, t2 in ipairs(tracks) do
      for i = 0, reaper.CountTrackMediaItems(t2) - 1 do
        local it = reaper.GetTrackMediaItem(t2, i)
        local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if p >= a - TOL and e <= b + TOL then
          local fin = math.max(reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN"),
                               reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO"))
          local fout = math.max(reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN"),
                                reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO"))
          local trimIn = cutIn[it] or p + fin > b + TOL     -- (cut edge, or runs out of the area)
          local trimOut = cutOut[it] or e - fout < a - TOL
          if (trimIn and fin > safe) or (trimOut and fout > safe) then
            if not W.created[it] and not W.chunks[it] then   -- (so dropping it back home restores it)
              local ok, chunk = reaper.GetItemStateChunk(it, "", false)
              if ok then W.chunks[it] = chunk end
            end
            if trimIn then cap(it, "D_FADEINLEN") end
            if trimOut then cap(it, "D_FADEOUTLEN") end
          end
        end
      end
    end
    -- What's left outside the area: a fade the cut went through now ends at the cut
    -- (the part of it that's left, from where it began); no fade there, a safety fade
    local function set_len(it, key, v)
      reaper.SetMediaItemInfo_Value(it, key, v)
      if reaper.GetMediaItemInfo_Value(it, key .. "_AUTO") >= 0 then reaper.SetMediaItemInfo_Value(it, key .. "_AUTO", v) end
    end
    for it in pairs(leftRem) do   -- (ends at a)
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        local o = origOf[it]
        local fs = o.e - o.fout
        if o.fout > 0 and fs < a - TOL then set_len(it, "D_FADEOUTLEN", a - math.max(fs, o.p))
        else cap(it, "D_FADEOUTLEN") end
      end
    end
    for it in pairs(rightRem) do   -- (starts at b)
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        local o = origOf[it]
        local fe = o.p + o.fin
        if o.fin > 0 and fe > b + TOL then set_len(it, "D_FADEINLEN", math.min(fe, o.e) - b)
        else cap(it, "D_FADEINLEN") end
      end
    end
  end
  -- A crossfade the area's edge cuts through: on each side of the cut only the item that
  -- carries on away from it stays; the sliver of the other one is removed (outside: the
  -- next item's start under the end of the one before; inside: the end of the item
  -- before under the next one's start). Clean cuts, no half crossfades.
  do
    local function lane_of(it)
      return reaper.GetMediaItemInfo_Value(it, "I_FIXEDLANE") or 0
    end
    local function remove(it)
      if not reaper.ValidatePtr2(0, it, "MediaItem*") then return end
      if W.created[it] then
        W.created[it] = nil
      elseif W.chunks[it] then   -- (an original item: put back whole if the drag is undone)
        W.recreate[#W.recreate + 1] = { tr = reaper.GetMediaItem_Track(it), chunk = W.chunks[it] }
        W.chunks[it] = nil
      else
        local ok, chunk = reaper.GetItemStateChunk(it, "", false)
        if ok then W.recreate[#W.recreate + 1] = { tr = reaper.GetMediaItem_Track(it), chunk = chunk } end
      end
      reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(it), it)
    end
    for _, t2 in ipairs(tracks) do
      for _, cut in ipairs({ a, b }) do
        local ending, starting = {}, {}   -- per lane: pieces that end / start at the cut
        for i = 0, reaper.CountTrackMediaItems(t2) - 1 do
          local it = reaper.GetTrackMediaItem(t2, i)
          local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          local ln = lane_of(it)
          if math.abs(e - cut) <= TOL then ending[ln] = ending[ln] or {}; table.insert(ending[ln], { it = it, p = p, e = e }) end
          if math.abs(p - cut) <= TOL then starting[ln] = starting[ln] or {}; table.insert(starting[ln], { it = it, p = p, e = e }) end
        end
        local doomed = {}
        -- (only pieces of two items that overlapped at their ends, a crossfade: an item
        -- lying entirely on top of another isn't touched)
        for _, list in pairs(ending) do       -- keep the one reaching furthest back
          if #list > 1 then
            table.sort(list, function(x, y) return x.p < y.p end)
            local oK = origOf[list[1].it]
            for k = 2, #list do
              local oX = origOf[list[k].it]
              if oK and oX and oX ~= oK and oX.p > oK.p + TOL and oX.e > oK.e + TOL then doomed[#doomed + 1] = list[k].it end
            end
          end
        end
        for _, list in pairs(starting) do     -- keep the one reaching furthest on
          if #list > 1 then
            table.sort(list, function(x, y) return x.e > y.e end)
            local oK = origOf[list[1].it]
            for k = 2, #list do
              local oX = origOf[list[k].it]
              if oK and oX and oX ~= oK and oX.e < oK.e - TOL and oX.p < oK.p - TOL then doomed[#doomed + 1] = list[k].it end
            end
          end
        end
        for _, it in ipairs(doomed) do remove(it) end
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
  for _, r in ipairs(W.recreate or {}) do   -- (items removed from a crossfade the area cut through)
    if reaper.ValidatePtr2(0, r.tr, "MediaTrack*") then
      local it = reaper.AddMediaItemToTrack(r.tr)
      if it then reaper.SetItemStateChunk(it, r.chunk, false) end
    end
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
                    { "MM_CTX_ITEM", 4, "0" }, { "MM_CTX_ITEMLOWER", 4, "0" }, { "MM_CTX_TRACK", 4, "0" },
                    -- Option/Alt-click too: REAPER picks the click action as the button goes
                    -- down, and runs it on the release of a Shuffle drag (a split at the mouse)
                    { "MM_CTX_ITEM_CLK", 4, "0" }, { "MM_CTX_ITEMLOWER_CLK", 4, "0" },
                    { "MM_CTX_TRACK_CLK", 4, "0" }, { "MM_CTX_AREASEL_CLK", 4, "0" } }
local hoverSaved = nil
-- Kept on disk while switched, so they can be put back even if this script (or
-- REAPER) stops before it can: ReaTooled_Tools lib.lua repair_hover()
local HOVER_KEY = "ShuffleHoverSaved"

local clickSaved = nil   -- click actions switched off for the drag (below)
local CMDALL = { forced = false, saved = nil }   -- Cmd = all tracks (below)
local function save_hover()
  if not hoverSaved then reaper.DeleteExtState(NS, HOVER_KEY, true) return end
  local out = {}
  for _, o in ipairs(hoverSaved or {}) do out[#out + 1] = table.concat({ o[1], o[2], o[3], o[4] or "" }, "|") end
  reaper.SetExtState(NS, HOVER_KEY, table.concat(out, ";"), true)
end

-- During a Shuffle drag REAPER doesn't see a drag of its own (its drag there is off),
-- so on the release it runs the click action for the modifier held (Option/Alt-click
-- on an item can be a split). Those are off from the moment the drag is picked up
-- until just after the release.
local CLICK_CTX = { "MM_CTX_ITEM_CLK", "MM_CTX_ITEMLOWER_CLK", "MM_CTX_TRACK_CLK", "MM_CTX_AREASEL_CLK" }
local clickRestoreAt = nil
local function click_actions_off()
  if clickSaved or not reaper.GetMouseModifier then return end
  local m = reaper.JS_Mouse_GetState(4 | 8 | 16 | 32) or 0
  local flag = ((m & 8) ~= 0 and 1 or 0) | ((m & 4) ~= 0 and 2 or 0) | ((m & 16) ~= 0 and 4 or 0) | ((m & 32) ~= 0 and 8 or 0)
  -- (in ReaTooled's shared record: Tools library temp_take/temp_give)
  for _, c in ipairs(CLICK_CTX) do tools.temp_take("shuffle-click", c, flag, "0") end
  clickSaved = flag
  clickRestoreAt = nil
end
local function click_actions_on()
  if not clickSaved then return end
  for _, c in ipairs(CLICK_CTX) do tools.temp_give("shuffle-click", c, clickSaved) end
  clickSaved, clickRestoreAt = nil, nil
end
click_actions_off_fwd = click_actions_off

local function hover_razor(on)
  if on and not hoverSaved then
    if not reaper.GetMouseModifier then return end
    -- (in ReaTooled's shared record: Tools library temp_take/temp_give)
    hoverSaved = {}
    local plain = separation_on()   -- (without Separation Mode only Option/Alt-drags are ours)
    for _, h in ipairs(HOVER_OFF) do
      if h[2] ~= 0 or plain then
        tools.temp_take("shuffle-hover", h[1], h[2], h[3])
        hoverSaved[#hoverSaved + 1] = h
      end
    end
  elseif not on and hoverSaved then
    -- (only where it's still ours: a tool chosen meanwhile has set its own)
    for _, h in ipairs(hoverSaved) do tools.temp_give("shuffle-hover", h[1], h[2]) end
    hoverSaved = nil
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
  bounds = add_copy_at_start(bounds, R, a, list)
  bounds = add_copy_at_end(bounds, R, b, list)
  G.splitTs = { a, b }
  add_fade_bounds(bounds, R, list)
  G.Dslot = { members = members, pos0 = a, len = len }
  G.memberSet, G.lane = set, 0
  G.src = { tr = tr, list = list, R = R, bounds = bounds }
  G.rows = { [tr] = G.src }
  G.D = members[1] and members[1].item or nil
  bounds = copy_follower_filter(bounds)
  if all then
    G.others = other_items(tr, list)
    -- (not the copies just made on this track: they're what moves, not "other" items)
    do
      local keep = {}
      for _, o in ipairs(G.others) do if not set[o.it] then keep[#keep + 1] = o end end
      G.others = keep
    end
    -- razor areas: the other tracks are cut plainly, like this track (no fades)
    G.all, G.splits, G.cutFade = true, {}, 0
    if MOVE_MARKERS then G.markSnap = snap_markers() end
    bounds = copy_all_setup(bounds)
  end
  copy_at_start_pick(bounds, a, len)
  G.src.bounds = bounds
  G.track, G.b, G.grab, G.active = tr, nil, P.t - a, true
  G.pressX, G.pressY = px, py
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
    razor_starting = true
    start_drag(D, P.t)
    razor_starting = false
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
    if G.claim and not G.copy then   -- let go where it started: its crossfades come back
      reaper.PreventUIRefresh(1)
      put_D_on(G.src.tr)
      restore_list(G.src.list)
      restore_fades()
      reaper.PreventUIRefresh(-1)
    end
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

-- Cmd held over something that does "all tracks" (a left edge, a Shuffle move zone, a razor
-- area): REAPER is switched to ripple all tracks, and back afterwards. Shared by the scripts
-- that do this (ExtState ReaTooled/CmdAllFrom: the ripple mode to go back to;
-- CmdAllWant_<who>: when each last wanted it), so moving from one of their zones to
-- another doesn't switch back and forth. ShuffleQuiet keeps Shuffle's tooltip quiet.
local CMDALL_NS, CMDALL_ALL, CMDALL_PER, CMDALL_OFF = "ReaTooled", 40311, 40310, 40309
local function cmdall_set(state, who, want)
  local now = reaper.time_precise()
  local tgl = function(id) return reaper.GetToggleCommandState(id) == 1 end
  if want then
    reaper.SetExtState(CMDALL_NS, "CmdAllWant_" .. who, tostring(now), false)
    if not state.forced then
      if reaper.GetExtState(CMDALL_NS, "CmdAllFrom") == "" then
        if tgl(CMDALL_ALL) then return end   -- (already all tracks: nothing to switch)
        reaper.SetExtState(CMDALL_NS, "CmdAllFrom", tostring(tgl(CMDALL_PER) and CMDALL_PER or CMDALL_OFF), false)
        reaper.SetExtState(CMDALL_NS, "ShuffleQuiet", "1", false)
        reaper.Main_OnCommand(CMDALL_ALL, 0)
      end
      state.forced = true
    end
  elseif state.forced then
    state.forced = false
    reaper.DeleteExtState(CMDALL_NS, "CmdAllWant_" .. who, false)
    -- (another script still wants it: that one switches back when it's done)
    for _, other in ipairs({ "leftedge", "shuffle", "trim" }) do
      local t = other ~= who and tonumber(reaper.GetExtState(CMDALL_NS, "CmdAllWant_" .. other))
      if t and now - t < 0.3 then return end
    end
    local from = tonumber(reaper.GetExtState(CMDALL_NS, "CmdAllFrom"))
    reaper.DeleteExtState(CMDALL_NS, "CmdAllFrom", false)
    if from and tgl(CMDALL_ALL) then reaper.Main_OnCommand(from, 0) end   -- (unless changed meanwhile)
    reaper.SetExtState(CMDALL_NS, "ShuffleQuiet", tostring(now + 0.5), false)   -- (quiet a moment more)
  end
end

-- Cmd = all tracks: Cmd+drag (Cmd+Option: a copy) on an item's move zone or a razor area
-- is a Shuffle all tracks drag. While Cmd is held over one, REAPER is in ripple all tracks
-- (cmdall_set) and REAPER's own Cmd drags there (a new razor area) are off.
CMDALL.CMD = 4   -- JS_Mouse_GetState: Command (macOS) / Ctrl (Windows)
CMDALL.OFF = { { "MM_CTX_ITEM", 2 }, { "MM_CTX_ITEMLOWER", 2 }, { "MM_CTX_TRACK", 2 }, { "MM_CTX_AREASEL", 2 },
               { "MM_CTX_ITEM", 6 }, { "MM_CTX_ITEMLOWER", 6 }, { "MM_CTX_TRACK", 6 }, { "MM_CTX_AREASEL", 6 } }
function CMDALL.held(mods) return (mods & CMDALL.CMD) ~= 0 and (mods & ~(CMDALL.CMD | ALT)) == 0 end
function CMDALL.mods_off(on)   -- (in ReaTooled's shared record: Tools library temp_take/temp_give)
  if on and not CMDALL.saved then
    for _, h in ipairs(CMDALL.OFF) do tools.temp_take("shuffle", h[1], h[2], "0") end
    CMDALL.saved = true
  elseif not on and CMDALL.saved then
    for _, h in ipairs(CMDALL.OFF) do tools.temp_give("shuffle", h[1], h[2]) end
    CMDALL.saved = nil
  end
end
function CMDALL.set(want) cmdall_set(CMDALL, "shuffle", want) end

-- Ours, and is it a copy (Option/Alt-drag)? Cmd and Cmd+Option: the same, all tracks.
-- Other modifier drags stay REAPER's own.
local function our_press(it, sx, sy, mods)
  mods = mods or 0
  if not it or (mods ~= 0 and mods ~= ALT and not CMDALL.held(mods)) then return false end
  local copy = (mods & ALT) ~= 0
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

-- The mouse is over a move zone (where a plain press would be ours) or a razor area
function CMDALL.zone(mx, my, overRazor)
  if overRazor then return true end
  local it = reaper.GetItemFromPoint(mx, my, false)
  return it ~= nil and (our_press(it, mx, my, 0)) == true
end

------------------------------------------------------------
-- Main loop
------------------------------------------------------------
local prevDown, lastTry = false, 0
local outlined = false   -- (the yellow outline is drawn: Tools library outline)

local function stop()
  if tools.outline then tools.outline("shuffle", nil) end
  if G then restore() G = nil end
  -- (only while Shuffle still has the Multi tool: otherwise its settings were just put back)
  if upper_half_fwd and tools.shuffle_on() and wanted_tool() == "smart" then upper_half_fwd(nil) end
  if hover_razor_fwd then hover_razor_fwd(false) end
  CMDALL.mods_off(false)
  CMDALL.set(false)
  click_actions_on()
  show_copy_cursor(false)
  mouse.clicks_stop()
  reaper.DeleteExtState(NS, HEARTBEAT, false)
end

-- what the hover part of the loop last read (see loop)
local hover = { pkey = nil, read = 0, ver = 0, mkey = nil, hit = 0, over = false, upper = false }
local HOVER_REREAD, HIT_REREAD = 0.25, 0.1   -- seconds

local function loop()
  if wanted_tool() == "" or not tools.shuffle_on() then stop() return end
  local now = reaper.time_precise()
  reaper.SetExtState(NS, HEARTBEAT, tostring(now), false)
  if not mouse.clicks_on() and now - lastTry > 1 then lastTry = now; mouse.clicks_start() end

  local down = reaper.JS_Mouse_GetState(1) == 1
  if clickRestoreAt and not down and not G and now > clickRestoreAt then click_actions_on() end
  local mods = reaper.JS_Mouse_GetState(4 | 8 | 16 | 32)
  local cursorBefore = hoverCursor
  if not down and not G then
    hoverCursor = mouse.current_cursor()
    -- razor areas (Option-drag copies them even without Separation Mode) and the undo
    -- history: read again only when something changed, or every HOVER_REREAD seconds
    local ls, le = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
    local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local pkey = table.concat({ tostring(reaper.EnumProjects(-1)), reaper.GetProjectStateChangeCount(0),
                                ls, le, ts, te }, "|")
    -- (also on the first frame after a button is let go: a razor area just drawn must be
    -- in the copy before the next click. NOT at the click itself: by then REAPER may
    -- already have cleared the area being clicked)
    if pkey ~= hover.pkey or prevDown or now - hover.read >= HOVER_REREAD then
      hover.pkey, hover.read, hover.ver = pkey, now, hover.ver + 1
      cache_razors()
      note_undo_top()
    end
    -- what's under the mouse: only when it moved (or every HIT_REREAD seconds, for scrolling)
    local mx, my = reaper.GetMousePosition()
    local mkey = table.concat({ mx, my, mods or 0, hover.ver }, "|")
    if mkey ~= hover.mkey or now - hover.hit >= HIT_REREAD then
      hover.mkey, hover.hit = mkey, now
      hover.over = razorCache ~= nil and mouse_over_razor()
      hover.upper = mouse_upper_half()
    end
    local overRazor = hover.over
    -- Multi tool's upper half: its own drags, except where a razor area takes them
    -- (Option/Alt-drags always over a razor area; plain ones with Separation Mode)
    local upper = hover.upper
    multi_upper_half(upper and { [0] = not (overRazor and separation_on()), [4] = not overRazor } or nil)
    hover_razor(overRazor)
    -- Cmd over a move zone or a razor area: all tracks (REAPER's Cmd drags there off)
    local cmdZone = CMDALL.held(mods) and CMDALL.zone(mx, my, overRazor)
    CMDALL.set(cmdZone)
    CMDALL.mods_off(cmdZone)
    show_copy_cursor(overRazor and (mods & ALT) ~= 0 and (mods & ~(ALT | CMDALL.CMD)) == 0)
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
      local cmd = CMDALL.held(mods or 0)   -- (REAPER is already in all tracks: the hover switched it)
      if ((separation_on() and (mods or 0) == 0) or mods == ALT or cmd) and rtr and (rinfo or 0) == 0 then
        local cx = reaper.JS_Window_ScreenToClient(mouse.ARRANGE, sx, sy)
        local pt = mouse.time_at(cx)
        if razor_cached_at(rtr, pt) then drop_razor_clear() end
        ra, rb = razor_press_area(rtr, pt)
        if ra then start_razor_press(rtr, ra, rb, pt, (mods & ALT) ~= 0) end
      end
      if ra then
        -- (taken by Separation)
      else
        local mine, copy = our_press(it, sx, sy, mods)
        if mine then
          local cx = reaper.JS_Window_ScreenToClient(mouse.ARRANGE, sx, sy)
          start_drag(it, mouse.time_at(cx))
          if G and copy then G.copy = true end
          if G and G.claim and not G.copy then   -- (its crossfades go as soon as it's pressed)
            reaper.PreventUIRefresh(1); apply_claim(); reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
          end
        end
      end
    end
  elseif down then
    if G.pendingRazor then razor_drag() else drag() end
    -- (the yellow outline around what's moving; none while it's back where it started)
    local home = G and G.active and (G.b == nil or at_start(G.track, G.b))
    if home and outlined then tools.outline("shuffle", nil); outlined = false end
    if G and G.active and not home and tools.outline then
      local list = {}
      for _, m in ipairs(G.Dslot and G.Dslot.members or {}) do list[#list + 1] = m.item end
      for _, F in ipairs(G.followers or {}) do
        for _, m in ipairs(F.blk and F.blk.members or {}) do list[#list + 1] = m.item end
      end
      for _, c in ipairs(G.allCopies or {}) do list[#list + 1] = c.it end
      tools.outline("shuffle", list); outlined = true
    end
  else
    if G.pendingRazor then G = nil else release() end
    if clickSaved then clickRestoreAt = reaper.time_precise() + 0.3 end
  end

  if outlined and not (G and G.active and down) then tools.outline("shuffle", nil); outlined = false end
  prevDown = down
  reaper.defer(loop)
end

-- Started again while running (each time a tool is applied): REAPER stops this copy
-- and runs the new one, so an updated script always takes over
if reaper.set_action_options then reaper.set_action_options(1 | 2) end
if tools.repair_hover then tools.repair_hover() end   -- left switched by a copy that didn't stop cleanly
if tools.temp_give_all then tools.temp_give_all("shuffle"); tools.temp_give_all("shuffle-click"); tools.temp_give_all("shuffle-hover") end
reaper.atexit(stop)
mouse.clicks_start()
loop()
