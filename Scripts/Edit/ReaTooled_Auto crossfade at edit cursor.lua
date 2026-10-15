 -- @description ReaTooled - Convert Butt Joint to Centered Crossfade
 -- @version 1.0
 -- @date 2025.05.07
 -- @author Brendan Baker
 -- @link https://brendanpatrickbaker.com/reatooled/
 -- @about
 --   Converts an existing butt joint at the edit cursor into a centered crossfade
 --   using REAPER's default crossfade length.
 --   WARNING: This necessarily modifies item boundaries (by design).
 
 local EPS = 1e-9
 
 -------------------------------------------------------
 -- Helpers
 -------------------------------------------------------
 
 local function get_default_xfade_len()
   -- Prefer split crossfade length (often ms)
   local ok, v = reaper.get_config_var_string("defsplitxfadelen")
   local n = ok and tonumber(v) or nil
   if n and n > 0 then
     if n > 10 then return n / 1000 end -- assume ms
     return n
   end
 
   -- Fallback: general fade length (seconds)
   ok, v = reaper.get_config_var_string("deffadelen")
   n = ok and tonumber(v) or nil
   if n and n > 0 then return n end
 
   return 0
 end
 
 local function get_pos_len_end(item)
   local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
   local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
   return pos, len, pos + len
 end
 
 local function nearly(a, b)
   return math.abs(a - b) <= EPS
 end
 
 -------------------------------------------------------
 -- Main
 -------------------------------------------------------
 
 reaper.Undo_BeginBlock()
 
 local cursor = reaper.GetCursorPosition()
 local xfade_len = get_default_xfade_len()
 
 if xfade_len <= 0 then
   reaper.Undo_EndBlock("ReaTooled - No default crossfade length", -1)
   return
 end
 
 local half = xfade_len * 0.5
 local did_any = false
 
 local track_count = reaper.CountTracks(0)
 for ti = 0, track_count - 1 do
   local tr = reaper.GetTrack(0, ti)
 
   local left, right = nil, nil
   local item_count = reaper.CountTrackMediaItems(tr)
 
   for i = 0, item_count - 1 do
     local it = reaper.GetTrackMediaItem(tr, i)
     local pos, len, fin = get_pos_len_end(it)
 
     if nearly(fin, cursor) then left = it end
     if nearly(pos, cursor) then right = it end
   end
 
   if left and right and left ~= right then
     local lpos, llen, lend = get_pos_len_end(left)
     local rpos, rlen, rend = get_pos_len_end(right)
 
     -- safety: confirm true butt joint
     if nearly(lend, rpos) then
       local take = reaper.GetActiveTake(right)
       if take then
         local startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
 
         -- Extend left
         reaper.SetMediaItemInfo_Value(left, "D_LENGTH", llen + half)
 
         -- Move right earlier, compensate take offset
         reaper.SetMediaItemInfo_Value(right, "D_POSITION", rpos - half)
         reaper.SetMediaItemInfo_Value(right, "D_LENGTH", rlen + half)
         reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", startoffs + half)
 
         -- Apply fades
         reaper.SetMediaItemInfo_Value(left,  "D_FADEOUTLEN", xfade_len)
         reaper.SetMediaItemInfo_Value(right, "D_FADEINLEN",  xfade_len)
         reaper.SetMediaItemInfo_Value(left,  "C_FADEOUTSHAPE", 1)
         reaper.SetMediaItemInfo_Value(right, "C_FADEINSHAPE",  1)
 
         did_any = true
       end
     end
   end
 end
 
 reaper.UpdateArrange()
 
 local name = "ReaTooled - Convert Butt Joint to Centered Crossfade"
 if not did_any then name = name .. " (no butt joint at cursor)" end
 reaper.Undo_EndBlock(name, -1)
