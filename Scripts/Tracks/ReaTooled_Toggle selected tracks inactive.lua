-- @description ReaTooled - Toggle selected tracks inactive (like Pro Tools "Make Inactive")
-- @version 1.0
-- @date 2026.10.26
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Make tracks inactive and active again, like Pro Tools
--   Works on the selected tracks, or the track under the mouse if none are selected.
--   Making a track inactive sets all its FX offline (track FX and input FX, which
--   frees their CPU and memory), mutes it (which silences its sends too), disarms
--   recording and turns the track grey. Running it again puts everything back
--   exactly as it was: FX that were already offline stay offline, and the track's
--   mute, record arm and colour come back.
--   Only REAPER's own track settings are used, so the project stays a normal REAPER
--   project. Without ReaTooled, an inactive track simply looks muted and grey with
--   its FX offline.
--   If some of the tracks are inactive and some aren't, all of them are made
--   active. The track stays visible; hide it as usual if you want.
-- @changelog
--   v1.0 Initial version

local TITLE = "Toggle tracks inactive"
local KEY = "P_EXT:ReaTooled_Inactive"
local GREY = reaper.ColorToNative(88, 88, 88) | 0x1000000
local REC_FX = 0x1000000

------------------------------------------------------------
-- Which tracks
------------------------------------------------------------

local tracks = {}
for i = 0, reaper.CountSelectedTracks(0) - 1 do
  tracks[#tracks + 1] = reaper.GetSelectedTrack(0, i)
end
if #tracks == 0 then
  local x, y = reaper.GetMousePosition()
  local tr = reaper.GetTrackFromPoint(x, y)
  if tr and tr ~= reaper.GetMasterTrack(0) then tracks[1] = tr end
end
if #tracks == 0 then
  reaper.ShowMessageBox("Select the tracks to make inactive (or point the mouse at one).", TITLE, 0)
  return
end

------------------------------------------------------------
-- Saved state: "mute=0;arm=1;color=16777216;fx=0,1;rfx=0"
------------------------------------------------------------

local function get_state(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, KEY, "", false)
  if not ok or s == "" then return nil end
  local st = {}
  for k, v in s:gmatch("(%w+)=([^;]*)") do st[k] = v end
  return st
end

local function set_state(tr, s)
  reaper.GetSetMediaTrackInfo_String(tr, KEY, s or "", true)
end

local function flags(tr, count, base)
  local t = {}
  for i = 0, count - 1 do t[#t + 1] = reaper.TrackFX_GetOffline(tr, base + i) and "1" or "0" end
  return table.concat(t, ",")
end

local function split(s)
  local t = {}
  for v in (s or ""):gmatch("[^,]+") do t[#t + 1] = (v == "1") end
  return t
end

------------------------------------------------------------
-- Make inactive / active
------------------------------------------------------------

local function make_inactive(tr)
  if get_state(tr) then return end   -- already inactive
  local nfx, nrfx = reaper.TrackFX_GetCount(tr), reaper.TrackFX_GetRecCount(tr)
  set_state(tr, string.format("mute=%d;arm=%d;color=%d;fx=%s;rfx=%s",
    math.floor(reaper.GetMediaTrackInfo_Value(tr, "B_MUTE")),
    math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_RECARM")),
    math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")),
    flags(tr, nfx, 0), flags(tr, nrfx, REC_FX)))
  for i = 0, nfx - 1 do reaper.TrackFX_SetOffline(tr, i, true) end
  for i = 0, nrfx - 1 do reaper.TrackFX_SetOffline(tr, REC_FX + i, true) end
  reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 1)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
  reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", GREY)
end

local function make_active(tr)
  local st = get_state(tr)
  if not st then return end
  local fx, rfx = split(st.fx), split(st.rfx)
  -- FX added while inactive come back online
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    reaper.TrackFX_SetOffline(tr, i, fx[i + 1] == true)
  end
  for i = 0, reaper.TrackFX_GetRecCount(tr) - 1 do
    reaper.TrackFX_SetOffline(tr, REC_FX + i, rfx[i + 1] == true)
  end
  reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", tonumber(st.mute) or 0)
  reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", tonumber(st.arm) or 0)
  -- keep a colour the user picked while the track was inactive
  if math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")) == GREY then
    reaper.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", tonumber(st.color) or 0)
  end
  set_state(tr, "")
end

------------------------------------------------------------
-- Toggle: if any track is inactive, make them all active
------------------------------------------------------------

local any_inactive = false
for _, tr in ipairs(tracks) do
  if get_state(tr) then any_inactive = true break end
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
for _, tr in ipairs(tracks) do
  if any_inactive then make_active(tr) else make_inactive(tr) end
end
reaper.PreventUIRefresh(-1)
reaper.TrackList_AdjustWindows(false)
reaper.UpdateArrange()
reaper.Undo_EndBlock(any_inactive and "Make tracks active" or "Make tracks inactive", -1)
