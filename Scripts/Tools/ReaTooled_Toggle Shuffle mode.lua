-- @description ReaTooled - Toggle Shuffle mode
-- @version 1.8
-- @date 2026.11.11
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
--   Cmd+click (or Option+click) on the button: the ripple options at the mouse ("Ripple
--   edit when editing media item edges", "+ Left edge ripple"); Shuffle stays as it was.
--   Spot mode is turned off (Spot and Shuffle are exclusive). Kept when REAPER
--   restarts (with the per-track or all-tracks choice).
--   With the Move Tool (or the Multi tool's lower half), dragging an item reorders
--   it, as in Pro Tools (see "Shuffle move").
--   On its own (without the rest of ReaTooled: only this, "Shuffle move" and the Mouse
--   library, plus js_ReaScriptAPI): plain and Option/Alt item drags shuffle while it's on,
--   and REAPER's own item drags come back when it's turned off or REAPER quits. It starts
--   off after a restart (add it to REAPER's startup actions to have it on).
-- @changelog
--   v1.8 Works without the Tools library: it then sets its own item drags for Shuffle (kept in
--        the same record, ModeOverrides) and starts Shuffle move as the Move Tool would, and
--        puts REAPER's drags back when it goes off or REAPER quits. With the rest of ReaTooled
--        installed it works exactly as before
--   v1.7 Cmd+click or Option+click: the ripple options menu (Shuffle isn't changed)
--   v1.6 No tooltip when the ripple mode changes only for a moment (Cmd held over a left edge,
--        an item or a razor area switches to all tracks and back: ExtState ShuffleQuiet)
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
if not ok or type(tools) ~= "table" then tools = nil end
local ALONE = tools == nil   -- (on its own: no ReaTooled tools, so Shuffle sets its own drags)
local ALIVE = "ShuffleModeAlive"   -- (while on, every moment: the running copy's heartbeat)

-- On its own: what the Tools library would do for Shuffle with the Move Tool
if ALONE then
  local SNAP_KEY = "ModeOverrides"   -- (the same record as the Tools library: "group|context|flag|original;...")
  local SHUFFLE_DRAGS = { { "MM_CTX_ITEM", 0 }, { "MM_CTX_ITEMLOWER", 0 }, { "MM_CTX_ITEM", 4 },
                          { "MM_CTX_ITEMLOWER", 4 }, { "MM_CTX_AREASEL", 4 } }
  local UPPER_OF = { MM_CTX_ITEMLOWER = "MM_CTX_ITEM" }
  local function read_snaps()
    local list = {}
    for line in reaper.GetExtState(NS, SNAP_KEY):gmatch("[^;]+") do
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
  -- (still as Shuffle left it: No action, or a lower half passing through to its upper half)
  local function still_set(ctx, flag)
    local v = reaper.GetMouseModifier(ctx, flag) or ""
    if v == "" or v == "-1" or v:match("^0%s*%a?$") then return true end
    return UPPER_OF[ctx] ~= nil and v == reaper.GetMouseModifier(UPPER_OF[ctx], flag)
  end
  local function drags_on()
    local list, known = read_snaps(), {}
    for _, e in ipairs(list) do known[e.ctx .. "|" .. e.flag] = true end
    for _, d in ipairs(SHUFFLE_DRAGS) do
      if not known[d[1] .. "|" .. d[2]] then
        local orig = reaper.GetMouseModifier(d[1], d[2]) or ""
        list[#list + 1] = { group = "shuffle", ctx = d[1], flag = d[2], value = orig ~= "" and orig or "-1" }
      end
    end
    write_snaps(list)
    for _, d in ipairs(SHUFFLE_DRAGS) do reaper.SetMouseModifier(d[1], d[2], "0") end
  end
  local function drags_off()   -- (lower halves first: they can pass through to the upper half)
    local list, keep = read_snaps(), {}
    table.sort(list, function(a, b) return (UPPER_OF[a.ctx] and 0 or 1) < (UPPER_OF[b.ctx] and 0 or 1) end)
    for _, e in ipairs(list) do
      if e.group == "shuffle" then
        if still_set(e.ctx, e.flag) then reaper.SetMouseModifier(e.ctx, e.flag, e.value) end
      else keep[#keep + 1] = e end
    end
    write_snaps(keep)
  end
  local function shuffle_on() return reaper.GetExtState(NS, "ShuffleMode") == "1" end
  tools = {
    shuffle_on = shuffle_on,
    set_shuffle = function(v) reaper.SetExtState(NS, "ShuffleMode", v and "1" or "0", true) end,
    spot_on = function() return false end, set_spot = function() end, set_button = function() end,
    options_click = function() return false end,
    -- Shuffle on: REAPER's plain and Option/Alt item drags (and Option/Alt razor drags) off, and
    -- Shuffle move started for them; off: REAPER's back, and Shuffle move stops by itself
    reapply_tool = function()
      if shuffle_on() then
        drags_on()
        reaper.SetExtState(NS, "ShuffleMoveTool", "grabber", false)
        local path = dir .. "ReaTooled_Shuffle move (background).lua"
        local cmd = reaper.file_exists(path) and reaper.AddRemoveReaScript(true, 0, path, true) or 0
        if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
      else
        reaper.SetExtState(NS, "ShuffleMoveTool", "", false)
        drags_off()
      end
    end,
    drags_off = drags_off,
  }
  -- Shuffle shown on, but no copy running (REAPER restarted, or it stopped without cleaning up):
  -- it's off, and anything it left switched is put back
  local beat = tonumber(reaper.GetExtState(NS, ALIVE))
  if shuffle_on() and not (beat and reaper.time_precise() - beat < 2) then
    tools.set_shuffle(false)
    tools.reapply_tool()
  end
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

-- Cmd+click or Option+click on the button: the ripple options, Shuffle left as it was
local options = tools.ripple_menu ~= nil and tools.options_click ~= nil and tools.options_click()
if options then tools.ripple_menu() end

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
elseif options then
  on = tools.shuffle_on()   -- (unchanged: the running copy this replaced goes on)
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
reaper.SetExtState(NS, ALIVE, tostring(reaper.time_precise()), false)
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
    local q = reaper.GetExtState(NS, "ShuffleQuiet")   -- (a Cmd switch for a moment: no tooltip)
    local quiet = q == "1" or (tonumber(q) ~= nil and reaper.time_precise() < tonumber(q))
    if not quiet then tooltip(all and "Shuffle: all tracks" or "Shuffle: per track") end
  end
  frames = frames + 1
  reaper.SetExtState(NS, ALIVE, tostring(reaper.time_precise()), false)
  if frames % 30 == 0 and reaper.GetToggleCommandStateEx(section, cmd_id) ~= 1 then
    set_button(true)
  end
  reaper.defer(watch)
end
reaper.atexit(function()
  -- REAPER quitting keeps the mode for next time; only the button goes off
  set_button(false)
  -- (on its own: REAPER's item drags are put back, as nothing would put them back at the next
  -- start; when this copy is being replaced, the new one sets them again right away)
  if ALONE then
    reaper.SetExtState(NS, "ShuffleMoveTool", "", false)
    tools.drags_off()
  end
end)
watch()
