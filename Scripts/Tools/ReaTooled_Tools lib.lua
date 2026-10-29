-- @description ReaTooled - Tools library (shared by the tool scripts)
-- @version 1.5
-- @date 2026.10.28
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

-- Re-apply the current tool when a mode changes what its clicks/drags do
function M.reapply_tool()
  for _, key in ipairs({ "grabber", "smart" }) do
    if M.is_active(key) and not (key == "grabber" and M.is_active("smart")) then
      local cmd = command_of(M.find(key))
      if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
      return
    end
  end
end

local function apply_spot(key)
  if not M.spot_on() then return end
  local contexts = (key == "grabber" and { "MM_CTX_ITEM_CLK", "MM_CTX_ITEMLOWER_CLK" })
                or (key == "smart" and { "MM_CTX_ITEMLOWER_CLK" })
  if not contexts then return end
  local cmd = command_of({ file = "ReaTooled_Spot click.lua" })
  if cmd == 0 then return end
  local action = "_" .. reaper.ReverseNamedCommandLookup(cmd)
  for _, c in ipairs(contexts) do reaper.SetMouseModifier(c, 0, action) end
end

-- Shuffle mode with the Move Tool or the Multi tool: REAPER's plain item drag off
-- (Move Tool: whole item; Multi tool: lower half, where it moves items), and the
-- Shuffle move background script started. Any other tool or mode: the script stops
-- by itself (each tool script sets its own item drags again).
local SHUFFLE_TOOL_KEY = "ShuffleMoveTool"
local function apply_shuffle(key)
  local want = (M.shuffle_on() and (key == "grabber" or key == "smart")) and key or ""
  reaper.SetExtState(NS, SHUFFLE_TOOL_KEY, want, false)
  if want == "" then return end
  if key == "grabber" then
    reaper.SetMouseModifier("MM_CTX_ITEM", 0, "0")
    reaper.SetMouseModifier("MM_CTX_ITEMLOWER", 0, "0")
  else
    reaper.SetMouseModifier("MM_CTX_ITEMLOWER", 0, "0")
  end
  -- (Re)start it: a running copy is stopped and the new one takes over
  local cmd = command_of({ file = "ReaTooled_Shuffle move (background).lua" })
  if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
end

------------------------------------------------------------
-- Called at the end of every tool script
------------------------------------------------------------
function M.finish(key)
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
