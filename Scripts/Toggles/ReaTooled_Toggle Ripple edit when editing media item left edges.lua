--[[
-- @description ReaTooled - Ripple edit when editing media item left edges
-- @version 1.46
-- @date 2026.11.19
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
      - The view follows the drag (VIEW_FOLLOWS, on): the edge stays where it is on the
        timeline, and the view scrolls with the mouse so the edge stays under it and the audio
        after it stays put on screen, as in a plain trim. Past the arrange's left or right side
        the edge stays in sight there and the trim carries on by itself, faster the further
        past the mouse is (as REAPER's own edge drag scrolls). Off: the view stays put.
      - Trim Tool: in a ripple mode it hands left-edge trims (and left-side body drags) to
        this script; the trim then ends as the Trim Tool's own (selection, cursor, outline).
    Which items are trimmed: the grabbed one; if it's selected, the overlapping selected item on
    each other track; item groups; on grouped tracks (media editing), an item starting at the same
    time. In ripple all, as REAPER's own ripple, nothing more (select or group items to trim them
    together). Locked items are never trimmed or moved.
    What follows, as REAPER's own right-edge ripple: what reaches past the trimmed item's right
    edge (items after it, butted or crossfaded into it), on its track, on grouped tracks (per
    track) and every track (ripple all). Items inside it, and items that started earlier and
    run across, stay put. With auto-crossfade on, overlaps the drag makes get crossfades, live
    (content behind is never trimmed, as REAPER's own ripple); markers
    with "Ripple edit all affects regions/markers"; automation with "Move envelope points with
    media items". Take envelopes, stretch markers and snap offsets stay with the audio.
    Snaps as REAPER's own edge drag (a line shows what it snapped to). Esc cancels; one undo step ("Resize media items"). Remembered when REAPER restarts (Recall
    ReaTooled Button States; on its own, without the rest of ReaTooled, add it to REAPER's
    startup actions). Works on its own too: it needs only the js_ReaScriptAPI extension. The rules: "Left edge ripple - design rules.md".
-- CHANGELOG
-- v1.46 Coming back in from past the right side, the edge follows the mouse from where it's parked
--       (a little slower moving left, so the mouse catches up; PARK_RETURN) instead of the view
--       jumping back to put it under the mouse
-- v1.45 Past the arrange's right side, the edge is parked a third of the way in from it (the view
--       glides there, and back when the mouse comes back in), so the audio after the edge is in
--       sight as the trim carries on; parked at the side it was trimmed away out of sight
-- v1.44 Past 0:00 the view is set exactly a whole number of 16 px steps after where it should be,
--       then scrolled back that many steps the way a control surface does (exact to the pixel,
--       and the keys held don't matter). 1.43's wheel messages were taken as Cmd+wheel with Cmd
--       held, and macOS smoothed them, which made the view shake
-- v1.43 Past 0:00 the view is steered with horizontal wheel messages (REAPER puts any view start
--       set before 0:00 back at 0:00, even with the limit lifted); after 0:00 as before
-- v1.42 The view follows the drag past 0:00 too: REAPER's "Limit horizontal zoom/scroll to project
--       start" is lifted for the drag (SWS needed) and put back as it was when the drag ends.
--       Before, the view stopped at 0:00 and the edge stayed put while the trim went on
-- v1.41 Lighter press with auto-crossfade on (ripple all in a big session): only the pairs of items
--       whose overlap can change are tracked (not two that both move, or both stay), items the
--       trim can never reach aren't read, and lanes and fades are read only for the pairs kept.
--       The crossfades are the same
-- v1.40 Markers and automation items before where the moving starts stay put (inside the grabbed
--       item too). 1.39 sent the ones in the stretch that closes up to the join, so as the drag
--       went on they piled up at the item's new right edge. Envelope points are as in 1.39 (one
--       value at a time: those in the stretch that closes up still go)
-- v1.39 Markers and regions (ripple all, with "Ripple edit all affects regions/markers") stick
--       with placement too: from where the moving starts on the grabbed item's track they move,
--       inside the grabbed item they stay, in the stretch that closes up they go to the join (a
--       region's start and end each by that). Ripple all no longer trims other tracks' items that
--       start where the grabbed one does, as REAPER's own ripple (select or group them for that).
--       Auto-crossfade: the crossfades show live while dragging (worked out from the trim alone,
--       a fade written only when it changes; nothing more when not dragging)
-- v1.38 Snapping in a ripple: the targets are what moves towards the left edge (the starts, ends
--       and snap offsets of the items that ripple, and the markers and regions that ripple),
--       and a snap is one of them reaching the edge. What stays put never gets closer to the
--       edge, so it's no longer a target (it snapped to where a marker had been). The grid, and
--       ripple off during a drag, as before. Without the view following, the snap line is at the
--       edge too
-- v1.37 Automation sticks with item placement, on every track that ripples: it moves exactly where
--       items move, and stays under every item that stays put (the trimmed item itself, items
--       inside it, items that run across). 1.36 still moved it under the trimmed item (with its
--       audio) and under items running across the grabbed item's right edge on other tracks
-- v1.36 Automation on tracks without a trimmed item (grouped tracks, every track in ripple all)
--       closes up where their items do, at the grabbed item's right edge, so it stays with them.
--       In 1.35 it still closed up from the grabbed item's start: under the grabbed item it moved
--       while the items there stayed put. Tracks with a trimmed item: as before
-- v1.35 What follows is now what REAPER's own right-edge ripple moves: what reaches past the
--       trimmed item's right edge (items after it, butted or crossfaded into it). Items inside it
--       (layered, or on another lane) stay put; they used to move, and could end up before the
--       trimmed item. Grouped tracks: only an item starting where the grabbed one does is
--       trimmed (one that only overlapped it, starting elsewhere, was trimmed from its own start,
--       out of sync). With auto-crossfade on, overlaps the drag makes get crossfades, as REAPER's
--       own ripple (content behind is never trimmed, as REAPER doesn't for what a ripple moves)
-- v1.33.1 The test log (1.33) is taken out
-- v1.33 (testing) Each drag writes what the trim and the view were asked to do, and what REAPER
--       did, to Data/ReaTooled/leftedge_view_log.txt (a new file each drag). To be taken out
-- v1.32 The view following the drag: past the arrange's left or right side, the edge stays in
--       sight just inside it and the trim carries on by itself, faster the further past the mouse
--       is, as REAPER's own edge drag scrolls the view there (the audio after the edge moves on
--       screen meanwhile, as the view can't follow both). Moving back in carries on from there
-- v1.31 Cmd works as REAPER's own mouse modifiers do again: Cmd at the press decides the drag
--       (ripple all tracks until the mouse goes up), as the Trim Tool does; 1.28's switching
--       when Cmd is pressed or let go during the drag is taken out. Changing the ripple mode
--       during a drag still carries on in the new mode (1.18, with 1.29-1.30's fixes)
-- v1.30 No jump when switching modes a second time in one drag (Cmd for ripple all, let go, Cmd
--       again, let go). Each switch kept the view's position from the first part of the drag
--       where the view stayed put, so after the view had followed in between, it was put back
--       there: the view jumped by everything the drag had scrolled since. Each part of the drag
--       now starts from where the view is
-- v1.29 No jump when the ripple mode changes during a drag (letting go of Cmd, or switching the
--       mode by hand). The drag carried on measuring snaps from the item's start, not from the
--       mouse: with the mouse a few pixels off the edge, or with something to snap to nearby,
--       the trim jumped by that much at the switch. It now carries on from exactly where the
--       mouse is, and doesn't snap until the mouse moves again
-- v1.28 Cmd during a drag: pressing or letting go of Cmd switches ripple all tracks on and off
--       right away (back to the ripple mode you started in, ripple off included), and the drag
--       carries on in that mode (as 1.18). It used to switch back only after the mouse went up
--     • The view readout (1.26) taken out
-- v1.27 The view following the drag: no more vibration. The readout showed REAPER rounding the
--       view's start down to a whole pixel, and the start asked for (a whole pixel, worked out
--       in seconds) landing a hair under it about every other frame: the view went one pixel too
--       far, then back. The start is now asked for a quarter pixel past the pixel wanted, so it
--       always lands on it. (The readout, 1.26, stays for testing)
-- v1.26 Testing: a per-frame readout of the view following the drag, to the ReaScript console,
--       when "ReaTooled_DEV Left edge view readout.lua" turns it on (off otherwise: nothing
--       measured or printed). No change to the trim or the view
-- v1.25 Back to 1.23 (1.24's "trim by what REAPER really scrolled" made the drag shake more)
-- v1.23 The view following the drag is steadier and lighter: the trim and the view's scroll are
--       drawn in one redraw a frame (they were two), and the view scrolls in whole pixels, so
--       the audio after the cut doesn't shimmer by a pixel as you drag
-- v1.22 The view follows the drag (setting VIEW_FOLLOWS, on). What's edited is the same as 1.21:
--       the item's start stays put on the timeline and what follows closes up; but the view
--       scrolls by as much as the trim, so on screen the edge moves with the mouse and the
--       audio after it stays where it is, as in a plain edge trim. The trim is measured from
--       where you pressed, as before (snapping and grid alike); the snap line is drawn at the
--       edge. Esc puts the view back too; on release the view stays where the drag left it.
--       Ripple off during the drag (1.18): the view stops following, the edge moves instead
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

-- Set up ReaTooled hasn't run here: the user's own mouse modifiers haven't been backed up,
-- so this tool leaves them alone (3.04: running a tool before setup had replaced them)
if not reaper.file_exists(reaper.GetResourcePath():gsub("\\", "/") .. "/Data/ReaTooled/Backups/Before ReaTooled/backup_info.txt") then
  reaper.ShowMessageBox("ReaTooled isn't set up yet, so this tool won't change your mouse settings.\n\n" ..
    "Run \"Set up ReaTooled\" from the Actions list first. It backs up your settings before changing anything.",
    "ReaTooled", 0)
  return
end

------------------------------------------------------------
-- SETTINGS (change, then turn the script off and on again)
------------------------------------------------------------
local GUIDE_COLOR = 0xD0FFFFFF   -- the snap guide line: 0xAARRGGBB (alpha, red, green, blue)
local DEBUG       = false        -- print what happens to the ReaScript console
-- The view follows the drag: true = the view scrolls with the trim, so the edge stays under the
-- mouse and the audio after it stays put on screen (the item's start still stays put on the
-- timeline: only the view moves). false = the view stays put (1.21 and before)
local VIEW_FOLLOWS = true

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
--   C.outline(owner, items, redrawn, ends, box): the yellow outline around items being edited
--     (box = { start, end }: also a frame around that stretch of time, across all tracks;
--     box.fit: one frame for each run of neighbouring tracks with items outlined)
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
function C.outline(owner, items, redrawn, ends, box)
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
  -- frames around what moves (first, so they're always drawn): with box.fit, one around
  -- each run of neighbouring tracks that have items moving (tracks in between that have
  -- none aren't framed); otherwise one around box's stretch of time across all tracks
  local function frame(t1, t2, top, bottom)
    local x1 = math.floor((t1 - view) * zoom + 0.5)
    local x2 = math.floor((t2 - view) * zoom + 0.5)
    local y1, y2 = math.floor(top), math.floor(bottom)
    if x2 > 0 and x1 < w and y2 > 0 and y1 < h and x2 - x1 >= 1 then
      local cx1, cx2 = math.max(x1, -OUTLINE_PX), math.min(x2, w + OUTLINE_PX)
      local cy1, cy2 = math.max(y1, -OUTLINE_PX), math.min(y2, h + OUTLINE_PX)
      local function add(x, y, ww, hh)
        if ww > 0 and hh > 0 then n = n + 1; want[n] = { x, y, ww, hh } end
      end
      if y1 >= -OUTLINE_PX then add(cx1, y1, cx2 - cx1, OUTLINE_PX) end                 -- top
      if y2 <= h + OUTLINE_PX then add(cx1, y2 - OUTLINE_PX, cx2 - cx1, OUTLINE_PX) end -- bottom
      if x1 >= -OUTLINE_PX then add(x1, cy1, OUTLINE_PX, cy2 - cy1) end                 -- left
      if x2 <= w + OUTLINE_PX then add(x2 - OUTLINE_PX, cy1, OUTLINE_PX, cy2 - cy1) end -- right
    end
  end
  if box and items and #items > 0 then
    if box.fit then
      -- per track: the moving items' span in time and height
      local per = {}
      for _, it in ipairs(items) do
        if reaper.ValidatePtr2(0, it, "MediaItem*") then
          local tr = reaper.GetMediaItem_Track(it)
          local ty = reaper.GetMediaTrackInfo_Value(tr, "I_TCPY")
          local iy = reaper.GetMediaItemInfo_Value(it, "I_LASTY")
          local ih = reaper.GetMediaItemInfo_Value(it, "I_LASTH")
          if reaper.GetMediaTrackInfo_Value(tr, "I_TCPH") > 0 and ih > 0 then
            local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
            local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
            local r = per[tr]
            if not r then r = { a = p, b = e, top = ty + iy, bottom = ty + iy + ih }; per[tr] = r end
            r.a, r.b = math.min(r.a, p), math.max(r.b, e)
            r.top, r.bottom = math.min(r.top, ty + iy), math.max(r.bottom, ty + iy + ih)
          end
        end
      end
      -- runs of neighbouring tracks (in track order, counting only tracks shown)
      local run
      for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        if reaper.IsTrackVisible(tr, false) and reaper.GetMediaTrackInfo_Value(tr, "I_WNDH") > 0 then
          local r = per[tr]
          if r then
            if run then
              run.a, run.b = math.min(run.a, r.a), math.max(run.b, r.b)
              run.bottom = math.max(run.bottom, r.bottom)
            else
              run = { a = r.a, b = r.b, top = r.top, bottom = r.bottom }
            end
          elseif run then
            frame(run.a, run.b, run.top, run.bottom); run = nil
          end
        end
      end
      if run then frame(run.a, run.b, run.top, run.bottom) end
    else
      local top, bottom
      for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        if reaper.IsTrackVisible(tr, false) then
          local ty = reaper.GetMediaTrackInfo_Value(tr, "I_TCPY")
          local wh = reaper.GetMediaTrackInfo_Value(tr, "I_WNDH")
          if wh > 0 then
            if not top or ty < top then top = ty end
            if not bottom or ty + wh > bottom then bottom = ty + wh end
          end
        end
      end
      if top then frame(box[1], box[2], top, bottom) end
    end
  end
  local boxes = n
  for _, it in ipairs(items or {}) do
    if n >= OUTLINE_MAX * 4 + boxes then break end
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
local ALL_START_TOL = 0.005   -- grouped tracks: an item starting this close to the grabbed one is trimmed with it
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
  -- (an item starting where the grabbed one does, as REAPER's own group edits: one that only
  -- overlaps it, starting elsewhere, isn't trimmed; it stays, like anything else running across)
  for tr in pairs(grouped) do
    if not drivers[tr] then
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        if not is_locked(it) and math.abs(item_start(it) - s) <= ALL_START_TOL then drivers[tr] = it; break end
      end
    end
  end
  return drivers, grouped, s, e
end

------------------------------------------------------------
-- The ripple trim
------------------------------------------------------------
local sh = nil                -- the ripple trim going on
local mark_place, live_xfades  -- (defined with apply, below)
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

-- Automation sticks with item placement (v1.37), on every track that ripples: it moves exactly
-- where items move. On each track, m is where the moving starts (the trimmed item's right edge,
-- or the grabbed item's on tracks without one, or the start of the earliest item that moves
-- there if that's sooner, e.g. one crossfaded into it), and holds are the items there that stay
-- put (not trimmed, not moved). For a trim of d:
--   - points from m on move by -d, except under an item that stays put: those stay
--   - a moved point that lands on an item that stays put goes (that item keeps its own)
--   - points in the stretch that closes up [m - d, m) go, except under an item that stays put
--   - points before that stay
--   - where what moved shows from, the value on each side stays what it was (two points); a
--     stretch that opens (d < 0) holds the value across it
-- Everything from en.at (the furthest anything can reach) is rebuilt each frame from the press
local function in_closed(spans, t)
  for _, h in ipairs(spans) do if t >= h[1] - TOL and t <= h[2] + TOL then return h end end
end
local function in_open(spans, t)
  for _, h in ipairs(spans) do if t > h[1] + TOL and t < h[2] - TOL then return h end end
end
local function apply_env_items(en, d)
  local m, lo, holds = en.m, en.at, en.holds
  local j = (d > 0) and (m - d) or m
  -- (points are gathered, then put in in order: at a join, the value before it, then after it,
  -- a microsecond apart, so the order never depends on how REAPER sorts points at one time)
  local pend = {}
  local function add(t, v, ord, shape, tens, sel)
    pend[#pend + 1] = { t = t, v = v, ord = ord, n = #pend, shape = shape or 0, tens = tens or 0, sel = sel or false }
  end
  local function ins(t, v) add(t, v, 1) end
  reaper.DeleteEnvelopePointRange(en.env, lo - 1e-6, 1e12)
  for _, p in ipairs(en.all) do
    if p.t >= lo - 1e-6 then
      local t = p.t
      if p.t >= m - TOL and not in_closed(holds, p.t) then
        t = p.t - d                                         -- (moves with the items)
        if in_closed(holds, t) then t = nil end             -- (lands on an item that stays put)
      elseif d > 0 and p.t >= j - EPS and p.t < m - TOL and not in_closed(holds, p.t) then
        t = nil                                             -- (in the stretch that closes up)
      end
      if t then add(t, p.v, 1, p.shape, p.tens, p.sel) end
    end
  end
  if math.abs(d) > EPS and #en.all > 0 then
    -- (the joins: where what moved meets what stays, the value on each side stays what it was)
    local function hold_at(t) for _, h in ipairs(holds) do if t >= h[1] - TOL and t < h[2] - TOL then return h end end end
    local function va(t) return value_at(en.all, t) end
    local function two(t, l, r) if l then add(t, l, 0) end; if r then add(t, r, 2) end end
    if d > 0 then
      if not hold_at(j) then two(j, va(j), va(m)) end           -- (the stretch that closed up)
      for _, h in ipairs(holds) do
        if h[2] > j + TOL then
          if h[1] >= m - TOL then
            -- (an item after m that stays put: what moved before it ends d before it)
            local v = va(h[1])
            if v then
              if not hold_at(h[1] - d) then ins(h[1] - d, v) end
              ins(h[1], v)   -- (its own automation starts where it did)
            end
          elseif h[1] > j + TOL then
            -- (one in the stretch that closes up: what moved meets it at its start)
            two(h[1], va(h[1] + d), va(h[1]))
          end
          -- (what moved shows again from its end)
          if h[2] + d >= m - TOL and not in_closed(holds, h[2] + d) then two(h[2], va(h[2]), va(h[2] + d)) end
        end
      end
    else
      if not hold_at(m) then local v = va(m); if v then ins(m, v); ins(m - d, v) end end   -- (the stretch that opens)
      for _, h in ipairs(holds) do
        if h[1] > m + TOL then two(h[1], va(h[1] + d), va(h[1])) end
        if h[2] > m + TOL then local v2 = va(h[2]); if v2 then ins(h[2], v2); ins(h[2] - d, v2) end end
      end
    end
  end
  table.sort(pend, function(a, b)
    if math.abs(a.t - b.t) > 1e-9 then return a.t < b.t end
    if a.ord ~= b.ord then return a.ord < b.ord end
    return a.n < b.n
  end)
  local last_t, k = nil, 0
  for _, q in ipairs(pend) do
    if last_t and math.abs(q.t - last_t) <= 1e-9 then k = k + 1 else last_t, k = q.t, 0 end
    reaper.InsertEnvelopePoint(en.env, q.t + k * 1e-6, q.v, q.shape, q.tens, q.sel, true)
  end
  reaper.Envelope_SortPoints(en.env)
  for _, ai in ipairs(en.ais) do
    local p = ai.p
    -- (an automation item is a block, as an item: from m on it moves, before that it stays put)
    if p >= m - TOL and not in_closed(holds, p) then p = p - d end
    reaper.GetSetAutomationItemInfo(en.env, ai.i, "D_POSITION", p, true)
  end
end

-- The view following the drag past 0:00. REAPER's "Limit horizontal zoom/scroll to project start"
-- (Preferences; on: bit 4 of vscrollflag clear) keeps the view from starting before 0:00, so the
-- view stopped following there (the edge stayed put while the trim went on). For the drag it's
-- lifted, and put back as it was when the drag ends; if the script stopped in between, it's put
-- back the next time it runs. Needs SWS (SNM_SetIntConfigVar); without it, as before
local VSCROLL_FREE = 4
local VS_KEY = "RippleLeftEdges_vscrollflag"
local function vscroll_free()
  if not reaper.SNM_SetIntConfigVar then return end
  local ok, v = reaper.get_config_var_string("vscrollflag")
  v = ok and math.tointeger(tonumber(v)) or nil
  if not v or v & VSCROLL_FREE ~= 0 or reaper.HasExtState(EXT, VS_KEY) then return end
  reaper.SetExtState(EXT, VS_KEY, tostring(v), false)
  reaper.SNM_SetIntConfigVar("vscrollflag", v | VSCROLL_FREE)
end
local function vscroll_restore()
  local saved = math.tointeger(tonumber(reaper.GetExtState(EXT, VS_KEY)))
  if saved and reaper.SNM_SetIntConfigVar then reaper.SNM_SetIntConfigVar("vscrollflag", saved) end
  reaper.DeleteExtState(EXT, VS_KEY, false)
end
vscroll_restore()   -- (left lifted by a script that stopped mid-drag)

local function cfg_int(name)
  local ok, v = reaper.get_config_var_string(name)
  return ok and math.tointeger(tonumber(v)) or 0
end

-- The view following the drag, past the arrange's left or right side: the edge stays just
-- inside it, and the trim carries on by itself (auto_d), faster the further past the mouse is,
-- as REAPER's own edge drag scrolls the view there
local AUTO_INSET_PX = 2       -- (the edge kept this far inside the side)
local AUTO_BASE_PX_S = 300    -- speed at the side, in pixels a second
local AUTO_PER_PX_S = 30      -- and this much faster for each pixel past it
local AUTO_MAX_PX_S = 6000

-- The mouse kept within the arrange's sides (and how far past them it is: - left, + right)
local function arrange_sides(mx)
  local ox = reaper.JS_Window_ClientToScreen(ARRANGE, 0, 0)
  local _, w = reaper.JS_Window_GetClientSize(ARRANGE)
  local lo, hi = ox + AUTO_INSET_PX, ox + w - 1 - AUTO_INSET_PX
  if mx < lo then return lo, mx - lo end
  if mx > hi then return hi, mx - hi end
  return mx, 0
end

local function auto_scroll(mx)
  local now = reaper.time_precise()
  local dt = sh.auto_t and math.min(now - sh.auto_t, 0.1) or 0
  sh.auto_t = now
  local inside, past = arrange_sides(mx)
  sh.mx_in, sh.auto_past = inside, past
  if past ~= 0 and dt > 0 then
    local speed = math.min(AUTO_MAX_PX_S, AUTO_BASE_PX_S + math.abs(past) * AUTO_PER_PX_S)
    sh.auto_d = sh.auto_d + (past > 0 and 1 or -1) * speed * dt / reaper.GetHZoomLevel()
    sh.last_mx = nil   -- (the trim carries on while the mouse stays still)
  end
end

-- Auto-crossfade, as REAPER's own right-edge ripple: where the drag leaves two items on a lane
-- partly overlapping (one ending inside the other, not one inside the other), that didn't
-- overlap that way at the press, they get a crossfade over the overlap; one the drag took away
-- goes. Content behind is never trimmed (REAPER doesn't, for what a ripple moves)
local AUTO_XFADE = 40041   -- Options: Toggle auto-crossfade on/off
-- (how far two items partly overlap: the first ends inside the second; nil otherwise)
local function part_overlap(x, y)
  if y.p < x.p then x, y = y, x end
  if x.p < y.p - EPS and x.e > y.p + EPS and x.e < y.e - EPS then return x.e - y.p end
end
-- plain: ripple off (from a mode change during the drag): the left edge is trimmed as REAPER
-- does without ripple (the item's start moves, nothing else does)
local function trim_begin(grabbed, mx, plain)
  if VIEW_FOLLOWS and not plain then vscroll_free() end   -- (the view can follow past 0:00)
  local drivers, grouped, gs, ge = plan(grabbed)
  local all = ripple_all()
  if plain then grouped, all = {}, false end
  local vs, ve = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  if VIEW_FOLLOWS and not plain then mx = arrange_sides(mx) end   -- (a part begun past a side: from it)
  local s_ = { d = 0, t0 = mouse_time(mx), x0 = mx, fv_s = vs, fv_e = ve, auto_d = 0, auto_past = 0,
               follow = VIEW_FOLLOWS and not plain,
               trims = {}, movers = {}, markers = {}, envs = {},
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
  local maxL = 0   -- (the most anything can be trimmed: how far back the join can reach)
  for _, c in ipairs(s_.trims) do maxL = math.max(maxL, c.L) end
  for tr, own in pairs(scope) do
    -- What moves, as REAPER's own right-edge ripple: what reaches past the trimmed item's right
    -- edge (items after it, butted or crossfaded into it). Items inside it stay put, on any lane,
    -- and so does anything that started before it and runs across. On tracks without a trimmed
    -- item, the same measured against the grabbed item
    local after = own and (item_start(own) + EPS) or (gs + TOL)
    local past = own and (item_start(own) + item_len(own)) or ge
    local m, here = past, {}   -- (m: where the moving starts on this track)
    local is_grabbed_track = (tr == reaper.GetMediaItem_Track(grabbed))
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      if not moving[it] and not is_locked(it) then
        local p = item_start(it)
        if p > after and p + item_len(it) > past + TOL then
          s_.movers[#s_.movers + 1] = { it = it, p = p }
          here[it] = true
          m = math.min(m, p)
        end
      end
    end
    if is_grabbed_track then s_.mark_m = m end
    if env_follow then
      -- (automation sticks with item placement: it moves where the items move, and stays under
      -- every item that stays put)
      local lo = m - maxL - TOL
      local holds = {}
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        if not moving[it] and not here[it] then
          local p = item_start(it)
          local e = p + item_len(it)
          if e > lo then holds[#holds + 1] = { p, e } end
        end
      end
      table.sort(holds, function(a, b) return a[1] < b[1] end)
      local n = #s_.envs
      capture_env(tr, lo, s_.envs)
      for k = n + 1, #s_.envs do s_.envs[k].m, s_.envs[k].holds = m, holds end
    end
  end
  for _, m in ipairs(s_.movers) do moving[m.it] = true end
  -- (live crossfades: worked out once, at the press. Only pairs that can change are kept: two
  -- items that both move keep their overlap, and two that both stay keep theirs, so only pairs
  -- with the trimmed item, or with an item that stays put next to one that moves, are tracked.
  -- Items ending before the furthest the trim can reach never meet anything and aren't read.
  -- Lanes and fades are read only for the items in those pairs)
  s_.autoxf = tg(AUTO_XFADE)
  s_.xf = (sh and sh.xf) or {}
  s_.xorig, s_.xcur, s_.xpairs = (sh and sh.xorig) or {}, (sh and sh.xcur) or {}, {}
  if s_.autoxf then
    local kind, from = {}, {}   -- item -> { "trim"/"move", start, length }; track -> earliest start
    local function note(it, k, p0, l0)
      kind[it] = { k, p0, l0 }
      local tr = reaper.GetMediaItem_Track(it)
      from[tr] = math.min(from[tr] or math.huge, p0)
    end
    for _, c in ipairs(s_.trims) do note(c.it, "trim", c.P, c.L) end
    for _, mv in ipairs(s_.movers) do note(mv.it, "move", mv.p, item_len(mv.it)) end
    for tr, first in pairs(from) do
      local reach = first - maxL - TOL
      local was = s_.xf[tr] or {}
      s_.xf[tr] = was
      local list = {}
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        local p0, l0 = item_start(it), item_len(it)
        if p0 + l0 >= reach then
          -- (where it was at the drag's first press: kept from an earlier part of the drag)
          if not was[it] then was[it] = { p = p0, e = p0 + l0 } end
          local k = kind[it]
          local e = { it = it, was = was[it] }
          if k then e.kind, e.p, e.len = k[1], k[2], k[3]
          else e.kind, e.p, e.len = "stay", p0, l0 end
          list[#list + 1] = e
        end
      end
      table.sort(list, function(a, b) return a.p < b.p end)
      local function lane(e)
        if e.lane == nil then e.lane = reaper.GetMediaItemInfo_Value(e.it, "I_FIXEDLANE") end
        return e.lane
      end
      local function orig(e)
        if not s_.xorig[e.it] then
          s_.xorig[e.it] = { fin = reaper.GetMediaItemInfo_Value(e.it, "D_FADEINLEN_AUTO"),
                             fout = reaper.GetMediaItemInfo_Value(e.it, "D_FADEOUTLEN_AUTO") }
        end
      end
      for a = 1, #list do
        local x = list[a]
        for b = a + 1, #list do
          local y = list[b]
          if y.p > x.p + x.len + maxL + TOL then break end   -- (too far to ever meet)
          local same = (x.kind == y.kind) and (x.kind == "stay" or x.kind == "move")
          if not same and lane(x) == lane(y) then
            orig(x); orig(y)
            s_.xpairs[#s_.xpairs + 1] = { x = x, y = y }
          end
        end
      end
    end
  end
  if all and tg(MARKERS_FOLLOW) then
    local i = 0
    while true do
      local ok, isrgn, pos, rend, name, num, color = reaper.EnumProjectMarkers3(0, i)
      if ok == 0 then break end
      -- (markers stick with placement, as the items and the automation: from where the moving
      -- starts on the grabbed item's track; a region's start and end each go by that)
      local lo = (s_.mark_m or ge) - maxL - TOL
      if pos >= lo or (isrgn and rend >= lo) then
        s_.markers[#s_.markers + 1] = { isrgn = isrgn, pos = pos, rend = rend, name = name, num = num, color = color }
      end
      i = i + 1
    end
  end
  s_.snaps = snap_targets(grabbed, moving, s_.flags, (not plain) and s_ or nil)
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

-- Where a marker (or a region's start or end) goes for a trim of d: as the items, from where the
-- moving starts (M) on it moves by -d; before that it stays put, inside the grabbed item too
-- (1.39 sent the ones in the stretch that closes up to the join, so they piled up there)
mark_place = function(t, d)
  if t >= sh.mark_m - TOL then return t - d end
  return t
end

-- Live crossfades (auto-crossfade on): the pairs that can meet are worked out at the press
-- (sh.xpairs); on each change of the trim their spans are worked out from the trim alone (no
-- reading items), and a fade is written only when its value changes. Two items on a lane that
-- partly overlap now, and didn't that way at the press, get a crossfade over the overlap; one
-- the drag took away goes; everything else is back as it was at the press
local function xspan(e, d)
  if e.kind == "trim" then
    if sh.plain then return e.p + d, e.p + e.len end
    return e.p, e.p + e.len - d
  elseif e.kind == "move" then return e.p - d, e.p - d + e.len end
  return e.p, e.p + e.len
end
live_xfades = function(d)
  if not (sh.autoxf and sh.xpairs and #sh.xpairs > 0) then return end
  local want = {}
  local function W(it) local w = want[it]; if not w then w = {}; want[it] = w end; return w end
  for _, pr in ipairs(sh.xpairs) do
    local xs, xe = xspan(pr.x, d)
    local ys, ye = xspan(pr.y, d)
    local first, second = pr.x, pr.y
    if ys < xs then first, second = pr.y, pr.x end
    local ov = part_overlap({ p = xs, e = xe }, { p = ys, e = ye })
    local ov0 = pr.x.was and pr.y.was and part_overlap(pr.x.was, pr.y.was)
    if ov and not (ov0 and math.abs(ov - ov0) < 1e-6) then
      W(first.it).fout = ov; W(second.it).fin = ov
    elseif not ov and ov0 then
      local o1, o2 = sh.xorig[first.it], sh.xorig[second.it]
      if o1 and math.abs(o1.fout - ov0) < 1e-6 then W(first.it).fout = -1 end
      if o2 and math.abs(o2.fin - ov0) < 1e-6 then W(second.it).fin = -1 end
    end
  end
  local function put(it, key, parm, v)
    local cur = sh.xcur[it]
    local now = cur and cur[key]
    if now == nil then now = sh.xorig[it][key] end
    if math.abs(now - v) > 1e-9 then
      reaper.SetMediaItemInfo_Value(it, parm, v)
      cur = cur or {}; cur[key] = v; sh.xcur[it] = cur
    end
  end
  for it, w in pairs(want) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      if w.fout then put(it, "fout", "D_FADEOUTLEN_AUTO", w.fout) end
      if w.fin then put(it, "fin", "D_FADEINLEN_AUTO", w.fin) end
    end
  end
  -- (set before, not wanted now: back as at the press)
  for it, cur in pairs(sh.xcur) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      local w = want[it] or {}
      if cur.fout ~= nil and w.fout == nil then put(it, "fout", "D_FADEOUTLEN_AUTO", sh.xorig[it].fout) end
      if cur.fin ~= nil and w.fin == nil then put(it, "fin", "D_FADEINLEN_AUTO", sh.xorig[it].fin) end
    end
  end
end

-- (no_redraw: the caller redraws, once, with the view's scroll: see trim_update)
local function apply(d, no_redraw)
  if math.abs(d - sh.d) < EPS then return false end
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
  for _, en in ipairs(sh.envs) do apply_env_items(en, d) end
  for _, m in ipairs(sh.markers) do
    local a, b = mark_place(m.pos, d), m.isrgn and mark_place(m.rend, d) or 0
    if m.isrgn and b < a then b = a end
    reaper.SetProjectMarker3(0, m.num, m.isrgn, a, b, m.name, m.color)
  end
  live_xfades(d)
  reaper.PreventUIRefresh(-1)
  if not no_redraw then reaper.UpdateArrange() end
  return true
end

------------------------------------------------------------
-- Snapping, as REAPER's own edge drag, from its Snap/Grid settings (projshowgrid bits,
-- measured in REAPER 7.85: 1 show grid, 2 media items to grid, 16 media items to
-- selection/markers/cursor, 128 snap to nearby media items (maxsnaptrack tracks away),
-- 1024 grid at any distance, 32768 grid snap follows grid visibility; itemsnap = snap
-- distance in pixels; relsnap = relative grid)
------------------------------------------------------------
-- What the trim point can snap to (fixed while dragging).
-- In a ripple (rip: this part of the drag), the left edge stays put on the timeline and what
-- ripples slides towards it, so the targets are what moves: the starts, ends and snap offsets
-- of the items that ripple (on tracks within maxsnaptrack), and the markers and region edges
-- that ripple (ripple all, with "Ripple edit all affects regions/markers"). A snap is the moment
-- one of them reaches the edge (the trim = where it was at the press - the edge). What stays put
-- (other items, markers that don't ripple, the edit cursor, the time selection) never gets any
-- closer to the edge, so it isn't a target. Without ripple (plain: the edge moves, as REAPER's
-- own drag): markers, region edges, time selection, edit cursor, other items' edges and snap
-- offsets nearby, as REAPER's
function snap_targets(grabbed, moving, flags, rip)
  local list = {}
  if rip then
    if flags & 16 ~= 0 then
      local M = rip.mark_m or 0
      for _, mk in ipairs(rip.markers) do
        if mk.pos >= M - TOL then list[#list + 1] = mk.pos end
        if mk.isrgn and mk.rend >= M - TOL then list[#list + 1] = mk.rend end
      end
    end
    if flags & 128 ~= 0 then
      local gi = reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(grabbed), "IP_TRACKNUMBER") - 1
      local reach = cfg_int("maxsnaptrack")
      for _, mv in ipairs(rip.movers) do
        local ti = reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(mv.it), "IP_TRACKNUMBER") - 1
        if math.abs(ti - gi) <= reach then
          local p, l = mv.p, item_len(mv.it)
          list[#list + 1] = p; list[#list + 1] = p + l
          local so = reaper.GetMediaItemInfo_Value(mv.it, "D_SNAPOFFSET")
          if so > 0 then list[#list + 1] = p + so end
        end
      end
    end
    return list
  end
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

-- The view follows the trim (VIEW_FOLLOWS): scrolled back by as much as is trimmed, from where
-- it was when this part of the drag began, so the edge stays under the mouse and the audio after
-- it stays put on screen. Anything else scrolling it (REAPER's own drag) is undone; where REAPER
-- won't scroll that far (before the project start), it's left where REAPER put it
-- Before 0:00 the view can't be set exactly: REAPER puts any view start set before 0:00 back at
-- 0:00, even with the limit lifted (tested). Control-surface scrolling does go there, by exactly 16
-- px a step at any zoom, and it ignores the keys held (Cmd included; tested). (Horizontal wheel
-- messages, 1.43, were taken as Cmd+wheel with Cmd held, and macOS smooths them over several
-- frames, which made the view shake.) So the view is set exactly where k whole steps back land on
-- the pixel wanted (that's after 0:00, so allowed), then scrolled back k steps, all in one redraw.
-- The step is measured as it goes: if one call scrolls only one step, the rest go one by one
local STEP = { px = 16, single = false }
local function scroll_before_zero(want, z)
  local k = math.ceil(-want / STEP.px - 1e-9)
  local p = want + k * STEP.px                       -- (>= 0: where the view is set exactly)
  local width = sh.fv_e - sh.fv_s
  reaper.PreventUIRefresh(1)
  local ts = (p + 0.25) / z
  reaper.GetSet_ArrangeView2(0, true, 0, 0, ts, ts + width)
  local s1 = reaper.GetSet_ArrangeView2(0, false, 0, 0) * z
  if STEP.single then
    for _ = 1, k do reaper.CSurf_OnScroll(-1, 0) end
  elseif k > 0 then
    reaper.CSurf_OnScroll(-k, 0)
    local moved = s1 - reaper.GetSet_ArrangeView2(0, false, 0, 0) * z
    if k > 1 and math.abs(moved - STEP.px) < 0.5 then
      STEP.single = true                             -- (one step a call: the rest one by one)
      for _ = 2, k do reaper.CSurf_OnScroll(-1, 0) end
    elseif moved > 0.5 and math.abs(moved - k * STEP.px) >= 0.5 then
      STEP.px = moved / k                            -- (a different step here: from now on)
    end
  end
  reaper.PreventUIRefresh(-1)
  return true
end

-- Past the arrange's right side, the edge is parked a third of the way in from it, so the audio
-- after it (to its right) is in sight as it slides into the edge; parked at the side itself, as
-- REAPER's own edge drag does, it was trimmed away out of sight. The view glides there (and back
-- when the mouse comes back in) rather than jumping. Past the left side: the edge stays just
-- inside it, as before (the audio after it is on screen there)
local PARK_FROM_RIGHT = 1 / 10     -- (of the arrange's width, from its right side)
local PARK_GLIDE = 0.05           -- seconds: how quickly the view glides to and from there
-- Coming back in, the edge follows the mouse from where it's parked, a little slower than it
-- moves left, so the mouse catches up with it gradually (no jump back under the mouse): this
-- much of each leftward move closes the gap (0.5: the gap is gone after the mouse has moved twice
-- its width). Moving right meanwhile, the edge moves with the mouse exactly
local PARK_RETURN = 0.5
local function right_park_shift(z)
  local now = reaper.time_precise()
  local dt = sh.park_t and math.min(now - sh.park_t, 0.1) or 0
  sh.park_t = now
  local target = 0
  if sh.auto_past > 0 then
    local _, w = reaper.JS_Window_GetClientSize(ARRANGE)
    local side = w - 1 - AUTO_INSET_PX
    target = math.max(0, side - math.floor(w * (1 - PARK_FROM_RIGHT))) / z   -- (seconds)
  end
  local cur = sh.park or 0
  local md = sh.mouse_d or 0
  if sh.auto_past > 0 then
    -- (past the side: to the parked spot, gliding)
    if math.abs(target - cur) * z < 0.5 then cur = target
    else cur = cur + (target - cur) * math.min(1, dt / PARK_GLIDE) end
  elseif cur > 0 and sh.park_md and md < sh.park_md then
    -- (back in, moving left: part of the move closes the gap, the rest moves the edge with it)
    cur = math.max(0, cur - (sh.park_md - md) * PARK_RETURN)
  end
  sh.park_md = md
  sh.park = cur
  return cur
end

local function follow_view()
  -- In whole pixels, worked out in pixels: the view's start at the press, back by the trim.
  -- REAPER rounds the view's start down to a whole pixel, and a start worked out in seconds can
  -- land a hair under the pixel meant (one pixel too far, then back: the view vibrated, 1.23-
  -- 1.26), so it's asked for a quarter pixel past it. (A snapped trim can be a fraction of a
  -- pixel: the view goes to the nearest one)
  local z = reaper.GetHZoomLevel()
  -- (what the trim carried on by itself past a side isn't scrolled: the edge stays in sight)
  -- (while it carries on, the view stays put by the mouse alone: following the snapped trim it
  -- went back and forth as the edge stepped from one snap to the next)
  local vd = (sh.auto_past ~= 0 and sh.mouse_d) or (sh.d - sh.auto_d)
  -- (past the right side: the edge a third of the way in. A part of the drag begun there, after a
  -- ripple mode change, starts from the view as it is, which has the shift in it already)
  vd = vd - (right_park_shift(z) - (sh.park_base or 0))
  local want = math.floor(sh.fv_s * z + 0.5) - math.floor(vd * z + 0.5)
  sh.fv_want = want
  local s = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  if math.floor(s * z + 0.5) == want then return false end
  if want < 0 then return scroll_before_zero(want, z) end   -- (before 0:00: see scroll_before_zero)
  local ts = (want + 0.25) / z
  reaper.GetSet_ArrangeView2(0, true, 0, 0, ts, ts + (sh.fv_e - sh.fv_s))
  return true
end

-- Snapping goes by what the mouse is over: within the snap distance of a target, the cut
-- lands exactly there; otherwise the trim follows the mouse from where you pressed
local function trim_update(mx)
  if sh.follow then auto_scroll(mx); mx = sh.mx_in end
  if mx ~= sh.last_mx then   -- (the mouse hasn't moved: the trim stays as it is)
    sh.last_mx = mx
    -- (the view following: the mouse measured against the view as it was when the drag began,
    -- so what's trimmed, and what snaps, is the same as with the view staying put)
    if sh.follow then sh.mouse_d = (mx - sh.x0) / reaper.GetHZoomLevel() end
    local m = sh.follow and (sh.t0 + sh.mouse_d + sh.auto_d) or mouse_time(mx)
    local s_, rel, snapped = m, false, false
    if not (sh.retargeted and mx == sh.x0) then s_, rel, snapped = snap_time(m, sh.t0) end
    local d
    if rel then d = s_ - sh.t0                              -- (relative grid: whole steps from the press)
    elseif math.abs(s_ - m) > EPS then d = s_ - sh.gP       -- (the cut lands on what the mouse is over)
    else d = m - sh.t0 end
    if sh.follow then
      -- (the trim and the view's scroll in one redraw: two a frame made it heavier and could
      -- show the trim a moment before the scroll)
      reaper.PreventUIRefresh(1)
      local dc = clamp(d)
      -- (as far as the trim can go: what carried on past that is dropped, so moving back in
      -- turns straight back)
      if dc > d + EPS and sh.auto_d < 0 then sh.auto_d = math.min(0, sh.auto_d + (dc - d)) end
      if dc < d - EPS and sh.auto_d > 0 then sh.auto_d = math.max(0, sh.auto_d + (dc - d)) end
      local changed = apply(dc, true)
      local scrolled = follow_view()
      reaper.PreventUIRefresh(-1)
      if changed or scrolled then reaper.UpdateArrange() end
      guide(snapped and sh.gP or nil)   -- (the line at the edge, which the view keeps under the mouse)
    else
      apply(clamp(d))
      guide(snapped and (sh.plain and s_ or sh.gP) or nil)   -- (in a ripple: at the edge, where the target arrived)
    end
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
  -- (not the view's position: each part starts from where the view is now; carrying it over put
  -- the view back after a part where it followed the drag, 1.29)
  for _, k in ipairs({ "started", "grabbed_was_selected", "trim_click", "no_jump" }) do sh[k] = prev[k] end
  sh.park, sh.park_base = prev.park, prev.park   -- (the right-side parking carries on, already in the view)
  -- (carries on from exactly where the mouse is: snaps measured from it, not from the item's start,
  -- and none until the mouse moves again; otherwise the trim jumped at the switch)
  sh.gP, sh.no_jump, sh.retargeted = sh.t0, true, true
  if prev.outline and not sh.outline then RTcore.outline("leftedge", nil) end
  log("ripple mode changed to " .. mode .. ": carrying on from here")
end

local function trim_end(cancel)
  if not sh then return end
  vscroll_restore()   -- (the limit at the project start back as it was)
  local top = sh
  if top.outline then RTcore.outline("leftedge", nil) end
  if cancel then   -- (the whole drag goes back, mode changes and all: latest first)
    local seg, first = top, top
    while seg do sh = seg; apply(0); first = seg; seg = seg.prev end
    sh = top
    -- (the view followed: back to where it was at the press)
    local followed = false
    seg = top
    while seg do if seg.follow then followed = true end; seg = seg.prev end
    if followed then reaper.GetSet_ArrangeView2(0, true, 0, 0, first.fv_s, first.fv_e) end
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
        if sh.follow then follow_view() else keep_view() end
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
  vscroll_restore()
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

