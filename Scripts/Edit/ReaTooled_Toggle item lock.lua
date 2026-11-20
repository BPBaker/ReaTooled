--[[
@description ReaTooled - Toggle item lock
@version 1.0
@author Brendan Baker
@website https://brendanpatrickbaker.com/reatooled/
@about
  Based on TJF Toggle Item Lock by Tim Farrell.
  # Toggle item lock
  Locks or unlocks the selected items, like Pro Tools' Cmd+L.
  If any selected item is unlocked, all of them are locked; if all of them are
  already locked, all of them are unlocked. So a mixed selection always ends up
  the same way, and pressing the key again undoes it.
@changelog
  v1.0 ReaTooled's own version, replacing TJF Toggle Item Lock (matches first item):
       a mixed selection is locked (not matched to the first item), and the
       change has its own undo point.
--]]

local n = reaper.CountSelectedMediaItems(0)
if n == 0 then return reaper.defer(function() end) end   -- nothing to do, no undo point

local items, lock = {}, 0
for i = 0, n - 1 do
  local it = reaper.GetSelectedMediaItem(0, i)
  items[#items + 1] = it
  if (math.floor(reaper.GetMediaItemInfo_Value(it, "C_LOCK")) & 1) == 0 then lock = 1 end
end

reaper.Undo_BeginBlock()
for _, it in ipairs(items) do
  reaper.SetMediaItemInfo_Value(it, "C_LOCK", lock)
end
reaper.UpdateArrange()
reaper.Undo_EndBlock(lock == 1 and "Lock items" or "Unlock items", 4)
