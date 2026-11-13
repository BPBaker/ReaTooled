--[[
-- @description ReaTooled - Ripple edit when editing media item left edges
-- @version 1.21
-- @date 2026.11.11
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Ripple edit when editing media item left edges
    A toggle that runs in the background, on top of REAPER's "Ripple edit when editing media
    item edges" (which only ripples right edges). It works while REAPER is in a ripple mode
    (per-track or all tracks) and that option is on; otherwise plain drags are left alone.
      - Drag an item's left edge (REAPER's single left-edge cursor): the item's start stays,
        dragging right trims audio off the front, and what follows closes up as you drag.
      - Cmd+drag (Ctrl+drag on Windows) a left edge: the same, rippling all tracks (REAPER
        switches to ripple all while Cmd is held on the edge, and back after).
      - Butt joints, right edges, other modifier keys and plain clicks: as usual.
      - Trim Tool: in a ripple mode it hands left-edge trims (and left-side body drags) to
        this script; the trim then ends as the Trim Tool's own (selection, cursor, outline).
    Which items are trimmed: the grabbed one; if it's selected, the overlapping selected item on
    each other track; item groups; track groups (media editing); in ripple all, items starting
    at the same time on every other track. Locked items are never trimmed or moved.
    What follows: on tracks with a trimmed item, what comes after it; on grouped tracks (per
    track) and every track (ripple all), what starts after the grabbed item's start; markers
    with "Ripple edit all affects regions/markers"; automation with "Move envelope points with
    media items". Take envelopes, stretch markers and snap offsets stay with the audio.
    Snaps as REAPER's own edge drag (a line shows what it snapped to). Esc cancels; the view
    stays put; one undo step ("Resize media items"). Remembered when REAPER restarts (Recall
    ReaTooled Button States; on its own, without the rest of ReaTooled, add it to REAPER's
    startup actions). Works on its own too: it needs only the js_ReaScriptAPI extension. The rules: "Left edge ripple - design rules.md".
-- CHANGELOG
-- v1.21 Back to 1.19's behaviour (1.20's "edge follows the mouse, ripple on release" taken out)
-- v1.19 Works on its own, without the rest of ReaTooled (only js_ReaScriptAPI needed): it carries
--       ReaTooled's shared core (the record of mouse modifiers switched for a moment, the yellow
--       outline, Cmd = all tracks) instead of loading the Tools library. With ReaTooled installed
--       it works exactly as before
-- v1.18 Changing the ripple mode during a drag (ripple off, per track, all tracks) keeps what the
--       drag has done so far and carries on in the new mode from there: ripple off trims the
--       left edge as REAPER does without ripple (the edge follows the mouse, nothing else moves),
--       per track / all tracks pick their items and tracks again. Esc still undoes the whole
--       drag; still one undo step
-- v1.17 (lean) Same behaviour as 1.16.1 with the never-used paths taken out (MODE "native",
--       JOINT_GUARD, AUTOSCROLL, the pre-1.13 record migration), one function for the Trim
--       Tool's selection/cursor/time selection (was written twice), snap settings read once per
--       drag, frames where the mouse hasn't moved skipped. Older history: "Left edge ripple -
--       history (to v1.16.1).txt"
--]]

------------------------------------------------------------
-- SETTINGS (change, then turn the script off and on again)
------------------------------------------------------------
local GUIDE_COLOR = 0xD0FFFFFF   -- the snap guide line: 0xAARRGGBB (alpha, red, green, blue)
local DEBUG       = false        -- print what happens to the ReaScript console

-- REAPER actions read or used
local RIPPLE_EDGES = 43475 -- Options: Ripple edit when editing media item edges
local RIPPLE_OFF, RIPPLE_PER_TRACK, RIPPLE_ALL = 40309, 40310, 40311
local MARKERS_FOLLOW = 43690  -- Options: Ripple edit all affects regions/markers
local SNAP = 1157             -- Options: Toggle snapping
local GROUPING = 1156         -- Options: Item grouping (also the master for track groups)
local TRACK_GROUPS = 40771    -- Options: Track grouping enabled
local ENV_FOLLOW = 40070      -- Options: Move envelope points with media items
local LINK_CMD_GUID = "_RSed328eb507619b18c1154efa1b048d816cfc2d0c"   -- Link Timeline and Edit Selection

------------------------------------------------------------
local TITLE = "Ripple edit when editing media item left edges"
if not (reaper.JS_Mouse_GetCursor and reaper.JS_WindowMessage_Intercept and reaper.JS_WindowMessage_Send) then
  reaper.ShowMessageBox("This needs the js_ReaScriptAPI extension.", TITLE, 0)
  return
end
-- On/off: run it again to turn it off. REAPER ends the running copy and starts this one
-- (options 1+2); a copy started right after one ended is the "off" press. Quitting REAPER
-- doesn't count as off, so it comes back on at the next start (Recall ReaTooled Button States).
if reaper.set_action_options then reaper.set_action_options(1 | 2) end
local EXT = "ReaTooled"
local STATE = "RippleLeftEdges"                  -- "1" on, "0" off (kept across restarts)
local BEAT, STOP, ENDED = "RippleLeftEdges_beat", "RippleLeftEdges_stop", "RippleLeftEdges_ended"
do
  local now = reaper.time_precise()
  local ended = tonumber(reaper.GetExtState(EXT, ENDED))
  local beat = tonumber(reaper.GetExtState(EXT, BEAT))
  reaper.DeleteExtState(EXT, ENDED, false)
  if (ended and now - ended < 1) or (beat and now - beat < 2) then
    -- run again: off (and the running copy, if it's still running, stops itself)
    if beat and now - beat < 2 then reaper.SetExtState(EXT, STOP, "1", false) end
    reaper.SetExtState(EXT, STATE, "0", true)
    local _, _, sec, cmd = reaper.get_action_context()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    return
  end
  reaper.DeleteExtState(EXT, STOP, false)
  local was_on = reaper.GetExtState(EXT, STATE) == "1"   -- (on already: restored at start-up)
  reaper.SetExtState(EXT, STATE, "1", true)
  -- turned on now: REAPER's "Ripple edit when editing media item edges" too (this needs it)
  if not was_on and reaper.GetToggleCommandState(RIPPLE_EDGES) ~= 1 then reaper.Main_OnCommand(RIPPLE_EDGES, 0) end
end

local _, _, SEC, CMD = reaper.get_action_context()
-- >>> ReaTooled shared core (v1)
-- Pasted into the scripts that use it by "ReaTooled_DEV Paste shared core.lua" from
-- "ReaTooled_Shared core.lua" in DEV SCRIPTS: edit that file, never a pasted copy (the release
-- build stops if a copy is out of date). It lets these scripts work on their own, without the
-- Tools library, and still cooperate with each other and with the rest of ReaTooled through the
-- same ExtStates. Keep the record formats as they are: older copies must read newer ones.
--   C.temp_take / temp_give / temp_give_all / temp_forget / temp_repair / temp_still_ours:
--     the shared record of mouse modifiers switched for a moment (ExtState ReaTooled/TempMods)
--   C.outline(owner, items, redrawn, ends): the yellow outline around items being edited
--   C.repair_hover(): crash repair for what Shuffle move switched (and the record)
--   C.cmdall_set(state, who, want): Cmd = ripple all tracks, shared
local RTcore = (function()
local C = {}
local NS = "ReaTooled"

------------------------------------------------------------
-- Mouse modifiers switched for a moment by background scripts (while the mouse is over
-- something, or during a drag), in one record (ExtState TempMods, kept on disk):
-- "context|flag|original|ours|owner,owner;...". The first script to switch one keeps its
-- original; it's put back when the last owner lets go (only if it's still ours: a tool
-- chosen meanwhile has set its own). Owners: "leftedge", "shuffle" (and their "-click" ones).
------------------------------------------------------------
local TEMP_KEY = "TempMods"
local TEMP_ALIVE = { leftedge = "RippleLeftEdges_beat", ["leftedge-click"] = "RippleLeftEdges_beat",
                     shuffle = "ShuffleMoveAlive", ["shuffle-click"] = "ShuffleMoveAlive",
                     ["shuffle-hover"] = "ShuffleMoveAlive", trim = "TrimToolHeartbeat",
                     ["trim-hand"] = "TrimToolHeartbeat", ["trim-click"] = "TrimToolHeartbeat" }   -- heartbeats
local function temp_read()
  local t = {}
  for line in reaper.GetExtState(NS, TEMP_KEY):gmatch("[^;]+") do
    local c, f, orig, ours, owners, set = line:match("^(.-)|(%-?%d+)|(.-)|(.-)|([^|]*)|?(.*)$")
    if c then
      local e = { ctx = c, flag = tonumber(f), orig = orig, applied = ours, set = set, owners = {} }
      for o in owners:gmatch("[^,]+") do e.owners[o] = true end
      t[c .. "|" .. f] = e
    end
  end
  return t
end
local function temp_write(t)
  local out = {}
  for _, e in pairs(t) do
    local o = {}
    for k in pairs(e.owners) do o[#o + 1] = k end
    out[#out + 1] = table.concat({ e.ctx, e.flag, e.orig, e.applied, table.concat(o, ","), e.set or "" }, "|")
  end
  if #out == 0 then reaper.DeleteExtState(NS, TEMP_KEY, true)
  else reaper.SetExtState(NS, TEMP_KEY, table.concat(out, ";"), true) end
end
local function mod_now(ctx, flag)
  local v = reaper.GetMouseModifier(ctx, flag)
  if v == nil or v == "" then v = "-1" end
  return v
end

-- Is a modifier still as a temp_take left it? (REAPER can report what was set differently from
-- what was written, e.g. "Pass through" on an item's lower half: so either counts, and so do
-- No action/blank/pass through when that's what was set)
local function noop(v) return v == nil or v == "" or v == "-1" or v:match("^0%s*%a?$") ~= nil end
-- (REAPER reports a lower half that passes through as the upper half's setting)
local UPPER_OF = { MM_CTX_ITEMLOWER = "MM_CTX_ITEM", MM_CTX_ITEMLOWER_CLK = "MM_CTX_ITEM_CLK",
                   MM_CTX_ITEMLOWER_DBLCLK = "MM_CTX_ITEM_DBLCLK" }
local function still_ours(e)
  local v = mod_now(e.ctx, e.flag)
  if v == e.applied or (e.set and e.set ~= "" and v == e.set) then return true end
  local up = UPPER_OF[e.ctx]
  return noop(e.set) and up ~= nil and v == mod_now(up, e.flag)   -- (still passing through)
end
C.temp_still_ours = still_ours

-- Switch a modifier to 'value' for 'owner' (kept until temp_give)
function C.temp_take(owner, ctx, flag, value)
  if not reaper.GetMouseModifier then return end
  local t = temp_read()
  local k = ctx .. "|" .. flag
  local e = t[k]
  if e and still_ours(e) then
    e.owners[owner] = true                      -- (already switched by another: share it)
  else
    -- (not switched, or changed since by something else: what's there now is the original)
    e = { ctx = ctx, flag = flag, orig = mod_now(ctx, flag), set = value, owners = { [owner] = true } }
    reaper.SetMouseModifier(ctx, flag, value)
    e.applied = mod_now(ctx, flag)
    t[k] = e
  end
  temp_write(t)
end

-- Let go of one ('forget': without putting it back, e.g. a tool now owns it)
function C.temp_give(owner, ctx, flag, forget)
  if not reaper.GetMouseModifier then return end
  local t = temp_read()
  local k = ctx .. "|" .. flag
  local e = t[k]
  if not e or not e.owners[owner] then return end
  e.owners[owner] = nil
  if not next(e.owners) then
    if not forget and still_ours(e) then reaper.SetMouseModifier(ctx, flag, e.orig) end
    t[k] = nil
  end
  temp_write(t)
end

-- Let go of everything one owner holds
function C.temp_give_all(owner)
  for _, e in pairs(temp_read()) do
    if e.owners[owner] then C.temp_give(owner, e.ctx, e.flag) end
  end
end


-- These contexts have just been set by something else (a tool, a mode): what was switched there
-- is forgotten, not put back over it when its owner lets go
function C.temp_forget(contexts)
  local t, changed = temp_read(), false
  for k, e in pairs(t) do
    if contexts[e.ctx] then t[k] = nil; changed = true end
  end
  if changed then temp_write(t) end
end

-- Owners that aren't running any more (stopped without letting go): let go for them
function C.temp_repair()
  local now = reaper.time_precise()
  for _, e in pairs(temp_read()) do
    for o in pairs(e.owners) do
      local beat = tonumber(reaper.GetExtState(NS, TEMP_ALIVE[o] or ""))
      if not beat or now - beat > 2 then C.temp_give(o, e.ctx, e.flag) end
    end
  end
end

------------------------------------------------------------
-- Outline: a yellow frame over the arrange view around items being edited (drawn on top of
-- everything, so an item can be seen where it overlaps others). Each owner has its own.
------------------------------------------------------------
local OUTLINE_COLOR = 0xFFFFD000   -- (ARGB: yellow)
local OUTLINE_PX = 2
local OUTLINE_MAX = 32             -- items outlined at most
local outlines = {}                -- owner -> { bms = {}, rects = {} }
local function arrange_hwnd()
  if not C._arrange then C._arrange = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000) end
  return C._arrange
end
function C.outline(owner, items, redrawn, ends)
  if not (reaper.JS_Composite and reaper.JS_LICE_CreateBitmap) then return end
  if items and reaper.GetExtState(NS, "OutlineOff") == "1" then items = {} end
  local hwnd = arrange_hwnd()
  if not hwnd then return end
  local o = outlines[owner]
  if not o then o = { bms = {}, rects = {} }; outlines[owner] = o end
  local _, w, h = reaper.JS_Window_GetClientSize(hwnd)
  local view = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local zoom = reaper.GetHZoomLevel()
  -- the frames: 4 lines an item, as rects { x, y, w, h }
  local want, n = {}, 0
  for _, it in ipairs(items or {}) do
    if n >= OUTLINE_MAX * 4 then break end
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      local tr = reaper.GetMediaItem_Track(it)
      local ty = reaper.GetMediaTrackInfo_Value(tr, "I_TCPY")
      local th = reaper.GetMediaTrackInfo_Value(tr, "I_TCPH")
      local iy = reaper.GetMediaItemInfo_Value(it, "I_LASTY")
      local ih = reaper.GetMediaItemInfo_Value(it, "I_LASTH")
      if th > 0 and ih > 0 then
        local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if ends and ends[it] then len = math.max(0, ends[it] - pos) end
        local x1 = math.floor((pos - view) * zoom + 0.5)
        local x2 = math.floor((pos + len - view) * zoom + 0.5)
        local y1, y2 = math.floor(ty + iy), math.floor(ty + iy + ih)
        if x2 > 0 and x1 < w and y2 > 0 and y1 < h and x2 - x1 >= 1 then
          local cx1, cx2 = math.max(x1, -OUTLINE_PX), math.min(x2, w + OUTLINE_PX)
          local function add(x, y, ww, hh)
            if ww > 0 and hh > 0 then n = n + 1; want[n] = { x, y, ww, hh } end
          end
          add(cx1, y1, cx2 - cx1, OUTLINE_PX)                              -- top
          add(cx1, y2 - OUTLINE_PX, cx2 - cx1, OUTLINE_PX)                 -- bottom
          if x1 >= -OUTLINE_PX then add(x1, y1, OUTLINE_PX, y2 - y1) end    -- left
          if x2 <= w + OUTLINE_PX then add(x2 - OUTLINE_PX, y1, OUTLINE_PX, y2 - y1) end   -- right
        end
      end
    end
  end
  -- what changed: put the lines there, take the rest away, redraw only those places
  local dirty = {}
  local count = math.max(n, #o.rects)
  for i = 1, count do
    local r, old = want[i], o.rects[i]
    local same = r and old and r[1] == old[1] and r[2] == old[2] and r[3] == old[3] and r[4] == old[4]
    if not same then
      if old then dirty[#dirty + 1] = old end
      if r then
        local bm = o.bms[i]
        if not bm then
          bm = reaper.JS_LICE_CreateBitmap(true, 1, 1)
          reaper.JS_LICE_Clear(bm, OUTLINE_COLOR)
          o.bms[i] = bm
        end
        reaper.JS_Composite(hwnd, r[1], r[2], r[3], r[4], bm, 0, 0, 1, 1)
        dirty[#dirty + 1] = r
      elseif o.bms[i] then
        reaper.JS_Composite_Unlink(hwnd, o.bms[i])
      end
    end
  end
  o.rects = want
  if redrawn then dirty = {} end   -- (the whole arrange view is redrawn this frame anyway)
  for _, r in ipairs(dirty) do
    reaper.JS_Window_InvalidateRect(hwnd, r[1] - 1, r[2] - 1, r[1] + r[3] + 1, r[2] + r[4] + 1, false)
  end
  if n == 0 and not items then   -- (gone: the bitmaps too)
    for i, bm in pairs(o.bms) do reaper.JS_Composite_Unlink(hwnd, bm); reaper.JS_LICE_DestroyBitmap(bm) end
    outlines[owner] = nil
  end
end

function C.repair_hover()
  C.temp_repair()
  local saved = reaper.GetExtState(NS, "ShuffleHoverSaved")
  if saved == "" or not reaper.GetMouseModifier then return end
  for line in saved:gmatch("[^;]+") do
    local c, f, orig, ours = line:match("^(.-)|(%-?%d+)|(.-)|(.*)$")
    f = tonumber(f)
    if c and f and still_ours({ ctx = c, flag = f, orig = orig, applied = ours, set = "0" }) then
      reaper.SetMouseModifier(c, f, orig)
    end
  end
  reaper.DeleteExtState(NS, "ShuffleHoverSaved", true)
end


-- Cmd held over something that does "all tracks" (a left edge, a Shuffle move zone, a razor
-- area): REAPER is switched to ripple all tracks, and back afterwards. Shared by the scripts
-- that do this (ExtState ReaTooled/CmdAllFrom: the ripple mode to go back to;
-- CmdAllWant_<who>: when each last wanted it), so moving from one of their zones to
-- another doesn't switch back and forth. ShuffleQuiet keeps Shuffle's tooltip quiet.
local CMDALL_NS, CMDALL_ALL, CMDALL_PER, CMDALL_OFF = "ReaTooled", 40311, 40310, 40309
function C.cmdall_set(state, who, want)
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

return C
end)()
-- <<< ReaTooled shared core

local OWNER = "leftedge"
local ARRANGE = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
local EPS = 1e-9
local TOL = 0.0005            -- seconds: edges this close count as the same time
local ALL_START_TOL = 0.005   -- ripple all: items starting this close to the grabbed one are trimmed with it
local MIN_LEN = 0.001         -- seconds an item can be trimmed down to
local EDGE_REACH_PX = 16      -- REAPER's left-edge zone reaches this far from the item's start

local function log(s) if DEBUG then reaper.ShowConsoleMsg(TITLE .. ": " .. s .. "\n") end end
local function tg(id) return reaper.GetToggleCommandState(id) == 1 end
local CURSOR_TRIM = reaper.JS_Mouse_LoadCursor(417)          -- REAPER's single left-edge cursor
local LEFT_EDGE = CURSOR_TRIM and tostring(CURSOR_TRIM)

local function is_locked(it) return (reaper.GetMediaItemInfo_Value(it, "C_LOCK") or 0) ~= 0 end
local function item_start(it) return reaper.GetMediaItemInfo_Value(it, "D_POSITION") end
local function item_len(it) return reaper.GetMediaItemInfo_Value(it, "D_LENGTH") end

local dragging = false

-- The item whose left edge is at the mouse, and the screen x of that edge
local function item_at_left_edge(mx, my)
  local start_t = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local zoom = reaper.GetHZoomLevel()
  local ox = reaper.JS_Window_ClientToScreen(ARRANGE, 0, 0)
  for dx = 0, EDGE_REACH_PX, 2 do   -- (the edge zone reaches a little past the item)
    local item = reaper.GetItemFromPoint(mx + dx, my, false)
    if item then
      local left = ox + (item_start(item) - start_t) * zoom
      if math.abs(left - mx) <= EDGE_REACH_PX then return item, left end
      return nil
    end
  end
end

------------------------------------------------------------
-- Which items are trimmed, and which tracks ripple
------------------------------------------------------------

-- A track's membership in groups 1-32 and 33-64 for one group setting (as the Trim Tool)
local function group_masks(tr, name)
  local lo, hi = 0, 0
  if reaper.GetSetTrackGroupMembershipEx then
    lo = reaper.GetSetTrackGroupMembershipEx(tr, name, 0, 0, 0) or 0
    hi = reaper.GetSetTrackGroupMembershipEx(tr, name, 32, 0, 0) or 0
  elseif reaper.GetSetTrackGroupMembership then
    lo = reaper.GetSetTrackGroupMembership(tr, name, 0, 0) or 0
    if reaper.GetSetTrackGroupMembershipHigh then hi = reaper.GetSetTrackGroupMembershipHigh(tr, name, 0, 0) or 0 end
  end
  return math.floor(lo) & 0xFFFFFFFF, math.floor(hi) & 0xFFFFFFFF
end

-- Tracks that follow the grabbed track's media editing groups
local function grouped_tracks(tr)
  local out = {}
  if not (tg(GROUPING) and tg(TRACK_GROUPS)) then return out end
  local lo, hi = group_masks(tr, "MEDIA_EDIT_LEAD")
  if lo == 0 and hi == 0 then return out end
  for t = 0, reaper.CountTracks(0) - 1 do
    local o = reaper.GetTrack(0, t)
    if o ~= tr then
      local flo, fhi = group_masks(o, "MEDIA_EDIT_FOLLOW")
      if (flo & lo) ~= 0 or (fhi & hi) ~= 0 then out[o] = true end
    end
  end
  return out
end

-- On a track, the item (passing 'ok') that overlaps [s, e] with its start nearest s
local function nearest_on(tr, s, e, ok)
  local best, bd = nil, math.huge
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if ok(it) and not is_locked(it) then
      local p = item_start(it)
      local overlap = math.min(p + item_len(it), e) - math.max(p, s)
      local d = math.abs(p - s)
      if (overlap > TOL or d <= TOL) and d < bd then best, bd = it, d end
    end
  end
  return best
end

local force_all = false       -- Cmd+drag: ripple all tracks, whatever REAPER's ripple mode
local function ripple_all() return force_all or tg(RIPPLE_ALL) end
-- REAPER's ripple mode now: "all", "per" or "off"
local function ripple_mode()
  if ripple_all() then return "all" end
  return tg(RIPPLE_PER_TRACK) and "per" or "off"
end

-- Every other track holding an item that passes 'ok': on each, the one nearest the grabbed item
local function add_nearest(drivers, gtr, s, e, ok)
  local tracks = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local tr = reaper.GetMediaItem_Track(it)
    if tr ~= gtr and not drivers[tr] and ok(it) then tracks[tr] = true end
  end
  for tr in pairs(tracks) do drivers[tr] = nearest_on(tr, s, e, ok) end
end

-- The items to trim (one per track), the tracks that ripple without one
local function plan(grabbed)
  local gtr = reaper.GetMediaItem_Track(grabbed)
  local s, e = item_start(grabbed), item_start(grabbed) + item_len(grabbed)
  local drivers = { [gtr] = grabbed }
  -- selected items on other tracks (only if the grabbed one is selected)
  if reaper.IsMediaItemSelected(grabbed) then
    add_nearest(drivers, gtr, s, e, function(it) return reaper.IsMediaItemSelected(it) end)
  end
  -- item group
  local gid = reaper.GetMediaItemInfo_Value(grabbed, "I_GROUPID") or 0
  if tg(GROUPING) and gid > 0 then
    add_nearest(drivers, gtr, s, e, function(it) return reaper.GetMediaItemInfo_Value(it, "I_GROUPID") == gid end)
  end
  -- track groups
  local grouped = grouped_tracks(gtr)
  for tr in pairs(grouped) do
    drivers[tr] = drivers[tr] or nearest_on(tr, s, e, function() return true end)
  end
  -- ripple all tracks: on every other track, an item starting at the same time (as the Trim Tool)
  if ripple_all() then
    for t = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, t)
      if not drivers[tr] then
        for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
          local it = reaper.GetTrackMediaItem(tr, i)
          if not is_locked(it) and math.abs(item_start(it) - s) <= ALL_START_TOL then drivers[tr] = it; break end
        end
      end
    end
  end
  return drivers, grouped, s, e
end

------------------------------------------------------------
-- The ripple trim
------------------------------------------------------------
local sh = nil                -- the ripple trim going on
local snap_targets            -- (defined with the snapping, below)

local function mouse_time(mx)
  local start_t = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local ox = reaper.JS_Window_ClientToScreen(ARRANGE, 0, 0)
  return start_t + (mx - ox) / reaper.GetHZoomLevel()
end

local function capture_trim(it)
  local c = { it = it, P = item_start(it), L = item_len(it), takes = {},
              loop = reaper.GetMediaItemInfo_Value(it, "B_LOOPSRC") == 1,
              snapoff = reaper.GetMediaItemInfo_Value(it, "D_SNAPOFFSET") }
  for i = 0, reaper.CountTakes(it) - 1 do
    local take = reaper.GetTake(it, i)
    if take then
      local src = reaper.GetMediaItemTake_Source(take)
      local srclen, isQN = 0, false
      if src then srclen, isQN = reaper.GetMediaSourceLength(src) end
      if isQN then srclen = reaper.TimeMap2_QNToTime(0, srclen) end
      c.takes[#c.takes + 1] = { take = take, off = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
                                rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
                                srclen = srclen or 0, shifted = 0,
                                midi = reaper.TakeIsMIDI and reaper.TakeIsMIDI(take) or false }
    end
  end
  return c
end

-- A track's automation, as at the press. The trim takes out a stretch of time [a, a + d)
-- (d < 0: puts one in) and everything after it moves by -d, a = the trimmed item's start
-- (or the grabbed item's start on tracks without one). Points before a stay, points in the
-- stretch go, points after move by -d, and at a the envelope keeps its value on both sides
-- (two points).
local function capture_env(tr, a, out)
  for e = 0, reaper.CountTrackEnvelopes(tr) - 1 do
    local env = reaper.GetTrackEnvelope(tr, e)
    local all, tail, ais = {}, false, {}
    for i = 0, reaper.CountEnvelopePoints(env) - 1 do
      local ok, t, v, shape, tens, sel = reaper.GetEnvelopePoint(env, i)
      if ok then
        all[#all + 1] = { t = t, v = v, shape = shape, tens = tens, sel = sel }
        if t >= a - TOL then tail = true end
      end
    end
    for i = 0, reaper.CountAutomationItems(env) - 1 do
      local p = reaper.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
      if p >= a - TOL then ais[#ais + 1] = { i = i, p = p } end
    end
    if tail or #ais > 0 then out[#out + 1] = { env = env, all = all, ais = ais, at = a } end
  end
end

-- The envelope's value at time t as captured (straight lines between points)
local function value_at(all, t)
  local prev
  for _, p in ipairs(all) do
    if p.t >= t then
      if not prev then return p.v end
      if p.t - prev.t < EPS or prev.shape == 1 then return prev.v end   -- (shape 1: square)
      return prev.v + (p.v - prev.v) * (t - prev.t) / (p.t - prev.t)
    end
    prev = p
  end
  return prev and prev.v or nil
end

-- Rebuild the envelope from the trim point on for a trim of d
local function apply_env(en, d)
  local a = en.at
  reaper.DeleteEnvelopePointRange(en.env, a - 1e-6, 1e12)
  for _, p in ipairs(en.all) do
    if p.t >= a - TOL then
      local t
      if p.t < a - EPS then t = p.t                       -- (before the stretch: stays)
      elseif d > 0 and p.t < a + d - EPS then t = nil     -- (in the trimmed-off stretch: goes)
      else t = p.t - d end                                -- (after it: moves with it)
      if t then reaper.InsertEnvelopePoint(en.env, t, p.v, p.shape, p.tens, p.sel, true) end
    end
  end
  if math.abs(d) > EPS and #en.all > 0 then
    -- (at the join, the value on each side stays what it was)
    local left = value_at(en.all, a)
    local right = value_at(en.all, d > 0 and (a + d) or a)
    if left then reaper.InsertEnvelopePoint(en.env, a, left, 0, 0, false, true) end
    if right and d > 0 then reaper.InsertEnvelopePoint(en.env, a, right, 0, 0, false, true) end
  end
  reaper.Envelope_SortPoints(en.env)
  for _, ai in ipairs(en.ais) do
    local p = ai.p
    if p >= a + math.max(d, 0) - EPS then p = p - d elseif p >= a - EPS then p = a end
    reaper.GetSetAutomationItemInfo(en.env, ai.i, "D_POSITION", p, true)
  end
end

local function cfg_int(name)
  local ok, v = reaper.get_config_var_string(name)
  return ok and math.tointeger(tonumber(v)) or 0
end

-- plain: ripple off (from a mode change during the drag): the left edge is trimmed as REAPER
-- does without ripple (the item's start moves, nothing else does)
local function trim_begin(grabbed, mx, plain)
  local drivers, grouped, gs = plan(grabbed)
  local all = ripple_all()
  if plain then grouped, all = {}, false end
  local s_ = { d = 0, t0 = mouse_time(mx), trims = {}, movers = {}, markers = {}, envs = {},
               mode = ripple_mode(), plain = plain,
               gP = item_start(grabbed), started = reaper.time_precise(),
               grabbed = grabbed, grabbed_was_selected = reaper.IsMediaItemSelected(grabbed),
               -- (REAPER's snap settings, read once: they can't change during a drag)
               flags = cfg_int("projshowgrid"), itemsnap = cfg_int("itemsnap"), relsnap = cfg_int("relsnap") == 1 }
  local moving = {}
  for _, it in pairs(drivers) do s_.trims[#s_.trims + 1] = capture_trim(it); moving[it] = true end

  -- the tracks that ripple: those with a trimmed item (from its start), grouped tracks, and in
  -- ripple all every track (from the grabbed item's start: what's after it follows its audio)
  local scope = {}   -- track -> the trimmed item on it (false: none)
  if not plain then for tr, it in pairs(drivers) do scope[tr] = it end end
  for tr in pairs(grouped) do if scope[tr] == nil then scope[tr] = false end end
  if all then
    for t = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, t)
      if scope[tr] == nil then scope[tr] = false end
    end
  end

  local env_follow = tg(ENV_FOLLOW)
  for tr, own in pairs(scope) do
    -- (own item: everything starting after its start; otherwise after the grabbed item's start)
    local after = own and (item_start(own) + EPS) or (gs + TOL)
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      if not moving[it] and not is_locked(it) then
        local p = item_start(it)
        if p > after then s_.movers[#s_.movers + 1] = { it = it, p = p } end
      end
    end
    if env_follow then capture_env(tr, own and item_start(own) or gs, s_.envs) end
  end
  for _, m in ipairs(s_.movers) do moving[m.it] = true end
  if all and tg(MARKERS_FOLLOW) then
    local i = 0
    while true do
      local ok, isrgn, pos, rend, name, num, color = reaper.EnumProjectMarkers3(0, i)
      if ok == 0 then break end
      if pos > gs + TOL then   -- (after the grabbed item's start: they follow its audio)
        s_.markers[#s_.markers + 1] = { isrgn = isrgn, pos = pos, rend = rend, name = name, num = num, color = color }
      end
      i = i + 1
    end
  end
  s_.snaps = snap_targets(grabbed, moving, s_.flags)
  -- (the Trim Tool's yellow outline, on the trimmed items)
  if RTcore and reaper.GetExtState("ReaTooled", "CurrentTool") == "trim" then
    s_.outline = {}
    for _, c in ipairs(s_.trims) do s_.outline[#s_.outline + 1] = c.it end
  end
  s_.prev = sh   -- (the drag so far, in the mode before: kept)
  sh = s_
  log(string.format((plain and "plain" or "ripple") .. " trim: %d item(s) trimmed, %d follow, %d envelope(s), %d marker(s)",
    #s_.trims, #s_.movers, #s_.envs, #s_.markers))
end

-- Take envelopes and stretch markers are in take time: when the start in source moves by x,
-- they move by -x so they stay with the audio (as the Trim Tool does)
local function shift_take_contents(take, dt)
  if dt == 0 then return end
  for e = 0, reaper.CountTakeEnvelopes(take) - 1 do
    local env = reaper.GetTakeEnvelope(take, e)
    if env then
      for i = 0, reaper.CountEnvelopePoints(env) - 1 do
        local ok, t, v, shape, tens, sel = reaper.GetEnvelopePoint(env, i)
        if ok then reaper.SetEnvelopePoint(env, i, t + dt, v, shape, tens, sel, true) end
      end
      reaper.Envelope_SortPoints(env)
    end
  end
  if reaper.GetTakeNumStretchMarkers then
    for i = 0, reaper.GetTakeNumStretchMarkers(take) - 1 do
      local idx, pos, srcpos = reaper.GetTakeStretchMarker(take, i)
      if idx and idx >= 0 then reaper.SetTakeStretchMarker(take, i, pos + dt, srcpos) end
    end
  end
end

-- The limits: every trimmed item keeps MIN_LEN, unlooped audio can't go before its start
local function clamp(d)
  for _, c in ipairs(sh.trims) do
    d = math.min(d, c.L - MIN_LEN)
    if sh.plain then d = math.max(d, -c.P) end   -- (ripple off: the start can't go before 0)
    if not c.loop then
      for _, t in ipairs(c.takes) do
        -- (MIDI can go back past its start: there's just empty space, as REAPER's own drag)
        if not t.midi and t.rate > 0 and t.off + d * t.rate < 0 then d = math.max(d, -t.off / t.rate) end
      end
    end
  end
  return d
end

local function apply(d)
  if math.abs(d - sh.d) < EPS then return end
  sh.d = d
  reaper.PreventUIRefresh(1)
  for _, c in ipairs(sh.trims) do
    reaper.SetMediaItemInfo_Value(c.it, "D_LENGTH", c.L - d)
    if sh.plain then reaper.SetMediaItemInfo_Value(c.it, "D_POSITION", c.P + d) end
    for _, t in ipairs(c.takes) do
      local set = t.off + d * t.rate                       -- (the start in source moves with the trim)
      if c.loop and t.srclen > 0 then set = set % t.srclen end
      reaper.SetMediaItemTakeInfo_Value(t.take, "D_STARTOFFS", set)
      local want = -(d * t.rate)                           -- (what's in the take stays with its audio)
      shift_take_contents(t.take, want - t.shifted)
      t.shifted = want
    end
    -- (no snap offset set: it stays at the left edge; one you set stays on its spot in the audio)
    if c.snapoff > EPS then reaper.SetMediaItemInfo_Value(c.it, "D_SNAPOFFSET", math.max(0, c.snapoff - d)) end
  end
  for _, m in ipairs(sh.movers) do reaper.SetMediaItemInfo_Value(m.it, "D_POSITION", m.p - d) end
  for _, en in ipairs(sh.envs) do apply_env(en, d) end
  for _, m in ipairs(sh.markers) do
    reaper.SetProjectMarker3(0, m.num, m.isrgn, m.pos - d, m.isrgn and (m.rend - d) or 0, m.name, m.color)
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end

------------------------------------------------------------
-- Snapping, as REAPER's own edge drag, from its Snap/Grid settings (projshowgrid bits,
-- measured in REAPER 7.85: 1 show grid, 2 media items to grid, 16 media items to
-- selection/markers/cursor, 128 snap to nearby media items (maxsnaptrack tracks away),
-- 1024 grid at any distance, 32768 grid snap follows grid visibility; itemsnap = snap
-- distance in pixels; relsnap = relative grid)
------------------------------------------------------------
-- What the trim point can snap to (fixed while dragging): markers, region edges, time
-- selection, edit cursor, other items' edges and snap offsets nearby
function snap_targets(grabbed, moving, flags)
  local list = {}
  if flags & 16 ~= 0 then
    local i = 0
    while true do
      local ok, isrgn, pos, rend = reaper.EnumProjectMarkers3(0, i)
      if ok == 0 then break end
      list[#list + 1] = pos
      if isrgn then list[#list + 1] = rend end
      i = i + 1
    end
    local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if te > ts then list[#list + 1] = ts; list[#list + 1] = te end
    list[#list + 1] = reaper.GetCursorPosition()
  end
  if flags & 128 ~= 0 then
    local gi = reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(grabbed), "IP_TRACKNUMBER") - 1
    local reach = cfg_int("maxsnaptrack")
    for t = math.max(0, gi - reach), math.min(reaper.CountTracks(0) - 1, gi + reach) do
      local tr = reaper.GetTrack(0, t)
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        if not moving[it] then
          local p, l = item_start(it), item_len(it)
          list[#list + 1] = p; list[#list + 1] = p + l
          local so = reaper.GetMediaItemInfo_Value(it, "D_SNAPOFFSET")
          if so > 0 then list[#list + 1] = p + so end
        end
      end
    end
  end
  return list
end

-- The snapped time, whether it's on a relative grid, and whether it snapped at all
local function snap_time(t, origin)
  if not tg(SNAP) then return t end
  local flags = sh.flags
  local best, bd = nil, math.max(1, sh.itemsnap) / reaper.GetHZoomLevel()   -- (snap distance in seconds)
  for _, x in ipairs(sh.snaps) do
    local dd = math.abs(x - t)
    if dd <= bd then best, bd = x, dd end
  end
  -- (a marker, cursor, selection edge or item edge within the snap distance wins over the
  -- grid; the grid is off when it follows grid visibility and the grid is hidden)
  if not best and flags & 2 ~= 0 and not (flags & 32768 ~= 0 and flags & 1 == 0) then
    local g
    if sh.relsnap then
      local g0 = reaper.SnapToGrid(0, origin)                 -- (relative grid: in grid steps from where it was)
      g = origin + (reaper.SnapToGrid(0, g0 + (t - origin)) - g0)
    else
      g = reaper.SnapToGrid(0, t)
    end
    if flags & 1024 ~= 0 or math.abs(g - t) <= bd then return g, sh.relsnap, true end
  end
  return best or t, false, best ~= nil
end

-- The snap guide: a thin line on the arrange view at what the trim snapped to (nil: none)
local guide_bm, guide_x = nil, nil
local function guide(t)
  if not (reaper.JS_Composite and reaper.JS_LICE_CreateBitmap) then return end
  local x = nil
  if t then x = math.floor((t - reaper.GetSet_ArrangeView2(0, false, 0, 0)) * reaper.GetHZoomLevel() + 0.5) end
  if x == guide_x then return end
  local _, w, h = reaper.JS_Window_GetClientSize(ARRANGE)
  if guide_x then reaper.JS_Window_InvalidateRect(ARRANGE, guide_x - 2, 0, guide_x + 3, h, false) end
  if x and x >= 0 and x < w then
    if not guide_bm then
      guide_bm = reaper.JS_LICE_CreateBitmap(true, 1, 1)
      reaper.JS_LICE_Clear(guide_bm, GUIDE_COLOR)
    end
    reaper.JS_Composite(ARRANGE, x, 0, 1, h, guide_bm, 0, 0, 1, 1)
    reaper.JS_Window_InvalidateRect(ARRANGE, x - 2, 0, x + 3, h, false)
    guide_x = x
  else
    if guide_bm and guide_x then reaper.JS_Composite_Unlink(ARRANGE, guide_bm) end
    guide_x = nil
  end
end

-- Snapping goes by what the mouse is over: within the snap distance of a target, the cut
-- lands exactly there; otherwise the trim follows the mouse from where you pressed
local function trim_update(mx)
  if mx ~= sh.last_mx then   -- (the mouse hasn't moved: the trim stays as it is)
    sh.last_mx = mx
    local m = mouse_time(mx)
    local s_, rel, snapped = snap_time(m, sh.t0)
    guide(snapped and s_ or nil)
    local d
    if rel then d = s_ - sh.t0                              -- (relative grid: whole steps from the press)
    elseif math.abs(s_ - m) > EPS then d = s_ - sh.gP       -- (the cut lands on what the mouse is over)
    else d = m - sh.t0 end
    apply(clamp(d))
  end
  if sh.outline then RTcore.outline("leftedge", sh.outline) end   -- (drawn right as the edge moves)
end

-- As the Trim Tool's own trims and clicks end: 'items' selected (added to the selection if
-- 'keep'), the edit cursor at the selection's start, and with Link Timeline and Edit
-- Selection on, the time selection over it
local function select_like_trim_tool(items, keep)
  if not keep then reaper.SelectAllMediaItems(0, false) end
  for _, it in ipairs(items) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then reaper.SetMediaItemSelected(it, true) end
  end
  local s, e = math.huge, -math.huge
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    s = math.min(s, item_start(it)); e = math.max(e, item_start(it) + item_len(it))
  end
  if s == math.huge then return end
  reaper.SetEditCurPos(s, false, false)
  local link = reaper.NamedCommandLookup(LINK_CMD_GUID)
  if e > s and link ~= 0 and reaper.GetToggleCommandStateEx(0, link) == 1 then
    reaper.GetSet_LoopTimeRange(true, true, s, e, false)
  end
  reaper.UpdateArrange()
end
-- The Trim Tool's click on an edge it left to this script (the selection kept if it was selected)
local function trim_click(item)
  if reaper.ValidatePtr2(0, item, "MediaItem*") then select_like_trim_tool({ item }, reaper.IsMediaItemSelected(item)) end
end

local reaper_drag   -- REAPER's own drag under the trim (see end_reaper_drag, below)

-- The ripple mode changed during the drag: what's done so far stays, and the drag carries on
-- in the new mode from where everything is now (its items and tracks picked again)
local function trim_retarget(mx, mode)
  local prev = sh
  trim_begin(prev.grabbed, mx, mode == "off")
  for _, k in ipairs({ "started", "grabbed_was_selected", "trim_click", "no_jump", "view_s", "view_e" }) do sh[k] = prev[k] end
  if sh.no_jump then sh.gP = sh.t0 end
  if prev.outline and not sh.outline then RTcore.outline("leftedge", nil) end
  log("ripple mode changed to " .. mode .. ": carrying on from here")
end

local function trim_end(cancel)
  if not sh then return end
  local top = sh
  if top.outline then RTcore.outline("leftedge", nil) end
  if cancel then   -- (the whole drag goes back, mode changes and all: latest first)
    local seg = top
    while seg do sh = seg; apply(0); seg = seg.prev end
    sh = top
  end
  local changed, trimmed, seen = false, {}, {}
  local seg = top
  while seg do
    if math.abs(seg.d) > EPS then changed = true end
    for _, c in ipairs(seg.trims) do if not seen[c.it] then seen[c.it] = true; trimmed[#trimmed + 1] = c.it end end
    seg = seg.prev
  end
  changed = changed and not cancel
  if changed then
    -- (selection, edit cursor and loop points are left alone, as REAPER's own trims; with the
    -- Trim Tool they're set as its own trims set them)
    if sh.outline then select_like_trim_tool(trimmed, sh.grabbed_was_selected) end
    reaper.UpdateArrange()
    reaper.Undo_OnStateChange("Resize media items")
  elseif not cancel and sh.trim_click and not (reaper_drag and reaper_drag.moved) then
    trim_click(sh.grabbed)   -- (a click, not a drag that came back to where it started)
  end
  guide(nil)
  log(cancel and "cancelled" or string.format("trimmed %.3f s", sh.d))
  sh = nil
end

-- Scroll the view while dragging past the arrange's edge: it doesn't. The view stays where it
-- was at the press (anything else scrolling it is undone)
local function keep_view()
  local s, e = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  if sh.view_s and (math.abs(s - sh.view_s) > EPS or math.abs(e - sh.view_e) > EPS) then
    log(string.format("view moved by something else (%.3f -> %.3f s): put back", sh.view_s, s))
    s, e = sh.view_s, sh.view_e
    reaper.GetSet_ArrangeView2(0, true, 0, 0, s, e)
  end
  sh.view_s, sh.view_e = s, e
end

local function esc_down()
  if not (reaper.JS_VKeys_GetState and sh) then return false end
  local st = reaper.JS_VKeys_GetState(sh.started)   -- (pressed since the drag began)
  return st and st:byte(27) ~= 0
end

------------------------------------------------------------
-- Cmd on a left edge: REAPER switched to ripple all tracks, and back afterwards
------------------------------------------------------------
-- Shared with Shuffle move and the Trim Tool (the shared core's cmdall_set), so moving from one
-- of their zones to another doesn't switch back and forth
local cmd_state = { forced = false }
local function cmd_force(on)
  local was = cmd_state.forced
  RTcore.cmdall_set(cmd_state, "leftedge", on)
  if was ~= cmd_state.forced then log(cmd_state.forced and "Cmd on a left edge: ripple all tracks" or "Cmd let go: back") end
end

------------------------------------------------------------
-- Mouse modifiers switched for a moment (Tools library: the shared record)
------------------------------------------------------------
-- Taking a press on a left edge without holding it back: while the mouse is on a left edge,
-- REAPER's item-edge left drag (plain, or Cmd) is set to No action for the moment, so a
-- press there does nothing in REAPER and this script does the trim. (Only one script can
-- hold back a mouse press, and Shuffle and the Trim Tool already listen to it.) With Cmd also
-- REAPER's other Cmd drags and Cmd-clicks there (REAPER picks its action as the button goes
-- down, and could take the press as being on the item or the track: a copy, a split)
local HOLD_CTX = {
  [0] = { "MM_CTX_ITEMEDGE" },
  [2] = { "MM_CTX_ITEMEDGE", "MM_CTX_ITEM", "MM_CTX_ITEMLOWER", "MM_CTX_TRACK",
          "MM_CTX_ITEM_CLK", "MM_CTX_ITEMLOWER_CLK", "MM_CTX_TRACK_CLK" },
}
local hold = nil      -- the modifier flag switched off (0 plain, 2 Cmd)
-- (forget: let go without putting back, as another script now owns those settings, e.g. the Trim Tool)
local function set_hold(flag, forget)
  if hold == flag then return end
  if hold then for _, ctx in ipairs(HOLD_CTX[hold]) do RTcore.temp_give(OWNER, ctx, hold, forget) end end
  hold = flag
  if flag then for _, ctx in ipairs(HOLD_CTX[flag]) do RTcore.temp_take(OWNER, ctx, flag, "0") end end
end

-- REAPER's click actions for the modifier held, off while a drag is handed back (REAPER could
-- take that as a click: select the item, move the edit cursor), back a moment after the release
local CLICK_CTX = { "MM_CTX_ITEM_CLK", "MM_CTX_ITEMLOWER_CLK", "MM_CTX_TRACK_CLK" }
local click_flag, click_back_at = nil, nil   -- (the flag switched off)
local function clicks_off()
  if click_flag then return end
  local m = reaper.JS_Mouse_GetState(4 | 8 | 16 | 32) or 0
  click_flag = ((m & 8) ~= 0 and 1 or 0) | ((m & 4) ~= 0 and 2 or 0) | ((m & 16) ~= 0 and 4 or 0) | ((m & 32) ~= 0 and 8 or 0)
  for _, c in ipairs(CLICK_CTX) do RTcore.temp_take(OWNER .. "-click", c, click_flag, "0") end
end
local function clicks_on()
  if not click_flag then return end
  for _, c in ipairs(CLICK_CTX) do RTcore.temp_give(OWNER .. "-click", c, click_flag) end
  click_flag, click_back_at = nil, nil
end

-- (anything left switched by a crash: put back)
RTcore.temp_give_all(OWNER)
RTcore.temp_give_all(OWNER .. "-click")

------------------------------------------------------------
-- REAPER's own drag (the No action one under the trim): ended just before the mouse reaches
-- the arrange's left or right edge (where REAPER would scroll the view), once it's well clear
-- of the press (before that REAPER could take it as a click); the real release is then kept
-- from REAPER until it has come
------------------------------------------------------------
local up_block = nil            -- { last = time stamp, released = time } while the real release is kept from REAPER
local HANDBACK_MARGIN_PX = 24   -- (REAPER's drag ended this far before the arrange's edge)
local HANDBACK_CLEAR_PX = 16    -- (once the mouse is this far from the press)
local END_DRAG_PX = 6           -- (moved this far: a drag, not a click)
local TRIM_EDGE_PX = 6          -- Trim Tool: this close to an item's start counts as its left edge

local function end_reaper_drag(mx, my)
  if math.abs(mx - reaper_drag.x) >= END_DRAG_PX then reaper_drag.moved = true end
  if reaper_drag.ended then return end
  local ox = reaper.JS_Window_ClientToScreen(ARRANGE, 0, 0)
  local _, w = reaper.JS_Window_GetClientSize(ARRANGE)
  local speed = reaper_drag.lastx and math.abs(mx - reaper_drag.lastx) or 0
  reaper_drag.lastx = mx
  local margin = 0   -- (the margin grows with the mouse's speed)
  if math.abs(mx - reaper_drag.x) >= HANDBACK_CLEAR_PX then margin = math.max(HANDBACK_MARGIN_PX, math.floor(speed * 2 + 0.5)) end
  if mx >= ox + margin and mx <= ox + w - margin then return end
  clicks_off()
  local cx, cy = reaper.JS_Window_ScreenToClient(ARRANGE, mx, my)
  reaper.JS_WindowMessage_Send(ARRANGE, "WM_LBUTTONUP", 0, 0, cx, cy)   -- (REAPER: the drag is over)
  if reaper.JS_WindowMessage_Intercept(ARRANGE, "WM_LBUTTONUP", false) == 1 then
    local ok, _, t = reaper.JS_WindowMessage_Peek(ARRANGE, "WM_LBUTTONUP")
    up_block = { last = ok and t or nil }   -- (a new time stamp: the real one came)
  end
  reaper_drag.ended = true
  log("REAPER's drag ended (so it won't scroll the view)")
end

-- Let REAPER have mouse releases again once the real one has been kept from it (or, the
-- button's up and a moment has passed: the release went elsewhere, e.g. off the window)
local function check_up_block()
  if not up_block then return end
  local ok, _, t = reaper.JS_WindowMessage_Peek(ARRANGE, "WM_LBUTTONUP")
  if (ok and t ~= up_block.last) or (up_block.released and reaper.time_precise() - up_block.released > 0.5) then
    reaper.JS_WindowMessage_Release(ARRANGE, "WM_LBUTTONUP")
    up_block = nil
  end
end

local function start_drag(item, mx)
  trim_begin(item, mx)
  reaper_drag = { x = mx, ended = false }
  dragging = true
end
-- The button went up (or the drag was cancelled and then let go)
local function drag_over()
  dragging = false
  local now = reaper.time_precise()
  if up_block then up_block.released = now end
  if click_flag then click_back_at = now + 0.6 end
end

------------------------------------------------------------
-- Main loop
------------------------------------------------------------
local last_key_check, active, was_down = 0, false, false
local last_deferred = reaper.GetExtState(EXT, "TrimDeferredLeftEdge")   -- (the Trim Tool's note)

-- The item a Trim Tool note names: by GUID (a body drag: its edge isn't under the mouse), or
-- the one whose left edge is at the mouse
local function noted_item(note, mx, my)
  local guid = note:match("|(.+)$")
  if not guid then return item_at_left_edge(mx, my), false end
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if g == guid then return it, true end
  end
end

local function loop()
  local now = reaper.time_precise()
  if now - last_key_check > 0.25 then
    last_key_check = now
    if reaper.GetExtState(EXT, STOP) == "1" and not dragging then return end   -- (run again: off)
    reaper.SetExtState(EXT, BEAT, tostring(now), false)
    local was = active
    active = tg(RIPPLE_EDGES) and (tg(RIPPLE_PER_TRACK) or tg(RIPPLE_ALL))
    if was ~= active then log(active and "active" or "bypassed (not in a ripple mode, or ripple edge editing off)") end
  end

  local down = reaper.JS_Mouse_GetState(1) == 1
  local pressed = down and not was_down
  was_down = down

  if dragging then
    if sh then
      if not down then trim_end(false); drag_over()
      elseif esc_down() then trim_end(true)   -- (cancelled: the rest of the drag does nothing)
      else
        local mx, my = reaper.GetMousePosition()
        end_reaper_drag(mx, my)
        local mode = ripple_mode()
        if mode ~= sh.mode then trim_retarget(mx, mode) end
        keep_view()
        trim_update(mx)
        reaper.JS_Mouse_SetCursor(CURSOR_TRIM)
      end
    elseif not down then drag_over() end
    reaper.defer(loop)
    return
  end
  check_up_block()
  if click_back_at and not down and now >= click_back_at then clicks_on() end

  -- the Trim Tool is the active tool: plain edge drags are its own (it owns that setting:
  -- forgotten, not put back); only Cmd on a left edge is taken here
  local trim_tool = reaper.HasExtState(EXT, "TrimToolWorkerRunning")
  if trim_tool and hold == 0 then set_hold(nil, true) end

  local mx, my = reaper.GetMousePosition()
  -- the Trim Tool left a press on a single left edge to this script (Trim Tool 7.8.6+)
  if trim_tool then
    local note = reaper.GetExtState(EXT, "TrimDeferredLeftEdge")
    if note ~= "" and note ~= last_deferred then
      last_deferred = note
      local item, named = noted_item(note, mx, my)
      if item and not is_locked(item) then
        if down then
          start_drag(item, mx)
          sh.trim_click = true
          if named then sh.gP = sh.t0; sh.no_jump = true end   -- (its edge isn't under the mouse: no jump when snapping)
        else
          trim_click(item)   -- (pressed and let go between two looks: a click)
        end
        reaper.defer(loop)
        return
      end
    end
  end

  -- a press on a left edge while REAPER's edge drag is set to No action: the trim starts
  if hold and pressed then
    local item = item_at_left_edge(mx, my)
    if item and not is_locked(item) then
      start_drag(item, mx)
      reaper.defer(loop)
      return
    end
  end

  -- what's under the mouse (while the button is down, everything stays as it is)
  if not down then
    local hold_flag, on_edge, mods = nil, false, 0
    if reaper.JS_Window_FromPoint(mx, my) == ARRANGE then
      mods = reaper.JS_Mouse_GetState(4 | 8 | 16 | 32)
      if trim_tool then
        -- (the Trim Tool shows its trim cursor over the whole item, so the edge is measured)
        local item, left = item_at_left_edge(mx, my)
        on_edge = item ~= nil and math.abs(mx - left) <= TRIM_EDGE_PX
      else
        on_edge = tostring(reaper.JS_Mouse_GetCursor()) == LEFT_EDGE
      end
    end
    -- first: on a left edge? then: Cmd held? then REAPER goes to ripple all (and back after)
    cmd_force(on_edge and mods == 4)
    if on_edge then
      if mods == 0 and active and not trim_tool then hold_flag = 0
      elseif mods == 4 and (active or cmd_state.forced) then hold_flag = 2 end   -- (Cmd: REAPER's modifier 2)
    end
    set_hold(hold_flag)
  end
  reaper.defer(loop)
end

reaper.SetToggleCommandState(SEC, CMD, 1)
reaper.RefreshToolbar2(SEC, CMD)
reaper.atexit(function()
  if sh then trim_end(false) end
  if up_block then reaper.JS_WindowMessage_Release(ARRANGE, "WM_LBUTTONUP") end
  clicks_on()
  set_hold(nil)
  cmd_force(false)
  guide(nil)
  if guide_bm then reaper.JS_LICE_DestroyBitmap(guide_bm) end
  reaper.DeleteExtState(EXT, BEAT, false)
  reaper.DeleteExtState(EXT, STOP, false)
  reaper.SetExtState(EXT, ENDED, tostring(reaper.time_precise()), false)   -- (see the top)
  reaper.SetToggleCommandState(SEC, CMD, 0)
  reaper.RefreshToolbar2(SEC, CMD)
end)
reaper.defer(loop)

