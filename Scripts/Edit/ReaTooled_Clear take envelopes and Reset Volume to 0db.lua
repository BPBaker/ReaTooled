-- @description Clear Take Envelopes & Reset Item/Take Volume to 0dB
-- @version 1.0
-- @date 2026.03.17
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
-- Clears all take envelopes and resets item and take volume to 0.0dB
-- for all selected items / takes.

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local item_count = reaper.CountSelectedMediaItems(0)

if item_count == 0 then
  reaper.ShowMessageBox("No items selected. Please select one or more items and try again.", "Clear Take Envelopes & Reset Volume", 0)
else
  local processed_items  = 0
  local processed_takes  = 0
  local processed_envs   = 0

  for i = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    if item then
      -- Reset item volume to 1.0 (0 dB)
      reaper.SetMediaItemInfo_Value(item, "D_VOL", 1.0)

      local take_count = reaper.CountTakes(item)
      for t = 0, take_count - 1 do
        local take = reaper.GetTake(item, t)
        if take then
          -- Reset take volume to 1.0 (0 dB)
          reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", 1.0)

          -- Clear all take envelopes
          local env_count = reaper.CountTakeEnvelopes(take)
          -- Iterate in reverse so indices stay valid as we clear points
          for e = env_count - 1, 0, -1 do
            local env = reaper.GetTakeEnvelope(take, e)
            if env then
              local point_count = reaper.CountEnvelopePoints(env)
              if point_count > 0 then
                reaper.DeleteEnvelopePointRange(env, -math.huge, math.huge)
                reaper.Envelope_SortPoints(env)
                processed_envs = processed_envs + 1
              end
            end
          end

          processed_takes = processed_takes + 1
        end
      end

      processed_items = processed_items + 1
    end
  end

  reaper.UpdateArrange()
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Clear Take Envelopes & Reset Volume to 0dB", -1)

--  local msg = string.format(
--    "Done!\n\nItems processed:  %d\nTakes processed:  %d\nEnvelopes cleared: %d",
--    processed_items, processed_takes, processed_envs
--  )
--  reaper.ShowMessageBox(msg, "Clear Take Envelopes & Reset Volume", 0)
--  return
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Clear Take Envelopes & Reset Volume to 0dB", -1)
