-- @description ReaTooled - Toggle Shuffle mode
-- @version 1.3
-- @date 2026.10.29
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Like Pro Tools' Shuffle mode
--   On: ripple editing per track, so trims, deletes and pastes close up or push out
--   the items after them on the same track. Spot mode is turned off (Spot and
--   Shuffle are exclusive). Kept when REAPER restarts.
--   Off: back to Slip (ripple editing off).
--   Switching ripple editing off or to all tracks any other way (the Slip button,
--   REAPER's ripple buttons) also turns Shuffle mode off, so the button always shows
--   the real state.
--   With the Move Tool (or the Multi tool's lower half), dragging an item reorders
--   it among the items on its track, as in Pro Tools (see "Shuffle move").
-- @changelog
--   v1.3 With the Move Tool or the Multi tool, dragging an item reorders it on its
--        track (ReaTooled_Shuffle move (background).lua); the tool is set up again
--        whenever Shuffle turns on or off, however that happens
--   v1.2 At startup, per-track ripple is set again (the Slip button switches ripple
--        off when it starts, so Shuffle came back as Shuffle + Slip)
--   v1.1 The button stays lit after a restart (REAPER keeps the toggle state of the
--        running script, and it is re-lit if anything turns it off; the startup
--        check waits a moment for REAPER to settle)
--   v1.0 Initial version

local NS          = "ReaTooled"
local RECALL_KEY  = "ShuffleRecall"   -- set by Recall ReaTooled Button States at startup
local RIPPLE_OFF       = 40309        -- Options: Set ripple editing off
local RIPPLE_PER_TRACK = 40310        -- Options: Set ripple editing per-track

local _, script_path, section, cmd_id = reaper.get_action_context()
local dir = script_path:match("^(.*[/\\])") or ""

local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
if not ok or type(tools) ~= "table" then
  reaper.ShowMessageBox("ReaTooled_Tools lib.lua is missing from:\n" .. dir ..
    "\n\nUpdate ReaTooled in ReaPack (Extensions > ReaPack > Synchronize packages).", "ReaTooled", 0)
  return
end

-- Running it again stops the running copy and starts this one (which toggles)
if reaper.set_action_options then reaper.set_action_options(1 | 2) end
local START = reaper.time_precise()
local STARTUP_GRACE = 3   -- seconds before a startup recall judges the ripple mode

local function per_track_ripple() return reaper.GetToggleCommandState(RIPPLE_PER_TRACK) == 1 end

local function set_button(on)
  -- REAPER keeps the toggle state of a running script (like the Slip button) ...
  if reaper.set_action_options then reaper.set_action_options(1 | 2 | (on and 4 or 8)) end
  -- ... and the toolbar is told directly too
  reaper.SetToggleCommandState(section, cmd_id, on and 1 or 0)
  reaper.RefreshToolbar2(section, cmd_id)
end

local recall = reaper.GetExtState(NS, RECALL_KEY) == "1"
reaper.DeleteExtState(NS, RECALL_KEY, false)

local on
if recall then
  -- Startup: back on if it was on. The Slip button switches ripple off when it
  -- starts, so per-track ripple is set again here (Recall runs Slip first).
  on = tools.shuffle_on()
  if on then reaper.Main_OnCommand(RIPPLE_PER_TRACK, 0) end
  tools.reapply_tool()   -- the Move/Multi tool's drags for Shuffle (or back to normal)
else
  on = not tools.shuffle_on()
  tools.set_shuffle(on)
  if on then
    if tools.spot_on() then                       -- Spot and Shuffle are exclusive
      tools.set_spot(false)
      tools.set_button("ReaTooled_Toggle Spot mode.lua", false)
    end
    reaper.Main_OnCommand(RIPPLE_PER_TRACK, 0)
  else
    reaper.Main_OnCommand(RIPPLE_OFF, 0)          -- back to Slip
  end
  tools.reapply_tool()
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip("Shuffle mode " .. (on and "on" or "off (Slip)"), x + 12, y + 12, true)
end

set_button(on)
if not on then
  reaper.defer(function() end)   -- no undo point
  return
end

-- While on: watch for Shuffle being switched off some other way, and keep the
-- button lit
local frames = 0
local function watch()
  local settled = (not recall) or (reaper.time_precise() - START > STARTUP_GRACE)
  if not tools.shuffle_on() or (settled and not per_track_ripple()) then
    tools.set_shuffle(false)
    set_button(false)
    tools.reapply_tool()   -- the Move/Multi tool's own drags again
    return
  end
  frames = frames + 1
  if frames % 30 == 0 and reaper.GetToggleCommandStateEx(section, cmd_id) ~= 1 then
    set_button(true)
  end
  reaper.defer(watch)
end
reaper.atexit(function()
  -- REAPER quitting keeps the mode for next time; only the button goes off
  set_button(false)
end)
watch()
