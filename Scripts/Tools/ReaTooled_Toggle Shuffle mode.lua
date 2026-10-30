-- @description ReaTooled - Toggle Shuffle mode
-- @version 1.5
-- @date 2026.10.29
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Like Pro Tools' Shuffle mode
--   Each press goes to the next of three states:
--     1. Shuffle, per track: ripple editing per track, so trims, deletes and pastes
--        close up or push out the items after them on the same track
--     2. Shuffle, all tracks: ripple editing all tracks; a Shuffle drag moves the
--        same stretch of time on every track (a razor move of the whole project)
--     3. Off: back to Slip (ripple editing off)
--   Turned on while REAPER is already in a ripple mode, it starts in that mode.
--   The button is lit in both Shuffle states; REAPER's ripple buttons show which.
--   While Shuffle is on, choosing per-track or all-tracks ripple in REAPER switches
--   between the two; switching ripple off any other way (the Slip button, REAPER's
--   ripple buttons) turns Shuffle off, so the button always shows the real state.
--   Spot mode is turned off (Spot and Shuffle are exclusive). Kept when REAPER
--   restarts (with the per-track or all-tracks choice).
--   With the Move Tool (or the Multi tool's lower half), dragging an item reorders
--   it, as in Pro Tools (see "Shuffle move").
-- @changelog
--   v1.5 Turned on while REAPER is already in a ripple mode, Shuffle starts in that mode
--        (all-tracks ripple on: Shuffle all tracks)
--   v1.4 Three states: Shuffle per track, Shuffle all tracks, off. Choosing all-tracks
--        ripple in REAPER while Shuffle is on keeps Shuffle on (all tracks).
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
local RIPPLE_ALL       = 40311        -- Options: Set ripple editing all tracks
local ALL_KEY     = "ShuffleAllTracks" -- "1": Shuffle on with all-tracks ripple (kept)

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
local function all_ripple() return reaper.GetToggleCommandState(RIPPLE_ALL) == 1 end
local function set_all(v) reaper.SetExtState(NS, ALL_KEY, v and "1" or "0", true) end
local function tooltip(msg)
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(msg, x + 12, y + 12, true)
end

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
  if on then
    reaper.Main_OnCommand((reaper.GetExtState(NS, ALL_KEY) == "1") and RIPPLE_ALL or RIPPLE_PER_TRACK, 0)
  end
  tools.reapply_tool()   -- the Move/Multi tool's drags for Shuffle (or back to normal)
else
  -- off -> per track -> all tracks -> off. Turned on while REAPER is already in a
  -- ripple mode, Shuffle starts in that mode.
  local wasOn = tools.shuffle_on()
  local toAll
  if wasOn then toAll = not all_ripple() else toAll = all_ripple() end
  on = (not wasOn) or toAll
  tools.set_shuffle(on)
  if on then
    if tools.spot_on() then                       -- Spot and Shuffle are exclusive
      tools.set_spot(false)
      tools.set_button("ReaTooled_Toggle Spot mode.lua", false)
    end
    reaper.Main_OnCommand(toAll and RIPPLE_ALL or RIPPLE_PER_TRACK, 0)
    set_all(toAll)
  else
    reaper.Main_OnCommand(RIPPLE_OFF, 0)          -- back to Slip
  end
  tools.reapply_tool()
  tooltip(on and (toAll and "Shuffle: all tracks" or "Shuffle: per track") or "Shuffle off (Slip)")
end

set_button(on)
if not on then
  reaper.defer(function() end)   -- no undo point
  return
end

-- While on: watch for Shuffle being switched off some other way, and keep the
-- button lit
local frames = 0
local lastAll = nil   -- (read once settled)
local function watch()
  local settled = (not recall) or (reaper.time_precise() - START > STARTUP_GRACE)
  local all = all_ripple()
  if not tools.shuffle_on() or (settled and not per_track_ripple() and not all) then
    tools.set_shuffle(false)
    set_button(false)
    tools.reapply_tool()   -- the Move/Multi tool's own drags again
    return
  end
  if settled and lastAll == nil then lastAll = all end
  if settled and all ~= lastAll then   -- ripple mode changed in REAPER: Shuffle follows
    lastAll = all
    set_all(all)
    tooltip(all and "Shuffle: all tracks" or "Shuffle: per track")
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
