-- @description ReaTooled - Scrolling settings
-- @version 1.2
-- @date 2026.10.26
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Try and choose scroll and wheel-zoom directions
--   Shows REAPER's vertical and horizontal scroll direction (Preferences >
--   Keyboard/Multitouch) and the direction of ReaTooled's wheel scripts
--   (zoom, take volume, pitch, peaks gain), with what each choice does.
--   Every choice takes effect right away, so you can try it in REAPER while
--   the window is open. "Put back how it was" returns all three to what they
--   were when the window opened. Your Mac's own scrolling setting is read,
--   never changed. Opens once after "Set up ReaTooled"; run it any time from
--   the Actions list. Needs ReaImGui and SWS (both installed with ReaTooled).
-- @changelog
--   v1.2 Pro Tools note reworded
--   v1.1 Wording works on every system ("like your other apps", Alt instead of Option
--        on Windows/Linux); says when the suggestions come from macOS natural scrolling
--   v1.0 Initial version

local TITLE = "Scrolling and zooming"
local REV_V, REV_H = 512, 1024   -- REAPER "multitouch" bits: Reverse vertical / horizontal scroll

if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox("This window needs ReaImGui. Install it with ReaPack (Extensions > ReaPack > Browse packages > ReaImGui), then restart REAPER.", TITLE, 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"

------------------------------------------------------------
-- Read and write the three settings
------------------------------------------------------------

local IS_MAC = reaper.GetOS():match("^OSX") or reaper.GetOS():match("^macOS")
local MOD = IS_MAC and "Option" or "Alt"

-- macOS natural scrolling (com.apple.swipescrolldirection; missing = macOS default, on)
local function mac_natural()
  if not IS_MAC then return false end
  local out = reaper.ExecProcess('/usr/bin/defaults read -g com.apple.swipescrolldirection', 3000) or ""
  local code, value = out:match("^(%-?%d+)\n(.*)$")
  if code == "0" then return (value or ""):match("%d") ~= "0" end
  return true
end

local function get_multitouch()
  if reaper.SNM_GetIntConfigVar then return math.floor(reaper.SNM_GetIntConfigVar("multitouch", 0)) end
  local ok, s = reaper.get_config_var_string("multitouch")
  return math.floor(tonumber(ok and s or "") or 0)
end

local can_set_reaper = reaper.SNM_SetIntConfigVar ~= nil

local function set_multitouch(v)
  if not can_set_reaper then return end
  reaper.SNM_SetIntConfigVar("multitouch", v)
  -- also saved in reaper.ini right away, in case REAPER doesn't quit normally
  if reaper.BR_Win32_WritePrivateProfileString then
    reaper.BR_Win32_WritePrivateProfileString("REAPER", "multitouch", tostring(v), reaper.get_ini_file())
  end
end

local function read_state()
  local mt = get_multitouch()
  return { vrev = (mt & REV_V) ~= 0, hrev = (mt & REV_H) ~= 0,
           inv = reaper.GetExtState("ReaTooled", "WheelInvert") == "1" }
end

local function apply(st)
  local mt = get_multitouch()
  local want = mt & ~(REV_V | REV_H)
  if st.vrev then want = want | REV_V end
  if st.hrev then want = want | REV_H end
  if want ~= mt then set_multitouch(want) end
  reaper.SetExtState("ReaTooled", "WheelInvert", st.inv and "1" or "0", true)
end

local natural = mac_natural()
local orig = read_state()
local cur = { vrev = orig.vrev, hrev = orig.hrev, inv = orig.inv }

-- Opened by Startup after Set up: only once
reaper.DeleteExtState("ReaTooled", "ScrollingWindowOnce", true)

------------------------------------------------------------
-- What each choice does
-- (worked out from tests: macOS natural scrolling and REAPER's reverse
--  boxes each flip what REAPER and ReaTooled's wheel scripts receive)
------------------------------------------------------------

local function zooms_in(st) return not ((natural ~= st.vrev) ~= st.inv) end
local function suggested_inv(st) return natural ~= st.vrev end

local function changed()
  return cur.vrev ~= orig.vrev or cur.hrev ~= orig.hrev or cur.inv ~= orig.inv
end

------------------------------------------------------------
-- Window (same look as the other ReaTooled windows)
------------------------------------------------------------

local ctx = ImGui.CreateContext(TITLE)
local font = ImGui.CreateFont("sans-serif", 14)
local font_b = ImGui.CreateFont("sans-serif", 15, ImGui.FontFlags_Bold)
ImGui.Attach(ctx, font); ImGui.Attach(ctx, font_b)

local C_ACCENT   = 0x2F7FD6FF
local C_ACCENT_H = 0x3A8FE8FF
local C_ACCENT_A = 0x2669B3FF
local C_RESULT   = 0x8FC3FFFF
local C_NOTE     = 0x8A8A8AFF
local WRAP = 470
local first_frame = true
local done = false

local function bold(text)
  ImGui.PushFont(ctx, font_b); ImGui.Text(ctx, text); ImGui.PopFont(ctx)
end

local function note(text)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_NOTE)
  ImGui.PushTextWrapPos(ctx, WRAP); ImGui.TextWrapped(ctx, text); ImGui.PopTextWrapPos(ctx)
  ImGui.PopStyleColor(ctx)
end

local function result(text)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_RESULT)
  ImGui.PushTextWrapPos(ctx, WRAP); ImGui.TextWrapped(ctx, text); ImGui.PopTextWrapPos(ctx)
  ImGui.PopStyleColor(ctx)
end

-- Two radio buttons: Standard / Reversed, with "(suggested)" after one
local function choice(id, value, suggest_reversed, enabled)
  local new = value
  ImGui.BeginDisabled(ctx, not enabled)
  if ImGui.RadioButton(ctx, "Standard" .. (suggest_reversed and "" or " (suggested)") .. "##s" .. id, not value) then new = false end
  ImGui.SameLine(ctx, 0, 18)
  if ImGui.RadioButton(ctx, "Reversed" .. (suggest_reversed and " (suggested)" or "") .. "##r" .. id, value) then new = true end
  ImGui.EndDisabled(ctx)
  return new
end

local function accent_button(label, w, enabled)
  ImGui.BeginDisabled(ctx, not enabled)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_ACCENT)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_ACCENT_H)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_ACCENT_A)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)
  local pressed = ImGui.Button(ctx, label, w, 0)
  ImGui.PopStyleColor(ctx, 4)
  ImGui.EndDisabled(ctx)
  return pressed
end

local function frame()
  ImGui.PushFont(ctx, font)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 14)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 8, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8, 7)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 6)

  if first_frame then
    local vp = ImGui.GetMainViewport(ctx)
    local cx, cy = ImGui.Viewport_GetCenter(vp)
    ImGui.SetNextWindowPos(ctx, cx, cy, ImGui.Cond_Appearing, 0.5, 0.5)
    ImGui.SetNextWindowFocus(ctx)
  end

  local flags = ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoDocking
  local visible, open = ImGui.Begin(ctx, TITLE, true, flags)
  if visible then
    ImGui.PushFont(ctx, font_b); ImGui.Text(ctx, "Scrolling and zooming"); ImGui.PopFont(ctx)
    ImGui.SameLine(ctx)
    local tw = ImGui.CalcTextSize(ctx, "ReaTooled")
    ImGui.SetCursorPosX(ctx, WRAP + 16 - tw)
    ImGui.TextDisabled(ctx, "ReaTooled")
    ImGui.Separator(ctx)
    note("Try these now: each choice takes effect right away.")
    if IS_MAC and natural then
      note("Your Mac uses natural scrolling, so the suggested settings below are based on that.")
    end
    ImGui.Dummy(ctx, 0, 4)

    local before = { vrev = cur.vrev, hrev = cur.hrev, inv = cur.inv }

    -- REAPER vertical
    bold("REAPER vertical scrolling")
    cur.vrev = choice("v", cur.vrev, false, can_set_reaper)
    result("Two fingers up or wheel up: tracks scroll " ..
      (cur.vrev and "the opposite way from your other apps" or "like your other apps") .. ".")
    ImGui.Dummy(ctx, 0, 4)

    -- REAPER horizontal
    bold("REAPER horizontal scrolling")
    cur.hrev = choice("h", cur.hrev, false, can_set_reaper)
    result("Swipe left: the timeline scrolls " ..
      (cur.hrev and "the opposite way from your other apps" or "like your other apps") .. ".")
    if not can_set_reaper then note("Changing these needs the SWS extension. You can also change them in REAPER Preferences > Keyboard/Multitouch.") end
    ImGui.Dummy(ctx, 0, 4)

    -- ReaTooled wheel scripts
    bold("ReaTooled wheel scripts")
    cur.inv = choice("i", cur.inv, suggested_inv(cur), true)
    result(MOD .. " + two fingers up or wheel up: " .. (zooms_in(cur) and "zooms in." or "zooms out.") ..
      " The same choice also sets take volume, pitch and peaks gain.")
    ImGui.Dummy(ctx, 0, 6)

    note("Note: Pro Tools zooms in with two fingers up on a trackpad, and out with the mouse wheel up. Pick whichever you prefer.")
    ImGui.Dummy(ctx, 0, 2)
    note("Open this again any time: Actions > ReaTooled_Scrolling settings")
    ImGui.Separator(ctx)

    if cur.vrev ~= before.vrev or cur.hrev ~= before.hrev or cur.inv ~= before.inv then apply(cur) end

    -- Buttons, right-aligned
    local w1, w2 = 150, 86
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, WRAP - w1 - w2 - 8))
    ImGui.BeginDisabled(ctx, not changed())
    if ImGui.Button(ctx, "Put back how it was", w1, 0) then
      cur = { vrev = orig.vrev, hrev = orig.hrev, inv = orig.inv }
      apply(cur)
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if accent_button("Done", w2, true) then done = true end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then done = true end

    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, 5)
  ImGui.PopFont(ctx)
  first_frame = false
  if not open then done = true end
end

local function loop()
  frame()
  if done then return end
  reaper.defer(loop)
end

reaper.defer(loop)
