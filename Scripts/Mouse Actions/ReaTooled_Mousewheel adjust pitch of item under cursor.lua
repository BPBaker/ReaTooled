-- @description Adjust Item Pitch by Mousewheel (ReaTooled Compatible)
-- @version 1.1
-- @author Brendan
-- @link https://brendanpatrickbaker.com/reatooled/
-- @changelog
--   + v1.1 Added support for ReaTooled inversion ExtState
--   + Initial pitch shift via hovered item or selected items
-- @about
--   Adjusts pitch of item takes using the mousewheel.
--   Uses REAPER's native pitch shifting API.
--   Direction is invertible via ReaTooled inversion toggle script.

-- ========== CONFIG ==========
local speed = 1           -- How many "steps" to apply per scroll
local pshift = 0.1        -- Pitch shift amount per full scroll bump
local selected_items = true -- Apply to selected items if nothing under mouse

-- ========== NORMALIZE SCROLL DELTA ==========
local _, _, _, _, _, _, val = reaper.get_action_context()
if not val or val == 0 then return end

-- Apply ReaTooled inversion (ExtState: WheelInvert)
local invert = tonumber(reaper.GetExtState("ReaTooled", "WheelInvert")) or 0
if invert == 1 then val = -val end

-- ========== MAIN FUNCTION ==========
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local pitch_delta = (val < 0 and -pshift or pshift) / 2

for s = 1, speed + 1 do
  local item, _ = reaper.BR_ItemAtMouseCursor()
  if item then
    local take = reaper.GetActiveTake(item)
    if take then
      local pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
      reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", pitch + pitch_delta)
      reaper.UpdateItemInProject(item)
    end
  elseif selected_items then
    local num_sel = reaper.CountSelectedMediaItems(0)
    for i = 0, num_sel - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local take = reaper.GetActiveTake(item)
      if take then
        local pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH")
        reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", pitch + pitch_delta)
        reaper.UpdateItemInProject(item)
      end
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Mousewheel Adjust Take Pitch", -1)
