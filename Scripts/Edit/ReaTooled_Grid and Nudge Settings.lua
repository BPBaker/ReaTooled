-- @description ReaTooled - Grid & Nudge Settings (Dockable GUI)
-- @version 3.2.4
-- @date 2026.10.31
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Dockable Grid & Nudge controller for REAPER
--   • One-row, mouse-first UI for toggling Grid, selecting Grid mode/division, and editing Nudge amount/unit.
--   • Grid selector supports Frame rate, 1 Measure, and musical divisions; writes via GetSetProjectGrid.
--   • Nudge value edit field with unit-aware formatting (ms, seconds mm:ss.mmm, measures.beats, samples, frames, etc).
--   • Unit presets menu (with dotted/triplet modifiers for measures/beats) and persistent extstate storage.
--   • Focus-friendly popups and small-screen friendly layout; safe on older ReaImGui builds.
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

  local _, sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if not sr or sr == 0 then sr = 44100 end
  local fps = reaper.TimeMap_curFrameRate(0)

  local _, grid_beats = reaper.GetSetProjectGrid(0, false)
  local grid_secs     = reaper.TimeMap2_beatsToTime(0, grid_beats)

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
    local base_presets = {
      { label = "1 bar",      value = 1.0     },
      { label = "1/2 note",   value = 0.2     },
      { label = "1/4 note",   value = 0.1     },
      { label = "1/8 note",   value = 0.05    },
      { label = "1/16 note",  value = 0.025   },
      { label = "1/32 note",  value = 0.0125  },
      { label = "1/64 note",  value = 0.00625 },
    }
    local mul = (selected_modifier == "dotted")  and 1.5
             or (selected_modifier == "triplet") and (2/3) or 1.0
    local t = {}
    for _, p in ipairs(base_presets) do
      t[#t+1] = { label = p.label, value = p.value * mul }
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
      local expected_val = preset.value * modifier_multipliers[selected_modifier]
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
        nudge_val         = (nudge_val / prev_mul) * new_mul
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
local MODE_KEY = "grid_nudge_mode"        -- "window" (dockable, default) | "transport"
local TR_KEY   = "grid_nudge_transport"   -- "anchor,offset,locked,rows,size"

local OS_NAME = reaper.GetOS()
local IS_MAC  = OS_NAME:match("OS") ~= nil
local IS_WIN  = OS_NAME:match("Win") ~= nil
local CAN_TRANSPORT = (reaper.JS_Composite and reaper.JS_LICE_CreateBitmap and reaper.JS_WindowMessage_Intercept
                       and reaper.JS_GDI_CreateFont and reaper.JS_Window_FromPoint) and true or false

local mode = reaper.GetExtState(EXT_SECTION, MODE_KEY)
if mode ~= "transport" or not CAN_TRANSPORT then mode = "window" end

-- Anchors: 1 = Transport's left edge, 2 = its right edge,
--          3 = left of the time display, 4 = right of the time display,
--          5 = left of the selection display
-- rows: 1 = one row, 2 = Grid above Nudge (like the window). size: row height in
-- points (nil = fit the Transport)
local T = { anchor = 2, offset = nil, locked = false, rows = 2, size = nil }
do
  local s = reaper.GetExtState(EXT_SECTION, TR_KEY)
  local a, o, l, r, z = s:match("^(%d),([^,]*),(%d),?(%d?),?([^,]*)$")
  if a then
    T.anchor = tonumber(a) or 2; T.offset = tonumber(o); T.locked = (l == "1")
    T.rows = tonumber(r) or 2; T.size = tonumber(z)
    if T.anchor == 6 then T.anchor = 2; T.offset = nil end   -- (3.2.2's right-of-selection, withdrawn)
  end
end
local function save_T()
  reaper.SetExtState(EXT_SECTION, TR_KEY,
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

local INTERCEPTS = { "WM_LBUTTONDOWN", "WM_LBUTTONUP", "WM_LBUTTONDBLCLK", "WM_RBUTTONDOWN", "WM_RBUTTONUP", "WM_SETCURSOR" }
local CURSOR = {}
local function cursor_for(id)
  local cid = (id == "resize") and 32644 or (id == "grip" and not T.locked) and 32646 or 32512
  CURSOR[cid] = CURSOR[cid] or reaper.JS_Mouse_LoadCursor(cid)
  return CURSOR[cid]
end

local function intercepts(on)
  if not TR.hwnd then TR.intercept = false return end
  if on and not TR.intercept then
    for _, m in ipairs(INTERCEPTS) do reaper.JS_WindowMessage_Intercept(TR.hwnd, m, false) end
    TR.intercept = true
    for _, m in ipairs(INTERCEPTS) do
      local ok, _, t = reaper.JS_WindowMessage_Peek(TR.hwnd, m)
      TR.stamps[m] = ok and t or 0
    end
  elseif not on and TR.intercept then
    for _, m in ipairs(INTERCEPTS) do reaper.JS_WindowMessage_Release(TR.hwnd, m) end
    TR.intercept = false
  end
end

local function invalidate(x, y, w, h)
  if TR.hwnd and reaper.ValidatePtr(TR.hwnd, "HWND*") then
    reaper.JS_Window_InvalidateRect(TR.hwnd, x, y, x + w, y + h, false)
  end
end

local function transport_teardown()
  intercepts(false)
  if TR.hwnd and TR.bm and TR.linked and reaper.ValidatePtr(TR.hwnd, "HWND*") then
    reaper.JS_Composite_Unlink(TR.hwnd, TR.bm)
    reaper.JS_Composite_Delay(TR.hwnd, 0, 0, 0)
    invalidate(TR.x, TR.y, TR.w, TR.h)
  end
  TR.linked = false
  if TR.bm then reaper.JS_LICE_DestroyBitmap(TR.bm); TR.bm = nil end
  if TR.font then reaper.JS_LICE_DestroyFont(TR.font); TR.font = nil end
  TR.hwnd, TR.key, TR.drag, TR.hover = nil, nil, nil, nil
  edit = nil
end

local function set_mode(m)
  if m == mode then return end
  if mode == "transport" then transport_teardown() end
  mode = m
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
-- there). Measured again when the Transport's size changes, or every 2 s.
local sel_cache = { key = nil, t = 0, l = nil, r = nil, y = nil }

local function sel_at(cx, cy)
  local sx, sy = reaper.JS_Window_ClientToScreen(TR.hwnd, cx, cy)
  local _, thing = reaper.GetThingFromPoint(sx, sy)
  return thing ~= nil and thing:sub(1, 9) == "trans.sel"
end

-- Full measure: every few points across the Transport, at three heights
local function selection_scan(ww, wh)
  local l, r, y
  local step = math.max(1, math.floor(2 * (TR.measure or 1)))
  for _, fy in ipairs({ 0.5, 0.25, 0.75 }) do
    local cy = math.floor(wh * fy)
    for cx = 0, ww - 1, step do
      if sel_at(cx, cy) then
        if not l or cx < l then l, y = cx, cy end
        r = r and math.max(r, cx + step) or (cx + step)
      end
    end
  end
  -- exact left edge (to the point)
  if l then
    local x = l
    while x > 0 and sel_at(x - 1, y) do x = x - 1 end
    l = x
  end
  return l, r, y
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
  local key = ww .. "x" .. wh
  local now = reaper.time_precise()
  if sel_cache.l and sel_cache.key == key and now - sel_cache.t < 2 then return sel_cache.l, sel_cache.r end
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
  return sel_cache.l, sel_cache.r
end

local function anchor_base(a)
  local _, ww = reaper.JS_Window_GetClientSize(TR.hwnd)
  if a == 1 then return 0 end
  if a == 2 then return ww end
  if a == 5 or a == 6 then
    local l, r = selection_edges()
    if l then return a == 5 and l or math.min(ww, r) end
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
  local function attach(a)
    return function()
      T.anchor = a
      -- moves next to that edge (then drag the grip to fine-tune; it stays that far from it)
      local gap = math.floor(6 * TR.measure + 0.5)
      if a == 1 or a == 4 or a == 6 then T.offset = gap else T.offset = -(TR.w + gap) end
      save_T()
    end
  end
  show_menu({
    { title = "Show as a window (dockable)", run = function() set_mode("window") end },
    { separator = true },
    { title = "Lock position", checked = T.locked, run = function() T.locked = not T.locked; save_T() end },
    { title = "Attach to", sub = {
      { title = "Left edge of the Transport",   checked = T.anchor == 1, run = attach(1) },
      { title = "Right edge of the Transport",  checked = T.anchor == 2, run = attach(2) },
      { title = "Left of the time display",     checked = T.anchor == 3, run = attach(3) },
      { title = "Right of the time display",    checked = T.anchor == 4, run = attach(4) },
      { title = "Left of the selection display",  checked = T.anchor == 5, run = attach(5) },
    } },
    { title = "Grid above Nudge (two rows)", checked = T.rows == 2, run = function() T.rows = 2; save_T() end },
    { title = "Grid and Nudge in one row",   checked = T.rows == 1, run = function() T.rows = 1; save_T() end },
    { separator = true },
    { title = "HiDPI (Retina)", sub = {
      { title = "Automatic" .. (IS_MAC and (" (now " .. (retina >= 2 and "on" or "off") .. ")") or ""),
        checked = hidpi == "auto", run = function() hidpi = "auto"; reaper.SetExtState(EXT_SECTION, "grid_nudge_hidpi", hidpi, true) end },
      { title = "Always on",  checked = hidpi == "on",  run = function() hidpi = "on";  reaper.SetExtState(EXT_SECTION, "grid_nudge_hidpi", hidpi, true) end },
      { title = "Always off", checked = hidpi == "off", run = function() hidpi = "off"; reaper.SetExtState(EXT_SECTION, "grid_nudge_hidpi", hidpi, true) end },
    } },
    { separator = true },
    { title = "Reset position", run = function() T.anchor = 2; T.offset = nil; save_T() end },
    { title = "Reset size (fit the Transport)", grayed = T.size == nil, run = function() T.size = nil; save_T() end },
    { separator = true },
    { title = "Close Grid and Nudge", run = function() close_requested = true end },
  })
end

-- ----- layout and drawing --------------------------------------------
local function text_w(s)
  gfx.setfont(1, "Arial", TR.font_px)
  return (gfx.measurestr(s))
end

local layout_sig = nil
local function layout()
  local _, ww, wh = reaper.JS_Window_GetClientSize(TR.hwnd)
  local measure, draw = transport_scale()
  -- (the sizes only change with these: skip the text measuring otherwise)
  local sig = table.concat({ ww, wh, measure, draw, T.rows, tostring(T.size), grid_index,
                             nudge_text(nudge_val, unit_index) }, "|")
  if sig == layout_sig and TR.font then
    local bx = anchor_base(T.anchor) + (T.offset or 0)
    TR.x = math.max(0, math.min(ww - TR.w, bx))
    return
  end
  layout_sig = sig
  TR.measure, TR.ratio = measure, draw / measure
  local rows = T.rows == 1 and 1 or 2
  -- row height (points/pixels of the Transport): the saved size, or the full height
  local fit = math.floor(wh / rows)
  local row_h = T.size and math.floor(T.size * measure + 0.5) or fit
  row_h = math.max(math.floor(9 * measure + 0.5), math.min(row_h, fit))
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
  local label_w = math.max(text_w("Grid"), text_w("Nudge")) + pad * 2
  local div_w = math.max(text_w("Measure"), text_w(grid_options[grid_index] or "1/16")) + pad
  local val_w = math.max(text_w("000000000"), text_w(nudge_text(nudge_val, unit_index))) + pad
  local segs = {}
  local function add(id, x, y, w, h) segs[#segs + 1] = { id = id, x = x, y = y, w = w, h = h } end
  local bm_w
  if rows == 1 then
    local x = 0
    local function nxt(id, w) add(id, x, 0, w, rb); x = x + w end
    nxt("grip", grip); nxt("grid", text_w("Grid") + pad * 2)
    nxt("div", text_w(grid_options[grid_index] or "1/16") + pad); nxt("divarrow", arrow)
    nxt("sep", math.floor(pad * 0.8)); nxt("nudge", text_w("Nudge") + pad * 2)
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
  local bm_h = rb * rows
  TR.segs = segs
  -- The bitmap must be exactly (size on screen) x (pixel density): any other size is
  -- stretched when it's shown, which is what made it look pixelated (3.1.1-3.1.3)
  TR.w = math.ceil(bm_w / TR.ratio - 0.001)
  TR.h = math.ceil(bm_h / TR.ratio - 0.001)
  bm_w = math.floor(TR.w * TR.ratio + 0.5)
  bm_h = math.floor(TR.h * TR.ratio + 0.5)
  TR.bm_w, TR.bm_h = bm_w, bm_h
  -- position
  if not T.offset then T.offset = -(TR.w + math.floor(8 * measure + 0.5)); T.anchor = 2 end
  local bx = anchor_base(T.anchor) + T.offset
  TR.x = math.max(0, math.min(ww - TR.w, bx))
  TR.y = math.max(0, math.floor((wh - TR.h) / 2))
end

local function seg_at(cx, cy)
  if cx < TR.x or cy < TR.y or cx >= TR.x + TR.w or cy >= TR.y + TR.h then return nil end
  local px, py = (cx - TR.x) * TR.ratio, (cy - TR.y) * TR.ratio
  -- the right edge resizes (unless locked)
  if not T.locked and (cx - TR.x) >= TR.w - math.floor(6 * TR.measure + 0.5) then return "resize" end
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
        local n = T.rows == 1 and 3 or 5
        local gy0 = math.floor(s.y + s.h / 2 - dot * (n - 0.5))
        for row = 0, n - 1 do
          local gy = gy0 + row * dot * 2
          FR(bm, gx, gy, dot, dot, COL.grip, 1, "COPY")
          FR(bm, gx + dot * 2, gy, dot, dot, COL.grip, 1, "COPY")
        end
      end
    elseif s.id == "grid" then
      if grid_on then box(s, COL.on_bg) elseif hovered("grid") then box(s, COL.hover) end
      text("Grid", s, grid_on and COL.accent or COL.text, true)
    elseif s.id == "div" then
      if hovered("div") then box(s, COL.hover) end
      text(grid_options[grid_index] or "1/16", s, COL.accent)
    elseif s.id == "divarrow" then
      if hovered("divarrow") then box(s, COL.hover) end
      tri(s, COL.text)
    elseif s.id == "sep" then
      if T.rows == 1 then
        FR(bm, s.x + math.floor(s.w / 2), math.floor(h * 0.2), math.max(1, math.floor(TR.ratio)), h - math.floor(h * 0.4), COL.sep, 1, "COPY")
      else
        FR(bm, s.x, s.y, s.w, math.max(1, math.floor(TR.ratio)), COL.sep, 1, "COPY")
      end
    elseif s.id == "nudge" then
      if hovered("nudge") then box(s, COL.hover) end
      text("Nudge", s, COL.white, true)
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
  local ok, _, t = reaper.JS_WindowMessage_Peek(TR.hwnd, m)
  if ok and t ~= TR.stamps[m] then TR.stamps[m] = t; return true end
  return false
end

-- One pass. False if the Transport can't be used (hidden, not found): the
-- window shows instead until it's back.
local function transport_frame()
  local now = reaper.time_precise()
  if not TR.hwnd or not reaper.ValidatePtr(TR.hwnd, "HWND*") then
    if TR.hwnd then transport_teardown() end
    if now - TR.last_find < 0.5 then return false end
    TR.last_find = now
    TR.hwnd = find_transport()
    if not TR.hwnd then return false end
    check_retina(TR.hwnd)
    TR.key, TR.linked = nil, false
  end
  if not reaper.JS_Window_IsVisible(TR.hwnd) then
    intercepts(false)
    return false
  end

  if palette_changed() then load_col(); TR.key = nil end
  local old_x, old_y, old_w, old_h = TR.x, TR.y, TR.w, TR.h
  layout()

  -- mouse
  local mx, my = reaper.GetMousePosition()
  local cx, cy = reaper.JS_Window_ScreenToClient(TR.hwnd, mx, my)
  local over = reaper.JS_Window_FromPoint(mx, my) == TR.hwnd
  local id = over and seg_at(cx, cy) or nil
  if TR.drag then
    if reaper.JS_Mouse_GetState(1) == 1 then
      local dx = cx - TR.drag.cx
      if math.abs(dx) > 2 then TR.drag.moved = true end
      if TR.drag.moved then
        if TR.drag.resize then
          -- the row height follows the width (it keeps its proportions)
          local w = math.max(10, TR.drag.w + dx)
          T.size = math.max(9, TR.drag.size * w / TR.drag.w)
        else
          T.offset = TR.drag.off + dx
        end
        layout()
      end
    else
      local moved, was_resize = TR.drag.moved, TR.drag.resize
      TR.drag = nil
      for _, m in ipairs(INTERCEPTS) do   -- (this release is handled here, not again below)
        local ok, _, t = reaper.JS_WindowMessage_Peek(TR.hwnd, m)
        if ok then TR.stamps[m] = t end
      end
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
    if ldown and id == "grip" and not T.locked then
      TR.drag = { cx = cx, off = T.offset or 0 }
    elseif ldown and id == "resize" then
      TR.drag = { cx = cx, resize = true, w = TR.w, size = TR.row_b / TR.ratio / TR.measure }
    elseif lup and id then
      click(id, false)
    elseif rup and id then
      click(id, true)
    end
  end
  if id ~= TR.hover then TR.hover = id end
  if TR.intercept and reaper.JS_Mouse_SetCursor then   -- (REAPER's own cursor is held back while over it)
    reaper.JS_Mouse_SetCursor(cursor_for(TR.drag and (TR.drag.resize and "resize" or "grip") or id))
  end

  -- bitmap and position
  local size_changed = TR.bm_w ~= (TR.bm and reaper.JS_LICE_GetWidth(TR.bm) or -1)
                    or TR.bm_h ~= (TR.bm and reaper.JS_LICE_GetHeight(TR.bm) or -1)
  if not TR.bm or size_changed then
    if TR.bm then
      if TR.linked then reaper.JS_Composite_Unlink(TR.hwnd, TR.bm) end
      reaper.JS_LICE_DestroyBitmap(TR.bm)
    end
    TR.bm = reaper.JS_LICE_CreateBitmap(true, TR.bm_w, TR.bm_h)
    TR.linked, TR.key = false, nil
  end
  if not TR.linked or TR.x ~= old_x or TR.y ~= old_y or TR.w ~= old_w or TR.h ~= old_h then
    if TR.linked then invalidate(old_x, old_y, old_w, old_h) end
    reaper.JS_Composite_Delay(TR.hwnd, 0.03, 0.045, 2)
    reaper.JS_Composite(TR.hwnd, TR.x, TR.y, TR.w, TR.h, TR.bm, 0, 0, TR.bm_w, TR.bm_h)
    TR.linked, TR.key = true, nil
  end
  local key = table.concat({ reaper.GetToggleCommandState(CMD_GRID_TOGGLE), grid_index, nudge_val, unit_index,
                             selected_modifier, tostring(TR.hover), T.locked and 1 or 0, edit and 1 or 0,
                             TR.bm_w, TR.bm_h }, "|")
  if key ~= TR.key then
    TR.key = key
    draw()
    invalidate(TR.x, TR.y, TR.w, TR.h)
  end
  return true
end

transport_teardown_fwd = transport_teardown
window_menu_can_transport = CAN_TRANSPORT

-- ===================================================================
--  MAIN LOOP
-- ===================================================================
local frame_failures = 0

local function Main()
  -- Dead context (sleep/wake, monitor change, GPU reset, GC)?
  -- Replace it BEFORE any ImGui call touches it. Window position and
  -- dock state are restored from ReaImGui's ini for the same name.
  if mode ~= "transport" and not context_is_valid() then   -- (Transport mode uses it only for the typed value)
    create_context()
  end

  grid_poll_frame = grid_poll_frame + 1
  if grid_poll_frame >= 10 then
    grid_poll_frame = 0
    update_grid_index_from_reaper()
  end

  if close_requested then return end   -- (Close, from the Transport menu; atexit cleans up)

  if mode == "transport" then
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
  local ok, result = pcall(DrawFrame)
  if window_menu_choice == "transport" then
    window_menu_choice = nil
    set_mode("transport")
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

reaper.defer(Main)
