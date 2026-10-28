-- @description ReaTooled - Pencil click on item (add a clip gain point)
-- @version 1.0
-- @date 2026.10.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Used by the Pencil Tool for clicks on items. Adds a point at the mouse to the
--   item's take volume envelope (ReaTooled's clip gain), on the current line, so
--   it can then be dragged or drawn through. Creates and shows the envelope if
--   the take doesn't have one yet. Follows snap.
-- @changelog
--   v1.0 Initial version

if not reaper.BR_GetMouseCursorContext then
  reaper.ShowMessageBox("The Pencil Tool needs the SWS extension.", "ReaTooled", 0)
  return
end

reaper.BR_GetMouseCursorContext()
local item = reaper.BR_GetMouseCursorContext_Item()
local take = reaper.BR_GetMouseCursorContext_Take()
local pos  = reaper.BR_GetMouseCursorContext_Position()
if not item or not take or pos < 0 then return end
if take ~= reaper.GetActiveTake(item) then return end      -- only the take that plays
if reaper.TakeIsMIDI(take) then return end                  -- MIDI: use the MIDI editor

if reaper.GetToggleCommandState(1157) == 1 then pos = reaper.SnapToGrid(0, pos) end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Make sure the take has a visible volume envelope
local env = reaper.GetTakeEnvelopeByName(take, "Volume")
if not env then
  -- "Take: Toggle take volume envelope" works on the selected items:
  -- select only this one for a moment
  local sel = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = reaper.GetSelectedMediaItem(0, i) end
  reaper.SelectAllMediaItems(0, false)
  reaper.SetMediaItemSelected(item, true)
  reaper.Main_OnCommand(40693, 0)   -- Take: Toggle take volume envelope
  reaper.SetMediaItemSelected(item, false)
  for _, it in ipairs(sel) do reaper.SetMediaItemSelected(it, true) end
  env = reaper.GetTakeEnvelopeByName(take, "Volume")
end

if env then
  -- Envelope time is relative to the take, at its playrate
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  pos = math.max(item_pos, math.min(item_pos + item_len, pos))
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local t = (pos - item_pos) * rate
  local _, value = reaper.Envelope_Evaluate(env, t, 0, 0)
  reaper.InsertEnvelopePoint(env, t, value, 0, 0, false, true)
  reaper.Envelope_SortPoints(env)
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock("Pencil: add clip gain point", -1)
