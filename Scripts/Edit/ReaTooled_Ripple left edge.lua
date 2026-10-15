--[[
  Ripple Left Edge – "Start-Locked Left Drag" (background defer)
  Author: Reaper DAW Ultimate Assistant (ChatGPT)
  Version: 0.3.0

  WHAT IT DOES (simple start):
    While this script is running, if *Ripple Editing* is ON and *Auto Crossfades* is OFF,
    then a left-edge drag behaves like a start-locked edit:
      • Dragging LEFT  over an item's LEFT edge  => increases item length; START POSITION stays fixed; SOURCE OFFSET moves earlier by the same amount
      • Dragging RIGHT over an item's LEFT edge  => decreases item length; START POSITION stays fixed; SOURCE OFFSET moves later by the same amount

    We counteract REAPER's native left-trim move by restoring D_POSITION every frame, and we update
    the take's D_STARTOFFS by the same time change (scaled by take playrate), while setting D_LENGTH.

  SCOPE:
    Works on the item whose left edge you begin dragging. No project-wide ripple shifts here yet.

  DEPENDENCIES:
    • SWS Extension (for BR_GetMouseCursorContext*)
    • js_ReaScriptAPI (for JS_Mouse_GetState)

  NOTES:
    • Auto-crossfades must be OFF; Ripple must be ON (either per-track or all-tracks). If these change mid-drag, the edit finalizes.
    • For AUDIO takes, D_STARTOFFS is adjusted by (mouse delta * take playrate). For MIDI, source offset is ignored (REAPER does not use it the same way).
    • For NON-LOOPING sources, source offset is clamped so the item does not exceed available media.
]]

local SCRIPT_NAME = "Ripple Left Edge – Start-Locked Left Drag"
local EPS = 1e-9

-- User options ---------------------------------------------------------------
local REQUIRE_RIPPLE = true
local REQUIRE_AUTOCROSSFADE_OFF = true
local MIN_LEN = 0.0005 -- seconds; prevent collapsing to zero
local CLAMP_NON_LOOPING = true -- stop offset from exceeding source bounds when loopsrc is off

-- Command IDs we query for toggle state (stock)
local CMD_AUTOCROSSFADE   = 41194 -- Options: Toggle auto-crossfade on/off
local CMD_RIPPLE_PER_TRACK = 40501 -- Options: Toggle ripple editing per-track
local CMD_RIPPLE_ALL       = 40576 -- Options: Toggle ripple editing all tracks

-- State ---------------------------------------------------------------------
local dragging = false
local drag_item = nil
local drag_take = nil
local start_mouse_t = 0.0
local start_len = 0.0
local start_pos = 0.0
local start_soffs = 0.0
local start_rate = 1.0
local src_len = nil
local loopsrc = 1.0

-- Utilities -----------------------------------------------------------------
local function is_auto_xfade_off()
  if not REQUIRE_AUTOCROSSFADE_OFF then return true end
  local v = reaper.GetToggleCommandStateEx(0, CMD_AUTOCROSSFADE)
  return v == 0
end

local function is_ripple_on()
  if not REQUIRE_RIPPLE then return true end
  local per = reaper.GetToggleCommandStateEx(0, CMD_RIPPLE_PER_TRACK)
  local all = reaper.GetToggleCommandStateEx(0, CMD_RIPPLE_ALL)
  return (per == 1) or (all == 1)
end

local function get_mouse_context()
  -- requires SWS
  local window, segment, details = reaper.BR_GetMouseCursorContext()
  local item = reaper.BR_GetMouseCursorContext_Item()
  local take = reaper.BR_GetMouseCursorContext_Take()
  local pos  = reaper.BR_GetMouseCursorContext_Position()
  return window, segment, details, item, take, pos
end

local function left_button_down()
  -- requires js_ReaScriptAPI
  local state = reaper.JS_Mouse_GetState(1) -- 1 = left button mask
  return (state & 1) == 1
end

local function capture_item_props(it)
  local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local take = reaper.GetActiveTake(it)
  local soffs = 0.0
  local rate = 1.0
  local srcLen = nil
  local loop = 1.0
  if take and reaper.TakeIsMIDI(take) == false then
    soffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    rate  = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    loop  = reaper.GetMediaItemTakeInfo_Value(take, "B_LOOPSRC")
    local src = reaper.GetMediaItemTake_Source(take)
    if src ~= nil then srcLen = reaper.GetMediaSourceLength(src) end
  end
  return pos, len, soffs, take, rate, srcLen, loop
end

local function clamp_soffs_and_len(soffs, len, rate, srcLen, loop)
  if not CLAMP_NON_LOOPING or not srcLen or loop == 1.0 then
    return soffs, len
  end
  -- Ensure 0 <= soffs <= srcLen - len*rate
  if soffs < 0 then soffs = 0 end
  local max_soffs = srcLen - (len * (rate or 1.0))
  if max_soffs < 0 then max_soffs = 0 end
  if soffs > max_soffs then soffs = max_soffs end
  return soffs, len
end

local function apply_start_locked(it, tk, start_pos, new_len, new_soffs, rate, srcLen, loop)
  if new_len < MIN_LEN then new_len = MIN_LEN end
  new_soffs, new_len = clamp_soffs_and_len(new_soffs, new_len, rate or 1.0, srcLen, loop)
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", start_pos)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", new_len)
  if tk and reaper.TakeIsMIDI(tk) == false then
    reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", new_soffs)
  end
end

-- Main loop -----------------------------------------------------------------
local function run()
  -- Only arm behavior when prerequisites are satisfied
  if is_ripple_on() and is_auto_xfade_off() then
    local window, segment, details, it, tk, mouse_t = get_mouse_context()

    if not dragging then
      -- Idle/armed state: wait for left-edge hover + mouse down
      if segment == "item" and details == "left_trim" and it ~= nil then
        if left_button_down() then
          -- Begin our managed drag
          dragging = true
          drag_item = it
          start_pos, start_len, start_soffs, drag_take, start_rate, src_len, loopsrc = capture_item_props(it)
          start_mouse_t = mouse_t
          reaper.Undo_BeginBlock()
          reaper.PreventUIRefresh(1)
        end
      end
    else
      -- During drag: keep position fixed; modify length and source offset by mouse delta
      if left_button_down() and reaper.ValidatePtr2(0, drag_item, "MediaItem*") then
        local _, _, _, it2, _, cur_mouse_t = get_mouse_context()
        local delta = (cur_mouse_t or start_mouse_t) - start_mouse_t -- project seconds; >0 moved right
        local new_len = start_len - delta
        local new_soffs = start_soffs + (delta * (start_rate or 1.0))
        apply_start_locked(drag_item, drag_take, start_pos, new_len, new_soffs, start_rate, src_len, loopsrc)
        reaper.UpdateItemInProject(drag_item)
      else
        -- Mouse released: end drag
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock(SCRIPT_NAME .. ": start-locked left-edge drag", -1)
        dragging = false
        drag_item, drag_take = nil, nil
      end
    end
  else
    -- prerequisites not met; if we were mid-drag, finalize cleanly
    if dragging then
      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock(SCRIPT_NAME .. ": cancelled (prereqs changed)", -1)
      dragging = false
      drag_item, drag_take = nil, nil
    end
  end

  reaper.defer(run)
end

-- Startup guardrails ---------------------------------------------------------
local function check_extensions()
  local ok_sws = reaper.BR_GetMouseCursorContext ~= nil
  local ok_js  = reaper.JS_Mouse_GetState ~= nil
  if not (ok_sws and ok_js) then
    reaper.ShowMessageBox(
      "This script requires SWS and js_ReaScriptAPI extensions.\n\n" ..
      "• SWS: https://www.sws-extension.org/\n" ..
      "• js_ReaScriptAPI: via ReaPack (ReaTeam Extensions)",
      SCRIPT_NAME, 0)
    return false
  end
  return true
end

if check_extensions() then
  run()
end
