-- @description ReaTooled - Glue items with handles (AudioSuite-style)
-- @version 1.1
-- @date 2026.10.25
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Glue items and keep handles, like Pro Tools AudioSuite rendering
--   Opens a small window (it remembers your last choices):
--     • File mode: "Create continuous file" glues the selected items on each
--       track into one item; "Create individual files" glues each item on its own
--     • Handle length in seconds (default 2), or press "Whole File" to keep
--       all the source audio
--   Render (or Enter) glues, Cancel (or Esc) closes. The window can stay open
--   while you change the selection.
--   The glued item stays exactly where and as long as the original selection,
--   but its new file has extra audio beyond its edges, so you can still trim it
--   out afterwards. Like REAPER's own glue, take FX and take envelopes are printed.
--   Handles only reach as far as the source audio exists (and not before the
--   project start). Fades at the outer edges are kept; crossfades inside a
--   continuous glue are printed as they are. Works with fixed item lanes
--   (one item per lane). Needs ReaImGui (installed with ReaTooled).
-- @changelog
--   v1.1 New AudioSuite-style window: File mode dropdown, Whole File button, live selection summary
--   v1.0 Initial version

local TITLE = "Glue with Handles"
local NS = "ReaTooled_GlueHandles"

if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox("This script needs ReaImGui. Install it with ReaPack (Extensions > ReaPack > Browse packages > ReaImGui), then restart REAPER.", TITLE, 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"

------------------------------------------------------------
-- Settings
------------------------------------------------------------

local handle, whole, continuous   -- set from the window before each render

local saved_h = reaper.GetExtState(NS, "handles")
local saved_m = reaper.GetExtState(NS, "mode")
local ui_whole = (saved_h == "W")
local ui_handle = tonumber(saved_h) or 2
local ui_mode = (saved_m == "I") and 1 or 0     -- 0 continuous, 1 individual

local function save_settings()
  reaper.SetExtState(NS, "handles", ui_whole and "W" or tostring(ui_handle), true)
  reaper.SetExtState(NS, "mode", ui_mode == 1 and "I" or "1", true)
end

local function fmt_secs(v)
  local s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
  return s
end

------------------------------------------------------------
-- Glue logic
------------------------------------------------------------

local function get(item, k) return reaper.GetMediaItemInfo_Value(item, k) end
local function set(item, k, v) reaper.SetMediaItemInfo_Value(item, k, v) end

-- How much audio exists before the item start and after its end (project seconds)
local function available(item)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return 0, 0 end
  if get(item, "B_LOOPSRC") == 1 then
    -- a looping item has no "outside" to keep
    local src = reaper.GetMediaItemTake_Source(take)
    local srclen = reaper.GetMediaSourceLength(src)
    local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    if get(item, "D_LENGTH") * rate > srclen then return 0, 0 end
  end
  local src = reaper.GetMediaItemTake_Source(take)
  local srclen = reaper.GetMediaSourceLength(src)
  local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local len = get(item, "D_LENGTH")
  local before = math.max(0, offs) / rate
  local after = math.max(0, srclen - offs - len * rate) / rate
  return before, after
end

local function handles_for(first, last)
  local before = select(1, available(first))
  local after = select(2, available(last))
  local hl = whole and before or math.min(handle, before)
  local hr = whole and after or math.min(handle, after)
  hl = math.min(hl, get(first, "D_POSITION"))   -- not before the project start
  return math.max(0, hl), math.max(0, hr)
end

local function save_fade(item, side)
  local p = (side == "in") and "D_FADEIN" or "D_FADEOUT"
  local c = (side == "in") and "C_FADEINSHAPE" or "C_FADEOUTSHAPE"
  return { len = get(item, p .. "LEN"), auto = get(item, p .. "LEN_AUTO"),
           shape = get(item, c), dir = get(item, p .. "DIR") }
end
local function clear_fade(item, side)
  local p = (side == "in") and "D_FADEIN" or "D_FADEOUT"
  set(item, p .. "LEN", 0); set(item, p .. "LEN_AUTO", 0)
end
local function restore_fade(item, side, f)
  local p = (side == "in") and "D_FADEIN" or "D_FADEOUT"
  local c = (side == "in") and "C_FADEINSHAPE" or "C_FADEOUTSHAPE"
  set(item, p .. "LEN", f.len); set(item, p .. "LEN_AUTO", f.auto)
  set(item, c, f.shape); set(item, p .. "DIR", f.dir)
end

local function extend_left(item, h)
  if h <= 0 then return end
  local take = reaper.GetActiveTake(item)
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  set(item, "D_POSITION", get(item, "D_POSITION") - h)
  set(item, "D_LENGTH", get(item, "D_LENGTH") + h)
  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS",
    reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") - h * rate)
end
local function extend_right(item, h)
  if h <= 0 then return end
  set(item, "D_LENGTH", get(item, "D_LENGTH") + h)
end

-- Glue exactly these items (REAPER: "Item: Glue items, ignoring time selection")
local GLUE = 40362
local function glue(items)
  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(items) do reaper.SetMediaItemSelected(it, true) end
  reaper.Main_OnCommand(GLUE, 0)
  return reaper.GetSelectedMediaItem(0, 0)
end

local function run_glue()
  local n_sel = reaper.CountSelectedMediaItems(0)
    local items = {}
  for i = 0, n_sel - 1 do items[#items + 1] = reaper.GetSelectedMediaItem(0, i) end

  local groups = {}
  if continuous then
    local by_key, order = {}, {}
    for _, it in ipairs(items) do
      local key = tostring(reaper.GetMediaItem_Track(it)) .. "|" .. tostring(get(it, "I_FIXEDLANE"))
      if not by_key[key] then by_key[key] = {}; order[#order + 1] = key end
      table.insert(by_key[key], it)
    end
    for _, key in ipairs(order) do
      local g = by_key[key]
      table.sort(g, function(a, b) return get(a, "D_POSITION") < get(b, "D_POSITION") end)
      groups[#groups + 1] = g
    end
  else
    for _, it in ipairs(items) do groups[#groups + 1] = { it } end
  end

  ------------------------------------------------------------
  -- Glue
  ------------------------------------------------------------

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local results, short = {}, 0
  for _, g in ipairs(groups) do
    local first, last = g[1], g[1]
    local s, e = math.huge, -math.huge
    for _, it in ipairs(g) do
      local p = get(it, "D_POSITION"); local q = p + get(it, "D_LENGTH")
      if p < s then s = p; first = it end
      if q > e then e = q; last = it end
    end

    local hl, hr = handles_for(first, last)
    if not whole and (hl < handle - 1e-6 or hr < handle - 1e-6) then short = short + 1 end

    local fin, fout = save_fade(first, "in"), save_fade(last, "out")
    clear_fade(first, "in"); clear_fade(last, "out")
    extend_left(first, hl)
    extend_right(last, hr)

    local new = glue(g)
    if new then
      -- Trim back to the original edges; the handles stay inside the new file
      local take = reaper.GetActiveTake(new)
      set(new, "D_POSITION", s)
      set(new, "D_LENGTH", e - s)
      if take then
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS",
          reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") + hl)
      end
      restore_fade(new, "in", fin)
      restore_fade(new, "out", fout)
      results[#results + 1] = new
    end
  end

  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(results) do reaper.SetMediaItemSelected(it, true) end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Glue items with handles", -1)

  return short, #results
end

------------------------------------------------------------
-- Selection summary
------------------------------------------------------------

local function summary()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return 0, "Select the items to glue." end
  local keys, k = {}, 0
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local key = tostring(reaper.GetMediaItem_Track(it)) .. "|" .. tostring(reaper.GetMediaItemInfo_Value(it, "I_FIXEDLANE"))
    if not keys[key] then keys[key] = true; k = k + 1 end
  end
  local out = (ui_mode == 0) and k or n
  return n, string.format("%d item%s selected  >  %d new item%s", n, n == 1 and "" or "s", out, out == 1 and "" or "s")
end

------------------------------------------------------------
-- Window
------------------------------------------------------------

local ctx = ImGui.CreateContext(TITLE)
local font = ImGui.CreateFont("sans-serif", 14)
local font_b = ImGui.CreateFont("sans-serif", 15, ImGui.FontFlags_Bold)
ImGui.Attach(ctx, font); ImGui.Attach(ctx, font_b)

local MODES = "Create continuous file\0Create individual files\0"
local LABEL_W = 92
local first_frame = true
local result = nil   -- "render" | "cancel"

local C_ACCENT   = 0x2F7FD6FF
local C_ACCENT_H = 0x3A8FE8FF
local C_ACCENT_A = 0x2669B3FF

local function render_button(label, w, enabled)
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

local function toggle_button(label, on, w)
  if on then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_ACCENT)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_ACCENT_H)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_ACCENT_A)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)
  end
  local pressed = ImGui.Button(ctx, label, w, 0)
  if on then ImGui.PopStyleColor(ctx, 4) end
  return pressed
end

local function row_label(text)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextDisabled(ctx, text)
  ImGui.SameLine(ctx, LABEL_W)
end

local function frame()
  ImGui.PushFont(ctx, font)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 14, 12)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 8, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8, 8)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 6)

  if first_frame then
    local mx, my = reaper.GetMousePosition()
    mx, my = ImGui.PointConvertNative(ctx, mx, my, false)
    ImGui.SetNextWindowPos(ctx, mx - 40, my - 20, ImGui.Cond_Appearing)
    ImGui.SetNextWindowFocus(ctx)
  end

  local flags = ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoDocking
  local visible, open = ImGui.Begin(ctx, TITLE, true, flags)
  if visible then
    -- Header
    ImGui.PushFont(ctx, font_b)
    ImGui.Text(ctx, "Glue with Handles")
    ImGui.PopFont(ctx)
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "  ReaTooled")
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 0, 2)

    -- File mode
    row_label("File mode")
    ImGui.SetNextItemWidth(ctx, 236)
    local ch, v = ImGui.Combo(ctx, "##mode", ui_mode, MODES)
    if ch then ui_mode = v; save_settings() end

    -- Handles
    row_label("Handles")
    ImGui.BeginDisabled(ctx, ui_whole)
    ImGui.SetNextItemWidth(ctx, 70)
    local chh, hv = ImGui.InputDouble(ctx, "##handle", ui_handle, 0, 0, "%.1f")
    if chh then
      ui_handle = math.max(0, math.min(600, hv or 0)); save_settings()
    end
    ImGui.SameLine(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "seconds")
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if toggle_button("Whole File", ui_whole, 94) then ui_whole = not ui_whole; save_settings() end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Keep all the source audio beyond the edges")
    end

    -- Summary
    ImGui.Dummy(ctx, 0, 2)
    local n, text = summary()
    if n == 0 then ImGui.TextColored(ctx, 0xE0A040FF, text) else ImGui.TextDisabled(ctx, text) end
    ImGui.Separator(ctx)

    -- Buttons, right-aligned
    local bw = 86
    local avail = ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, avail - bw * 2 - 8))
    if ImGui.Button(ctx, "Cancel", bw, 0) then result = "cancel" end
    ImGui.SameLine(ctx)
    if render_button("Render", bw, n > 0) then result = "render" end

    -- Keys (not while typing in the handle field)
    if not ImGui.IsAnyItemActive(ctx) then
      if n > 0 and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)) then
        result = "render"
      end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then result = "cancel" end

    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, 6)
  ImGui.PopFont(ctx)
  first_frame = false
  if not open then result = "cancel" end
end

local function do_render()
  save_settings()
  handle, whole, continuous = ui_handle, ui_whole, (ui_mode == 0)
  local short = run_glue()
  if short and short > 0 then
    reaper.ShowMessageBox(short .. " glued item(s) got shorter handles than " .. fmt_secs(handle) ..
      " s on one side, because the source audio (or the project start) doesn't reach that far.", TITLE, 0)
  end
end

local function loop()
  frame()
  if result == "render" then do_render() return end
  if result == "cancel" then return end
  reaper.defer(loop)
end

reaper.defer(loop)
