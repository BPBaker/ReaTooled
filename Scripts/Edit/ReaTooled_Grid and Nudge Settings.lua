-- @description ReaTooled - Grid & Nudge Settings (Dockable GUI)
-- @version 3.4
-- @date 2026.11.13
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Grid and nudge settings, like Pro Tools' Edit window
--   Turn the grid on and off, choose its division, and set the nudge amount and unit, in a
--   dockable window, right inside REAPER's Transport bar, or in the empty space next to
--   the ruler (between the main toolbar and the ruler, above the track list).
--   • Grid: click to toggle the grid; the division menu has frame rate, 1 measure and
--     musical divisions.
--   • Nudge: click the value to type one; the unit menu has milliseconds, seconds, measures
--     and beats (with dotted and triplet), samples, frames and more.
--   • In the Transport (right-click the window > Put in the Transport): Grid above Nudge
--     (or one row), sharp on Retina/HiDPI screens and drawn in your theme's colors. Drag
--     the grip to move it along the Transport and its right edge to resize it; the grip's menu attaches it to an edge
--     of the Transport, either side of the time display or left of the selection display,
--     locks it, or puts it back in a window.
--   • It moves and resizes with the Transport, never covers the transport buttons or time
--     display, moves to free space when it runs out of room, and hides when there is none.
--   • Next to the ruler (right-click the window > Put next to the ruler): fills the empty
--     space between the main toolbar's buttons and the ruler, following it as the track
--     list or the toolbar changes width. Drag the grip left to make it bigger (it grows to
--     the left, over the toolbar); the grip menu sets its height and layout there.
--   • The grip menu: where to show it (Transport, next to the ruler, or a window), its
--     position, its layout (rows, size, HiDPI), and Close.
--   Mapped to M. Starts with REAPER, in the window or the Transport, whichever you used last.
--
-- @requires
--   • ReaImGui v0.10.0.2+ (tested; forwards-compatible via feature detection)
--   • JS_ReaScriptAPI (recommended) for robust keyboard-focus restore
--   • REAPER 7.03+ recommended (set_action_options for clean toggle/terminate)
--
-- @notes
--   • ExtState keys (section "ReaTooled"):
--       nudge_val   (number)   – current nudge value
--       nudge_unit  (integer)  – current unit index
--       nudge_modifier ("none"|"dotted"|"triplet") – swing modifier for measures/beats presets
--   • The grid selector never imposes a grid on the project. DEFAULT_GRID_INDEX is only
--     the label shown when the project's grid can't be matched to a menu entry.
--
-- @changelog
--   v3.4 (2026-11-13)
--     • New: Put next to the ruler (the window's right-click menu, or the grip menu). It
--       fills the empty space between the main toolbar's buttons and the ruler (where REAPER
--       shows the grid division, above the track list), covering it completely, with the
--       controls kept to the right, by the ruler. It follows that space as the track list or
--       the toolbar changes width. It fits itself to the space: two rows when there's room,
--       else one column (Grid, division, Nudge, value), as large as fits. Drag the grip (or
--       the background) to the left to make it bigger: it grows to the left, over the
--       toolbar if need be; drag right to make it smaller; Reset size fits the space again.
--       The grip menu sets its height in the space, the layout (automatic, two rows, one
--       column) and Lock size. If it can't fit, the window shows instead. Its settings are
--       kept apart from the Transport's
--     • The grip menu is reorganised: where to show it first (Transport, next to the ruler,
--       window, with a tick on the current one), then Position (in the Transport, its
--       attach points in left-to-right order; then Lock and Reset position), then Layout
--       (rows, Reset size, HiDPI), then Close
--   v3.3.9 (2026-11-13)
--     • Transport: the box finds its spot again when REAPER's Transport is laid out anew without
--       changing size (a fresh install, the theme loading, a different layout). It measured the
--       Transport only when its size changed, so a measurement taken before REAPER had finished
--       laying it out at startup stayed until the window was resized. The layout (where the
--       time display sits, and the theme) now counts as a change too, and for the first 12
--       seconds after starting it looks again every 2 seconds while REAPER settles
--   v3.3.8 (2026-11-06)
--     • Optional timing report for testing: when "ReaTooled_DEV Interface smoothness
--       monitor.lua" turns it on, it measures how long each part of the script takes per
--       frame and shows it in the monitor. Off otherwise (no measuring, nothing written)
--   v3.3.7 (2026-11-06)
--     • Transport: no more lag in REAPER when the strip is attached next to the selection
--       display but the Transport isn't showing one (too narrow, or a layout without it).
--       It then searched the whole Transport for it on every frame, thousands of "what's
--       under this point?" questions to REAPER, 30 times a second. Not finding it is now
--       remembered until the Transport changes size (with a look every 5 seconds)
--     • Transport: finding the selection display and the transport buttons asks REAPER
--       about far fewer points (a coarse pass, then only the edges point by point)
--   v3.3.6 (2026-11-05)
--     • Changing the nudge unit converts with the project's sample rate (it was always
--       44.1 kHz) and the grid's real size (grid values came out four times off)
--     • Dotted and triplet "1 bar" is right in REAPER's measures.beats notation (dotted was
--       1.5, which REAPER reads as 1 measure + 5 beats; now 1.2 in 4/4, i.e. 6 beats), and
--       switching dotted/triplet on and off converts the value the same way
--   v3.3.5 (2026-11-05)
--     • Dotted and triplet: picking a measures/beats preset applies the dotted (x1.5) or
--       triplet (x2/3) length once, not twice (a dotted 1/8 note was 1.5 x 1.5 x 1/8)
--   v3.3.4 (2026-11-04)
--     • Transport: no more stutter in the rest of REAPER while it runs. Attached to the
--       selection display, it measured that display all over again every 2 seconds
--       (thousands of "what's under this point?" questions to REAPER at once); now it
--       only checks the display's edge twice a second, and measures again when the
--       Transport changes size.
--   v3.3.3 (2026-11-03)
--     • ReaPack's About text describes the Transport mode.
--   v3.3.2 (2026-11-02)
--     • Transport: only the transport buttons (rewind, forward, record, play, repeat, stop,
--       pause) and the time display are protected; the box may cover everything else the
--       same way: selection, time signature, tempo, timebase, global automation, play
--       rate. (It used to hide over some of those and cover others.) By REAPER's names
--       for them, so themes and the Theme Adjuster's centred layout are covered too.
--   v3.3.1 (2026-11-02)
--     • Transport: the box keeps the size you gave it (no more shrinking text as the
--       window narrows): it stays at its spot, moves to clear space if it must, or hides.
--     • Transport: its background always fills the Transport's full height, whatever its
--       size, so it sits in the Transport like one of its own parts.
--   v3.3  (2026-11-02)
--     • Transport: never covers the transport buttons or the time display. As REAPER's
--       window shrinks and its Transport folds up, the box stays where you put it while
--       that spot is clear; otherwise it moves to the nearest clear space anywhere in
--       the Transport (it may cover the selection display, BPM and play rate); if none
--       is wide enough it gets smaller (smaller text, then "G"/"N" instead of
--       "Grid"/"Nudge"); if it still doesn't fit it hides until there's room. Works with
--       centred and uncentred transport controls (what's where is read from REAPER).
--     • "Left of the selection display" leaves a few more points of space.
--   v3.2.5 (2026-11-01)
--     • Fixed: after the computer slept, "expected a valid ImGui_Context*" and the script
--       stopping. In the Transport the window's ImGui context sits unused, so ReaImGui
--       can let it go; when the window was shown again (the Transport briefly missing
--       on wake) it used the old one. It's now checked, and made again, right before
--       the window is drawn, whatever the mode.
--   v3.2.4 (2026-10-31)
--     • Transport, attached to the selection display: it follows the display every frame
--       while the Transport is resized (the edge is tracked from where it was, a few
--       lookups a frame) instead of re-measuring 3 times a second, so it moves with it.
--   v3.2.3 (2026-10-31)
--     • Transport: "Right of the selection display" removed (left stays). The selection
--       display is only measured when attached to it, and at most ~3 times a second
--       while the Transport is being resized (resizing was sluggish).
--   v3.2.2 (2026-10-31)
--     • Transport: Attach to > Left/Right of the selection display (found by asking REAPER
--       what's under points across the Transport, as Gridbox does).
--   v3.2.1 (2026-10-31)
--     • The value fields are the selection box's darker shade again (not the theme's
--       Transport edit background colour).
--   v3.2  (2026-10-31)
--     • Colours follow the theme, in both the window and the Transport: background and
--       text from the theme's main window/Transport colours, the teal accent kept (darker
--       on light themes), and grid-on, value field, hover and divider mixed from those the
--       way the design mixes them. A theme change is picked up within a second.
--     • Transport: fills the Transport's full height by default.
--   v3.1.4 (2026-10-31)
--     • Transport: sharp again. The bitmap is always exactly its on-screen size times the
--       pixel density (an odd width was being stretched by a fraction of a pixel).
--   v3.1.3 (2026-10-31)
--     • Transport: the Retina check updates its window before reading the result (it read
--       too early); grip menu > HiDPI (Retina): Automatic / Always on / Always off.
--   v3.1.2 (2026-10-31)
--     • Transport: Retina detected again at start (the check now runs on the Transport's
--       screen; the last result is remembered).
--   v3.1.1 (2026-10-31)
--     • Transport: bigger text (about the Transport's own); "Attach to" now moves it next
--       to that edge; the resize zone at the right edge is wider and shows a resize
--       cursor (the grip shows a move cursor).
--   v3.1  (2026-10-31)
--     • Transport: sharp on HiDPI/Retina screens (drawn at the screen's pixel density).
--     • Transport: Grid above Nudge (two rows, like the window) is the default; one row is
--       in the grip menu. Drag the right edge to resize (unless locked); "Reset size
--       (fit the Transport)" in the grip menu.
--   v3.0  (2026-10-31)
--     • New: "In the Transport" mode. The same controls are drawn right into REAPER's
--       Transport (like FeedTheCat's Gridbox), so they move, resize, dock and undock with
--       it. Grid toggles the grid, the division and the arrows open REAPER menus (the
--       same entries as before), clicking the value lets you type one (Enter keeps it,
--       Esc or a click elsewhere cancels). The grip at the left drags it along the
--       Transport and opens its menu: back to a window, Lock position, Attach to (left
--       or right edge of the Transport, left or right of the time display), Reset
--       position, Close. If the Transport is hidden the window shows until it's back.
--     • The dockable window works as before. Right-click its background for
--       "Put in the Transport". The mode is remembered.
--   v2.1.8  (2026-10-29)
--     • The nudge value field is wider (room for 9 characters instead of 6), so longer
--       values like 1:23.456 or 12.345678 show in full.
--   v2.1.7  (2026-10-20)
--     • Fixed: Grid button showed "1/16" for the first ~10 frames regardless of the
--       project's actual grid, because the first sync waited on the poll throttle.
--       The grid is now read once at startup, so the label is correct immediately.
--     • Fixed: If the project grid matched no menu entry (e.g. a custom division),
--       the button kept showing whatever was selected before. It now falls back to
--       the default label.
--     • Default grid label (1/16) is now a named constant, DEFAULT_GRID_INDEX.
--
--   v2.1.6  (2026-09-28)
--     • Fixed (root cause): "ImGui_End: Calling End() too many times!" recurring after
--       sleep/wake and display changes. Previous fixes relied on pcall to contain the
--       error, but the error still surfaced. This version prevents the imbalance instead:
--         - Context is validated with ImGui_ValidatePtr at the top of every defer cycle
--           and silently recreated (with a fresh font) if it has died, instead of the
--           script touching a dead context and tearing itself down.
--         - All REAPER state-changing calls (Main_OnCommand, GetSetProjectGrid set) are
--           queued and executed AFTER ImGui_End, so nothing that can pump the message
--           loop or trigger a redraw runs between Begin and End.
--         - A failed frame now discards and recreates the context on the next cycle
--           (up to a retry limit) rather than killing the script.
--     • Fixed: Toggle/close logic used _G to signal the running instance, but every
--       ReaScript launch gets its own Lua state, so the flag never reached it. Now uses
--       set_action_options (REAPER 7.03+) to terminate on relaunch, and atexit() to
--       reset the toolbar toggle however the script ends.
--     • Fixed: ImGui_IsWindowDocked was called before Begin (queried ImGui's implicit
--       debug window, always false), so docked-only flags never applied. Dock state is
--       now read inside the window and used on the next frame.
--
--   v2.1.5  (2026-04-20)
--     • Wrapped the entire ImGui frame in a single pcall (monitor disconnect fix attempt).
--   v2.1.4  (2026-04-17)
--     • pcall around ImGui_Begin (sleep/wake fix attempt).
--   v2.1.3  (2026-04-16)
--     • Lifecycle guard against stale deferred Main().
--   v2.1.2  (2026-04-07)
--     • PopStyleColor moved before ImGui_End.
--   v2.1.0  (2026-03-18)
--     • End always called after Begin; grid polling throttled; focus restore rewrite;
--       seconds-field error tint; dynamic color push counter; named HWND constant.
--   v2.0.0  (2025-09-27)
--     • Grid dropdown fix; unified action IDs; safer focus restore; compat detection.
--   v1.x
--     • Initial dockable Grid/Nudge GUI, unit presets, dotted/triplet, and extstate persistence.

local DEBUG_FOCUS = false
if DEBUG_FOCUS then reaper.ShowConsoleMsg("=== ReaTooled Grid/Nudge Debug Start ===\n") end

-- ===================================================================
--  TOGGLE / INSTANCE HANDLING
--  Each launch of a ReaScript runs in its own Lua state, so globals
--  can't be used to signal a running instance. Let REAPER do it.
-- ===================================================================
local _, _, section, cmdID = reaper.get_action_context()

if reaper.set_action_options then
  -- 1 = auto-terminate the running instance when relaunched (relaunch ignored)
  -- 4 = set toggle state ON
  reaper.set_action_options(1 | 4)
else
  reaper.SetToggleCommandState(section, cmdID, 1)
  reaper.RefreshToolbar2(section, cmdID)
end

-- ===================================================================
--  CONTEXT MANAGEMENT
-- ===================================================================
local CTX_NAME = 'Grid and Nudge Settings'
local ctx, FONT

local function create_context()
  ctx  = reaper.ImGui_CreateContext(CTX_NAME)
  FONT = reaper.ImGui_CreateFont('sans-serif', 10)  -- fresh font: old one may be GC'd with old ctx
  reaper.ImGui_Attach(ctx, FONT)
end

local function context_is_valid()
  if not ctx then return false end
  if reaper.ImGui_ValidatePtr then
    return reaper.ImGui_ValidatePtr(ctx, 'ImGui_Context*')
  end
  return true
end

local transport_teardown_fwd   -- (TRANSPORT MODE, below)
reaper.atexit(function()
  if transport_teardown_fwd then pcall(transport_teardown_fwd) end
  reaper.SetToggleCommandState(section, cmdID, 0)
  reaper.RefreshToolbar2(section, cmdID)
  -- Pre-0.9 ReaImGui only; newer builds garbage-collect contexts automatically.
  if ctx and reaper.ImGui_DestroyContext then
    pcall(reaper.ImGui_DestroyContext, ctx)
  end
end)

create_context()

-- === Feature detection (v0.10.0.2-safe) ============================
local HAS_NAV_COLORS = (
  reaper.ImGui_Col_NavHighlight ~= nil and
  reaper.ImGui_Col_NavWindowingHighlight ~= nil and
  reaper.ImGui_Col_NavWindowingDimBg ~= nil
)
local HAS_WINDOW_FONT_SCALE = (reaper.ImGui_SetWindowFontScale ~= nil)

-- ===================================================================
--  ACTION IDS (unified)
--    40904 = Grid: Set to frame rate
--    40923 = Grid: Set to 1 measure
--    40145 = Options: Snap/grid settings: Enable grid
-- ===================================================================
local CMD_GRID_FRAME   = 40904
local CMD_GRID_MEASURE = 40923
local CMD_GRID_TOGGLE  = 40145

-- ===================================================================
--  CONSTANTS
-- ===================================================================
local EXT_SECTION  = "ReaTooled"

-- Timing report, for testing only. Off unless the DEV monitor script sets
-- ExtState ReaTooled/GridNudge_timing = "1"; then, once a second, it writes how long each
-- part took to ReaTooled/GridNudge_timing_report (lines "name|ms per frame|worst ms|calls/s").
local PROF = { on = false, checked = 0, since = 0, frames = 0, t = {}, n = {}, mx = {}, order = {} }
function PROF.add(name, dt)
  if not PROF.t[name] then PROF.t[name], PROF.n[name], PROF.mx[name] = 0, 0, 0; PROF.order[#PROF.order + 1] = name end
  PROF.t[name], PROF.n[name] = PROF.t[name] + dt, PROF.n[name] + 1
  if dt > PROF.mx[name] then PROF.mx[name] = dt end
end
function PROF.wrap(name, f)
  return function(...)
    if not PROF.on then return f(...) end
    local t0 = reaper.time_precise()
    local a, b, c, d = f(...)
    PROF.add(name, reaper.time_precise() - t0)
    return a, b, c, d
  end
end
function PROF.tick(mode_name)
  local now = reaper.time_precise()
  if now - PROF.checked >= 0.5 then
    PROF.checked = now
    local on = reaper.GetExtState(EXT_SECTION, "GridNudge_timing") == "1"
    if on ~= PROF.on then
      PROF.on, PROF.since, PROF.frames, PROF.t, PROF.n, PROF.mx, PROF.order = on, now, 0, {}, {}, {}, {}
    end
  end
  if PROF.on and now - PROF.since >= 1 and PROF.frames > 0 then
    local secs = now - PROF.since
    local out = { string.format("%s|%.1f|%.3f", mode_name, PROF.frames / secs, now) }
    for _, k in ipairs(PROF.order) do
      out[#out + 1] = string.format("%s|%.3f|%.2f|%.1f", k, PROF.t[k] * 1000 / PROF.frames,
                                    PROF.mx[k] * 1000, PROF.n[k] / secs)
    end
    reaper.SetExtState(EXT_SECTION, "GridNudge_timing_report", table.concat(out, "\n"), false)
    PROF.since, PROF.frames, PROF.t, PROF.n, PROF.mx, PROF.order = now, 0, {}, {}, {}, {}
  end
end
local EXT_KEY_VAL  = "nudge_val"
local EXT_KEY_UNIT = "nudge_unit"

-- Child window ID of REAPER's main arrange view (focus restore target).
local REAPER_MAIN_EDIT_HWND_ID = 1000

-- Consecutive failed frames tolerated before giving up.
local MAX_FRAME_FAILURES = 5

-- Grid label shown when the project grid matches no menu entry.
-- Index into grid_options below: 8 = '1/16'. Display only; never
-- written to the project.
local DEFAULT_GRID_INDEX = 8

-- ===================================================================
--  THEME COLOURS (v3.2)
--  The design's colours, worked out from the current theme: background
--  and text from the theme's main window/Transport colours, the teal
--  accent kept (its contrast adjusted for light themes), and the rest
--  (grid-on fill, value field, hover, divider) mixed from those, as the
--  design mixes them on its dark grey. Read again when the theme changes.
--  P.* are 0xRRGGBB.
-- ===================================================================
local P = {}
local ACCENT = 0x1ABC98

local function theme_rgb(key, fallback)
  local c = reaper.GetThemeColor and reaper.GetThemeColor(key, 0) or -1
  if not c or c < 0 then return fallback end
  local r, g, b = reaper.ColorFromNative(c)
  return (r << 16) | (g << 8) | b
end
local function split(c) return (c >> 16) & 255, (c >> 8) & 255, c & 255 end
local function mix(a, b, t)   -- a towards b by t (0..1)
  local ar, ag, ab = split(a); local br, bg, bb = split(b)
  local function m(x, y) return math.floor(x + (y - x) * t + 0.5) end
  return (m(ar, br) << 16) | (m(ag, bg) << 8) | m(ab, bb)
end
local function lum(c) local r, g, b = split(c); return (0.299 * r + 0.587 * g + 0.114 * b) / 255 end

local function load_palette()
  local bg   = theme_rgb("col_main_bg2", 0x333333)
  local text = theme_rgb("col_main_text2", 0x9F9F9F)
  if math.abs(lum(text) - lum(bg)) < 0.25 then text = lum(bg) > 0.5 and 0x202020 or 0xBFBFBF end
  local dark = lum(bg) < 0.5
  local toward = dark and 0xFFFFFF or 0x000000          -- "lighter" on dark themes, "darker" on light ones
  P.bg     = bg
  P.text   = text
  P.label  = dark and mix(text, 0xFFFFFF, 0.85) or mix(text, 0x000000, 0.85)   -- the design's white "Nudge"
  P.accent = dark and ACCENT or mix(ACCENT, 0x000000, 0.35)                     -- teal, readable on light themes
  P.on_bg  = mix(bg, P.accent, 0.22)                                           -- the design's 0x2D5047 on 0x333333
  -- the value fields: the darker shade the Transport's selection box uses (the design's
  -- 0x2A2A2A on 0x333333). The theme's "Transport edit background" colour isn't what
  -- the box shows (the box is drawn from the theme's image), so it's mixed from the
  -- background the same way.
  P.field  = mix(bg, dark and 0x000000 or 0xFFFFFF, 0.18)
  P.hover  = mix(bg, toward, 0.06)
  P.sep    = mix(bg, text, 0.2)
  P.grip   = mix(bg, text, 0.5)
  P.title  = mix(bg, 0x000000, dark and 0.6 or 0.15)
  P.error  = 0xFF4444
end
load_palette()
local palette_theme = reaper.GetLastColorThemeFile and reaper.GetLastColorThemeFile() or ""
local palette_check = 0
-- (true if the theme changed since the last check)
local function palette_changed()
  local now = reaper.time_precise()
  if now - palette_check < 1 then return false end
  palette_check = now
  local f = reaper.GetLastColorThemeFile and reaper.GetLastColorThemeFile() or ""
  local before = P.bg .. "|" .. P.text
  load_palette()
  local changed = f ~= palette_theme or before ~= (P.bg .. "|" .. P.text)
  palette_theme = f
  return changed
end
local function IM(c, a) return (c << 8) | (a or 0xFF) end   -- ReaImGui: 0xRRGGBBAA

-- ===================================================================
--  POST-FRAME ACTION QUEUE
--  Anything that changes REAPER state is queued here and run after
--  ImGui_End, so nothing can re-enter the message loop mid-frame.
-- ===================================================================
local pending_actions = {}

local function queue_action(fn)
  pending_actions[#pending_actions + 1] = fn
end

local function run_pending_actions()
  local list = pending_actions
  pending_actions = {}
  for _, fn in ipairs(list) do fn() end
end

-- ===================================================================
--  STATE
-- ===================================================================
local nudge_val  = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_VAL))  or 10.0
local unit_index = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_UNIT)) or 0

local last_valid_seconds_str = nil
local seconds_input_error    = false
local seconds_error_frames   = 0
local SECONDS_ERROR_DURATION = 30

local is_docked = false  -- read inside the window, applied on the next frame

local units = {
  'Milliseconds', 'Seconds', 'Grid Units', 'Measures.Beats', 'Samples',
  'Frames', 'Pixels', 'Item lengths', 'Item selections'
}

local grid_options = {
  'Frame', 'Measure',
  '1/128', '1/64', '1/32T', '1/32', '1/16T', '1/16',
  '1/8T', '1/8', '1/4T', '1/4', '1/2', '1', '2', '4'
}

-- Intentionally sparse: indices 1 and 2 are the "Frame"/"Measure"
-- sentinels (handled via action IDs, not GetSetProjectGrid).
local grid_div_values = {
  [3] = 0.0078125, [4] = 0.015625, [5] = 0.0208333, [6] = 0.03125,
  [7] = 0.0416667, [8] = 0.0625, [9] = 0.0833333, [10] = 0.125,
  [11] = 0.1666667, [12] = 0.25, [13] = 0.5, [14] = 1.0, [15] = 2.0, [16] = 4.0
}

local grid_index      = DEFAULT_GRID_INDEX
local grid_mode       = "division"
local grid_poll_frame = 0

local convertible_units = {
  [0] = true,  -- ms
  [1] = true,  -- sec
  [2] = true,  -- grid units
  [4] = true,  -- samples
  [5] = true,  -- frames
}

-- ===================================================================
--  HELPERS
-- ===================================================================
local function update_grid_index_from_reaper()
  if reaper.GetToggleCommandStateEx(0, CMD_GRID_FRAME) == 1 then
    grid_mode = "frame";   grid_index = 1; return
  elseif reaper.GetToggleCommandStateEx(0, CMD_GRID_MEASURE) == 1 then
    grid_mode = "measure"; grid_index = 2; return
  end
  grid_mode = "division"
  local _, current_val = reaper.GetSetProjectGrid(0, false)
  for i, v in pairs(grid_div_values) do
    if current_val and math.abs(v - current_val) < 0.00001 then
      grid_index = i
      return
    end
  end
  -- No matching menu entry (custom division): show the default label
  -- rather than a stale selection.
  grid_index = DEFAULT_GRID_INDEX
end

-- Sync with the project immediately so the first frame is correct.
update_grid_index_from_reaper()

local function ConvertNudgeValue(old_unit, new_unit, val)
  if old_unit == new_unit then return val end
  if not convertible_units[old_unit] or not convertible_units[new_unit] then
    return val
  end

  -- the project's sample rate (the audio device's when the project doesn't set its own)
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if (reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false) == 0 or not sr or sr <= 0)
     and reaper.GetAudioDeviceInfo then
    local ok, v = reaper.GetAudioDeviceInfo("SRATE", "")
    if ok and tonumber(v) and tonumber(v) > 0 then sr = tonumber(v) end
  end
  if not sr or sr <= 0 then sr = 44100 end
  local fps = reaper.TimeMap_curFrameRate(0)

  -- the grid's division is in whole notes (0.25 = a quarter note): its length in seconds
  -- at the edit cursor
  local _, grid_div = reaper.GetSetProjectGrid(0, false)
  local cur = reaper.GetCursorPosition()
  local grid_secs = reaper.TimeMap2_QNToTime(0, reaper.TimeMap2_timeToQN(0, cur) + grid_div * 4) - cur
  if not grid_secs or grid_secs <= 0 then grid_secs = 1 end

  -- normalize old → seconds
  if old_unit == 0 then            val = val / 1000
  elseif old_unit == 2 then        val = val * grid_secs
  elseif old_unit == 4 then        val = val / sr
  elseif old_unit == 5 then        val = val / fps
  end

  -- seconds → new
  if new_unit == 0 then            val = val * 1000
  elseif new_unit == 2 then        val = val / grid_secs
  elseif new_unit == 4 then        val = val * sr
  elseif new_unit == 5 then        val = val * fps
  end
  return val
end

-- REAPER's measures.beats notation (1.15 = 1 measure + 1.5 beats) <-> beats of the time
-- signature at the edit cursor. Dotted and triplet scale the beats, then go back to the
-- notation (a dotted bar in 4/4 is 6 beats = 1.2, not 1.5).
local function timesig_num()
  local num = reaper.TimeMap_GetTimeSigAtTime(0, reaper.GetCursorPosition())
  return (num and num > 0) and num or 4
end
local function mb_to_beats(v, num)
  local m = math.floor(v + 1e-9)
  return m * num + (v - m) * 10
end
local function beats_to_mb(b, num)
  local m = math.floor(b / num + 1e-9)
  return m + (b - m * num) / 10
end

local selected_modifier    = reaper.GetExtState("ReaTooled", "nudge_modifier")
if selected_modifier == "" then selected_modifier = "none" end
local modifier_multipliers = { none = 1.0, dotted = 1.5, triplet = 2/3 }

-- 0-based keys to match unit_index directly.
local unit_presets = {
  [0] = {
    { label = "1000 ms", value = 1000 },
    { label = "500 ms",  value = 500  },
    { label = "100 ms",  value = 100  },
    { label = "10 ms",   value = 10   },
    { label = "1 ms",    value = 1    },
    { label = "0.1 ms",  value = 0.1  },
  },
  [1] = {
    { label = "1 second",     value = 1.0    },
    { label = "0.5 second",   value = 0.5    },
    { label = "0.1 second",   value = 0.1    },
    { label = "0.01 second",  value = 0.01   },
    { label = "0.001 second", value = 0.001  },
    { label = "0.0001 second",value = 0.0001 },
  },
  [3] = function()
    local num = timesig_num()
    local base_presets = {   -- (in beats; keep in step with next_larger in ReaTooled_SmartNudge_Core.lua)
      { label = "1 bar",      beats = num    },
      { label = "1/2 note",   beats = 2      },
      { label = "1/4 note",   beats = 1      },
      { label = "1/8 note",   beats = 0.5    },
      { label = "1/16 note",  beats = 0.25   },
      { label = "1/32 note",  beats = 0.125  },
      { label = "1/64 note",  beats = 0.0625 },
    }
    local mul = (selected_modifier == "dotted")  and 1.5
             or (selected_modifier == "triplet") and (2/3) or 1.0
    local t = {}
    for _, p in ipairs(base_presets) do
      t[#t+1] = { label = p.label, value = beats_to_mb(p.beats * mul, num) }
    end
    return t
  end,
  [4] = {
    { label = "10000 samples", value = 10000 },
    { label = "1000 samples",  value = 1000  },
    { label = "100 samples",   value = 100   },
    { label = "10 samples",    value = 10    },
    { label = "2 samples",     value = 2     },
    { label = "1 sample",      value = 1     },
  },
  [5] = function()
    local fps = reaper.TimeMap_curFrameRate(0)
    return {
      { label = "1 second",    value = fps   },
      { label = "6 frames",    value = 6     },
      { label = "1 frame",     value = 1     },
      { label = "1/2 frame",   value = 0.5   },
      { label = "1/4 frame",   value = 0.25  },
      { label = "1 sub frame", value = 1/80  },
    }
  end,
  [6] = {
    { label = "100 pixels", value = 100 },
    { label = "50 pixels",  value = 50  },
    { label = "10 pixels",  value = 10  },
    { label = "5 pixels",   value = 5   },
    { label = "1 pixel",    value = 1   },
  },
  [7] = {
    { label = "8 items",   value = 8.0  },
    { label = "4 items",   value = 4.0  },
    { label = "2 items",   value = 2.0  },
    { label = "1 item",    value = 1.0  },
    { label = "1/2 item",  value = 0.5  },
    { label = "1/4 item",  value = 0.25 },
  },
  [8] = {
    { label = "8x selection",  value = 8.0  },
    { label = "4x selection",  value = 4.0  },
    { label = "2x selection",  value = 2.0  },
    { label = "1x selection",  value = 1.0  },
    { label = "1/2 selection", value = 0.5  },
    { label = "1/4 selection", value = 0.25 },
  },
}

local function get_current_presets()
  local p = unit_presets[unit_index]
  if type(p) == "function" then return p() end
  return p
end

-- ===================================================================
--  FOCUS RESTORE
-- ===================================================================
local nudge_input_was_active = false
local focus_restore_armed    = false
local focus_restore_pending  = false

local function arm_focus_restore()
  focus_restore_armed = true
end

-- Called after the frame (outside Begin/End).
local function try_restore_focus()
  if not focus_restore_armed or focus_restore_pending then return end
  if not nudge_input_was_active then
    focus_restore_armed = false
    return
  end
  focus_restore_pending = true
  reaper.defer(function()
    focus_restore_pending = false
    focus_restore_armed   = false
    nudge_input_was_active = false
    if not reaper.JS_Window_FindChildByID then return end
    local hwnd = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), REAPER_MAIN_EDIT_HWND_ID)
    if hwnd and reaper.JS_Window_IsVisible(hwnd) then
      reaper.JS_Window_SetFocus(hwnd)
    end
  end)
end

-- ===================================================================
--  POPUPS
-- ===================================================================
local function DrawPresetsPopup()
  if not modifier_multipliers[selected_modifier] then selected_modifier = "none" end
  local presets = get_current_presets()

  if presets then
    for _, preset in ipairs(presets) do
      local expected_val = preset.value   -- (the measures/beats presets include dotted/triplet already)
      local is_selected  = math.abs(expected_val - nudge_val) < 0.00001
      if is_selected then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), IM(P.accent))
      end
      if reaper.ImGui_MenuItem(ctx, preset.label, nil, is_selected, true) then
        nudge_val = expected_val
        reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL, tostring(nudge_val), true)
        reaper.ImGui_CloseCurrentPopup(ctx)
        arm_focus_restore()
      end
      if is_selected then reaper.ImGui_PopStyleColor(ctx) end
    end
    reaper.ImGui_Separator(ctx)
  end

  if unit_index == 3 then
    for _, mod in ipairs({ "dotted", "triplet" }) do
      local label       = mod:gsub("^%l", string.upper)
      local is_selected = (selected_modifier == mod)
      if is_selected then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), IM(P.accent))
      end
      if reaper.ImGui_MenuItem(ctx, label, nil, is_selected, true) then
        local prev_mul    = modifier_multipliers[selected_modifier]
        selected_modifier = (is_selected and "none" or mod)
        local new_mul     = modifier_multipliers[selected_modifier]
        local num         = timesig_num()
        nudge_val         = beats_to_mb(mb_to_beats(nudge_val, num) / prev_mul * new_mul, num)
        reaper.SetExtState(EXT_SECTION, "nudge_modifier", selected_modifier, true)
        reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL, tostring(nudge_val), true)
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      if is_selected then reaper.ImGui_PopStyleColor(ctx) end
    end
    reaper.ImGui_Separator(ctx)
  end

  for i, name in ipairs(units) do
    local unit_idx    = i - 1
    local is_selected = (unit_idx == unit_index)
    if is_selected then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), IM(P.accent))
    end
    if reaper.ImGui_MenuItem(ctx, name, nil, is_selected, true) then
      if unit_idx ~= 3 and selected_modifier ~= "none" then
        selected_modifier = "none"
        reaper.SetExtState(EXT_SECTION, "nudge_modifier", selected_modifier, true)
      end
      nudge_val  = ConvertNudgeValue(unit_index, unit_idx, nudge_val)
      unit_index = unit_idx
      reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL,  tostring(nudge_val),  true)
      reaper.SetExtState(EXT_SECTION, EXT_KEY_UNIT, tostring(unit_index), true)
      reaper.ImGui_CloseCurrentPopup(ctx)
      arm_focus_restore()
    end
    if is_selected then reaper.ImGui_PopStyleColor(ctx) end
  end
end

local function DrawGridPopup()
  for i, name in ipairs(grid_options) do
    local is_selected = (i == grid_index)
    if is_selected then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), IM(P.accent))
    end
    if reaper.ImGui_MenuItem(ctx, name, nil, is_selected, true) then
      grid_index = i
      local choice = i
      -- Apply the grid change after ImGui_End (see POST-FRAME ACTION QUEUE).
      queue_action(function()
        if name == "Frame" then
          reaper.Main_OnCommand(CMD_GRID_FRAME, 0)
        elseif name == "Measure" then
          reaper.Main_OnCommand(CMD_GRID_MEASURE, 0)
        else
          local val = grid_div_values[choice]
          if val and val > 0 then reaper.GetSetProjectGrid(0, true, val, 0, 0) end
        end
        grid_poll_frame = 0
        update_grid_index_from_reaper()
      end)
      reaper.ImGui_CloseCurrentPopup(ctx)
      arm_focus_restore()
    end
    if is_selected then reaper.ImGui_PopStyleColor(ctx) end
  end
end

-- ===================================================================
--  FRAME
--  Pure ImGui drawing. No REAPER state changes happen in here; they
--  are queued and run after End. Returns the window's `open` flag.
-- ===================================================================
local window_menu_can_transport = false   -- (TRANSPORT MODE, below)
local window_menu_choice = nil
local function DrawFrame()
  if not is_docked then
    reaper.ImGui_SetNextWindowSize(ctx, 360, 0, reaper.ImGui_Cond_Once())
  end

  local color_count = 0
  local function push_color(col, val)
    reaper.ImGui_PushStyleColor(ctx, col, val)
    color_count = color_count + 1
  end

  push_color(reaper.ImGui_Col_WindowBg(),      IM(P.bg))
  push_color(reaper.ImGui_Col_Button(),        IM(P.bg))
  push_color(reaper.ImGui_Col_FrameBg(),       IM(P.bg))
  push_color(reaper.ImGui_Col_Text(),          IM(P.text))
  push_color(reaper.ImGui_Col_ButtonHovered(), IM(P.bg))
  push_color(reaper.ImGui_Col_TitleBg(),       IM(P.title))
  push_color(reaper.ImGui_Col_TitleBgActive(), IM(P.title))

  if HAS_NAV_COLORS then
    push_color(reaper.ImGui_Col_NavHighlight(),          0x00000000)
    push_color(reaper.ImGui_Col_NavWindowingHighlight(), 0x00000000)
    push_color(reaper.ImGui_Col_NavWindowingDimBg(),     0x00000000)
  end

  local flags = reaper.ImGui_WindowFlags_NoCollapse()
              | reaper.ImGui_WindowFlags_NoScrollbar()
              | reaper.ImGui_WindowFlags_NoScrollWithMouse()
              | reaper.ImGui_WindowFlags_NoFocusOnAppearing()
              | (is_docked and reaper.ImGui_WindowFlags_NoTitleBar() or 0)
              | (is_docked and reaper.ImGui_WindowFlags_NoMove()     or 0)

  if reaper.ImGui_WindowFlags_NoNav then
    flags = flags | reaper.ImGui_WindowFlags_NoNav()
  else
    if reaper.ImGui_WindowFlags_NoNavFocus  then flags = flags | reaper.ImGui_WindowFlags_NoNavFocus()  end
    if reaper.ImGui_WindowFlags_NoNavInputs then flags = flags | reaper.ImGui_WindowFlags_NoNavInputs() end
  end

  local visible, open = reaper.ImGui_Begin(ctx, CTX_NAME, true, flags)

  -- Dock state of THIS window (used for next frame's flags).
  is_docked = reaper.ImGui_IsWindowDocked(ctx)

  if HAS_WINDOW_FONT_SCALE then
    reaper.ImGui_SetWindowFontScale(ctx, 1.0)
  end

  -- Paint over the corner chevron/triangle (version-agnostic)
  do
    local wx, wy = reaper.ImGui_GetWindowPos(ctx)
    local fs     = reaper.ImGui_GetFontSize(ctx)
    local s      = math.floor(fs * 0.9)
    local pad    = math.floor(fs * 0.9)
    local fgd    = reaper.ImGui_GetForegroundDrawList(ctx)
    if fgd then
      reaper.ImGui_DrawList_AddRectFilled(fgd, wx - pad, wy - pad, wx + s, wy + s, IM(P.bg), 2.0)
    end
  end

  if visible then
    ------------------------------------------------------------
    -- GRID
    ------------------------------------------------------------
    local grid_on = reaper.GetToggleCommandState(CMD_GRID_TOGGLE) == 1
    if grid_on then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), IM(P.on_bg))
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),   IM(P.accent))
    end
    if reaper.ImGui_Button(ctx, 'Grid') or reaper.ImGui_IsItemClicked(ctx, 1) then
      queue_action(function() reaper.Main_OnCommand(CMD_GRID_TOGGLE, 0) end)
      arm_focus_restore()
    end
    if grid_on then reaper.ImGui_PopStyleColor(ctx, 2) end

    reaper.ImGui_SameLine(ctx, nil, 4)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), IM(P.accent))
    if reaper.ImGui_Button(ctx, grid_options[grid_index]) or reaper.ImGui_IsItemClicked(ctx, 1) then
      reaper.ImGui_OpenPopup(ctx, 'grid_selector_popup')
    end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), IM(P.bg))
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),   IM(P.text))
    if reaper.ImGui_ArrowButton(ctx, '##grid_menu', reaper.ImGui_Dir_Down()) then
      reaper.ImGui_OpenPopup(ctx, 'grid_selector_popup')
    end
    reaper.ImGui_PopStyleColor(ctx, 2)

    if reaper.ImGui_BeginPopup(ctx, 'grid_selector_popup') then
      DrawGridPopup()
      reaper.ImGui_EndPopup(ctx)
    end

    reaper.ImGui_Separator(ctx)

    ------------------------------------------------------------
    -- NUDGE
    ------------------------------------------------------------
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), IM(P.label))
    if reaper.ImGui_Button(ctx, 'Nudge') or reaper.ImGui_IsItemClicked(ctx, 1) then
      reaper.ImGui_OpenPopup(ctx, 'nudge_val_popup')
    end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_SameLine(ctx, nil, 2)
    local text_width = ({ reaper.ImGui_CalcTextSize(ctx, '000000000') })[1]   -- room for 9 digits
    reaper.ImGui_SetNextItemWidth(ctx, text_width)

    local nudge_field_active_this_frame = false

    if unit_index == 3 then
      -- Measures.Beats: 6-decimal format
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), IM(P.accent))
      local input_str = string.format('%.6f', nudge_val)
      local ret, new_str = reaper.ImGui_InputText(ctx, '##nudge_val', input_str, 64)
      if reaper.ImGui_IsItemActive(ctx) then nudge_field_active_this_frame = true end
      if ret then
        local new_val = tonumber(new_str)
        if new_val then
          nudge_val = new_val
          reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL, tostring(nudge_val), true)
        end
      end
      reaper.ImGui_PopStyleColor(ctx)

    elseif unit_index == 1 then
      -- Seconds: mm:ss.mmm display with error tint on malformed input
      local mins = math.floor(nudge_val / 60)
      local secs = math.floor(nudge_val % 60)
      local ms   = math.floor((nudge_val - math.floor(nudge_val)) * 1000)
      local display_str = string.format('%d:%02d.%03d', mins, secs, ms)

      if not last_valid_seconds_str then
        last_valid_seconds_str = display_str
      end

      if seconds_input_error then
        seconds_error_frames = seconds_error_frames - 1
        if seconds_error_frames <= 0 then
          seconds_input_error = false
        end
      end

      local text_color = seconds_input_error and IM(P.error) or IM(P.accent)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color)
      local ret, new_str = reaper.ImGui_InputText(ctx, '##nudge_val', display_str, 64)
      if reaper.ImGui_IsItemActive(ctx) then nudge_field_active_this_frame = true end
      if ret then
        local m_str, s_str, ms_str = new_str:match('(%d+):(%d%d)%.(%d%d%d)')
        if m_str and s_str and ms_str then
          nudge_val = tonumber(m_str) * 60 + tonumber(s_str) + tonumber(ms_str) / 1000
          reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL, tostring(nudge_val), true)
          last_valid_seconds_str = new_str
          seconds_input_error    = false
        else
          seconds_input_error  = true
          seconds_error_frames = SECONDS_ERROR_DURATION
        end
      end
      reaper.ImGui_PopStyleColor(ctx)

    elseif unit_index == 0 or unit_index == 2 or unit_index == 4 or unit_index == 6 then
      -- Integer-display units: ms, grid, samples, pixels
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), IM(P.accent))
      local ret, new_val = reaper.ImGui_InputDouble(ctx, '##nudge_val', nudge_val, 0, 0, '%.0f')
      if reaper.ImGui_IsItemActive(ctx) then nudge_field_active_this_frame = true end
      if ret then
        nudge_val = math.floor(new_val + 0.5)
        reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL, tostring(nudge_val), true)
      end
      reaper.ImGui_PopStyleColor(ctx)

    else
      -- All other units: 3-decimal format
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), IM(P.accent))
      local ret
      ret, nudge_val = reaper.ImGui_InputDouble(ctx, '##nudge_val', nudge_val, 0, 0, '%.3f')
      if reaper.ImGui_IsItemActive(ctx) then nudge_field_active_this_frame = true end
      if ret then
        reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL, tostring(nudge_val), true)
      end
      reaper.ImGui_PopStyleColor(ctx)
    end

    if nudge_field_active_this_frame then
      nudge_input_was_active = true
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_ArrowButton(ctx, '##val_menu', reaper.ImGui_Dir_Down()) then
      reaper.ImGui_OpenPopup(ctx, 'nudge_val_popup')
    end

    if reaper.ImGui_BeginPopup(ctx, 'nudge_val_popup') then
      DrawPresetsPopup()
      reaper.ImGui_EndPopup(ctx)
    else
      queue_action(try_restore_focus)
    end

    -- Right-click the background: put it in the Transport (v3.0)
    local pflags = reaper.ImGui_PopupFlags_MouseButtonRight and reaper.ImGui_PopupFlags_MouseButtonRight() or 1
    if reaper.ImGui_PopupFlags_NoOpenOverItems then pflags = pflags | reaper.ImGui_PopupFlags_NoOpenOverItems() end
    if reaper.ImGui_BeginPopupContextWindow(ctx, 'grid_nudge_window_menu', pflags) then
      if reaper.ImGui_MenuItem(ctx, 'Put in the Transport', nil, false, window_menu_can_transport) then
        queue_action(function() window_menu_choice = "transport" end)
      end
      if reaper.ImGui_MenuItem(ctx, 'Put next to the ruler', nil, false, window_menu_can_transport) then
        queue_action(function() window_menu_choice = "ruler" end)
      end
      reaper.ImGui_EndPopup(ctx)
    end
  end -- if visible

  reaper.ImGui_PopStyleColor(ctx, color_count)
  reaper.ImGui_End(ctx)

  return open
end

-- ===================================================================
--  TRANSPORT MODE (v3.0)
--  The same controls drawn straight into REAPER's Transport, the way
--  FeedTheCat's Gridbox does it (MIT licence; approach used with thanks):
--  a LICE bitmap composited onto the Transport window, and the
--  Transport's own mouse messages intercepted while the mouse is over
--  it. So it moves, resizes, docks and undocks with the Transport.
--  Menus are REAPER menus; a typed value goes in a small field shown
--  over the value. The dockable window is the other mode (right-click
--  its background, or use the grip menu here, to switch).
-- ===================================================================
local MODE_KEY = "grid_nudge_mode"        -- "window" (dockable, default) | "transport" | "ruler"
local TR_KEY   = "grid_nudge_transport"   -- "anchor,offset,locked,rows,size"
local RH_KEY   = "grid_nudge_ruler_space"   -- (next to the ruler, v3.4: size = its width in points; rows 0 = automatic, 2, 4 = one column)
local RH_V_KEY = "grid_nudge_ruler_v"     -- "top" | "middle" | "bottom" (next to the ruler)

local OS_NAME = reaper.GetOS()
local IS_MAC  = OS_NAME:match("OS") ~= nil
local IS_WIN  = OS_NAME:match("Win") ~= nil
local CAN_TRANSPORT = (reaper.JS_Composite and reaper.JS_LICE_CreateBitmap and reaper.JS_WindowMessage_Intercept
                       and reaper.JS_GDI_CreateFont and reaper.JS_Window_FromPoint) and true or false

local mode = reaper.GetExtState(EXT_SECTION, MODE_KEY)
if mode == "toolbar" then mode = "ruler" end   -- (3.4's first draft)
if (mode ~= "transport" and mode ~= "ruler") or not CAN_TRANSPORT then mode = "window" end
-- (the Transport and the space next to the ruler are drawn the same way: "hosts")
local function in_host() return mode == "transport" or mode == "ruler" end
local RV = reaper.GetExtState(EXT_SECTION, RH_V_KEY)
if RV ~= "top" and RV ~= "middle" then RV = "bottom" end

-- Anchors: 1 = Transport's left edge, 2 = its right edge,
--          3 = left of the time display, 4 = right of the time display,
--          5 = left of the selection display
-- rows: 1 = one row, 2 = Grid above Nudge (like the window). size: row height in
-- points (nil = fit the Transport)
-- (next to the ruler: it fills the space and keeps to its right, by the ruler; size is how
-- wide it is, in points (nil = the space's width), and it grows to the left over the toolbar;
-- rows 0 = automatic (two rows when there's room, else one column), 2, or 4 = one column)
local function T_key() return mode == "ruler" and RH_KEY or TR_KEY end
local function load_T(key)
  local t = { anchor = 2, offset = nil, locked = false, rows = (key == RH_KEY) and 0 or 2, size = nil }
  local s = reaper.GetExtState(EXT_SECTION, key)
  local a, o, l, r, z = s:match("^(%d),([^,]*),(%d),?(%d?),?([^,]*)$")
  if a then
    t.anchor = tonumber(a) or 2; t.offset = tonumber(o); t.locked = (l == "1")
    t.rows = tonumber(r) or t.rows; t.size = tonumber(z)
    if t.anchor == 6 then t.anchor = 2; t.offset = nil end   -- (3.2.2's right-of-selection, withdrawn)
  end
  if key == RH_KEY then t.anchor = 2; t.offset = nil end
  return t
end
local T = load_T(T_key())
local function save_T()
  reaper.SetExtState(EXT_SECTION, T_key(),
    ("%d,%s,%d,%d,%s"):format(T.anchor, T.offset and string.format("%.0f", T.offset) or "", T.locked and 1 or 0,
      T.rows, T.size and string.format("%.1f", T.size) or ""), true)
end

local COL = {}
local function load_col()   -- (the theme palette, as LICE colours 0xAARRGGBB)
  for k, v in pairs({ bg = P.bg, text = P.text, accent = P.accent, on_bg = P.on_bg, white = P.label,
                      field = P.field, hover = P.hover, sep = P.sep, grip = P.grip }) do
    COL[k] = 0xFF000000 | v
  end
end
load_col()

local TRANSPORT_TITLE = reaper.JS_Localize and reaper.JS_Localize("Transport", "common") or "Transport"
local main_hwnd = reaper.GetMainHwnd()

-- HiDPI. Client sizes are in points on macOS (pixels elsewhere); the bitmap is
-- drawn at the screen's real pixel density and shown at point size, so it's sharp.
-- macOS: a Retina screen has 2 pixels per point (REAPER's gfx tells us, via
-- gfx.ext_retina, checked at start and each time a menu opens); Windows/Linux:
-- REAPER's own scaling of the Transport (from Gridbox).
-- (the check window opens on the Transport's screen, 1 pixel and invisible: a window
-- off-screen isn't on a Retina screen, which is what 3.1.1 got wrong at start)
local retina = tonumber(reaper.GetExtState(EXT_SECTION, "grid_nudge_retina")) or 1
-- "auto" (default), "on" (always 2x), "off" (always 1x): the grip menu's HiDPI choice
local hidpi = reaper.GetExtState(EXT_SECTION, "grid_nudge_hidpi")
if hidpi ~= "on" and hidpi ~= "off" then hidpi = "auto" end
local function check_retina(hwnd)
  if not IS_MAC then return end
  local _, l, t = reaper.JS_Window_GetRect(hwnd or reaper.GetMainHwnd())
  local title = "ReaTooled Grid and Nudge (retina check)"
  gfx.ext_retina = 1
  gfx.init(title, 1, 1, 0, (l or 0) + 4, (t or 0) + 4)
  local w = reaper.JS_Window_Find and reaper.JS_Window_Find(title, true)
  if w and reaper.JS_Window_SetOpacity then reaper.JS_Window_SetOpacity(w, "ALPHA", 0) end
  gfx.update()   -- (ext_retina is only filled in once the window has been updated)
  local r = tonumber(gfx.ext_retina) or 1
  gfx.quit()
  if r >= 1 and r ~= retina then
    retina = r
    reaper.SetExtState(EXT_SECTION, "grid_nudge_retina", tostring(r), true)
  end
end

local function transport_scale()
  local _, dpi = reaper.ThemeLayout_GetLayout("trans", -3)
  local px = (tonumber(dpi) or 256) / 256
  if IS_MAC then
    local _, ui = reaper.get_config_var_string("ui_scale")
    local ini = tonumber(ui) or 1
    local r = (hidpi == "on" and 2) or (hidpi == "off" and 1) or math.max(retina, px / ini)
    return ini, r * ini   -- measure (points), draw (pixels per unit)
  end
  px = math.floor(px * 100 + 0.5) / 100
  return px, px
end

local TR = {
  hwnd = nil, bm = nil, bm_w = 0, bm_h = 0, font = nil, font_px = 0,
  x = 0, y = 0, w = 0, h = 0, segs = {}, key = nil, linked = false,
  intercept = false, stamps = {}, drag = nil, menu_time = 0, last_find = 0,
  hover = nil, ratio = 1, measure = 1,
  shrink = 1, compact = false, hidden = false, variant = 1, ww = 0, wh = 0,
}
local edit = nil   -- the typed-value field while it's open

local function owned_by_reaper(h)
  local c, i = h, 0
  while c and i < 50 do
    if c == main_hwnd then return true end
    c = reaper.JS_Window_GetParent(c); i = i + 1
  end
  return false
end

local function find_transport()
  local n, list = reaper.JS_Window_ListFind(TRANSPORT_TITLE, true)
  if not n or n == 0 then return nil end
  local found
  for addr in ((list or "") .. ","):gmatch("(.-),") do
    local h = addr ~= "" and reaper.JS_Window_HandleFromAddress(addr)
    if h and owned_by_reaper(h) then
      if found then return nil end   -- more than one: don't guess
      found = h
    end
  end
  return found
end

-- The space next to the ruler (v3.4): REAPER's ruler header, its own window (a direct child of
-- REAPER's main window), between the main toolbar's buttons and the ruler. REAPER widens it as
-- the toolbar narrows, so it's always the empty part of that strip.
local function find_ruler_header()
  local arr = reaper.new_array({}, 1024)
  local n = reaper.JS_Window_ArrayAllChild(main_hwnd, arr) or 0
  local found
  for i, a in ipairs(arr.table()) do
    if i > n then break end
    local h = reaper.JS_Window_HandleFromAddress(a)
    if h and reaper.JS_Window_GetParent(h) == main_hwnd and reaper.JS_Window_GetClassName(h) == "REAPERRulerHeader" then
      if found then return nil end   -- more than one: don't guess
      found = h
    end
  end
  return found
end
local function find_host()
  if mode == "ruler" then return find_ruler_header() end
  return find_transport()
end

local INTERCEPTS = { "WM_LBUTTONDOWN", "WM_LBUTTONUP", "WM_LBUTTONDBLCLK", "WM_RBUTTONDOWN", "WM_RBUTTONUP", "WM_SETCURSOR" }
local CURSOR = {}
local function cursor_for(id)
  local cid = (id == "resize") and 32644
              or (id == "grip" and not T.locked) and (mode == "ruler" and 32644 or 32646) or 32512
  CURSOR[cid] = CURSOR[cid] or reaper.JS_Mouse_LoadCursor(cid)
  return CURSOR[cid]
end

-- (the windows it's drawn in: the host, and next to the ruler, the toolbar when it reaches
-- over it)
local function host_list()
  local l = { TR.hwnd }
  if TR.linked_ext and reaper.ValidatePtr(TR.linked_ext, "HWND*") then l[2] = TR.linked_ext end
  return l
end

local function intercepts(on)
  local want = (on and TR.hwnd) and host_list() or {}
  local cur = TR.icpt or {}
  local same = #want == #cur
  if same then for i, h in ipairs(want) do if cur[i] ~= h then same = false end end end
  if same then TR.intercept = #want > 0 return end
  for _, h in ipairs(cur) do
    if reaper.ValidatePtr(h, "HWND*") then
      for _, m in ipairs(INTERCEPTS) do reaper.JS_WindowMessage_Release(h, m) end
    end
  end
  TR.icpt = {}
  for _, h in ipairs(want) do
    for _, m in ipairs(INTERCEPTS) do reaper.JS_WindowMessage_Intercept(h, m, false) end
    TR.icpt[#TR.icpt + 1] = h
    for _, m in ipairs(INTERCEPTS) do
      local ok, _, t = reaper.JS_WindowMessage_Peek(h, m)
      TR.stamps[tostring(h) .. m] = ok and t or 0
    end
  end
  TR.intercept = #want > 0
end

-- (x, y in the host's coordinates; a part left of it is on the toolbar)
local function ext_point(x, y)
  local sx, sy = reaper.JS_Window_ClientToScreen(TR.hwnd, x, y)
  return reaper.JS_Window_ScreenToClient(TR.ext, sx, sy)
end

local function invalidate(x, y, w, h)
  if TR.hwnd and reaper.ValidatePtr(TR.hwnd, "HWND*") then
    reaper.JS_Window_InvalidateRect(TR.hwnd, x, y, x + w, y + h, false)
    if x < 0 and TR.ext and reaper.ValidatePtr(TR.ext, "HWND*") then
      local ex, ey = ext_point(x, y)
      reaper.JS_Window_InvalidateRect(TR.ext, ex, ey, ex - x, ey + h, false)
    end
  end
end

-- (next to the ruler, when the box reaches over the toolbar, each window shows a bitmap of
-- its own: its part, copied from the one the box is drawn in. A window shown only part of a
-- bitmap drew it at 1x on Retina screens; shown a whole one, it's sharp)
local function free_bm(k)
  if TR[k] then reaper.JS_LICE_DestroyBitmap(TR[k]); TR[k] = nil end
end

local function unlink_ext()
  if TR.linked_ext and TR.le and reaper.ValidatePtr(TR.linked_ext, "HWND*") then
    reaper.JS_Composite_Unlink(TR.linked_ext, TR.le)
    reaper.JS_Composite_Delay(TR.linked_ext, 0, 0, 0)
  end
  TR.linked_ext, TR.le = nil, nil
  free_bm("bme")
end

-- (the bitmap the host window shows: the box's own, or its part of it)
local function unlink_host()
  if TR.hwnd and TR.lh and reaper.ValidatePtr(TR.hwnd, "HWND*") then
    reaper.JS_Composite_Unlink(TR.hwnd, TR.lh)
  end
  TR.lh = nil
end

-- (a bitmap of this size, made again if it's another size)
local function sized_bm(k, w, h)
  local b = TR[k]
  if b and reaper.JS_LICE_GetWidth(b) == w and reaper.JS_LICE_GetHeight(b) == h then return b end
  free_bm(k)
  TR[k] = reaper.JS_LICE_CreateBitmap(true, w, h)
  return TR[k]
end

-- Copies the box's drawing into the two parts (when it's split)
local function present()
  if not TR.split or not TR.bm then return end
  local split = TR.split
  if TR.bmh then reaper.JS_LICE_Blit(TR.bmh, 0, 0, TR.bm, split, 0, TR.bm_w - split, TR.bm_h, 1, "COPY") end
  local c = TR.eclip
  if TR.bme and c then reaper.JS_LICE_Blit(TR.bme, 0, 0, TR.bm, c[1], c[2], c[3], c[4], 1, "COPY") end
end

-- Shows the bitmap: in the host; next to the ruler, the part that reaches left of the
-- space goes in the toolbar's window (each window shows its own part of the one bitmap)
-- (next to the ruler: the whole space and the whole toolbar are redrawn when it moves, so no
-- piece is left behind where it was; the toolbar's part was left over before, because the
-- old spot was worked out from where the toolbar is now)
local function invalidate_all()
  for _, h in ipairs({ TR.hwnd, TR.linked_ext, TR.ext }) do
    if h and reaper.ValidatePtr(h, "HWND*") then
      local _, w, hh = reaper.JS_Window_GetClientSize(h)
      reaper.JS_Window_InvalidateRect(h, 0, 0, w, hh, false)
    end
  end
end

-- (how soon it's redrawn after REAPER redraws the window: in the Transport a little later,
-- which is lighter; next to the ruler at once, so both parts change together)
local function delay(h)
  if mode == "ruler" then reaper.JS_Composite_Delay(h, 0, 0, 0)
  else reaper.JS_Composite_Delay(h, 0.03, 0.045, 2) end
end

local function link()
  delay(TR.hwnd)
  if TR.x < 0 and TR.ext and reaper.ValidatePtr(TR.ext, "HWND*") then
    local split = math.floor(-TR.x * TR.ratio + 0.5)
    TR.split = split
    local bh = sized_bm("bmh", TR.bm_w - split, TR.bm_h)
    if TR.lh ~= bh then unlink_host() end
    reaper.JS_Composite(TR.hwnd, 0, TR.y, TR.w + TR.x, TR.h, bh, 0, 0, TR.bm_w - split, TR.bm_h)
    TR.lh = bh
    if TR.linked_ext and TR.linked_ext ~= TR.ext then unlink_ext() end
    -- The toolbar's part, cut to the toolbar's own edges: the box is as tall as the ruler
    -- space, which is a little taller than the toolbar, and a picture reaching past a
    -- window's edge was drawn at 1x on Retina screens (pixelated as the box grew)
    local ex, ey = ext_point(TR.x, TR.y)
    local _, tw, th = reaper.JS_Window_GetClientSize(TR.ext)
    local x0, y0 = math.max(0, ex), math.max(0, ey)
    local x1, y1 = math.min(tw, ex - TR.x), math.min(th, ey + TR.h)
    if x1 > x0 and y1 > y0 then
      local r = TR.ratio
      local sx, sy = math.floor((x0 - ex) * r + 0.5), math.floor((y0 - ey) * r + 0.5)
      local sw, sh = math.floor((x1 - x0) * r + 0.5), math.floor((y1 - y0) * r + 0.5)
      TR.eclip = { sx, sy, sw, sh }
      local be = sized_bm("bme", sw, sh)
      if TR.le and TR.le ~= be and TR.linked_ext then reaper.JS_Composite_Unlink(TR.linked_ext, TR.le) end
      delay(TR.ext)
      reaper.JS_Composite(TR.ext, x0, y0, x1 - x0, y1 - y0, be, 0, 0, sw, sh)
      TR.linked_ext, TR.le = TR.ext, be
    else
      unlink_ext()
    end
    present()
  else
    TR.split = nil
    unlink_ext()
    if TR.lh ~= TR.bm then unlink_host() end
    free_bm("bmh")
    reaper.JS_Composite(TR.hwnd, TR.x, TR.y, TR.w, TR.h, TR.bm, 0, 0, TR.bm_w, TR.bm_h)
    TR.lh = TR.bm
  end
end


local function transport_teardown()
  intercepts(false)
  if TR.hwnd and TR.linked and reaper.ValidatePtr(TR.hwnd, "HWND*") then
    unlink_host()
    reaper.JS_Composite_Delay(TR.hwnd, 0, 0, 0)
    invalidate(TR.x, TR.y, TR.w, TR.h)
  end
  unlink_ext()
  TR.lh = nil
  free_bm("bmh")
  TR.split = nil
  TR.linked = false
  if TR.bm then reaper.JS_LICE_DestroyBitmap(TR.bm); TR.bm = nil end
  if TR.font then reaper.JS_LICE_DestroyFont(TR.font); TR.font = nil end
  TR.hwnd, TR.key, TR.drag, TR.hover = nil, nil, nil, nil
  TR.ext, TR.ext_min, TR.fit_key, TR.fit, TR.ext_sig = nil, 0, nil, nil, nil
  edit = nil
end

local function set_mode(m)
  if m == mode then return end
  if in_host() then transport_teardown() end
  mode = m
  T = load_T(T_key())   -- (the Transport and the ruler space keep their own position and size)
  TR.last_find, TR.hidden, TR.variant = 0, false, 1
  reaper.SetExtState(EXT_SECTION, MODE_KEY, m, true)
end

-- ----- nudge value text (shared with the typed field) ---------------
local function nudge_text(val, unit)
  if unit == 3 then return string.format("%.6f", val)
  elseif unit == 1 then
    local mins = math.floor(val / 60)
    local secs = math.floor(val % 60)
    local ms   = math.floor((val - math.floor(val)) * 1000)
    return string.format("%d:%02d.%03d", mins, secs, ms)
  elseif unit == 0 or unit == 2 or unit == 4 or unit == 6 then return string.format("%.0f", val)
  end
  return string.format("%.3f", val)
end

local function parse_nudge(str, unit)
  str = (str or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if unit == 1 then
    local m, s, ms = str:match("^(%d+):(%d%d)%.(%d%d%d)$")
    if m then return tonumber(m) * 60 + tonumber(s) + tonumber(ms) / 1000 end
    local m2, s2 = str:match("^(%d+):(%d+%.?%d*)$")
    if m2 then return tonumber(m2) * 60 + tonumber(s2) end
    return tonumber(str)
  end
  local v = tonumber(str)
  if not v then return nil end
  if unit == 0 or unit == 2 or unit == 4 or unit == 6 then v = math.floor(v + 0.5) end
  return v
end

local function set_nudge_val(v)
  nudge_val = v
  reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL, tostring(nudge_val), true)
  last_valid_seconds_str = nil
end

-- ----- menus (REAPER's own, at the mouse) ---------------------------
local function menu_string(menu)
  local out = {}
  for _, e in ipairs(menu) do
    if e.separator then out[#out + 1] = ""
    elseif e.sub then
      out[#out + 1] = ">" .. e.title .. "|" .. menu_string(e.sub) .. "<"
    else
      out[#out + 1] = (e.grayed and "#" or "") .. (e.checked and "!" or "") .. e.title
    end
  end
  return table.concat(out, "|")
end

local function menu_pick(menu, idx, i)
  i = i or 1
  for _, e in ipairs(menu) do
    if e.sub then
      i = menu_pick(e.sub, idx, i)
      if i < 0 then return i end
    elseif not e.separator then
      if i == idx then if e.run and not e.grayed then e.run() end return -1 end
      i = i + 1
    end
  end
  return i
end

local function show_menu(menu)
  intercepts(false)
  local focus = reaper.JS_Window_GetFocus and reaper.JS_Window_GetFocus()
  local title = "ReaTooled Grid and Nudge menu"
  local x, y = reaper.GetMousePosition()
  if IS_MAC then gfx.ext_retina = 1 end
  gfx.init(title, 0, 0, 0, x, y)
  if IS_MAC and tonumber(gfx.ext_retina) and gfx.ext_retina >= 1 and gfx.ext_retina ~= retina then
    retina = gfx.ext_retina
    reaper.SetExtState(EXT_SECTION, "grid_nudge_retina", tostring(retina), true)
  end
  local w = reaper.JS_Window_Find and reaper.JS_Window_Find(title, true)
  if w and reaper.JS_Window_SetOpacity then reaper.JS_Window_SetOpacity(w, "ALPHA", 0) end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  local choice = gfx.showmenu(menu_string(menu))
  gfx.quit()
  if focus and reaper.JS_Window_SetFocus then reaper.JS_Window_SetFocus(focus) end
  if choice and choice > 0 then menu_pick(menu, choice) end
  TR.menu_time = reaper.time_precise()
  TR.key = nil   -- redraw
end

local function grid_menu()
  local m = {}
  for i, name in ipairs(grid_options) do
    m[#m + 1] = { title = name, checked = (i == grid_index), run = function()
      if name == "Frame" then reaper.Main_OnCommand(CMD_GRID_FRAME, 0)
      elseif name == "Measure" then reaper.Main_OnCommand(CMD_GRID_MEASURE, 0)
      else
        local val = grid_div_values[i]
        if val and val > 0 then reaper.GetSetProjectGrid(0, true, val, 0, 0) end
      end
      grid_poll_frame = 0
      update_grid_index_from_reaper()
    end }
  end
  show_menu(m)
end

local function nudge_menu()
  if not modifier_multipliers[selected_modifier] then selected_modifier = "none" end
  local m = {}
  local presets = get_current_presets()
  if presets then
    for _, p in ipairs(presets) do
      local expected = p.value * modifier_multipliers[selected_modifier]
      m[#m + 1] = { title = p.label, checked = math.abs(expected - nudge_val) < 0.00001,
                    run = function() set_nudge_val(expected) end }
    end
    m[#m + 1] = { separator = true }
  end
  if unit_index == 3 then
    for _, mod in ipairs({ "dotted", "triplet" }) do
      local on = (selected_modifier == mod)
      m[#m + 1] = { title = mod:gsub("^%l", string.upper), checked = on, run = function()
        local prev_mul = modifier_multipliers[selected_modifier]
        selected_modifier = on and "none" or mod
        local new_mul = modifier_multipliers[selected_modifier]
        reaper.SetExtState(EXT_SECTION, "nudge_modifier", selected_modifier, true)
        set_nudge_val((nudge_val / prev_mul) * new_mul)
      end }
    end
    m[#m + 1] = { separator = true }
  end
  for i, name in ipairs(units) do
    local idx = i - 1
    m[#m + 1] = { title = name, checked = (idx == unit_index), run = function()
      if idx ~= 3 and selected_modifier ~= "none" then
        selected_modifier = "none"
        reaper.SetExtState(EXT_SECTION, "nudge_modifier", selected_modifier, true)
      end
      local v = ConvertNudgeValue(unit_index, idx, nudge_val)
      unit_index = idx
      reaper.SetExtState(EXT_SECTION, EXT_KEY_UNIT, tostring(unit_index), true)
      set_nudge_val(v)
    end }
  end
  show_menu(m)
end

local close_requested = false

-- The selection display (start/end/length) isn't a window of its own: REAPER paints it
-- into the Transport. Its edges are found the way Gridbox finds empty space: asking
-- REAPER what's under points across the Transport (GetThingFromPoint says "trans.sel"
-- there). Measured when the Transport's size changes; otherwise its left edge is only
-- checked (two lookups) twice a second. (Re-measuring all of it every 2 s, as before,
-- asked REAPER about thousands of points at once: everything in REAPER stuttered.)
local sel_cache = { key = nil, t = 0, l = nil, r = nil, y = nil }

-- The Transport's layout, beyond its size: where the time display sits and the theme in use
-- (one lookup). Plus, for the first seconds after starting, a step every 2 seconds: REAPER may
-- still be laying the Transport out (a fresh install, the theme loading), and a measurement
-- taken then would otherwise stay until the window is resized.
local LAYOUT_T0 = reaper.time_precise()
local function layout_key()
  local st = reaper.JS_Window_FindChildByID(TR.hwnd, 1010)
  local pos = "-"
  if st then
    local _, l, t, r = reaper.JS_Window_GetRect(st)
    pos = tostring(reaper.JS_Window_ScreenToClient(TR.hwnd, l, t)) .. ":" .. tostring(reaper.JS_Window_ScreenToClient(TR.hwnd, r, t))
  end
  local since = reaper.time_precise() - LAYOUT_T0
  local settling = since < 12 and tostring(math.floor(since / 2)) or "s"
  return pos .. "|" .. (reaper.GetLastColorThemeFile and reaper.GetLastColorThemeFile() or "") .. "|" .. settling
end

local function sel_at(cx, cy)
  local sx, sy = reaper.JS_Window_ClientToScreen(TR.hwnd, cx, cy)
  local _, thing = reaper.GetThingFromPoint(sx, sy)
  return thing ~= nil and thing:sub(1, 9) == "trans.sel"
end

-- Full measure: a coarse pass across the Transport (middle height first, then above and
-- below if it isn't there), then its two edges point by point
local function selection_scan(ww, wh)
  local step = math.max(2, math.floor(8 * (TR.measure or 1)))
  for _, fy in ipairs({ 0.5, 0.25, 0.75 }) do
    local cy = math.floor(wh * fy)
    local first, last
    for cx = 0, ww - 1, step do
      if sel_at(cx, cy) then
        first = first or cx
        last = cx
      end
    end
    if first then
      local l = first
      while l > 0 and l > first - step and sel_at(l - 1, cy) do l = l - 1 end
      local r = last
      while r < ww - 1 and r < last + step and sel_at(r + 1, cy) do r = r + 1 end
      return l, r + 1, cy
    end
  end
  return nil
end

-- While the Transport is resized: the left edge is followed from where it was (a few
-- lookups each frame), so the strip moves with it as if it were part of the Transport
local function selection_follow(ww)
  local l0, y = sel_cache.l, sel_cache.y
  if not l0 or not y then return nil end
  local function edge(x) return x >= 0 and x < ww and sel_at(x, y) and (x == 0 or not sel_at(x - 1, y)) end
  for d = 0, math.min(ww, 400) do
    if edge(l0 + d) then return l0 + d end
    if d > 0 and edge(l0 - d) then return l0 - d end
  end
  return nil
end

local function selection_edges()
  local _, ww, wh = reaper.JS_Window_GetClientSize(TR.hwnd)
  local key = ww .. "x" .. wh .. "|" .. layout_key()
  local now = reaper.time_precise()
  -- (no selection display at this size: don't look again until the size changes, or for
  -- 5 seconds; before, the whole Transport was searched again on every frame)
  if sel_cache.none and sel_cache.key == key and now - sel_cache.t < 5 then return nil end
  if sel_cache.l and sel_cache.key == key then
    if now - sel_cache.t < 0.5 then return sel_cache.l, sel_cache.r end
    sel_cache.t = now
    local l, y = sel_cache.l, sel_cache.y
    if y and sel_at(l, y) and (l == 0 or not sel_at(l - 1, y)) then return sel_cache.l, sel_cache.r end
    -- (it moved without the Transport changing size, e.g. a theme or layout change)
    local nl = selection_follow(ww)
    if nl then
      sel_cache.r = sel_cache.r and (sel_cache.r + (nl - sel_cache.l)) or nil
      sel_cache.l = nl
      return sel_cache.l, sel_cache.r
    end
  end
  if sel_cache.l and sel_cache.key ~= key then
    local l = selection_follow(ww)
    if l then
      sel_cache.r = sel_cache.r and (sel_cache.r + (l - sel_cache.l)) or nil
      sel_cache.l, sel_cache.key = l, key
      return sel_cache.l, sel_cache.r
    end
  end
  sel_cache.key, sel_cache.t = key, now
  sel_cache.l, sel_cache.r, sel_cache.y = selection_scan(ww, wh)
  sel_cache.none = (sel_cache.l == nil)
  return sel_cache.l, sel_cache.r
end

local function anchor_base(a)
  local _, ww = reaper.JS_Window_GetClientSize(TR.hwnd)
  if mode == "ruler" then return T.anchor == 1 and 0 or ww end   -- (next to the ruler: a side)
  if a == 1 then return 0 end
  if a == 2 then return ww end
  if a == 5 or a == 6 then
    local l, r = selection_edges()
    -- (a few points clear of it: its drawn box starts a little left of where it reacts)
    if l then return a == 5 and (l - math.floor(4 * (TR.measure or 1) + 0.5)) or math.min(ww, r) end
    a = (a == 5) and 3 or 4   -- (no selection display in this layout: the time display's edge)
  end
  local st = reaper.JS_Window_FindChildByID(TR.hwnd, 1010)
  if not st then return a == 3 and 0 or ww end
  local _, l, t, r, b = reaper.JS_Window_GetRect(st)
  local cl = reaper.JS_Window_ScreenToClient(TR.hwnd, l, t)
  local cr = reaper.JS_Window_ScreenToClient(TR.hwnd, r, b)
  if a == 3 then return math.max(0, cl) end
  return math.min(ww, cr)
end

local function settings_menu()
  local in_ruler = mode == "ruler"
  local function attach(a)
    return function()
      T.anchor = a
      -- moves next to that edge (then drag the grip to fine-tune; it stays that far from it)
      local gap = math.floor(6 * TR.measure + 0.5)
      if a == 1 or a == 4 then T.offset = gap else T.offset = -(TR.w + gap) end
      save_T()
    end
  end
  local function vert(v) return function() RV = v; reaper.SetExtState(EXT_SECTION, RH_V_KEY, v, true); TR.fit_key = nil end end
  local function dpi(v) return function() hidpi = v; reaper.SetExtState(EXT_SECTION, "grid_nudge_hidpi", v, true) end end
  local function rows(n) return function() T.rows = n; save_T(); TR.fit_key = nil end end
  local position, layout_items
  if in_ruler then
    position = {
      { title = "Top",    checked = RV == "top",    run = vert("top") },
      { title = "Middle", checked = RV == "middle", run = vert("middle") },
      { title = "Bottom", checked = RV == "bottom", run = vert("bottom") },
      { separator = true },
      { title = "Lock size", checked = T.locked, run = function() T.locked = not T.locked; save_T() end },
    }
    layout_items = {
      { title = "Automatic (two rows when there's room)", checked = T.rows ~= 2 and T.rows ~= 4, run = rows(0) },
      { title = "Two rows (Grid above Nudge)", checked = T.rows == 2, run = rows(2) },
      { title = "One column",                  checked = T.rows == 4, run = rows(4) },
      { separator = true },
      { title = "Reset size (fit the space)", grayed = T.size == nil,
        run = function() T.size = nil; save_T(); TR.fit_key = nil end },
    }
  else
    position = {   -- (in the order they usually sit, left to right)
      { title = "Left edge of the Transport",    checked = T.anchor == 1, run = attach(1) },
      { title = "Left of the time display",      checked = T.anchor == 3, run = attach(3) },
      { title = "Right of the time display",     checked = T.anchor == 4, run = attach(4) },
      { title = "Left of the selection display", checked = T.anchor == 5, run = attach(5) },
      { title = "Right edge of the Transport",   checked = T.anchor == 2, run = attach(2) },
      { separator = true },
      { title = "Lock position", checked = T.locked, run = function() T.locked = not T.locked; save_T() end },
      { title = "Reset position", run = function() T.anchor = 2; T.offset = nil; save_T() end },
    }
    layout_items = {
      { title = "Two rows (Grid above Nudge)", checked = T.rows == 2, run = rows(2) },
      { title = "One row",                     checked = T.rows == 1, run = rows(1) },
      { separator = true },
      { title = "Reset size (fit the Transport)", grayed = T.size == nil, run = function() T.size = nil; save_T() end },
    }
  end
  layout_items[#layout_items + 1] = { separator = true }
  layout_items[#layout_items + 1] = { title = "HiDPI (Retina)", sub = {
    { title = "Automatic" .. (IS_MAC and (" (now " .. (retina >= 2 and "on" or "off") .. ")") or ""),
      checked = hidpi == "auto", run = dpi("auto") },
    { title = "Always on",  checked = hidpi == "on",  run = dpi("on") },
    { title = "Always off", checked = hidpi == "off", run = dpi("off") },
  } }
  show_menu({
    { title = "Show Grid and Nudge in:", grayed = true },
    { title = "The Transport",               checked = mode == "transport", run = function() set_mode("transport") end },
    { title = "The space next to the ruler", checked = in_ruler,            run = function() set_mode("ruler") end },
    { title = "A window (dockable)",                                          run = function() set_mode("window") end },
    { separator = true },
    { title = in_ruler and "Height in the space" or "Position", sub = position },
    { title = "Layout", sub = layout_items },
    { separator = true },
    { title = "Close Grid and Nudge", run = function() close_requested = true end },
  })
end

-- ----- layout and drawing --------------------------------------------
local function text_w(s)
  gfx.setfont(1, "Arial", TR.font_px)
  return (gfx.measurestr(s))
end

-- (next to the ruler: its side, plus however far the grip has moved it from there; it keeps
-- to that side whatever its size)
local function ruler_x(ww)
  local inset, off = TR.inset or 0, T.offset or 0
  local x = (T.anchor == 1) and (inset + off) or (ww - TR.w - inset + off)
  return math.max(0, math.min(ww - TR.w, x))
end
-- (next to the ruler: the box's height in the space, from the grip menu)
local function ruler_y(wh)
  local inset = TR.inset or 0
  local y = (RV == "top" and inset) or (RV == "middle" and math.floor((wh - TR.h) / 2)) or (wh - TR.h - inset)
  return math.max(0, math.min(wh - TR.h, y))
end

local layout_sig = nil
local function layout()
  local _, ww, wh = reaper.JS_Window_GetClientSize(TR.hwnd)
  local measure, draw = transport_scale()
  -- (the sizes only change with these: skip the text measuring otherwise)
  local sig = table.concat({ mode, ww, wh, measure, draw, T.rows, tostring(T.size), grid_index,
                             nudge_text(nudge_val, unit_index), TR.shrink, tostring(TR.compact), tostring(TR.stack),
                             tostring(TR.rows_used), RV }, "|")
  TR.ww, TR.wh = ww, wh
  if sig == layout_sig and TR.font then
    if mode == "ruler" then return end   -- (next to the ruler, nothing else moves it)
    local bx = anchor_base(T.anchor) + (T.offset or 0)
    TR.x = math.max(0, math.min(ww - TR.w, bx))
    if mode == "ruler" then TR.x, TR.y = ruler_x(ww), ruler_y(wh) end
    return
  end
  layout_sig = sig
  TR.measure, TR.ratio = measure, draw / measure
  local rows = T.rows == 1 and 1 or 2
  -- row height (points/pixels of the Transport): the saved size, or the full height
  local fit = math.floor(wh / rows)
  local row_h = T.size and math.floor(T.size * measure + 0.5) or fit
  TR.inset = math.floor(3 * measure + 0.5)
  if mode == "ruler" then
    -- (next to the ruler: two rows, or one column (Grid, division, Nudge, value); the
    -- rows as tall as the space allows, up to about the Transport's, made smaller
    -- (TR.shrink) until it's as wide as it should be: fit_box tries the sizes)
    rows = TR.rows_used or 4
    TR.stack = rows == 4
    fit = math.max(1, math.floor((wh - TR.inset * 2) / rows))
    row_h = math.min(fit, math.floor(18 * measure + 0.5))
    row_h = math.max(math.floor(6 * measure + 0.5), math.floor(row_h * TR.shrink + 0.5))
  else
    TR.stack = false
    row_h = math.max(math.floor(9 * measure + 0.5), math.min(row_h, fit))
    row_h = math.max(math.floor(9 * measure + 0.5), math.floor(row_h * TR.shrink + 0.5))   -- (made smaller to fit)
  end
  local rb = math.floor(row_h * TR.ratio + 0.5)   -- row height in bitmap pixels
  local font_px = math.max(6, math.floor(rb * 0.8 + 0.5))   -- (about the Transport's own text size)
  if font_px ~= TR.font_px or not TR.font then
    TR.font_px = font_px
    if TR.font then reaper.JS_LICE_DestroyFont(TR.font) end
    TR.font = reaper.JS_LICE_CreateFont()
    local gdi = reaper.JS_GDI_CreateFont(font_px, 0, 0, 0, 0, 0, "Arial")
    reaper.JS_LICE_SetFontFromGDI(TR.font, gdi, "")
    reaper.JS_GDI_DeleteObject(gdi)
  end
  TR.row_b = rb
  -- segments, in bitmap pixels: { id, x, y, w, h }
  local pad = math.floor(rb * 0.3 + 0.5)
  local arrow = math.floor(rb * 0.55 + 0.5)
  local grip = math.floor(rb * 0.45 + 0.5)
  local GL, NL = TR.compact and "G" or "Grid", TR.compact and "N" or "Nudge"   -- (compact: short labels)
  local label_w = math.max(text_w(GL), text_w(NL)) + pad * 2
  local div_w = math.max(text_w("Measure"), text_w(grid_options[grid_index] or "1/16")) + pad
  local val_w = math.max(text_w("000000000"), text_w(nudge_text(nudge_val, unit_index))) + pad
  local segs = {}
  local function add(id, x, y, w, h) segs[#segs + 1] = { id = id, x = x, y = y, w = w, h = h } end
  local bm_w
  if TR.stack then
    -- one column, for the narrow space next to the ruler: Grid / division / Nudge / value,
    -- with a thin grip down the left
    local sp = math.max(1, math.floor(rb * 0.15 + 0.5))
    local sgrip = math.max(2, math.floor(rb * 0.3 + 0.5))
    local sarrow = math.floor(rb * 0.45 + 0.5)
    local fw = math.max(text_w(GL) + sp * 2, text_w(NL) + sp * 2,
                        text_w(grid_options[grid_index] or "1/16") + sp * 2 + sarrow,
                        text_w(nudge_text(nudge_val, unit_index)) + sp * 2 + sarrow)
    add("grip", 0, 0, sgrip, rb * 4)
    local x0 = sgrip
    add("grid", x0, 0, fw, rb)
    add("div", x0, rb, fw - sarrow, rb); add("divarrow", x0 + fw - sarrow, rb, sarrow, rb)
    add("sep", x0, rb * 2 - 1, fw, 1)
    add("nudge", x0, rb * 2, fw, rb)
    add("value", x0, rb * 3, fw - sarrow, rb); add("arrow", x0 + fw - sarrow, rb * 3, sarrow, rb)
    bm_w = x0 + fw + sp
  elseif rows == 1 then
    local x = 0
    local function nxt(id, w) add(id, x, 0, w, rb); x = x + w end
    nxt("grip", grip); nxt("grid", text_w(GL) + pad * 2)
    nxt("div", text_w(grid_options[grid_index] or "1/16") + pad); nxt("divarrow", arrow)
    nxt("sep", math.floor(pad * 0.8)); nxt("nudge", text_w(NL) + pad * 2)
    nxt("value", val_w); nxt("arrow", arrow + math.floor(pad / 2))
    bm_w = x
  else
    -- like the window: Grid above Nudge, labels and fields lined up
    add("grip", 0, 0, grip, rb * 2)
    local x0 = grip
    add("grid", x0, 0, label_w, rb)
    add("nudge", x0, rb, label_w, rb)
    local x1 = x0 + label_w
    local field_w = math.max(div_w, val_w)
    add("div", x1, 0, field_w, rb); add("divarrow", x1 + field_w, 0, arrow, rb)
    add("value", x1, rb, field_w, rb); add("arrow", x1 + field_w, rb, arrow, rb)
    add("sep", x0, rb - 1, label_w + field_w + arrow, 1)
    bm_w = x1 + field_w + arrow + math.floor(pad / 2)
  end
  -- The background fills the Transport's full height; the rows sit in the middle
  local content_h = rb * rows
  if mode == "ruler" then
    -- The background fills the whole space (and reaches left over the toolbar when the
    -- box is wider than the space); the controls keep to its right, by the ruler, at the
    -- height chosen in the grip menu
    local m = TR.inset
    local cw = math.ceil(bm_w / TR.ratio - 0.001)
    local ch = math.ceil(content_h / TR.ratio - 0.001)
    TR.cw, TR.ch = cw, ch
    local L = math.min(0, ww - cw - m)   -- (no margin on the ruler side: right against it)
    TR.x, TR.y, TR.w, TR.h = L, 0, ww - L, wh
    TR.bm_w, TR.bm_h = math.floor(TR.w * TR.ratio + 0.5), math.floor(TR.h * TR.ratio + 0.5)
    local top = (RV == "top" and m) or (RV == "middle" and math.floor((wh - ch) / 2)) or (wh - ch - m)
    top = math.max(0, math.min(wh - ch, top))
    local dx = math.floor((ww - cw - L) * TR.ratio + 0.5)
    local dy = math.floor(top * TR.ratio + 0.5)
    for _, sg in ipairs(segs) do sg.x, sg.y = sg.x + dx, sg.y + dy end
    TR.segs = segs
    return
  end
  local host_h = wh
  if mode == "ruler" then
    host_h = math.min(wh, math.ceil(content_h / TR.ratio - 0.001) + 2 * math.floor(2 * measure + 0.5))
  end
  local bm_h = math.floor(host_h * TR.ratio + 0.5)
  local top = math.max(0, math.floor((bm_h - content_h) / 2))
  for _, sg in ipairs(segs) do sg.y = sg.y + top end
  TR.segs = segs
  -- The bitmap must be exactly (size on screen) x (pixel density): any other size is
  -- stretched when it's shown, which is what made it look pixelated (3.1.1-3.1.3)
  TR.w = math.ceil(bm_w / TR.ratio - 0.001)
  TR.h = host_h
  bm_w = math.floor(TR.w * TR.ratio + 0.5)
  bm_h = math.floor(TR.h * TR.ratio + 0.5)
  TR.bm_w, TR.bm_h = bm_w, bm_h
  -- position
  if not T.offset and mode ~= "ruler" then
    T.offset = -(TR.w + (mode == "ruler" and TR.inset or math.floor(8 * measure + 0.5))); T.anchor = 2
  end
  local bx = anchor_base(T.anchor) + (T.offset or 0)
  TR.x = math.max(0, math.min(ww - TR.w, bx))
  TR.y = mode == "ruler" and ruler_y(wh) or 0
  if mode == "ruler" then TR.x = ruler_x(ww) end
end

local function seg_at(cx, cy)
  if cx < TR.x or cy < TR.y or cx >= TR.x + TR.w or cy >= TR.y + TR.h then return nil end
  local px, py = (cx - TR.x) * TR.ratio, (cy - TR.y) * TR.ratio
  -- the right edge resizes (unless locked)
  if not T.locked and mode ~= "ruler" and (cx - TR.x) >= TR.w - math.floor(6 * TR.measure + 0.5) then return "resize" end
  for _, s in ipairs(TR.segs) do
    if s.id ~= "sep" and px >= s.x and px < s.x + s.w and py >= s.y and py < s.y + s.h then return s.id end
  end
  return "grip"
end

local function seg_of(id) for _, s in ipairs(TR.segs) do if s.id == id then return s end end end

local function draw()
  local bm, w, h = TR.bm, TR.bm_w, TR.bm_h
  local FR, TX = reaper.JS_LICE_FillRect, reaper.JS_LICE_DrawText
  gfx.setfont(1, "Arial", TR.font_px)
  reaper.JS_LICE_Clear(bm, IS_WIN and 0 or (COL.bg & 0x00FFFFFF))
  FR(bm, 0, 0, w, h, COL.bg, 1, "COPY")
  local _, th = gfx.measurestr("Ag")
  local grid_on = reaper.GetToggleCommandState(CMD_GRID_TOGGLE) == 1
  local inset = math.max(1, math.floor(TR.row_b * 0.08))
  local function box(s, col) FR(bm, s.x + 1, s.y + inset, s.w - 2, s.h - inset * 2, col, 1, "COPY") end
  local function text(str, s, col, centered)
    reaper.JS_LICE_SetFontColor(TR.font, col)
    local tw = text_w(str)
    local x = centered and (s.x + math.floor((s.w - tw) / 2)) or (s.x + math.floor(TR.row_b * 0.18))
    local y = s.y + math.floor((s.h - th) / 2)
    TX(bm, TR.font, str, #str, x, y, s.x + s.w, s.y + s.h)
  end
  local function tri(s, col)
    local cx, cy, z = s.x + s.w / 2, s.y + s.h / 2, math.max(3, math.floor(TR.row_b * 0.14))
    reaper.JS_LICE_FillTriangle(bm, math.floor(cx - z), math.floor(cy - z / 2), math.floor(cx + z), math.floor(cy - z / 2),
      math.floor(cx), math.floor(cy + z / 2 + 1), col, 1, "COPY")
  end
  local hov = TR.hover
  local function hovered(id)
    return hov == id or (hov == "div" and id == "divarrow") or (hov == "divarrow" and id == "div")
        or (hov == "value" and id == "arrow" and false)
  end
  for _, s in ipairs(TR.segs) do
    if s.id == "grip" then
      if not T.locked then
        local dot = math.max(1, math.floor(TR.row_b * 0.08))
        local gx = s.x + math.floor((s.w - dot * 3) / 2)
        local n = (T.rows == 1 and not TR.stack) and 3 or 5
        local gy0 = math.floor(s.y + s.h / 2 - dot * (n - 0.5))
        for row = 0, n - 1 do
          local gy = gy0 + row * dot * 2
          FR(bm, gx, gy, dot, dot, COL.grip, 1, "COPY")
          FR(bm, gx + dot * 2, gy, dot, dot, COL.grip, 1, "COPY")
        end
      end
    elseif s.id == "grid" then
      if grid_on then box(s, COL.on_bg) elseif hovered("grid") then box(s, COL.hover) end
      text(TR.compact and "G" or "Grid", s, grid_on and COL.accent or COL.text, true)
    elseif s.id == "div" then
      if hovered("div") then box(s, COL.hover) end
      text(grid_options[grid_index] or "1/16", s, COL.accent)
    elseif s.id == "divarrow" then
      if hovered("divarrow") then box(s, COL.hover) end
      tri(s, COL.text)
    elseif s.id == "sep" then
      if T.rows == 1 and not TR.stack then
        FR(bm, s.x + math.floor(s.w / 2), s.y + math.floor(s.h * 0.2), math.max(1, math.floor(TR.ratio)), s.h - math.floor(s.h * 0.4), COL.sep, 1, "COPY")
      else
        FR(bm, s.x, s.y, s.w, math.max(1, math.floor(TR.ratio)), COL.sep, 1, "COPY")
      end
    elseif s.id == "nudge" then
      if hovered("nudge") then box(s, COL.hover) end
      text(TR.compact and "N" or "Nudge", s, COL.white, true)
    elseif s.id == "value" then
      box(s, hovered("value") and COL.hover or COL.field)
      if not edit then text(nudge_text(nudge_val, unit_index), s, COL.accent) end
    elseif s.id == "arrow" then
      if hovered("arrow") then box(s, COL.hover) end
      tri(s, COL.text)
    end
  end
  if hov == "resize" then FR(bm, w - math.max(2, math.floor(TR.ratio * 2)), 0, math.max(2, math.floor(TR.ratio * 2)), h, COL.grip, 1, "COPY") end
end

-- ----- the typed value -----------------------------------------------
local function start_edit()
  local s = seg_of("value")
  if not s then return end
  local cx = TR.x + math.floor(s.x / TR.ratio)
  local cy = TR.y + math.floor(s.y / TR.ratio)
  local sx, sy = reaper.JS_Window_ClientToScreen(TR.hwnd, cx, cy)
  edit = { sx = sx, sy = sy, w = math.floor(s.w / TR.ratio), h = math.floor(s.h / TR.ratio),
           text = nudge_text(nudge_val, unit_index), first = true, frames = 0 }
  TR.key = nil
end

local function end_edit(commit_str)
  if commit_str then
    local v = parse_nudge(commit_str, unit_index)
    if v then set_nudge_val(v) end
  end
  edit = nil
  TR.key = nil
  -- the arrange view gets the keyboard back (as after the window's field)
  if reaper.JS_Window_FindChildByID then
    local hwnd = reaper.JS_Window_FindChildByID(main_hwnd, REAPER_MAIN_EDIT_HWND_ID)
    if hwnd and reaper.JS_Window_IsVisible(hwnd) then reaper.JS_Window_SetFocus(hwnd) end
  end
end

local function draw_edit()
  if not context_is_valid() then create_context() end
  local x, y = edit.sx, edit.sy
  if reaper.ImGui_PointConvertNative then x, y = reaper.ImGui_PointConvertNative(ctx, x, y, false) end
  reaper.ImGui_SetNextWindowPos(ctx, x, y)
  local flags = reaper.ImGui_WindowFlags_NoDecoration() | reaper.ImGui_WindowFlags_NoDocking()
              | reaper.ImGui_WindowFlags_NoSavedSettings() | reaper.ImGui_WindowFlags_AlwaysAutoResize()
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 0, 0)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), IM(P.field))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),  IM(P.field))
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),     IM(P.accent))
  local visible = reaper.ImGui_Begin(ctx, "##ReaTooled grid nudge value", nil, flags)
  local result, done = nil, false
  if visible then
    if edit.first then reaper.ImGui_SetKeyboardFocusHere(ctx) end
    reaper.ImGui_SetNextItemWidth(ctx, math.max(60, edit.w))
    local tf = reaper.ImGui_InputTextFlags_EnterReturnsTrue() | reaper.ImGui_InputTextFlags_AutoSelectAll()
    local r, s = reaper.ImGui_InputText(ctx, "##v", edit.text, tf)
    edit.text = s
    edit.frames = edit.frames + 1
    if r then result, done = s, true
    elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then done = true
    elseif edit.frames > 3 and not reaper.ImGui_IsWindowFocused(ctx) then done = true   -- clicked elsewhere
    end
    edit.first = false
  end
  reaper.ImGui_End(ctx)
  reaper.ImGui_PopStyleColor(ctx, 3)
  reaper.ImGui_PopStyleVar(ctx)
  if done then end_edit(result) end
end

-- ----- room in the Transport --------------------------------------------
-- What REAPER has under each point of the Transport (GetThingFromPoint), read across
-- the box's rows: the transport buttons and the time display are protected (never
-- covered); the selection display, BPM and play rate may be covered; the rest is
-- free. Measured again when the Transport's size or layout changes: coarsely while
-- it's changing, finely once it has settled.
-- (REAPER's names for the transport buttons; themes move them, never rename them)
local PROTECTED = { rew = true, fwd = true, rec = true, play = true, ["repeat"] = true,
                    stop = true, pause = true }
local function is_protected(thing)
  local name = thing and thing:match("^trans%.([%a_]+)")
  return name ~= nil and PROTECTED[name] == true
end

local room = { key = nil, spans = {}, fine = false, changed = 0 }
local function protected_spans()
  local ww, wh = TR.ww, TR.wh
  local centred = reaper.GetToggleCommandState(40533)
  local key = table.concat({ ww, wh, centred, layout_key() }, "|")
  local now = reaper.time_precise()
  if key ~= room.key then room.key, room.fine, room.changed = key, false, now
  elseif room.fine or now - room.changed < 0.25 then return room.spans end
  local fine = room.key == key and now - room.changed >= 0.25
  local step = math.max(2, math.floor(6 * TR.measure))
  local ys = { math.floor(wh * 0.3), math.floor(wh * 0.7) }   -- (the box is centred, about full height)
  local function protected_at(cx)
    for _, cy in ipairs(ys) do
      local sx, sy = reaper.JS_Window_ClientToScreen(TR.hwnd, cx, cy)
      local _, thing = reaper.GetThingFromPoint(sx, sy)
      if is_protected(thing) then return true end
    end
    return false
  end
  -- a coarse pass; then (once the size has settled) each edge point by point, instead of
  -- asking about every other point across the whole Transport
  local hit = {}
  for cx = 0, ww - 1, step do if protected_at(cx) then hit[cx] = true end end
  local spans, cur = {}, nil
  for cx = 0, ww - 1, step do
    if hit[cx] then
      if cur and cx <= cur[2] then cur[2] = cx + step
      else cur = { cx, cx + step, first = cx, last = cx }; spans[#spans + 1] = cur end
      cur.last = cx
    end
  end
  if fine then
    for _, sp in ipairs(spans) do
      local l = sp.first
      while l > 0 and l > sp.first - step and protected_at(l - 1) do l = l - 1 end
      local r = sp.last
      while r < ww - 1 and r < sp.last + step and protected_at(r + 1) do r = r + 1 end
      sp[1], sp[2] = l, r + 1
    end
  end
  -- the time display: its own window
  local st = reaper.JS_Window_FindChildByID(TR.hwnd, 1010)
  if st and reaper.JS_Window_IsVisible(st) then
    local _, l, t, r, b = reaper.JS_Window_GetRect(st)
    local cl = reaper.JS_Window_ScreenToClient(TR.hwnd, l, t)
    local cr = reaper.JS_Window_ScreenToClient(TR.hwnd, r, b)
    spans[#spans + 1] = { math.min(cl, cr), math.max(cl, cr) }
  end
  -- a little clearance around each, coarse ones a bit more
  local m = math.floor((fine and 3 or 6) * TR.measure + 0.5)
  for _, sp in ipairs(spans) do sp[1], sp[2] = sp[1] - m, sp[2] + m end
  table.sort(spans, function(a, b) return a[1] < b[1] end)
  room.spans, room.fine = spans, fine
  return spans
end

-- Where the box (w wide, plus 'extra' room) can go: its own spot if that's clear,
-- else the nearest clear space anywhere in the Transport; nil if there's none
local function find_spot(want, w, extra)
  local spans, ww = protected_spans(), TR.ww
  local need = w + (extra or 0)
  local function clear(x)
    if x < 0 or x + w > ww then return false end
    for _, sp in ipairs(spans) do
      if x < sp[2] + (extra or 0) and x + w > sp[1] - (extra or 0) then return false end
    end
    return true
  end
  want = math.max(0, math.min(ww - w, want))
  if clear(want) then return want end
  -- the clear stretches between protected ones
  local best, bestd, left = nil, math.huge, 0
  local function try(l, r)
    if r - l >= need then
      local x = math.max(l + (extra or 0), math.min(r - w - (extra or 0), want))
      x = math.max(l, math.min(r - w, x))
      if clear(x) and math.abs(x - want) < bestd then best, bestd = x, math.abs(x - want) end
    end
  end
  for _, sp in ipairs(spans) do
    try(left, sp[1]); left = math.max(left, sp[2])
  end
  try(left, ww)
  return best
end

-- The largest form of the box that has room (variants in order), and where
local RULER_VARIANTS = {   -- { one column, "G"/"N" labels, size }
  { false, false, 1 }, { true, false, 1 }, { true, false, 0.85 }, { true, true, 0.85 },
  { true, true, 0.7 }, { true, true, 0.6 },
}
local VARIANTS = { { 1, false } }   -- (3.3 also tried smaller versions; that looked unsteady)
local function fit_box()
  if mode == "ruler" then
    -- (the space is empty, so nothing to avoid.) Its width: the one you've dragged it to,
    -- else the space's. The largest size that fits that width, as two rows or one column
    -- (Automatic: whichever is bigger); else the window shows. Worked out again only when
    -- something it depends on changes
    local measure = transport_scale()
    local m = math.floor(3 * measure + 0.5)
    local _, ww, wh = reaper.JS_Window_GetClientSize(TR.hwnd)
    TR.ww, TR.wh = ww, wh
    local W_max = ww - (TR.ext_min or 0) - m
    local W = math.min(T.size or (ww - m), W_max)
    TR.W, TR.W_max = W, W_max
    local key = table.concat({ ww, wh, W, W_max, T.rows, measure, grid_index, nudge_text(nudge_val, unit_index),
                               RV, hidpi, retina }, "|")
    if key ~= TR.fit_key then
      TR.fit_key, TR.fit = key, nil
      local orders = (T.rows == 2 and { 2 }) or (T.rows == 4 and { 4 }) or { 2, 4 }
      for _, r in ipairs(orders) do
        for sh = 100, 30, -5 do
          TR.rows_used, TR.shrink, TR.compact = r, sh / 100, (r == 4 and sh < 60)
          layout()
          if TR.cw <= W and TR.ch <= wh then
            if not TR.fit or TR.row_b > TR.fit[4] then TR.fit = { r, sh / 100, TR.compact, TR.row_b } end
            break
          end
        end
      end
    end
    if not TR.fit then TR.hidden = true return false end
    TR.rows_used, TR.shrink, TR.compact = TR.fit[1], TR.fit[2], TR.fit[3]
    layout()
    TR.variant, TR.hidden = 1, false
    -- (DEV: "ReaTooled_DEV Grid and Nudge sharpness report.lua" turns this on)
    if reaper.GetExtState(EXT_SECTION, "grid_nudge_debug") == "1" then
      local m2, d2 = transport_scale()
      local line = string.format("ruler: retina %s hidpi %s measure %s draw %s ratio %s | space %dx%d | box x%d y%d %dx%d pt, bitmap %dx%d px | rows %d shrink %.2f font %d px row %d px | toolbar part (px x,y,w,h) %s",
        tostring(retina), hidpi, tostring(m2), tostring(d2), tostring(TR.ratio), ww, wh, TR.x, TR.y, TR.w, TR.h,
        TR.bm_w, TR.bm_h, TR.rows_used or -1, TR.shrink or -1, TR.font_px or -1, TR.row_b or -1, (TR.eclip and TR.split) and table.concat(TR.eclip, ",") or "none")
      if line ~= TR.debug_line then TR.debug_line = line; reaper.ShowConsoleMsg(line .. "\n") end
    end
    return true
  end
  TR.stack = false
  local cur = TR.variant or 1
  for i, v in ipairs(VARIANTS) do
    TR.shrink, TR.compact = v[1], v[2]
    layout()
    local want = TR.x
    -- (growing back takes a few points more than it needs, so it doesn't flicker)
    local extra = (i < cur) and math.floor(6 * TR.measure + 0.5) or 0
    local x = find_spot(want, TR.w, extra)
    if x then
      TR.x, TR.variant, TR.hidden = x, i, false
      return true
    end
  end
  TR.variant, TR.hidden = #VARIANTS + 1, true
  return false
end

-- ----- clicks ----------------------------------------------------------
local function click(id, right)
  if reaper.time_precise() < TR.menu_time + 0.15 then return end   -- (the click that closed a menu)
  if id == "grid" then reaper.Main_OnCommand(CMD_GRID_TOGGLE, 0)
  elseif id == "div" or id == "divarrow" then grid_menu()
  elseif id == "nudge" or id == "arrow" then nudge_menu()
  elseif id == "value" then if right then nudge_menu() else start_edit() end
  elseif id == "resize" then if right then settings_menu() end
  else settings_menu() end
  TR.key = nil
end

local function peek(m)
  local hit = false
  for _, h in ipairs(TR.icpt or {}) do
    local ok, _, t = reaper.JS_WindowMessage_Peek(h, m)
    local k = tostring(h) .. m
    if ok and t ~= TR.stamps[k] then TR.stamps[k] = t; hit = true end
  end
  return hit
end

-- One pass. False if the Transport can't be used (hidden, not found): the
-- window shows instead until it's back.
local function transport_frame()
  local now = reaper.time_precise()
  if not TR.hwnd or not reaper.ValidatePtr(TR.hwnd, "HWND*") then
    if TR.hwnd then transport_teardown() end
    if now - TR.last_find < 0.5 then return false end
    TR.last_find = now
    TR.hwnd = find_host()
    if not TR.hwnd then return false end
    check_retina(TR.hwnd)
    TR.key, TR.linked = nil, false
  end
  if not reaper.JS_Window_IsVisible(TR.hwnd) then
    intercepts(false)
    return false
  end

  if palette_changed() then load_col(); TR.key = nil end
  if mode == "ruler" then
    -- (the window just left of the space, if it's a toolbar: the box can reach over it)
    local _, l, t, r, b = reaper.JS_Window_GetRect(TR.hwnd)
    local h = reaper.JS_Window_FromPoint(l - 2, math.floor((t + b) / 2))
    local title = h and h ~= main_hwnd and h ~= TR.hwnd and (reaper.JS_Window_GetTitle(h) or ""):lower() or ""
    if title:find("toolbar", 1, true) then
      local _, el, et = reaper.JS_Window_GetRect(h)
      TR.ext, TR.ext_min = h, math.min(0, (reaper.JS_Window_ScreenToClient(TR.hwnd, el, et)))
    else
      TR.ext, TR.ext_min = nil, 0
    end
  end
  local old_x, old_y, old_w, old_h = TR.x, TR.y, TR.w, TR.h
  local was_hidden = TR.hidden
  if TR.drag and mode ~= "ruler" then layout() else fit_box() end   -- (while you drag it, it goes where you put it)
  if TR.hidden then
    -- no room anywhere: out of the way until there is
    if not was_hidden then
      intercepts(false)
      if TR.bm and TR.linked then
        unlink_host()
        invalidate(old_x, old_y, old_w, old_h)
      end
      if mode == "ruler" then invalidate_all() end
      unlink_ext()
      TR.ext_sig = nil
      TR.linked, TR.hover = false, nil
    end
    -- (next to the ruler: the window shows instead until there's room, so it never just vanishes)
    return mode ~= "ruler"
  end

  -- mouse
  local pm = PROF.on and reaper.time_precise()
  local mx, my = reaper.GetMousePosition()
  local cx, cy = reaper.JS_Window_ScreenToClient(TR.hwnd, mx, my)
  local under = reaper.JS_Window_FromPoint(mx, my)
  local over = under == TR.hwnd or (TR.linked_ext ~= nil and under == TR.linked_ext)
  local id = over and seg_at(cx, cy) or nil
  if TR.drag then
    if reaper.JS_Mouse_GetState(1) == 1 then
      local dx = cx - TR.drag.cx
      if math.abs(dx) > 2 then TR.drag.moved = true end
      if TR.drag.moved then
        if TR.drag.ruler then
          -- (next to the ruler: wider to the left, narrower to the right; it stays by the ruler)
          T.size = math.max(16, math.min(TR.W_max or TR.drag.W, TR.drag.W - dx))
        elseif TR.drag.resize then
          -- the row height follows the width (it keeps its proportions)
          local w = math.max(10, TR.drag.w + dx)
          T.size = math.max(9, TR.drag.size * w / TR.drag.w)
        else
          T.offset = TR.drag.off + dx
        end
        if mode == "ruler" then fit_box() else layout() end
      end
    else
      local moved, was_resize = TR.drag.moved, TR.drag.resize and not TR.drag.ruler
      TR.drag = nil
      for _, m in ipairs(INTERCEPTS) do peek(m) end   -- (this release is handled here, not again below)
      if moved then save_T() elseif not was_resize then click("grip") end
    end
  end
  intercepts((id ~= nil) or TR.drag ~= nil)
  if TR.intercept and not TR.drag then
    local ldown = peek("WM_LBUTTONDOWN")
    peek("WM_LBUTTONDBLCLK")
    local lup = peek("WM_LBUTTONUP")
    peek("WM_RBUTTONDOWN")
    local rup = peek("WM_RBUTTONUP")
    if ldown and id == "grip" and not T.locked and mode == "ruler" then
      TR.drag = { cx = cx, ruler = true, W = TR.W or TR.cw }   -- (next to the ruler: the grip sizes it)
    elseif ldown and id == "grip" and not T.locked then
      TR.drag = { cx = cx, off = T.offset or 0 }
    elseif ldown and id == "resize" then
      TR.drag = { cx = cx, resize = true, w = TR.w, size = TR.row_b / TR.ratio / TR.measure }
    elseif lup and id then
      click(id, false)
    elseif rup and id then
      click(id, true)
    end
  end
  if not TR.hwnd or not in_host() then return true end   -- (a menu choice moved it: next frame)
  if id ~= TR.hover then TR.hover = id end
  if TR.intercept and reaper.JS_Mouse_SetCursor then   -- (REAPER's own cursor is held back while over it)
    reaper.JS_Mouse_SetCursor(cursor_for(TR.drag and (TR.drag.resize and "resize" or "grip") or id))
  end
  if pm then PROF.add("mouse, clicks and cursor", reaper.time_precise() - pm) end

  -- bitmap and position
  local size_changed = TR.bm_w ~= (TR.bm and reaper.JS_LICE_GetWidth(TR.bm) or -1)
                    or TR.bm_h ~= (TR.bm and reaper.JS_LICE_GetHeight(TR.bm) or -1)
  if not TR.bm or size_changed then
    if TR.bm then
      if TR.linked then unlink_host() end
      unlink_ext()
      reaper.JS_LICE_DestroyBitmap(TR.bm)
    end
    TR.bm = reaper.JS_LICE_CreateBitmap(true, TR.bm_w, TR.bm_h)
    TR.linked, TR.key = false, nil
  end
  -- (where the toolbar is compared with where it was when the box was last placed on it: it
  -- changes width when the panel does, and its part of the box has to move with it. Compared
  -- within one frame, as before, it never looked changed, so that part was left behind)
  local new_ext = TR.ext and table.concat({ tostring(TR.ext), ext_point(0, 0) }, ",") or ""
  if not TR.linked or TR.x ~= old_x or TR.y ~= old_y or TR.w ~= old_w or TR.h ~= old_h or new_ext ~= (TR.ext_sig or "") then
    if TR.linked then
      if mode == "ruler" then invalidate_all() else invalidate(old_x, old_y, old_w, old_h) end
    end
    link()
    TR.ext_sig = new_ext
    if mode == "ruler" then invalidate_all() end
    TR.linked, TR.key = true, nil
    if PROF.on then PROF.add("re-attach to Transport (moved/resized)", 0) end
  end
  local pk = PROF.on and reaper.time_precise()
  local key = table.concat({ reaper.GetToggleCommandState(CMD_GRID_TOGGLE), grid_index, nudge_val, unit_index,
                             selected_modifier, tostring(TR.hover), T.locked and 1 or 0, edit and 1 or 0,
                             TR.bm_w, TR.bm_h }, "|")
  if pk then PROF.add("change check (toggle states)", reaper.time_precise() - pk) end
  if key ~= TR.key then
    TR.key = key
    draw()
    present()
    invalidate(TR.x, TR.y, TR.w, TR.h)
  end
  return true
end

transport_teardown_fwd = transport_teardown

-- (timing report: these names are wrapped so each call is measured while it's on)
transport_frame  = PROF.wrap("Transport: all of it", transport_frame)
find_transport   = PROF.wrap("find the Transport", find_transport)
palette_changed  = PROF.wrap("theme colour check", palette_changed)
fit_box          = PROF.wrap("fit to free space (incl. layout)", fit_box)
layout           = PROF.wrap("layout", layout)
protected_spans  = PROF.wrap("find transport buttons/time display", protected_spans)
selection_edges  = PROF.wrap("find selection display", selection_edges)
selection_scan   = PROF.wrap("full search for selection display", selection_scan)
draw             = PROF.wrap("redraw the strip", draw)
draw_edit        = PROF.wrap("typed value field", draw_edit)
DrawFrame        = PROF.wrap("Window: draw (ImGui)", DrawFrame)
update_grid_index_from_reaper = PROF.wrap("read project grid", update_grid_index_from_reaper)
window_menu_can_transport = CAN_TRANSPORT

-- ===================================================================
--  MAIN LOOP
-- ===================================================================
local frame_failures = 0

local function Main()
  -- Dead context (sleep/wake, monitor change, GPU reset, GC)?
  -- Replace it BEFORE any ImGui call touches it. Window position and
  -- dock state are restored from ReaImGui's ini for the same name.
  if not in_host() and not context_is_valid() then   -- (Transport mode uses it only for the typed value)
    create_context()
  end

  grid_poll_frame = grid_poll_frame + 1
  if grid_poll_frame >= 10 then
    grid_poll_frame = 0
    update_grid_index_from_reaper()
  end

  if close_requested then return end   -- (Close, from the Transport menu; atexit cleans up)

  if in_host() then
    local ok, handled = pcall(transport_frame)
    if not ok then
      reaper.ShowConsoleMsg("ReaTooled Grid & Nudge (Transport): " .. tostring(handled) .. "\n")
      transport_teardown()
      set_mode("window")
    elseif handled then
      if edit then
        local ok2, err = pcall(draw_edit)
        if not ok2 then edit = nil; ctx = nil
          reaper.ShowConsoleMsg("ReaTooled Grid & Nudge (value field): " .. tostring(err) .. "\n") end
      end
      run_pending_actions()
      reaper.defer(Main)
      return
    end
    -- (Transport hidden or not found: the window shows until it's back)
  end

  palette_changed()   -- (theme colours, checked once a second)
  -- (in Transport mode the context may have gone unused long enough to be released)
  if not context_is_valid() then create_context() end
  local ok, result = pcall(DrawFrame)
  if window_menu_choice then
    local m = window_menu_choice
    window_menu_choice = nil
    set_mode(m)
  end

  if ok then
    frame_failures = 0
    run_pending_actions()          -- REAPER state changes, safely after End
    if not result then return end  -- window closed; atexit resets toggle
  else
    -- Frame failed: drop queued actions, discard the context, and let
    -- the next cycle build a fresh one instead of killing the script.
    pending_actions = {}
    frame_failures  = frame_failures + 1
    ctx = nil
    if frame_failures >= MAX_FRAME_FAILURES then
      reaper.ShowConsoleMsg("ReaTooled Grid & Nudge: stopping after repeated ImGui errors:\n"
        .. tostring(result) .. "\n")
      return
    end
  end

  reaper.defer(Main)
end

do   -- (timing report: the whole frame, and the once-a-second report)
  local inner = Main
  Main = function()
    PROF.tick(mode)
    if not PROF.on then return inner() end
    local t0 = reaper.time_precise()
    inner()
    PROF.add("whole frame", reaper.time_precise() - t0)
    PROF.frames = PROF.frames + 1
  end
end

reaper.defer(Main)
