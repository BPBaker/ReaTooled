-- @description ReaTooled - Trim Tool (Controller)
-- @version 2.1
-- @date 2025.11.18
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about Launches Trim Tool background worker if not already running.
--        If already running, simply reapplies Trim modifiers/locks and syncs toolbar.
--        Does NOT toggle off and does NOT spawn duplicates.
-- CHANGELOG
-- v2.1  add new item edge ripple mouse modifiers

local NS         = "ReaTooled"
local RUN_KEY    = "TrimToolWorkerRunning"
local KILL_KEY   = "KillTrimTool"
local WORKER_RS  = "_RS9a9ee6e4eb895674476dc0226ffbda20d9318887" -- background worker ID

-- Toolbar button sync (same set you used)
local toggle_ids = {
  "_RS21aa0b14cf72a27be535d32efe0d05513523aec9",
  "_RSd77ea649952c67db183a19cece290cf3e1b3d49d", -- Trim tool button (this one ON)
  "_RSb08c9a159d1a7537eda8df72b777b1cc4c9422e8",
  "_RSc2c7d733888679038b4a4341074dc703d0f7f9c2",
  "_RS5e85a066efd01fde2482832bf4a3502dce0427b6",
  "_RS27973b4ea6ddfabb982b8206b117b31843c68991", -- scrub tool
  "_RSb90cf42a9ad3d180fdab1c2fbe82e70a76347b1f"  -- TCE tool
}

local function sync_toolbar_leds(on)
  for _, id in ipairs(toggle_ids) do
    local cmd = reaper.NamedCommandLookup(id)
    if cmd ~= 0 then
      local lit = (id == "_RSd77ea649952c67db183a19cece290cf3e1b3d49d") and (on and 1 or 0) or 0
      reaper.SetToggleCommandState(0, cmd, lit)
    end
  end
  reaper.RefreshToolbar(0)
end

-- === Preserve ALL your modifiers/locks EXACTLY ===
local function SetAllMouseModifiers()
  for i = 0, 15 do
    reaper.SetMouseModifier('MM_CTX_ITEM', i, '0')
    reaper.SetMouseModifier('MM_CTX_ITEMLOWER', i, '0')
    reaper.SetMouseModifier('MM_CTX_ITEM_DBLCLK', i, (i == 0) and '0' or '-1')
    reaper.SetMouseModifier('MM_CTX_ITEMLOWER_DBLCLK', i, (i == 0) and '0' or '-1')
    reaper.SetMouseModifier('MM_CTX_ITEM_CLK', i, (i == 0) and '3' or '-1')
    reaper.SetMouseModifier('MM_CTX_ITEMLOWER_CLK', i, (i == 0) and '3' or '-1')
    reaper.SetMouseModifier('MM_CTX_TRACK_CLK', i, '0')
    reaper.SetMouseModifier('MM_CTX_TRACK', i, '0')
  end

  -- ITEM EDGE custom map (from your controller)
  local item_edge_values = {
    [0] = '1 m', [1] = '9 m', [2] = '35 m', [3] = '5 m',
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
  sync_toolbar_leds(true)
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
  sync_toolbar_leds(true)
end
