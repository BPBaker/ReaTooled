-- @description ReaTooled - Spot dialog
-- @version 1.0.1
-- @date 2026.10.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Move items to an exact time, like Pro Tools' Spot dialog
--   Opens for the selected item (or the item clicked in Spot mode, see
--   "ReaTooled_Toggle Spot mode"). Type a new Start, Sync Point or End and press
--   Enter (or OK): the item moves so that point lands at the time you typed.
--   Every selected item moves by the same amount, so they keep their spacing.
--     - Time scale: follow REAPER's ruler, Timecode, Min:Sec, Bars|Beats, Seconds
--       or Samples (remembered)
--     - Original Time Stamp: from the file (BWF), including where the item starts
--       in the file. The arrow puts it in Start.
--     - User Time Stamp: your own time stamp for the item, saved with it.
--       "Stamp" saves the current Start; the arrow puts it in Start.
--     - Type +value or -value in a field to move by that amount
--     - "Edit cursor" puts the edit cursor time in Start
--   Sync Point is REAPER's snap offset. Spotting never ripples, whatever the
--   ripple mode, and follows "Envelope points move with media items".
--   Needs ReaImGui and SWS (both installed with ReaTooled).
-- @changelog
--   v1.0.1 Labels no longer overlap the values; one font throughout; shorter help line
--   v1.0 Initial version

local TITLE = "Spot Dialog"
local NS = "ReaTooled"

if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox("The Spot dialog needs ReaImGui. Install it with ReaPack, then restart REAPER.", TITLE, 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"

-- Run again while open: close it (no "script is already running" question)
if reaper.set_action_options then reaper.set_action_options(1) end

------------------------------------------------------------
-- Which item
------------------------------------------------------------

local function item_from_guid(guid)
  if guid == "" or not reaper.BR_GetMediaItemByGUID then return nil end
  local it = reaper.BR_GetMediaItemByGUID(0, guid)
  if it and reaper.ValidatePtr2(0, it, "MediaItem*") then return it end
end

local function pick_item()
  local guid = reaper.GetExtState(NS, "SpotItem")
  reaper.DeleteExtState(NS, "SpotItem", false)
  return item_from_guid(guid) or reaper.GetSelectedMediaItem(0, 0)
end

local item = pick_item()
if not item then
  reaper.ShowMessageBox("Select an item to spot.", TITLE, 0)
  return
end

------------------------------------------------------------
-- Time formats
------------------------------------------------------------

local SCALES = {
  { name = "Ruler (REAPER's time display)", mode = -1 },
  { name = "Timecode",   mode = 5 },
  { name = "Min:Sec",    mode = 0 },
  { name = "Bars|Beats", mode = 2 },
  { name = "Seconds",    mode = 3 },
  { name = "Samples",    mode = 4 },
}
local scale = math.floor(tonumber(reaper.GetExtState(NS, "SpotTimeScale")) or 2)
if not SCALES[scale] then scale = 2 end
local function mode() return SCALES[scale].mode end

local function fmt_pos(t) return reaper.format_timestr_pos(t, "", mode()) end
local function fmt_len(len, from) return reaper.format_timestr_len(len, "", from, mode()) end

-- Parse a typed time. "+x" / "-x" = relative to base. Returns nil if it isn't a time.
local function parse(text, base)
  local s = (text or ""):match("^%s*(.-)%s*$")
  if s == "" or not s:match("%d") then return nil end
  local sign, rest = s:match("^([%+%-])%s*(.+)$")
  if sign and base then
    local len = reaper.parse_timestr_len(rest, base, mode())
    return base + (sign == "-" and -len or len)
  end
  return reaper.parse_timestr_pos(s, mode())
end

------------------------------------------------------------
-- Item values
------------------------------------------------------------

local function project_offset() return reaper.GetProjectTimeOffset(0, false) end

local function source_of(take)
  local src = reaper.GetMediaItemTake_Source(take)
  while src and reaper.GetMediaSourceParent(src) do src = reaper.GetMediaSourceParent(src) end
  return src
end

-- Original time stamp as a project position (or nil)
local function original_stamp(it)
  local take = reaper.GetActiveTake(it)
  if not take or reaper.TakeIsMIDI(take) then return nil end
  local src = source_of(take)
  if not src then return nil end
  local ok, ref = reaper.GetMediaFileMetadata(src, "BWF:TimeReference")
  local sr = reaper.GetMediaSourceSampleRate(src)
  ref = tonumber(ok and ref or "")
  if not ref or sr <= 0 then return nil end
  -- the file's stamp, plus where this item starts in the file
  local startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  return ref / sr + startoffs - project_offset()
end

local function user_stamp(it)
  local ok, v = reaper.GetSetMediaItemInfo_String(it, "P_EXT:ReaTooled_UserTimeStamp", "", false)
  local abs = tonumber(ok and v or "")
  if abs then return abs - project_offset() end
  return nil
end

local function set_user_stamp(it, pos)
  reaper.GetSetMediaItemInfo_String(it, "P_EXT:ReaTooled_UserTimeStamp",
    pos and string.format("%.10f", pos + project_offset()) or "", true)
end

local function item_name(it)
  local take = reaper.GetActiveTake(it)
  local name = take and reaper.GetTakeName(take) or ""
  local tr = reaper.GetMediaItem_Track(it)
  local _, tname = reaper.GetTrackName(tr)
  return (name ~= "" and name or "(unnamed item)") .. "   on " .. tname
end

------------------------------------------------------------
-- State
------------------------------------------------------------

local S = {}
local function load(it)
  item = it
  S.pos    = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  S.len    = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  S.snap   = reaper.GetMediaItemInfo_Value(it, "D_SNAPOFFSET")
  S.locked = (math.floor(reaper.GetMediaItemInfo_Value(it, "C_LOCK")) & 1) == 1
  S.orig   = original_stamp(it)
  S.user   = user_stamp(it)
  S.new    = S.pos        -- the start the item will move to
  S.name   = item_name(it)
  S.msg    = nil
  S.focus  = true
end
load(item)

local buf = {}
local function refresh()
  buf.start = fmt_pos(S.new)
  buf.sync  = fmt_pos(S.new + S.snap)
  buf.stop  = fmt_pos(S.new + S.len)
  buf.user  = S.user and fmt_pos(S.user) or ""
end
refresh()

------------------------------------------------------------
-- Move
------------------------------------------------------------

local function selected_items()
  local list = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do list[#list + 1] = reaper.GetSelectedMediaItem(0, i) end
  return list
end

local function apply()
  local delta = S.new - S.pos
  if math.abs(delta) < 1e-10 then return true end
  -- the spotted item is always part of the move
  if not reaper.IsMediaItemSelected(item) then
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)
  end
  local items = selected_items()
  local earliest = math.huge
  for _, it in ipairs(items) do
    earliest = math.min(earliest, reaper.GetMediaItemInfo_Value(it, "D_POSITION"))
  end
  if earliest + delta < -1e-9 then
    S.msg = "That would move an item before the start of the project."
    return false
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  -- Spotting never ripples (Pro Tools' Spot mode): ripple off while moving
  local per_track, all_tracks = reaper.GetToggleCommandState(40310) == 1, reaper.GetToggleCommandState(40311) == 1
  if per_track or all_tracks then reaper.Main_OnCommand(40309, 0) end   -- ripple off
  -- REAPER's nudge moves the selected items (with their envelope points when
  -- "Envelope points move with media items" is on)
  reaper.ApplyNudge(0, 0, 0, 1, math.abs(delta), delta < 0, 0)
  if per_track then reaper.Main_OnCommand(40310, 0) elseif all_tracks then reaper.Main_OnCommand(40311, 0) end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Spot " .. #items .. " item" .. (#items == 1 and "" or "s"), -1)
  return true
end

------------------------------------------------------------
-- Window
------------------------------------------------------------

local ctx = ImGui.CreateContext(TITLE)
local font = ImGui.CreateFont("sans-serif", 14)
local font_b = ImGui.CreateFont("sans-serif", 15, ImGui.FontFlags_Bold)
ImGui.Attach(ctx, font); ImGui.Attach(ctx, font_b)

local C_ACCENT, C_ACCENT_H, C_ACCENT_A = 0x2F7FD6FF, 0x3A8FE8FF, 0x2669B3FF
local C_NOTE, C_WARN = 0x8A8A8AFF, 0xE8A33AFF
local W = 470
local LABEL_W = 170
local FIELD_W = 170
local first_frame, done = true, false

local function note(text, col)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, col or C_NOTE)
  ImGui.PushTextWrapPos(ctx, W); ImGui.TextWrapped(ctx, text); ImGui.PopTextWrapPos(ctx)
  ImGui.PopStyleColor(ctx)
end

local function accent_button(label, w)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_ACCENT)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_ACCENT_H)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_ACCENT_A)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)
  local pressed = ImGui.Button(ctx, label, w, 0)
  ImGui.PopStyleColor(ctx, 4)
  return pressed
end

-- A labelled time field. on_commit(new_value) is called when editing ends.
local function field(id, label, key, base, on_commit, disabled, focus)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, label)
  ImGui.SameLine(ctx, LABEL_W)
  ImGui.SetNextItemWidth(ctx, FIELD_W)
  ImGui.BeginDisabled(ctx, disabled or false)
  if focus then ImGui.SetKeyboardFocusHere(ctx) end
  local changed, v = ImGui.InputText(ctx, "##" .. id, buf[key], ImGui.InputTextFlags_AutoSelectAll)
  ImGui.EndDisabled(ctx)
  if changed then buf[key] = v end
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then
    local t = parse(buf[key], base)
    if t then on_commit(t) else
      S.msg = "\"" .. buf[key] .. "\" isn't a time in this time scale."
      S.bad = true
    end
    refresh()
  end
end

local function frame()
  ImGui.PushFont(ctx, font)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 14)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 8, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8, 7)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 6)

  if first_frame then
    local cx, cy = ImGui.Viewport_GetCenter(ImGui.GetMainViewport(ctx))
    ImGui.SetNextWindowPos(ctx, cx, cy, ImGui.Cond_Appearing, 0.5, 0.5)
    ImGui.SetNextWindowFocus(ctx)
  end

  local flags = ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoDocking
  local visible, open = ImGui.Begin(ctx, TITLE, true, flags)
  if visible then
    -- Another item clicked in Spot mode while the window is open: switch to it
    local guid = reaper.GetExtState(NS, "SpotItem")
    if guid ~= "" then
      reaper.DeleteExtState(NS, "SpotItem", false)
      local it = item_from_guid(guid)
      if it then load(it); refresh() end
    end
    if not reaper.ValidatePtr2(0, item, "MediaItem*") then done = true end

    ImGui.PushFont(ctx, font_b); ImGui.Text(ctx, "Spot"); ImGui.PopFont(ctx)
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, W + 16 - ImGui.CalcTextSize(ctx, "ReaTooled"))
    ImGui.TextDisabled(ctx, "ReaTooled")
    note(S.name)
    local nsel = reaper.CountSelectedMediaItems(0)
    if nsel > 1 then note(nsel .. " selected items move together.") end
    ImGui.Separator(ctx)

    -- Time scale
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Time Scale")
    ImGui.SameLine(ctx, LABEL_W)
    ImGui.SetNextItemWidth(ctx, W - LABEL_W + 16)
    if ImGui.BeginCombo(ctx, "##scale", SCALES[scale].name) then
      for i, s in ipairs(SCALES) do
        if ImGui.Selectable(ctx, s.name, i == scale) then
          scale = i
          reaper.SetExtState(NS, "SpotTimeScale", tostring(i), true)
          refresh()
        end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.Dummy(ctx, 0, 2)

    -- Start / Sync Point / End / Duration
    S.bad = false
    field("start", "Start", "start", S.new, function(t) S.new = t; S.msg = nil end, S.locked, S.focus and not S.locked)
    S.focus = false
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Edit cursor") then S.new = reaper.GetCursorPosition(); refresh() end
    field("sync", "Sync Point", "sync", S.new + S.snap, function(t) S.new = t - S.snap; S.msg = nil end, S.locked)
    field("stop", "End", "stop", S.new + S.len, function(t) S.new = t - S.len; S.msg = nil end, S.locked)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Duration")
    ImGui.SameLine(ctx, LABEL_W)
    ImGui.TextDisabled(ctx, fmt_len(S.len, S.new))
    ImGui.Dummy(ctx, 0, 2)
    ImGui.Separator(ctx)

    -- Time stamps
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Original Time Stamp")
    ImGui.SameLine(ctx, LABEL_W)
      ImGui.TextDisabled(ctx, S.orig and fmt_pos(S.orig) or "none in this file")
    if S.orig then
      ImGui.SameLine(ctx)
      ImGui.BeginDisabled(ctx, S.locked)
      if ImGui.SmallButton(ctx, "^##orig") then S.new = S.orig; refresh() end
      ImGui.EndDisabled(ctx)
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Use as Start") end
    end

    field("user", "User Time Stamp", "user", S.user or S.new, function(t) S.user = t; set_user_stamp(item, t) end)
    ImGui.SameLine(ctx)
    ImGui.BeginDisabled(ctx, S.locked or not S.user)
    if ImGui.SmallButton(ctx, "^##user") then S.new = S.user; refresh() end
    ImGui.EndDisabled(ctx)
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Use as Start") end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Stamp") then S.user = S.pos; set_user_stamp(item, S.pos); refresh() end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Save the item's current Start as its User Time Stamp") end

    ImGui.Dummy(ctx, 0, 2)
    if S.locked then note("This item is locked, so it can't be spotted.", C_WARN) end
    if S.msg then note(S.msg, C_WARN) end
    note("Put + or - before a time to move by that amount.")
    ImGui.Separator(ctx)

    -- Buttons, right-aligned
    local w1, w2 = 86, 86
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, W - w1 - w2 - 8))
    if ImGui.Button(ctx, "Cancel", w1, 0) then done = true end
    ImGui.SameLine(ctx)
    local ok_pressed = accent_button("OK", w2)
    local enter = ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)
    if (ok_pressed or enter) and not S.locked and not S.bad then
      if apply() then done = true end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then done = true end

    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, 5)
  ImGui.PopFont(ctx)
  first_frame = false
  if not open then done = true end
end

local function loop()
  reaper.SetExtState(NS, "SpotDialogAlive", tostring(reaper.time_precise()), false)
  frame()
  if done then
    reaper.DeleteExtState(NS, "SpotDialogAlive", false)
    return
  end
  reaper.defer(loop)
end
reaper.atexit(function() reaper.DeleteExtState(NS, "SpotDialogAlive", false) end)
reaper.defer(loop)
