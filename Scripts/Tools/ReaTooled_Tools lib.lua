-- @description ReaTooled - Tools library (shared by the tool scripts)
-- @version 1.20
-- @date 2026.11.11
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Not an action. Every tool script (Zoom, Trim, Selector, Move, Multi, Scrub,
--   Pencil) sets its own mouse modifiers and locking, then calls finish(), which:
--     - stops the Trim Tool's background worker (except for the Trim Tool)
--     - applies the left/right drag swap (ReaTooled_Drag swap lib.lua)
--     - undoes the Pencil Tool's envelope and sample-edit drawing when another
--       tool is chosen
--     - in Spot mode, makes Move Tool clicks (and Multi tool lower-half clicks)
--       open the Spot dialog
--     - in Shuffle mode, has Move Tool drags (and Multi tool lower-half drags)
--       reorder items (ReaTooled_Shuffle move (background).lua)
--     - lights the tool's toolbar button(s) and turns the others off
--   Adding a tool means adding it to TOOLS below, and nowhere else.
-- @changelog
--   v1.20 smart_chord(tool): two tool keys pressed together choose the Smart Tool, as in Pro Tools
--         (F6+F7, F7+F8, F6+F8: Trim, Selector, Move). Holding them doesn't switch back and
--         forth (REAPER repeats a held shortcut)
--   v1.19 The record of mouse modifiers switched for a moment, the yellow outline and the hover
--         repair now come from ReaTooled's shared core (pasted in below), the same code that
--         Shuffle and the left-edge ripple carry so they also work without this library. No
--         change in what they do
--   v1.17.4 outline(owner, items, redrawn, ends): ends[item] = where to draw its right side
--           (the Trim Tool leads REAPER's own edge drag with it)
--   v1.17.3 outline(owner, items, redrawn): no extra redraws asked for when the caller redraws
--           the arrange view itself that frame; off while ExtState ReaTooled/OutlineOff is "1"
--           (the smoothness monitor's switch, to measure what it costs)
--   v1.17.2 Trim Tool 7.12 owners: "trim-hand", "trim-click" (a body drag handed over)
--   v1.17.1 Choosing the Trim, Zoom or Pencil Tool no longer puts the previous tool's item
--           drags back over its own (a mode's remembered originals, e.g. Shuffle's from the
--           Multi tool): they set their item modifiers too. With the Trim Tool, REAPER's own
--           item drags then moved and rippled items under the trim, and the top half made a
--           selection
--   v1.17 outline(owner, items): a yellow outline drawn over the arrange view around the items
--         being trimmed or moved (Trim Tool, Shuffle move), so they can be seen where they
--         overlap other items; outline(owner, nil) takes it away
--   v1.16.4 The Trim Tool (7.10) is an owner too ("trim": its Cmd item-edge drag)
--   v1.16.3 Choosing a tool (or a mode re-applying it) forgets any modifier switched off for a
--            moment that the tool has just set itself, so it isn't "put back" over the tool's
--            own (Shuffle could put the Multi tool's item drags back over the Trim Tool's:
--            REAPER then moved and rippled items under the Trim Tool's body-drag trim). Only
--            REAPER's lower-half Pass through is treated as unchanged now (not any "0")
--   v1.16.2 An item's lower half set to "Pass through" is reported by REAPER as whatever the
--            upper half has: that counts as still switched too, so it's put back (it stayed
--            on Pass through when the upper half was put back first)
--   v1.16.1 A modifier switched off for a moment is put back even when REAPER reports it
--            differently from what was written (e.g. an item's lower half "Pass through")
--   v1.16 temp_take() / temp_give(): one record of mouse modifiers switched off for a moment by
--         the background scripts (Shuffle move, Ripple edit when editing media item left
--         edges). When two of them switch off the same one, the first one's original is kept
--         and it's put back when the last lets go (before, one could take the other's "off"
--         for the original and put that back). repair_hover() also puts back anything left
--         switched off by a script that stopped without doing it
--   v1.14 Option/Alt-dragging a razor area in Shuffle copies with or without Separation
--         Mode (the Selector included)
--   v1.13 Shuffle mode: Option/Alt item drags (and razor area drags with Separation) go
--         to the Shuffle move script, which copies
--   v1.12 repair_hover(): drags the Shuffle move script switched off over a razor area
--         are put back if it stopped before it could (also at startup and on tool apply)
--   v1.11 Shuffle + Separation with the Selector: razor area drags shuffle there too
--   v1.10 Shuffle + Separation: razor area drags go to the Shuffle move script
--         (release_mode_overrides() for the Separation toggle)
--   v1.9 tool_options(): Cmd+click or Option+click on the Move, Selector, Trim or Multi
--        tool button
--        shows a menu of that tool's options at the mouse (Separation, Swap left and
--        right drag), ticked when on
--   v1.8 Turning Spot or Shuffle on or off no longer re-runs the tool: only the few
--        modifiers the mode changes are set, and the tool's own values are put back
--        when it goes off (track, arrange, right-drag and the drag swap stay as the
--        tool set them). Remembers the tool last applied.
--   v1.7 Shuffle mode with the Multi tool: the plain item drag is No action too (the
--        upper half's razor drag is off), and the lower half passes through to it, so
--        nothing of REAPER's runs alongside the Shuffle drag
--   v1.6 Shuffle mode: the item lower half's plain drag is set to No action (it was
--        set to pass through to the item drag context)
--   v1.5 The Shuffle move script is restarted each time a tool is applied (an updated
--        script takes over)
--   v1.4 Shuffle mode: with the Move Tool or the Multi tool, REAPER's plain item drag is
--        turned off and the Shuffle move background script reorders items instead
--   v1.3 Shuffle mode state (shuffle_on, set_shuffle); Spot and Shuffle are exclusive
--   v1.2 Tools no longer touch "Take: Toggle sample edits active" (it is per take, not a switch)
--   v1.1 Spot mode
--   v1.0 Initial version (moved here from the tool scripts)

local M = {}

local NS = "ReaTooled"
local DIR = (debug.getinfo(1, "S").source:match("^@(.*[/\\])")) or ""

------------------------------------------------------------
-- Tools: key, script file (in this folder) or command ID, and which
-- toolbar buttons are lit while the tool is active (default: its own)
------------------------------------------------------------
M.TOOLS = {
  { key = "zoom",     file = "Zoom Tool_ReaTooled.lua" },
  { key = "trim",     file = "Trim Tool_ReaTooled.lua" },
  { key = "selector", file = "Razor Select Tool (Selector)_ReaTooled.lua" },
  { key = "grabber",  file = "Move Tool (Grabber)_ReaTooled.lua" },
  { key = "smart",    file = "Default Multi Tool (Smart)_ReaTooled.lua",
    lit = { trim = true, selector = true, grabber = true, smart = true } },
  { key = "scrub",    file = "Scrub Tool_ReaTooled.lua" },
  { key = "pencil",   file = "Pencil Tool_ReaTooled.lua" },
  { key = "tce",      id = "_RSb90cf42a9ad3d180fdab1c2fbe82e70a76347b1f" },   -- not built yet
}

local function command_of(tool)
  if tool.file then
    local path = DIR .. tool.file
    if not reaper.file_exists(path) then return 0 end
    return reaper.AddRemoveReaScript(true, 0, path, true) or 0
  end
  return reaper.NamedCommandLookup(tool.id)
end
M.command_of = command_of

function M.find(key)
  for _, t in ipairs(M.TOOLS) do if t.key == key then return t end end
end

-- Is this tool the one selected? (its own toolbar button is lit)
function M.is_active(key)
  local t = M.find(key)
  if not t then return false end
  local cmd = command_of(t)
  return cmd ~= 0 and reaper.GetToggleCommandState(cmd) == 1
end

function M.light(active_key)
  local active = M.find(active_key)
  local lit = (active and active.lit) or { [active_key] = true }
  for _, t in ipairs(M.TOOLS) do
    local cmd = command_of(t)
    if cmd ~= 0 then reaper.SetToggleCommandState(0, cmd, lit[t.key] and 1 or 0) end
  end
  reaper.RefreshToolbar(0)
end

------------------------------------------------------------
-- Trim Tool background worker (keys and heartbeat match the worker script)
------------------------------------------------------------
local RT_RUN_KEY, RT_KILL_KEY, RT_HEARTBEAT = "TrimToolWorkerRunning", "KillTrimTool", "TrimToolHeartbeat"
local RT_STALE_SEC = 0.8

function M.kill_trim_tool()
  -- Persist the kill so the worker sees it even if we ran first or block briefly
  reaper.SetExtState(NS, RT_KILL_KEY, "1", true)
  -- Immediate cursor neutralization (visual fix while the worker exits)
  if reaper.JS_Mouse_LoadCursor and reaper.JS_Mouse_SetCursor then
    local arrow = reaper.JS_Mouse_LoadCursor(32512)
    if arrow then pcall(reaper.JS_Mouse_SetCursor, arrow) end
  end
  -- Don't busy-wait (it would block the worker). Clean up a stale run key.
  local hb = tonumber(reaper.GetExtState(NS, RT_HEARTBEAT) or "") or 0
  if hb ~= 0 and (reaper.time_precise() - hb) > RT_STALE_SEC then
    pcall(reaper.DeleteExtState, NS, RT_RUN_KEY, false)
    pcall(reaper.DeleteExtState, NS, RT_RUN_KEY, true)
  end
end

------------------------------------------------------------
-- Pencil Tool: what it changes outside the contexts every tool sets,
-- and what other tools put back ("-1" = REAPER's default, as shipped)
------------------------------------------------------------
M.PENCIL_KEY = "PencilChanged"   -- "1" while the Pencil's changes are in place

-- Plain drag only (the other keys keep what they have). REAPER's numbers, read
-- back from reaper-mouse.ini after setting them by name:
M.PENCIL_MODS = {
  MM_CTX_ENVLANE    = { [0] = "4 m" },    -- Freehand draw envelope
  MM_CTX_ENVSEG     = { [0] = "10 m" },   -- Freehand draw envelope
  MM_CTX_ENVPT      = { [0] = "13 m" },   -- Freehand draw envelope
  MM_CTX_SAMPLEEDIT = { [0] = "Draw sample edit" },   -- REAPER's default already
}
local PENCIL_RESTORE = {
  MM_CTX_ENVLANE    = { [0] = "-1" },
  MM_CTX_ENVSEG     = { [0] = "-1" },
  MM_CTX_ENVPT      = { [0] = "-1" },
  MM_CTX_SAMPLEEDIT = { [0] = "-1" },
}

local function set_mods(tbl)
  for context, mods in pairs(tbl) do
    for i = 0, 15 do
      if mods[i] then reaper.SetMouseModifier(context, i, mods[i]) end
    end
  end
end
M.set_mods = set_mods

function M.enter_pencil()
  set_mods(M.PENCIL_MODS)
  reaper.SetExtState(NS, M.PENCIL_KEY, "1", true)
end

-- The Scrub Tool sets no item modifiers of its own (its drags come from REAPER's
-- arrange override), so after the Pencil, item clicks go back to REAPER's default
-- instead of adding clip gain points
local SCRUB_RESTORE = {
  MM_CTX_ITEM_CLK      = { [0] = "-1" },
  MM_CTX_ITEMLOWER_CLK = { [0] = "-1" },
}

function M.leave_pencil(key)
  if reaper.GetExtState(NS, M.PENCIL_KEY) ~= "1" then return end
  set_mods(PENCIL_RESTORE)
  if key == "scrub" then set_mods(SCRUB_RESTORE) end
  reaper.DeleteExtState(NS, M.PENCIL_KEY, true)
end

------------------------------------------------------------
-- Spot mode (ReaTooled_Toggle Spot mode): Move Tool clicks, and Multi tool
-- lower-half clicks, open the Spot dialog. Not kept when REAPER restarts.
------------------------------------------------------------
local SPOT_KEY = "SpotMode"

function M.spot_on() return reaper.GetExtState(NS, SPOT_KEY) == "1" end
function M.set_spot(on) reaper.SetExtState(NS, SPOT_KEY, on and "1" or "0", false) end

------------------------------------------------------------
-- Shuffle mode (ReaTooled_Toggle Shuffle mode): per-track ripple, plus (later) the
-- Move Tool reordering items like Pro Tools' Shuffle. Kept when REAPER restarts.
-- Spot and Shuffle are exclusive, like Pro Tools' edit modes.
------------------------------------------------------------
local SHUFFLE_KEY = "ShuffleMode"

function M.shuffle_on() return reaper.GetExtState(NS, SHUFFLE_KEY) == "1" end
function M.set_shuffle(on) reaper.SetExtState(NS, SHUFFLE_KEY, on and "1" or "0", true) end

-- Toolbar button of a mode toggle script in this folder
function M.set_button(file, on)
  local cmd = command_of({ file = file })
  if cmd ~= 0 then
    reaper.SetToggleCommandState(0, cmd, on and 1 or 0)
    reaper.RefreshToolbar2(0, cmd)
  end
end

------------------------------------------------------------
-- Mode overrides: Spot and Shuffle change only a few of the tool's modifiers. Each
-- one changed is remembered as the tool had it, and put back when the mode goes
-- off, so the rest of the tool (track, arrange, right-drag, the drag swap) is never
-- touched by a mode change.
------------------------------------------------------------
local CUR_TOOL_KEY = "CurrentTool"   -- the tool last applied (kept across restarts)
local SNAP_KEY     = "ModeOverrides" -- "group|context|flag|original;..." (kept)

local function read_snaps()
  local list = {}
  for line in (reaper.GetExtState(NS, SNAP_KEY) or ""):gmatch("[^;]+") do
    local g, c, f, v = line:match("^(.-)|(.-)|(%-?%d+)|(.*)$")
    if g then list[#list + 1] = { group = g, ctx = c, flag = tonumber(f), value = v } end
  end
  return list
end

local function write_snaps(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = table.concat({ e.group, e.ctx, e.flag, e.value }, "|") end
  if #out == 0 then reaper.DeleteExtState(NS, SNAP_KEY, true)
  else reaper.SetExtState(NS, SNAP_KEY, table.concat(out, ";"), true) end
end

-- Set one modifier for a mode, remembering what the tool had there
local function override(group, ctx, flag, value)
  local list = read_snaps()
  local known = false
  for _, e in ipairs(list) do if e.ctx == ctx and e.flag == flag then known = true end end
  if not known then
    local orig = reaper.GetMouseModifier and reaper.GetMouseModifier(ctx, flag) or ""
    if orig == nil or orig == "" then orig = "-1" end
    list[#list + 1] = { group = group, ctx = ctx, flag = flag, value = orig }
    write_snaps(list)
  end
  reaper.SetMouseModifier(ctx, flag, value)
end

-- A mode's overrides gone: put back what the tool had (restore=true), or just forget
-- them (the tool has just set all its modifiers again)
local function release_overrides(group, restore)
  local keep = {}
  for _, e in ipairs(read_snaps()) do
    if group == nil or e.group == group then
      local put_back = restore
      if type(restore) == "function" then put_back = restore(e) end
      if put_back then reaper.SetMouseModifier(e.ctx, e.flag, e.value) end
    else
      keep[#keep + 1] = e
    end
  end
  write_snaps(keep)
end

-- The tool last applied (falls back to the lit toolbar buttons)
function M.current_tool()
  local k = reaper.GetExtState(NS, CUR_TOOL_KEY)
  if k ~= "" then return k end
  if M.is_active("smart") then return "smart" end
  if M.is_active("grabber") then return "grabber" end
  return ""
end

local apply_spot, apply_shuffle

-- A mode changed (Spot or Shuffle on or off): only the modes' own overrides change;
-- the tool's other modifiers stay exactly as they are
-- The Shuffle move script switches some drags off while the mouse is over a razor
-- area and keeps what it switched on disk. If it (or REAPER) stopped before it could
-- switch them back, they're put back here (only where they're still switched).
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

-- (from the shared core above)
M.temp_still_ours = RTcore.temp_still_ours
M.temp_take, M.temp_give, M.temp_give_all = RTcore.temp_take, RTcore.temp_give, RTcore.temp_give_all
M.temp_forget, M.temp_repair = RTcore.temp_forget, RTcore.temp_repair
M.outline, M.repair_hover = RTcore.outline, RTcore.repair_hover
M.cmdall_set = RTcore.cmdall_set


-- A tool (or mode) has just set these contexts itself: what was switched there is forgotten,
-- not put back over the tool's own when its owner lets go (temp_forget)
local TOOL_WRITES_ALL = { MM_CTX_ITEM = true, MM_CTX_ITEMLOWER = true, MM_CTX_ITEM_CLK = true,
  MM_CTX_ITEMLOWER_CLK = true, MM_CTX_ITEM_DBLCLK = true, MM_CTX_ITEMLOWER_DBLCLK = true,
  MM_CTX_TRACK = true, MM_CTX_TRACK_CLK = true }
local TOOL_WRITES_EDGE = { grabber = true, smart = true, trim = true, zoom = true }   -- (+ item edge)
local function tool_contexts(key)
  if key == "scrub" or key == nil or key == "" then return {} end
  local c = {}
  for k in pairs(TOOL_WRITES_ALL) do c[k] = true end
  if TOOL_WRITES_EDGE[key] then c.MM_CTX_ITEMEDGE = true end
  return c
end
-- Every mode's overrides put back as the tool had them (before a mode script
-- changes one of the same modifiers itself; reapply_tool() sets them again)
function M.release_mode_overrides() release_overrides(nil, true) end

function M.reapply_tool()
  local key = M.current_tool()
  M.temp_forget({ MM_CTX_ITEM = true, MM_CTX_ITEMLOWER = true, MM_CTX_ITEM_CLK = true,
                  MM_CTX_ITEMLOWER_CLK = true, MM_CTX_AREASEL = true })   -- (the modes' overrides)
  release_overrides(nil, true)
  apply_spot(key)
  apply_shuffle(key)
end

function apply_spot(key)
  if not M.spot_on() then return end
  local contexts = (key == "grabber" and { "MM_CTX_ITEM_CLK", "MM_CTX_ITEMLOWER_CLK" })
                or (key == "smart" and { "MM_CTX_ITEMLOWER_CLK" })
  if not contexts then return end
  local cmd = command_of({ file = "ReaTooled_Spot click.lua" })
  if cmd == 0 then return end
  local action = "_" .. reaper.ReverseNamedCommandLookup(cmd)
  for _, c in ipairs(contexts) do override("spot", c, 0, action) end
end

-- Shuffle mode with the Move Tool or the Multi tool: REAPER's plain item drag off
-- (two modifiers only), and the Shuffle move background script started. Any other
-- tool or mode: the script stops by itself.
local SHUFFLE_TOOL_KEY = "ShuffleMoveTool"
function apply_shuffle(key)
  local separation = reaper.GetExtState(NS, "SeparationMode") == "1"
  -- Move Tool and Multi tool: item and razor area drags. Selector: razor area drags
  -- only (Option/Alt-drag copies; plain drags too with Separation Mode); its other
  -- drags stay the Selector's own
  local ok = key == "grabber" or key == "smart" or key == "selector"
  local want = (M.shuffle_on() and ok) and key or ""
  reaper.SetExtState(NS, SHUFFLE_TOOL_KEY, want, false)
  if want == "" then return end
  if key ~= "selector" then
    -- Both tools: plain item drag No action ("0"); the lower half has no No action, so
    -- it passes through to that ("0", set explicitly). (The Multi tool's upper-half razor
    -- drag is off while Shuffle is on: shuffling comes first.)
    override("shuffle", "MM_CTX_ITEM", 0, "0")
    override("shuffle", "MM_CTX_ITEMLOWER", 0, "0")   -- ("0": pass through, set explicitly; "-1" is a blank entry)
    -- Option/Alt-drag: the Shuffle move script copies (like Pro Tools' Option-drag)
    override("shuffle", "MM_CTX_ITEM", 4, "0")
    override("shuffle", "MM_CTX_ITEMLOWER", 4, "0")
  end
  -- With Separation on, razor area drags are the Shuffle move script's too
  if separation then override("shuffle", "MM_CTX_AREASEL", 0, "0") end
  -- Option/Alt-drag on a razor area: the Shuffle move script copies what's in it
  override("shuffle", "MM_CTX_AREASEL", 4, "0")
  -- (Re)start it: a running copy is stopped and the new one takes over
  local cmd = command_of({ file = "ReaTooled_Shuffle move (background).lua" })
  if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
end

------------------------------------------------------------
-- Tool options: Cmd+click or Option+click on a tool's toolbar button shows a menu
-- of that tool's options at the mouse, ticked when on (the tool isn't chosen).
-- Each entry runs a toggle script in this folder.
------------------------------------------------------------
local function ext_on(k) return function() return reaper.GetExtState(NS, k) == "1" end end

local SEPARATION = { label = "Separation Mode (Move razor areas)",
                     file = "ReaTooled_Toggle Separation mode.lua", on = ext_on("SeparationMode") }
local DRAG_SWAP  = { label = "Object Grabber Mode (Marquee left drag, Razor right drag)",
                     file = "ReaTooled_Toggle swap left and right drag.lua", on = ext_on("DragSwap") }

local DRAG_SWAP_OTHER = { label = "Object Grabber Mode (Marquee left drag, Razor right drag: Selector and Multi tools)",
                          file = DRAG_SWAP.file, on = DRAG_SWAP.on }

M.TOOL_OPTIONS = {
  grabber  = { SEPARATION, DRAG_SWAP_OTHER },
  selector = { SEPARATION, DRAG_SWAP },
  smart    = { SEPARATION, DRAG_SWAP },
  trim     = { SEPARATION, DRAG_SWAP_OTHER },
}

M.BUSY_KEY = "ToolOptionsBusy"   -- set while an option runs (it may re-apply the tool)

-- Was this tool script started by a Cmd+click or Option+click on its button (not
-- by a keyboard shortcut: then a key other than the modifiers is down)?
function M.options_click()
  if reaper.GetExtState(NS, M.BUSY_KEY) == "1" then return false end
  local getMods, getKeys = reaper.JS_Mouse_GetState, reaper.JS_VKeys_GetState
  if not (getMods and getKeys) or (getMods(4 | 16) & (4 | 16)) == 0 then return false end
  local MODIFIER_KEYS = { [1]=1, [2]=1, [4]=1, [5]=1, [6]=1, [16]=1, [17]=1, [18]=1, [20]=1,
    [91]=1, [92]=1, [93]=1, [160]=1, [161]=1, [162]=1, [163]=1, [164]=1, [165]=1 }
  local keys = getKeys(-0.5) or ""
  for vk = 1, #keys do
    if keys:byte(vk) == 1 and not MODIFIER_KEYS[vk] then return false end
  end
  return true
end

function M.tool_options(key)
  local list = M.TOOL_OPTIONS[key]
  if not list then return false end
  local items = {}
  for i, o in ipairs(list) do items[i] = (o.on() and "!" or "") .. o.label end
  local title = "ReaTooled tool options"
  local x, y = reaper.GetMousePosition()
  gfx.init(title, 0, 0, 0, x, y)
  if reaper.JS_Window_Find and reaper.JS_Window_SetOpacity then
    local w = reaper.JS_Window_Find(title, true)
    if w then reaper.JS_Window_SetOpacity(w, "ALPHA", 0) end
  end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(table.concat(items, "|"))
  gfx.quit()
  local o = list[choice]
  if o then
    local cmd = command_of({ file = o.file })
    if cmd ~= 0 then
      reaper.SetExtState(NS, M.BUSY_KEY, "1", false)
      reaper.Main_OnCommand(cmd, 0)
      reaper.DeleteExtState(NS, M.BUSY_KEY, false)
    end
  end
  return true
end

------------------------------------------------------------
-- Called at the end of every tool script
------------------------------------------------------------
local WRITES_ITEM_MODS = { grabber = true, smart = true, selector = true,
                          trim = true, zoom = true, pencil = true }   -- (every tool but Scrub)
-- The contexts those tools write themselves (others, like razor area drags, are
-- never set by a tool: a mode's original there is still right)
local TOOL_CONTEXTS = { MM_CTX_ITEM = true, MM_CTX_ITEMLOWER = true,
                        MM_CTX_ITEM_CLK = true, MM_CTX_ITEMLOWER_CLK = true }

function M.finish(key)
  M.temp_forget(tool_contexts(key))   -- (first: the tool has just set these itself)
  M.repair_hover()
  -- The tool has just set its own modifiers: the modes' remembered originals are
  -- out of date for a tool that sets its item modifiers (forget them), and still
  -- right for one that doesn't (put them back)
  release_overrides(nil, function(e)
    return not (WRITES_ITEM_MODS[key] and TOOL_CONTEXTS[e.ctx])
  end)
  reaper.SetExtState(NS, CUR_TOOL_KEY, key, true)
  if key ~= "trim" then M.kill_trim_tool() end
  if key ~= "pencil" then M.leave_pencil(key) end
  local ok, swap = pcall(dofile, DIR .. "ReaTooled_Drag swap lib.lua")
  if ok and type(swap) == "table" then
    swap.apply(key)
  else
    reaper.ShowConsoleMsg("ReaTooled: drag swap library not loaded: " .. tostring(swap) .. "\n")
  end
  apply_spot(key)
  apply_shuffle(key)
  M.light(key)
end

------------------------------------------------------------
-- Two tool keys at once = the Smart Tool (Pro Tools: F6+F7, F7+F8, F6+F8). Each of the three
-- tool scripts calls this first with its own key; the second key of a chord runs while the
-- first is still held, and sees it (js_ReaScriptAPI). true: handled, the script stops there.
-- REAPER repeats a shortcut while its key is held: those repeats are ignored (a key that
-- hasn't been let go since the chord), so holding the keys doesn't switch back and forth.
------------------------------------------------------------
local TOOL_KEYS = { trim = 0x75, selector = 0x76, grabber = 0x77 }   -- F6, F7, F8
local CHORD_KEY = "ToolChord"    -- when the last chord was pressed
local SEEN_KEY = "ToolChordSeen" -- when it, or a repeat of one of its keys, was last seen
local CHORD_HOLD = 3             -- seconds a repeat keeps counting as part of the chord

function M.smart_chord(tool)
  local key = TOOL_KEYS[tool]
  if not key or not (reaper.JS_VKeys_GetState and reaper.JS_VKeys_GetUp) then return false end
  local down = reaper.JS_VKeys_GetState(0) or ""
  local function held(k) return (down:byte(k) or 0) ~= 0 end
  local now = reaper.time_precise()
  local other = false
  for t, k in pairs(TOOL_KEYS) do if t ~= tool and held(k) then other = true end end
  if other then
    reaper.SetExtState(NS, CHORD_KEY, tostring(now), false)
    reaper.SetExtState(NS, SEEN_KEY, tostring(now), false)
    if M.current_tool() ~= "smart" then
      local cmd = command_of(M.find("smart"))
      if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
    end
    return true
  end
  -- this key held since the chord and REAPER repeating it: not a new press
  local t = tonumber(reaper.GetExtState(NS, CHORD_KEY))
  local seen = tonumber(reaper.GetExtState(NS, SEEN_KEY)) or t
  if t and now - seen < CHORD_HOLD and held(key) then
    local up = reaper.JS_VKeys_GetUp(t) or ""   -- (let go since the chord: a new press)
    if (up:byte(key) or 0) == 0 then
      reaper.SetExtState(NS, SEEN_KEY, tostring(now), false)   -- (still held: keep ignoring)
      return true
    end
  end
  return false
end

return M
