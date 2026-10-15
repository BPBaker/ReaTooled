-- REAPER ReaImGui Nudge Parameter Box (Dockable GUI)
-- Stores editable numeric nudge value + unit selector into ExtState
-- Requires ReaImGui v0.9.3.3

local ctx = reaper.ImGui_CreateContext('Smart Nudge Param Box')
local FONT = reaper.ImGui_CreateFont('sans-serif', 10)
reaper.ImGui_Attach(ctx, FONT)

-- ExtState identifiers
local EXT_SECTION = "ReaTooled"
local EXT_KEY_VAL = "nudge_val"
local EXT_KEY_UNIT = "nudge_unit"

-- Load saved state
local nudge_val = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_VAL)) or 10.0
local unit_index = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_UNIT)) or 0

-- Units list, matching REAPER's Nudge dialog
local units = {
  'Milliseconds',       -- 0
  'Seconds',            -- 1 (displayed as Minutes:Seconds in REAPER)
  'Grid Units',         -- 2
  'Measures.Beats',     -- 3
  'Samples',            -- 4
  'Frames',             -- 5
  'Pixels',             -- 6
  'Item lengths',       -- 7
  'Item selections',    -- 8
  'Notes'               -- 9
}

local function show_units_popup()
  if reaper.ImGui_BeginPopup(ctx, 'unit_popup') then
    local new_index = unit_index
    for i, name in ipairs(units) do
      if reaper.ImGui_Selectable(ctx, name, i-1 == unit_index) then
        new_index = i - 1
      end
    end
    if new_index ~= unit_index then
      unit_index = new_index
      reaper.SetExtState(EXT_SECTION, EXT_KEY_UNIT, tostring(unit_index), true)
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

function Main()
  reaper.ImGui_PushFont(ctx, FONT)
  local visible, open = reaper.ImGui_Begin(ctx, 'Smart Nudge Param Box', true,
    reaper.ImGui_WindowFlags_NoCollapse() |
    reaper.ImGui_WindowFlags_AlwaysAutoResize() |
    reaper.ImGui_WindowFlags_NoScrollbar())

  if visible then
    if reaper.ImGui_Button(ctx, 'Nudge') or reaper.ImGui_IsItemClicked(ctx, 1) then
      reaper.ImGui_OpenPopup(ctx, 'unit_popup')
    end
    reaper.ImGui_SameLine(ctx)

    local changed_val
    local text_width = ({reaper.ImGui_CalcTextSize(ctx, "00000000")})[1]
    reaper.ImGui_SetNextItemWidth(ctx, text_width)
    changed_val, nudge_val = reaper.ImGui_InputDouble(ctx, '##nudge_val', nudge_val, 0, 0, '%.0f')
    if reaper.ImGui_IsItemClicked(ctx, 1) then
      reaper.ImGui_OpenPopup(ctx, 'unit_popup')
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, 'v') or reaper.ImGui_IsItemClicked(ctx, 1) then
      reaper.ImGui_OpenPopup(ctx, 'unit_popup')
    end

    show_units_popup()

    if changed_val then
      reaper.SetExtState(EXT_SECTION, EXT_KEY_VAL, tostring(nudge_val), true)
    end

    reaper.ImGui_End(ctx)
  end

  reaper.ImGui_PopFont(ctx)
  if open then
    reaper.defer(Main)
  else
    reaper.ImGui_DestroyContext(ctx)
  end
end

reaper.defer(Main)

