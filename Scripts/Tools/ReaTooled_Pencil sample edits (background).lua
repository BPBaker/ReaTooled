-- @description ReaTooled - Pencil sample edits (background, started by the Pencil Tool)
-- @version 1.1
-- @date 2026.10.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   Runs only while the Pencil Tool is selected, and stops when another tool is
--   chosen. When you're zoomed in far enough to draw samples and the mouse is over
--   an audio item whose sample edits are off (bypassed, or never turned on), it
--   turns them on for that item only, so the Pencil can draw on it. Every other
--   item is left as it is.
--   Zoomed in that far, every take envelope on screen (volume, pan, pitch, take FX
--   automation) is hidden, so you only see the samples you're drawing. They still
--   play. They're shown again when you zoom back out or choose another tool (and
--   the next time the Pencil starts, if REAPER quit while they were hidden).
--   Envelopes you had hidden yourself stay hidden.
-- @changelog
--   v1.1 Hides take envelopes while zoomed in to sample level; starts at the zoom
--        level where REAPER lets you edit samples (about 1.36 pixels per sample)
--   v1.0 Initial version

local NS = "ReaTooled"
local PENCIL_KEY = "PencilChanged"            -- set by the Tools library while the Pencil is selected
local HEARTBEAT = "PencilSampleEditsAlive"
-- Where REAPER lets the mouse edit samples: measured in REAPER 7.83, editable
-- from 65463 px/s at 48 kHz = about 1.36 pixels per sample
local ZOOM_RATIO = 1.36

local DEBUG = false   -- true: report what it sees in the REAPER console (testing)
local last_item, last_zoom_ok, last_report = nil, nil, ""
local next_check = 0
local tried = {}   -- items with no sample edits that were already turned on once

local function log(msg)
  if DEBUG and msg ~= last_report then
    reaper.ShowConsoleMsg("Pencil sample edits: " .. msg .. "\n")
    last_report = msg
  end
end

------------------------------------------------------------
-- Take envelopes hidden while zoomed in to sample level
------------------------------------------------------------
local HIDDEN_KEY = "PencilHiddenEnvelopes"   -- GUIDs, saved in case REAPER quits meanwhile
local hidden = {}                            -- envelope -> GUID, hidden by this script
local hiding = false

local function save_hidden()
  local g = {}
  for _, guid in pairs(hidden) do g[#g + 1] = guid end
  if #g > 0 then reaper.SetExtState(NS, HIDDEN_KEY, table.concat(g, " "), true)
  else reaper.DeleteExtState(NS, HIDDEN_KEY, true) end
end

local function visible(env)
  local _, v = reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "", false)
  return v == "1"
end

-- Hide the visible take envelopes of the items on screen
local function hide_on_screen()
  local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local changed = false
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if pos < view_end and pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH") > view_start then
      for t = 0, reaper.CountTakes(item) - 1 do
        local take = reaper.GetTake(item, t)
        if take then
          for e = 0, reaper.CountTakeEnvelopes(take) - 1 do
            local env = reaper.GetTakeEnvelope(take, e)
            if env and not hidden[env] and visible(env) then
              local _, guid = reaper.GetSetEnvelopeInfo_String(env, "GUID", "", false)
              reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "0", true)
              hidden[env] = guid
              changed = true
            end
          end
        end
      end
    end
  end
  if changed then save_hidden(); reaper.UpdateArrange() end
end

-- Show again what this script hid (by pointer, or by GUID after a restart)
local function show_hidden()
  local by_guid = {}
  for g in (reaper.GetExtState(NS, HIDDEN_KEY) or ""):gmatch("%S+") do by_guid[g] = true end
  local any = next(hidden) ~= nil
  for env in pairs(hidden) do
    if reaper.ValidatePtr2(0, env, "TrackEnvelope*") then
      reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "1", true)
    end
    by_guid[hidden[env]] = nil
  end
  if next(by_guid) then   -- left over from before a restart: find them by GUID
    for i = 0, reaper.CountMediaItems(0) - 1 do
      local item = reaper.GetMediaItem(0, i)
      for t = 0, reaper.CountTakes(item) - 1 do
        local take = reaper.GetTake(item, t)
        if take then
          for e = 0, reaper.CountTakeEnvelopes(take) - 1 do
            local env = reaper.GetTakeEnvelope(take, e)
            local _, guid = reaper.GetSetEnvelopeInfo_String(env, "GUID", "", false)
            if by_guid[guid] then reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "1", true); any = true end
          end
        end
      end
    end
  end
  hidden = {}
  reaper.DeleteExtState(NS, HIDDEN_KEY, true)
  if any then reaper.UpdateArrange() end
end

-- Zoomed in to sample level (by the project sample rate)?
local function sample_zoom()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if sr <= 0 then sr = 48000 end
  return reaper.GetHZoomLevel() >= sr * ZOOM_RATIO
end

local function update_hiding()
  if sample_zoom() then
    hide_on_screen()          -- also catches items scrolled into view
    if not hiding then hiding = true; log("zoomed in: take envelopes hidden") end
  elseif hiding then
    hiding = false
    show_hidden()
    log("zoomed out: take envelopes shown again")
  end
end


-- Find the active take's SAMPLEEDITS line in the item's state chunk
-- ("SAMPLEEDITS <active> ..."). Returns the chunk lines, the index of that line
-- and its flag ("0" = bypassed), or nil if the take has no sample edits.
local function find_sample_edits(item)
  local ok, chunk = reaper.GetItemStateChunk(item, "", false)
  if not ok then return nil end
  local want = math.floor(reaper.GetMediaItemInfo_Value(item, "I_CURTAKE"))
  local lines, depth, take, found, flag = {}, 0, 0, nil, nil
  for line in chunk:gmatch("[^\n]+") do
    lines[#lines + 1] = line
    local l = line:match("^%s*(.-)%s*$")
    if l:sub(1, 1) == "<" then
      depth = depth + 1
    elseif l == ">" then
      depth = depth - 1
    elseif depth == 1 and (l == "TAKE" or l:match("^TAKE ")) then
      take = take + 1
    elseif take == want and not found then
      local f = l:match("^SAMPLEEDITS%s+(%d+)")   -- at take level or in its source
      if f then found, flag = #lines, f end
    end
  end
  if not found then return nil end
  return lines, found, flag
end

local function edits_active(item)
  local _, _, flag = find_sample_edits(item)
  if not flag then return nil end
  return flag ~= "0"
end

-- Turn sample edits on for this item only.
-- Bypassed edits: the flag in its state is set back to 1.
-- No sample edits yet: "Take: Toggle sample edits active" (41668) turns them on;
-- it works on the selected items, so this item is selected alone for a moment.
local function enable(item)
  local lines, i = find_sample_edits(item)
  reaper.Undo_BeginBlock()
  if lines then
    lines[i] = lines[i]:gsub("SAMPLEEDITS%s+0", "SAMPLEEDITS 1", 1)
    reaper.SetItemStateChunk(item, table.concat(lines, "\n"), false)
  else
    reaper.PreventUIRefresh(1)
    local sel = {}
    for n = 0, reaper.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = reaper.GetSelectedMediaItem(0, n) end
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(item, true)
    reaper.Main_OnCommand(41668, 0)   -- Take: Toggle sample edits active
    reaper.SetMediaItemSelected(item, false)
    for _, it in ipairs(sel) do reaper.SetMediaItemSelected(it, true) end
    reaper.PreventUIRefresh(-1)
  end
  reaper.Undo_EndBlock("Pencil: sample edits on for item", -1)
  reaper.UpdateArrange()
  log("turned sample edits on" .. (edits_active(item) and "" or " - FAILED, still bypassed"))
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip("Sample edits on for this item", x + 14, y + 14, true)
end

local function check()
  local x, y = reaper.GetMousePosition()
  local item = reaper.GetItemFromPoint(x, y, true)
  if not item then log("no item under the mouse"); return end
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then log("item has no audio take"); return end
  local src = reaper.GetMediaItemTake_Source(take)
  while src and reaper.GetMediaSourceParent(src) do src = reaper.GetMediaSourceParent(src) end
  local sr = src and reaper.GetMediaSourceSampleRate(src) or 0
  if sr <= 0 then sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) end
  if sr <= 0 then sr = 48000 end
  local pps = reaper.GetHZoomLevel()
  local zoom_ok = sr > 0 and pps >= sr * ZOOM_RATIO
  local name = reaper.GetTakeName(take)
  if not zoom_ok then
    log(string.format("%s: not zoomed in enough (%.0f px/s, needs %.0f)", name, pps, sr * ZOOM_RATIO))
    return
  end
  local state = edits_active(item)
  local detail = ""
  if DEBUG then
    local _, chunk = reaper.GetItemStateChunk(item, "", false)
    local se = {}
    for l in chunk:gmatch("[^\n]+") do
      if l:match("SAMPLEEDITS") then se[#se + 1] = l:match("^%s*(.-)%s*$") end
    end
    detail = string.format(" [item at %.3f s, lane %d, take %d of %d, selected %s, lines: %s]",
      reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
      math.floor(reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE")),
      math.floor(reaper.GetMediaItemInfo_Value(item, "I_CURTAKE")) + 1, reaper.CountTakes(item),
      reaper.IsMediaItemSelected(item) and "yes" or "no", #se > 0 and table.concat(se, " | ") or "none")
  end
  log(string.format("%s: zoomed in (%.0f px/s), sample edits %s%s", name, pps,
    state == nil and "not found in the item" or (state and "on" or "bypassed"), detail))
  if state == false then
    enable(item)                      -- bypassed: back on
  elseif state == nil and not tried[item] then
    tried[item] = true                -- none yet: turn on once (never toggled twice)
    enable(item)
  end
end

local function loop()
  if reaper.GetExtState(NS, PENCIL_KEY) ~= "1" then   -- another tool was chosen
    show_hidden()
    reaper.DeleteExtState(NS, HEARTBEAT, false)
    return
  end
  local now = reaper.time_precise()
  reaper.SetExtState(NS, HEARTBEAT, tostring(now), false)
  if now >= next_check then
    next_check = now + 0.25   -- checked again regularly, so a bypass made while hovering is caught
    update_hiding()
    check()
  end
  reaper.defer(loop)
end

reaper.atexit(function()
  show_hidden()
  reaper.DeleteExtState(NS, HEARTBEAT, false)
end)
show_hidden()   -- anything left hidden from before (REAPER quit while zoomed in)
loop()
