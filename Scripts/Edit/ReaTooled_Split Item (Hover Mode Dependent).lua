-- @description ReaTooled Split Item Smart (Precise Time Selection Logic)
-- @version 1.6
-- @date 2025.04.24
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
--   # Split at time selection only if strictly smaller than selection, or nothing selected
--   - Otherwise, split at cursor or mouse depending on Hover Mode
--   - Includes debug logging

-- ===== DEBUG CONFIG =====
local debug = false
-- ========================

if debug then reaper.ClearConsole() end
local function log(msg)
  if debug then reaper.ShowConsoleMsg(tostring(msg) .. "\n") end
end

reaper.Undo_BeginBlock()

local proj = 0
local start_time, end_time = reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)
local use_time_selection = false

local selected_count = reaper.CountSelectedMediaItems(0)
local margin = 0.0001

-- Case 1: No selection, use time selection to split everything
if selected_count == 0 and start_time ~= end_time then
  log("🔹 No items selected. Time selection will split all items.")
  use_time_selection = true
end

-- Case 2: Time selection is strictly inside selected item range
if selected_count > 0 and start_time ~= end_time then
  local sel_start = math.huge
  local sel_end = -math.huge

  for i = 0, selected_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    sel_start = math.min(sel_start, pos)
    sel_end = math.max(sel_end, pos + len)
  end

  log(string.format("🔸 Time Sel: %.5f - %.5f | Sel Bounds: %.5f - %.5f", start_time, end_time, sel_start, sel_end))

  if start_time > sel_start + margin and end_time < sel_end - margin then
    log("✅ Time selection is fully inside item selection. Splitting selected items at time selection.")
    use_time_selection = true
  else
    log("⚠ Time selection not fully inside selected items — ignoring.")
  end
end

-- === SPLITTING ACTION ===

if use_time_selection then
  reaper.Main_OnCommand(40061, 0) -- Item: Split items at time selection
else
  local cmd_id = reaper.NamedCommandLookup("_RS7cb08a92f7a211ce66734644b4fbe99a91bd42f5") -- Hover Mode toggle
  local state = reaper.GetToggleCommandStateEx(0, cmd_id)
  local hover_mode = (state == 1)

  log("🎛 Hover Mode: " .. (hover_mode and "ON" or "OFF"))

  if hover_mode then
    local current_pos = reaper.GetCursorPosition()
    reaper.BR_GetMouseCursorContext()
    local item = reaper.BR_GetMouseCursorContext_Item()
    local mouse_pos = reaper.BR_GetMouseCursorContext_Position()

    log("🖱 Mouse Position: " .. mouse_pos)
    if item then
      local is_selected = reaper.IsMediaItemSelected(item)
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      log("🎯 Hovered Item: Start=" .. item_pos .. ", Len=" .. item_len)
      log("🔍 Hovered Item Selected: " .. tostring(is_selected))

      if not is_selected then
        log("✂️ Splitting hovered item only.")
        reaper.Main_OnCommand(42575, 0)
      else
        log("✂️ Splitting all selected items at mouse.")
        reaper.SetEditCurPos(mouse_pos, false, false)
        reaper.Main_OnCommand(40759, 0)
        reaper.SetEditCurPos(current_pos, false, false)
      end
    else
      log("⚠ Hover Mode ON but no item under mouse.")
    end
  else
    log("✂️ Hover Mode OFF: Splitting selected items at edit cursor.")
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SMARTSPLIT"), 0)
  end
end

reaper.Undo_EndBlock("Smart Split Item(s)", -1)

