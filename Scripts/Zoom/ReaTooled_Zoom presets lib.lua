-- @noindex
-- ReaTooled — Pro Tools-style horizontal zoom presets (shared library)
-- Used by the "Recall / Save zoom preset N" and "Reset zoom presets" scripts.
-- Edit the settings below once; every preset script picks them up.

local Z = {}

---------------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------------

-- Default zoom for each preset, as SECONDS VISIBLE PER 1000 PIXELS of
-- arrange width (1 = widest, 5 = closest, like Pro Tools).
-- These approximate the Pro Tools factory presets; tweak to taste, or just
-- set each level with the Save scripts.
Z.DEFAULTS = {
  [1] = 240,    -- ~4 min per 1000 px  (session overview)
  [2] = 60,     -- ~1 min
  [3] = 10,     -- ~10 sec
  [4] = 1,      -- ~1 sec
  [5] = 0.05,   -- ~50 ms (waveform detail)
}

-- Where the zoom anchors when a preset is recalled:
--   "selection" : Pro Tools behaviour — centre on the time selection if
--                 there is one, otherwise on the edit cursor
--   "reaper"    : use REAPER's own zoom-centre preference
Z.CENTER = "selection"

-- Save presets with each project (true) or globally for all projects (false).
-- With true, a project without its own saved value falls back to the global
-- value, then to the default above.
Z.PER_PROJECT = false

-- Show a short tooltip by the mouse when a preset is saved or reset.
Z.FEEDBACK = true

---------------------------------------------------------------------------

local SECTION = "ReaTooled_ZoomPresets"

local function key(n) return "preset" .. n end

local function default_pps(n)
  local secs = Z.DEFAULTS[n] or 10
  return 1000 / secs
end

-- Returns the stored pixels-per-second for preset n (or the default).
function Z.get(n)
  if Z.PER_PROJECT then
    local ok, v = reaper.GetProjExtState(0, SECTION, key(n))
    if ok == 1 and tonumber(v) then return tonumber(v) end
  end
  local v = tonumber(reaper.GetExtState(SECTION, key(n)))
  if v then return v end
  return default_pps(n)
end

function Z.set(n, pps)
  local s = string.format("%.6f", pps)
  if Z.PER_PROJECT then
    reaper.SetProjExtState(0, SECTION, key(n), s)
  else
    reaper.SetExtState(SECTION, key(n), s, true)
  end
end

function Z.reset(n)
  if Z.PER_PROJECT then reaper.SetProjExtState(0, SECTION, key(n), "") end
  reaper.DeleteExtState(SECTION, key(n), true)
end

-- Brief tooltip that clears itself; the defer also stops REAPER from
-- adding a pointless undo point for the script run.
function Z.notify(msg)
  if not Z.FEEDBACK then reaper.defer(function() end) return end
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(msg, x + 12, y + 12, true)
  local t0 = reaper.time_precise()
  local function wait()
    if reaper.time_precise() - t0 < 1.2 then
      reaper.defer(wait)
    else
      reaper.TrackCtl_SetToolTip("", 0, 0, true)
    end
  end
  reaper.defer(wait)
end

-- Cmd+click on a toolbar button (Ctrl+click on Windows) saves instead, like Pro Tools'
-- zoom preset buttons. A keyboard shortcut always recalls: if the preset's number
-- key is down, the script was started from the keyboard.
local function save_click(n)
  if not (reaper.JS_Mouse_GetState and reaper.JS_VKeys_GetState) then return false end
  if (reaper.JS_Mouse_GetState(4) & 4) == 0 then return false end   -- Cmd (Ctrl on Windows)
  local keys = reaper.JS_VKeys_GetState(-0.5) or ""
  local digit, numpad = 0x30 + n, 0x60 + n
  if keys:byte(digit) == 1 or keys:byte(numpad) == 1 then return false end
  return true
end

function Z.recall(n)
  if save_click(n) then
    Z.save(n)
    reaper.defer(function() end) -- no undo point
    return
  end
  local pps = Z.get(n)

  if Z.CENTER == "reaper" then
    reaper.adjustZoom(pps, 1, true, -1)
  else
    -- anchor: middle of time selection, else edit cursor
    local ts, te = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local anchor = (te > ts) and (ts + te) / 2 or reaper.GetCursorPosition()

    reaper.adjustZoom(pps, 1, true, -1)
    local vs, ve = reaper.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
    local width = ve - vs
    local start = math.max(0, anchor - width / 2)
    reaper.GetSet_ArrangeView2(0, true, 0, 0, start, start + width)
    reaper.UpdateTimeline()
  end

  reaper.defer(function() end) -- no undo point
end

function Z.save(n)
  Z.set(n, reaper.GetHZoomLevel())
  Z.notify("Zoom preset " .. n .. " saved")
end

return Z
