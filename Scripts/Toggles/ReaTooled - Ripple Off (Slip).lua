--[[
@description ReaTooled - Ripple OFF indicator (button ON when ripple OFF)
@version 1.2
@about
  - Clicking this button always runs "Ripple edit mode: OFF" (40309).
  - The button then stays synced as an indicator:
      * Button ON  when Ripple is OFF
      * Button OFF when Ripple per-track or Ripple all-tracks is enabled
  - Uses the same was_set / set_action_options pattern as your mouse-modifier script.
]]

local r = reaper

local RIPPLE_OFF       = 40309  -- Ripple edit mode off
local RIPPLE_PER_TRACK = 40310  -- Ripple editing per-track
local RIPPLE_ALL       = 40311  -- Ripple editing all tracks

local was_set = -1  -- last "button should be ON" state

local function UpdateState()
  -- Ripple is OFF when the "Ripple edit off" action reports ON
  local ripple_off = (r.GetToggleCommandState(RIPPLE_OFF) == 1)

  -- Button ON when ripple is OFF
  local is_set = ripple_off

  if is_set ~= was_set then
    was_set = is_set
    -- 3 = (1|2): kill previous instance + relaunch
    -- 4: script toggle ON, 8: script toggle OFF
    r.set_action_options(3 | (is_set and 4 or 8))
    -- Refresh all toolbars so every copy of this button updates
    r.RefreshToolbar2(0, 0)
  end

  r.defer(UpdateState)
end

-- When the script is invoked (toolbar click / shortcut),
-- force ripple OFF once. If it's already off, this is a no-op.
r.Main_OnCommand(RIPPLE_OFF, 0)

-- Start the indicator/watch loop
UpdateState()