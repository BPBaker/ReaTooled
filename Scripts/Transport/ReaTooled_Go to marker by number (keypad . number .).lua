-- @description ReaTooled - Go to marker by number (keypad . number .)
-- @version 1.1
-- @date 2026.10.25
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Pro Tools-style memory location recall with REAPER markers
--   Map this to the numeric keypad's "." key. Press [.], type a marker number,
--   then press [.] or Enter: the edit cursor (and playback, if playing) jumps
--   to that marker. If there's no marker with that number, the region with that
--   number is selected (time selection, cursor at its start), like recalling a
--   Pro Tools "selection" memory location.
--   While the window is open, [+] and [-] step to the next and previous marker
--   or region, and the window stays open so you can keep stepping (like
--   Pro Tools' [.] [+] / [.] [-]).
--   As you type, the window shows the marker's name, or says right away that
--   there's no such number. Uses REAPER's own marker and region numbers, so it
--   works in any project.
--   Esc cancels, Backspace deletes a digit. The window closes by itself after a
--   few seconds without a key press, or when you click somewhere else.
--   Needs ReaImGui (installed with ReaTooled).
-- @changelog
--   v1.1 New window in the ReaTooled style; + and - step to next/previous marker or region;
--        shows the marker name while you type; tells markers and regions apart;
--        stays open longer while you're stepping
--   v1.0 Initial version

local TITLE = "Go to Marker"
local TIMEOUT = 4        -- seconds without a key press before the window closes
local TIMEOUT_NAV = 10   -- ... while stepping with + / -
local MAX_NAME = 30

if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox("This script needs ReaImGui. Install it with ReaPack (Extensions > ReaPack > Browse packages > ReaImGui), then restart REAPER.", TITLE, 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"

------------------------------------------------------------
-- Markers and regions
------------------------------------------------------------

-- All markers and regions, in time order
local function locations()
  local list, i = {}, 0
  while true do
    local ok, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers3(0, i)
    if ok == 0 then break end
    list[#list + 1] = { isrgn = isrgn, pos = pos, rgnend = rgnend, name = name or "", num = idx }
    i = i + 1
  end
  table.sort(list, function(a, b)
    if math.abs(a.pos - b.pos) > 1e-9 then return a.pos < b.pos end
    if a.isrgn ~= b.isrgn then return not a.isrgn end   -- marker first
    return a.num < b.num
  end)
  return list
end

-- Marker with that number first; otherwise the region with that number
local function find(num)
  local list = locations()
  for _, l in ipairs(list) do if not l.isrgn and l.num == num then return l end end
  for _, l in ipairs(list) do if l.isrgn and l.num == num then return l end end
end

local function go(l)
  if l.isrgn then
    reaper.GetSet_LoopTimeRange(true, false, l.pos, l.rgnend, false)   -- select the region
  end
  reaper.SetEditCurPos(l.pos, true, true)   -- move view, and playback if playing
end

local function describe(l)
  local name = l.name
  if #name > MAX_NAME then name = name:sub(1, MAX_NAME - 1) .. "…" end
  local kind = l.isrgn and "Region " or "Marker "
  if name == "" then return kind .. l.num end
  return kind .. l.num .. "  ·  " .. name
end

------------------------------------------------------------
-- State
------------------------------------------------------------

local digits = ""
local status, status_kind = nil, nil   -- kind: "ok" | "bad" | "info"
local nav_mode = false
local nav_idx = nil                    -- index in locations() we last stepped to
local last_key = reaper.time_precise()
local done = false
local ever_focused = false

local function set_status(text, kind) status, status_kind = text, kind end

local function preview()
  if digits == "" then set_status(nil) return end
  local l = find(tonumber(digits))
  if l then set_status(describe(l), "ok")
  else set_status("No marker or region " .. digits, "bad") end
end

local function confirm()
  if digits == "" then done = true return end
  local l = find(tonumber(digits))
  if l then go(l); done = true return end
  set_status("No marker or region " .. digits, "bad")
  digits = ""
end

local function step(dir)
  digits = ""
  local list = locations()
  if #list == 0 then set_status("This project has no markers", "bad") return end
  local target
  if nav_idx and list[nav_idx] then
    target = nav_idx + dir
  else
    local playing = (reaper.GetPlayState() & 1) == 1
    local cur = playing and reaper.GetPlayPosition() or reaper.GetCursorPosition()
    if dir > 0 then
      for i = 1, #list do if list[i].pos > cur + 1e-6 then target = i break end end
    else
      for i = #list, 1, -1 do if list[i].pos < cur - 1e-6 then target = i break end end
    end
  end
  if not target or target < 1 or target > #list then
    set_status(dir > 0 and "No more markers after this" or "No more markers before this", "info")
    return
  end
  nav_idx, nav_mode = target, true
  go(list[target])
  set_status(describe(list[target]), "ok")
end

------------------------------------------------------------
-- Window (same look as the other ReaTooled windows)
------------------------------------------------------------

local ctx = ImGui.CreateContext(TITLE)
local font = ImGui.CreateFont("sans-serif", 14)
local font_b = ImGui.CreateFont("sans-serif", 15, ImGui.FontFlags_Bold)
local font_big = ImGui.CreateFont("sans-serif", 26, ImGui.FontFlags_Bold)
ImGui.Attach(ctx, font); ImGui.Attach(ctx, font_b); ImGui.Attach(ctx, font_big)

local C_ACCENT = 0x2F7FD6FF
local C_OK     = 0x8FC3FFFF
local C_BAD    = 0xE5605AFF
local C_FIELD  = 0x00000040
local W = 270

local first_frame = true

local function handle_keys()
  local any = false
  local i = 0
  while true do
    local ok, c = ImGui.GetInputQueueCharacter(ctx, i)
    if not ok then break end
    i = i + 1
    any = true
    if c >= 48 and c <= 57 then                 -- 0-9 (keypad or main keys)
      if #digits < 4 then digits = digits .. string.char(c) end
      nav_mode, nav_idx = false, nil
      preview()
    elseif c == 46 then                         -- "."
      confirm()
    elseif c == 43 or c == 61 then              -- "+" (or "=" on the main keys)
      step(1)
    elseif c == 45 then                         -- "-"
      step(-1)
    end
    if done then return true end
  end
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter) then
    any = true; confirm()
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Backspace) then
    any = true; digits = digits:sub(1, -2); preview()
  elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    done = true
  end
  return any
end

local function frame()
  ImGui.PushFont(ctx, font)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 14, 12)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8, 6)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 6)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 1)

  if first_frame then
    local mx, my = reaper.GetMousePosition()
    mx, my = ImGui.PointConvertNative(ctx, mx, my, false)
    ImGui.SetNextWindowPos(ctx, mx + 12, my + 12, ImGui.Cond_Appearing)
    ImGui.SetNextWindowFocus(ctx)
  end

  local flags = ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoCollapse |
                ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoDocking |
                ImGui.WindowFlags_NoScrollbar
  local visible, open = ImGui.Begin(ctx, TITLE, true, flags)
  if visible then
    if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) then
      ever_focused = true
      if handle_keys() then last_key = reaper.time_precise() end
    elseif ever_focused then
      done = true      -- clicked somewhere else
    end

    -- Header
    ImGui.PushFont(ctx, font_b)
    ImGui.Text(ctx, nav_mode and "Step Through Markers" or "Go to Marker")
    ImGui.PopFont(ctx)
    ImGui.SameLine(ctx)
    local tw = ImGui.CalcTextSize(ctx, "ReaTooled")
    ImGui.SetCursorPosX(ctx, W - 14 - tw)
    ImGui.TextDisabled(ctx, "ReaTooled")
    ImGui.Separator(ctx)

    -- Number field
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, C_FIELD)
    if ImGui.BeginChild(ctx, "##field", W - 28, 44, ImGui.ChildFlags_None or 0) then
      ImGui.PushFont(ctx, font_big)
      local blink = (math.floor(reaper.time_precise() * 2) % 2 == 0) and "_" or " "
      local text = nav_mode and "+ / -" or (digits .. blink)
      if not nav_mode and digits == "" then text = blink end
      local w, h = ImGui.CalcTextSize(ctx, text)
      ImGui.SetCursorPos(ctx, 12, (44 - h) / 2)
      if nav_mode then ImGui.TextDisabled(ctx, text) else ImGui.Text(ctx, text) end
      ImGui.PopFont(ctx)
      ImGui.EndChild(ctx)
    end
    ImGui.PopStyleColor(ctx)

    -- Status line: what you'll get
    if status then
      local col = (status_kind == "bad") and C_BAD or (status_kind == "ok") and C_OK or nil
      if col then ImGui.TextColored(ctx, col, status) else ImGui.TextDisabled(ctx, status) end
    else
      ImGui.TextDisabled(ctx, "Type a marker or region number")
    end

    -- Key hints
    ImGui.Dummy(ctx, 0, 2)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x8A8A8AFF)
    ImGui.Text(ctx, ". / Enter  go     + / -  step     Esc  close")
    ImGui.PopStyleColor(ctx)
    ImGui.Dummy(ctx, W - 28, 0)

    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, 5)
  ImGui.PopFont(ctx)

  if first_frame and reaper.JS_Window_Find and reaper.JS_Window_SetFocus then
    local hwnd = reaper.JS_Window_Find(TITLE, true)
    if hwnd then reaper.JS_Window_SetFocus(hwnd) end
  end
  first_frame = false
  if not open then done = true end
end

local function loop()
  frame()
  local limit = nav_mode and TIMEOUT_NAV or TIMEOUT
  if not done and reaper.time_precise() - last_key > limit then done = true end
  if done then
    if reaper.JS_Window_SetFocus then reaper.JS_Window_SetFocus(reaper.GetMainHwnd()) end
    return
  end
  reaper.defer(loop)
end

reaper.defer(loop)
