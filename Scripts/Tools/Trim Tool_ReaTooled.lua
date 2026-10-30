-- @description ReaTooled - Trim Tool (Controller)
-- @version 2.6
-- @date 2026.10.30
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about Launches Trim Tool background worker if not already running.
--        If already running, simply reapplies Trim modifiers/locks and syncs toolbar.
--        Does NOT toggle off and does NOT spawn duplicates.
-- CHANGELOG
-- v2.6  Cmd+click or Option+click on the toolbar button shows a menu of tool options (Separation, Swap left and right drag) instead of choosing the tool
-- v2.5  Left click in empty track space deselects all items and moves the edit cursor (as in the other tools), so you can clear the selection and move around
-- v2.4  Plain edge drags are the Trim Tool's own (the background worker trims the edge with group, selected-item, snap and ripple handling); edge drags with modifier keys stay REAPER's
-- v2.3  Stopping the Trim Tool and the toolbar buttons are shared with the other tools (ReaTooled_Tools lib.lua), which also knows the new Pencil Tool
-- v2.2  Puts right-drag back to marquee when "Toggle swap left and right drag" had changed it
-- v2.1  add new item edge ripple mouse modifiers

local NS         = "ReaTooled"
local RUN_KEY    = "TrimToolWorkerRunning"
local KILL_KEY   = "KillTrimTool"
local WORKER_RS  = "_RS9a9ee6e4eb895674476dc0226ffbda20d9318887" -- background worker ID


-- === Preserve ALL your modifiers/locks EXACTLY ===
----------------------------------------
-- Cmd+click or Option+click on the toolbar button: a menu of the tool's options
-- (Separation, Swap left and right drag) instead of choosing the tool. A keyboard
-- shortcut always chooses the tool. (ReaTooled_Tools lib.lua)
----------------------------------------
do
  local dir = ({ reaper.get_action_context() })[2]:match("^(.*[/\\])") or ""
  local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
  if ok and type(tools) == "table" and tools.options_click and tools.options_click() then
    tools.tool_options("trim")
    reaper.defer(function() end)   -- no undo point
    return
  end
end

local function SetAllMouseModifiers()
  for i = 0, 15 do
    reaper.SetMouseModifier('MM_CTX_ITEM', i, '0')
    reaper.SetMouseModifier('MM_CTX_ITEMLOWER', i, '0')
    reaper.SetMouseModifier('MM_CTX_ITEM_DBLCLK', i, (i == 0) and '0' or '-1')
    reaper.SetMouseModifier('MM_CTX_ITEMLOWER_DBLCLK', i, (i == 0) and '0' or '-1')
    reaper.SetMouseModifier('MM_CTX_ITEM_CLK', i, (i == 0) and '3' or '-1')
    reaper.SetMouseModifier('MM_CTX_ITEMLOWER_CLK', i, (i == 0) and '3' or '-1')
    -- Track (empty space) left click: deselect all items and move edit cursor ('1 m'); other keys no action
    reaper.SetMouseModifier('MM_CTX_TRACK_CLK', i, (i == 0) and '1 m' or '0')
    reaper.SetMouseModifier('MM_CTX_TRACK', i, '0')
  end

  -- ITEM EDGE custom map (from your controller)
  local item_edge_values = {
    -- [0] plain edge drag: no action, the Trim Tool's background worker does it
    [0] = '0', [1] = '9 m', [2] = '35 m', [3] = '5 m',
    [4] = '2 m', [5] = '10 m', [6] = '36 m', [7] = '40 m',
    [8] = '27 m', [9] = '-1', [10] = '-1', [11] = '-1',
    [12] = '28 m', [13] = '32 m', [14] = '19 m', [15] = '-1'
  }
  for i = 0, 15 do
    reaper.SetMouseModifier('MM_CTX_ITEMEDGE', i, item_edge_values[i] or '-1')
  end
end

local function ApplyTrimLocks()
  reaper.Main_OnCommand(40569,0) -- Enable locking
  reaper.Main_OnCommand(40596,0) -- Clear item edges lock
  --reaper.Main_OnCommand(40598,0) -- Set item fades lock
  reaper.Main_OnCommand(40599,0) -- Clear item fades lock
  reaper.Main_OnCommand(41852,0) -- Set item stretch markers lock
  reaper.Main_OnCommand(41849,0) -- Set item envelope lock
  reaper.Main_OnCommand(40572,0) -- Set time selection to UNlock
  reaper.Main_OnCommand(42621,0) -- Clear arrange override mode
end

-- Start-only semantics:
-- If already running: reapply modifiers/locks + LED ON
-- If not running: clear stale Kill, apply modifiers/locks, launch worker, LED ON
local running = reaper.HasExtState(NS, RUN_KEY)

if running then
  SetAllMouseModifiers()
  ApplyTrimLocks()
else
  -- Clear any stale Kill only when about to launch (don’t cancel a legit stop mid-flight)
  reaper.DeleteExtState(NS, KILL_KEY, false)

  SetAllMouseModifiers()
  ApplyTrimLocks()

  local cmd = reaper.NamedCommandLookup(WORKER_RS)
  if cmd == 0 then
    reaper.ShowMessageBox("Could not locate Trim Tool Background Worker!", "Error", 0)
    return
  end
  reaper.Main_OnCommand(cmd, 0)
end

----------------------------------------
-- Finish: Trim Tool off, drag swap, Pencil cleanup, toolbar buttons
-- (shared by every tool: ReaTooled_Tools lib.lua)
----------------------------------------
do
  local dir = ({reaper.get_action_context()})[2]:match("^(.*[/\\])") or ""
  local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
  if ok and type(tools) == "table" then
    tools.finish("trim")
  else
    reaper.ShowConsoleMsg("ReaTooled: tools library not loaded: " .. tostring(tools) .. "\n")
  end
end
