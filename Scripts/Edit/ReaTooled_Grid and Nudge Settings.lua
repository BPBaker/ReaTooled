-- @description ReaTooled - Grid & Nudge Settings (Dockable GUI)
-- @version 2.1.7
-- @date 2026.10.20
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

reaper.atexit(function()
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
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x1ABC98FF)
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
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x1ABC98FF)
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
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x1ABC98FF)
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
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x1ABC98FF)
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
local function DrawFrame()
  if not is_docked then
    reaper.ImGui_SetNextWindowSize(ctx, 360, 0, reaper.ImGui_Cond_Once())
  end

  local color_count = 0
  local function push_color(col, val)
    reaper.ImGui_PushStyleColor(ctx, col, val)
    color_count = color_count + 1
  end

  push_color(reaper.ImGui_Col_WindowBg(),      0x333333FF)
  push_color(reaper.ImGui_Col_Button(),        0x333333FF)
  push_color(reaper.ImGui_Col_FrameBg(),       0x333333FF)
  push_color(reaper.ImGui_Col_Text(),          0x9F9F9FFF)
  push_color(reaper.ImGui_Col_ButtonHovered(), 0x333333FF)
  push_color(reaper.ImGui_Col_TitleBg(),       0x000000FF)
  push_color(reaper.ImGui_Col_TitleBgActive(), 0x000000FF)

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
      reaper.ImGui_DrawList_AddRectFilled(fgd, wx - pad, wy - pad, wx + s, wy + s, 0x333333FF, 2.0)
    end
  end

  if visible then
    ------------------------------------------------------------
    -- GRID
    ------------------------------------------------------------
    local grid_on = reaper.GetToggleCommandState(CMD_GRID_TOGGLE) == 1
    if grid_on then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2D5047FF)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),   0x1ABC98FF)
    end
    if reaper.ImGui_Button(ctx, 'Grid') or reaper.ImGui_IsItemClicked(ctx, 1) then
      queue_action(function() reaper.Main_OnCommand(CMD_GRID_TOGGLE, 0) end)
      arm_focus_restore()
    end
    if grid_on then reaper.ImGui_PopStyleColor(ctx, 2) end

    reaper.ImGui_SameLine(ctx, nil, 4)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x1ABC98FF)
    if reaper.ImGui_Button(ctx, grid_options[grid_index]) or reaper.ImGui_IsItemClicked(ctx, 1) then
      reaper.ImGui_OpenPopup(ctx, 'grid_selector_popup')
    end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x333333FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),   0x9F9F9FFF)
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
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
    if reaper.ImGui_Button(ctx, 'Nudge') or reaper.ImGui_IsItemClicked(ctx, 1) then
      reaper.ImGui_OpenPopup(ctx, 'nudge_val_popup')
    end
    reaper.ImGui_PopStyleColor(ctx)

    reaper.ImGui_SameLine(ctx, nil, 2)
    local text_width = ({ reaper.ImGui_CalcTextSize(ctx, '000000') })[1]
    reaper.ImGui_SetNextItemWidth(ctx, text_width)

    local nudge_field_active_this_frame = false

    if unit_index == 3 then
      -- Measures.Beats: 6-decimal format
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x1ABC98FF)
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

      local text_color = seconds_input_error and 0xFF4444FF or 0x1ABC98FF
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
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x1ABC98FF)
      local ret, new_val = reaper.ImGui_InputDouble(ctx, '##nudge_val', nudge_val, 0, 0, '%.0f')
      if reaper.ImGui_IsItemActive(ctx) then nudge_field_active_this_frame = true end
      if ret then
        nudge_val = math.floor(new_val + 0.5)
        reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL, tostring(nudge_val), true)
      end
      reaper.ImGui_PopStyleColor(ctx)

    else
      -- All other units: 3-decimal format
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x1ABC98FF)
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
  end -- if visible

  reaper.ImGui_PopStyleColor(ctx, color_count)
  reaper.ImGui_End(ctx)

  return open
end

-- ===================================================================
--  MAIN LOOP
-- ===================================================================
local frame_failures = 0

local function Main()
  -- Dead context (sleep/wake, monitor change, GPU reset, GC)?
  -- Replace it BEFORE any ImGui call touches it. Window position and
  -- dock state are restored from ReaImGui's ini for the same name.
  if not context_is_valid() then
    create_context()
  end

  grid_poll_frame = grid_poll_frame + 1
  if grid_poll_frame >= 10 then
    grid_poll_frame = 0
    update_grid_index_from_reaper()
  end

  local ok, result = pcall(DrawFrame)

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
