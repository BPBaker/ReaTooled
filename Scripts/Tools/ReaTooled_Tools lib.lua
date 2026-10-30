-- @description ReaTooled - Tools library (shared by the tool scripts)
-- @version 1.15
-- @date 2026.10.30
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
function M.repair_hover()
  local saved = reaper.GetExtState(NS, "ShuffleHoverSaved")
  if saved == "" or not reaper.GetMouseModifier then return end
  for line in saved:gmatch("[^;]+") do
    local c, f, orig, ours = line:match("^(.-)|(%-?%d+)|(.-)|(.*)$")
    f = tonumber(f)
    if c and f and reaper.GetMouseModifier(c, f) == ours then reaper.SetMouseModifier(c, f, orig) end
  end
  reaper.DeleteExtState(NS, "ShuffleHoverSaved", true)
end

-- Every mode's overrides put back as the tool had them (before a mode script
-- changes one of the same modifiers itself; reapply_tool() sets them again)
function M.release_mode_overrides() release_overrides(nil, true) end

function M.reapply_tool()
  local key = M.current_tool()
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
local WRITES_ITEM_MODS = { grabber = true, smart = true, selector = true }
-- The contexts those tools write themselves (others, like razor area drags, are
-- never set by a tool: a mode's original there is still right)
local TOOL_CONTEXTS = { MM_CTX_ITEM = true, MM_CTX_ITEMLOWER = true,
                        MM_CTX_ITEM_CLK = true, MM_CTX_ITEMLOWER_CLK = true }

function M.finish(key)
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

return M
