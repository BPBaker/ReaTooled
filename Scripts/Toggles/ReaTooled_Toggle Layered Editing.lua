--[[
@description ReaTooled - Layered Editing (inverse of 41117, synced)
@version 1.1
@about
  - Uses native action 41117 as the underlying option.
  - Toolbar button shows the INVERSE of 41117:
      * Button ON  when 41117 is OFF
      * Button OFF when 41117 is ON
  - Button state stays in sync even if 41117 is changed elsewhere.
  - Uses the same was_set / set_action_options pattern as the mouse-modifier script.
]]

local r = reaper

local NATIVE_TOGGLE = 41117
local was_set = -1  -- last known "button should be ON" state

local function UpdateState()
  -- Read real state of 41117
  local native_state = r.GetToggleCommandState(NATIVE_TOGGLE)  -- 0 / non-zero

  -- Define when your script's button should be ON:
  -- Button ON when 41117 is OFF  → adjust this condition if needed
  local is_set = (native_state == 0)

  if is_set ~= was_set then
    was_set = is_set
    -- 3 = (1|2): kill previous instance + relaunch
    -- 4: script toggle ON, 8: script toggle OFF
    r.set_action_options(3 | (is_set and 4 or 8))
    -- Refresh all toolbars to show the new state
    r.RefreshToolbar2(0, 0)
  end

  r.defer(UpdateState)
end

-- Toggle 41117 once when this script is invoked (toolbar click, shortcut, etc.)
r.Main_OnCommand(NATIVE_TOGGLE, 0)

-- Start state tracking
UpdateState()