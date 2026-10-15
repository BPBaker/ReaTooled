--@description GLIDE envelopes to selection/items (ReaTooled, inspired by TJF)
--@version 3.0
--@author ReaTooled
--@about
--  Reatooled version that preserves the original behavior (Time Selection, Razor Edit,
--  Item Selection, Take/Track envelopes, Automation Items, optional Edit Cursor pickup),
--  with safer logic and performance improvements:
--    - No mutation of shared state across loops (per-AI/local clamping)
--    - Optional filters for envelope visibility and arming
--    - Fewer redundant Envelope_Evaluate calls (re-evaluate only when needed)
--    - Sort once per AI batch, not per-point
--    - Safer clamping for item-relative cursor
--    - Cleaner structure and locals
--  NOTE: This script uses only native ReaScript API (no SWS BR_ calls).

--[[------------------------------[[--
              SETTINGS
--]]------------------------------]]--

local CheckEditCursor = true   -- If true, and edit cursor falls in selection, write using value at cursor
local CheckArmed      = false  -- If true, only process ARMED envelopes
local RequireVisible  = true   -- If true, only process VISIBLE envelopes
local Smoothing       = 0.01   -- Seconds used to smooth back to post-region values



--[[------------------------------[[--
               DEBUG
--]]------------------------------]]--

local DEBUG = false
local function Msg(...)
  if DEBUG then reaper.ShowConsoleMsg(table.concat({...}, " ") .. "\n") end
end


--[[------------------------------[[--
           UTILITY HELPERS
--]]------------------------------]]--

local function RazorEditSelectionExists()
  local proj = 0
  for i = 0, reaper.CountTracks(proj)-1 do
    local _, x = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(proj, i), "P_RAZOREDITS", "", false)
    if x ~= "" then return true end
  end
  return false
end

local function GetItemsInRange(track, a, b)
  local out, n = {}, reaper.CountTrackMediaItems(track)
  for i = 0, n-1 do
    local it    = reaper.GetTrackMediaItem(track, i)
    local pos   = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len   = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local itEnd = pos + len
    if (itEnd > a and itEnd <= b) or (pos >= a and pos < b) or (pos <= a and itEnd >= b) then
      out[#out+1] = it
    end
  end
  return out
end

local function GetEnvelopePointsInRange(env, a, b)
  local pts = {}
  local cnt = reaper.CountEnvelopePoints(env)
  for i = 0, cnt-1 do
    local ok, t, v, sh, ten, sel = reaper.GetEnvelopePoint(env, i)
    if ok and t >= a and t <= b then
      pts[#pts+1] = { id=i, time=t, value=v, shape=sh, tension=ten, selected=sel }
    end
  end
  return pts
end

local function GetRazorEdits()
  local proj = 0
  local tc = reaper.CountTracks(proj)
  local areaMap = {}
  for i = 0, tc-1 do
    local trk = reaper.GetTrack(proj, i)
    local _, area = reaper.GetSetMediaTrackInfo_String(trk, "P_RAZOREDITS", "", false)
    if area ~= "" then
      local toks = {}
      for w in area:gmatch("%S+") do toks[#toks+1] = w end
      local j = 1
      while j <= #toks do
        local aStart   = tonumber(toks[j])
        local aEnd     = tonumber(toks[j+1])
        local GUIDwrap = toks[j+2]
        local isEnv    = GUIDwrap ~= '""'
        local items, env, envName, envPts, guid = {}, nil, nil, nil, GUIDwrap:sub(2,-2)

        if not isEnv then
          items = GetItemsInRange(trk, aStart, aEnd)
        else
          env = reaper.GetTrackEnvelopeByChunkName(trk, guid)
          if env then
            _, envName = reaper.GetEnvelopeName(env)
            envPts = GetEnvelopePointsInRange(env, aStart, aEnd)
          end
        end

        areaMap[#areaMap+1] = {
          areaStart=aStart, areaEnd=aEnd,
          track=trk, items=items,
          isEnvelope=isEnv, envelope=env, envelopeName=envName, envelopePoints=envPts, GUID=guid
        }
        j = j + 3
      end
    end
  end
  return areaMap
end

local function EnvelopePassesFilters(env)
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok then return true end
  if CheckArmed and chunk:match("\nARM%s+0") then return false end
  if RequireVisible then
    local vis = chunk:match("\nVIS%s+([01])")
    if vis ~= "1" then return false end
  end
  return true
end

local function GetAutoItems(env, a, b)
  local ai = {}
  local n = reaper.CountAutomationItems(env)
  local addOutside = true
  for i = 0, n-1 do
    local s = reaper.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
    local e = s + reaper.GetSetAutomationItemInfo(env, i, "D_LENGTH", 0, false)
    local overlaps = (s >= a and s < b) or (e > a and e <= b) or (s < a and e > b)
    if overlaps then
      if s < a and e > b then addOutside = false end
      ai[#ai+1] = i
    end
  end
  if addOutside then table.insert(ai, 1, -1) end -- -1 = envelope lane (no AI)
  return ai
end


--[[------------------------------[[--
          ENVELOPE PROCESSING
--]]------------------------------]]--

local function ProcessEnvelope(env, pointstart, pointend, curpos, forcedValue)
  if not env or not EnvelopePassesFilters(env) then return end
  if pointend <= pointstart then return end

  -- Base evaluations at global bounds (before per-AI clamping)
  local _, baseStart = reaper.Envelope_Evaluate(env, pointstart, 48000, 0)
  local _, baseEnd   = reaper.Envelope_Evaluate(env, pointend,   48000, 0)
  local _, smoothL   = reaper.Envelope_Evaluate(env, pointstart - Smoothing, 48000, 0)
  local _, smoothR   = reaper.Envelope_Evaluate(env, pointend   + Smoothing, 48000, 0)

  local value = forcedValue
  if value == nil then
    if CheckEditCursor then
      _, value = reaper.Envelope_Evaluate(env, curpos, 48000, 0)
    else
      value = baseEnd
    end
  end

  local AIs = GetAutoItems(env, pointstart, pointend)
  for idx = 1, #AIs do
    local ai = AIs[idx]
    local ai_ps, ai_pe = pointstart, pointend
    local sv, ev, sl, sr = baseStart, baseEnd, smoothL, smoothR

    -- Clamp to AI bounds if needed and re-evaluate at clamped edges
    if ai ~= -1 then
      local s = reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
      local e = s + reaper.GetSetAutomationItemInfo(env, ai, "D_LENGTH", 0, false)
      if s > ai_ps then ai_ps = s end
      if e < ai_pe then ai_pe = e end
      _, sv = reaper.Envelope_Evaluate(env, ai_ps, 48000, 0)
      _, ev = reaper.Envelope_Evaluate(env, ai_pe, 48000, 0)
      _, sl = reaper.Envelope_Evaluate(env, ai_ps - Smoothing, 48000, 0)
      _, sr = reaper.Envelope_Evaluate(env, ai_pe + Smoothing, 48000, 0)
    end

    -- Write
    reaper.DeleteEnvelopePointRangeEx(env, ai, ai_ps, ai_pe + Smoothing)
    reaper.InsertEnvelopePointEx(env, ai, ai_ps, sv,    0, 1, 0, true)  -- hold entering value
    reaper.InsertEnvelopePointEx(env, ai, ai_pe, value, 0, 1, 0, true)  -- target at region end
    if value ~= ev or #AIs > 1 then
      reaper.InsertEnvelopePointEx(env, ai, ai_pe + Smoothing, sr, 0, 1, 0, true) -- smooth back
    end
    reaper.Envelope_SortPointsEx(env, ai)
  end
end

local function ProcessItemEnvelopes(items, starttime, endtime, curpos, forcedValue)
  -- Item envelopes have no "armed" flag; ignore CheckArmed during this pass
  local savedCheckArmed = CheckArmed
  CheckArmed = false

  for i = 1, #items do
    local it = items[i]
    local itemstart = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local itemlen   = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local itemend   = itemstart + itemlen

    -- Clamp edit cursor within item and convert to item-local time
    local cp = math.max(itemstart, math.min(curpos, itemend - Smoothing)) - itemstart

    -- Convert selection to item-local bounds
    local ps = starttime - itemstart
    local pe = endtime   - itemstart
    if ps == pe then ps, pe = 0, itemlen end
    if itemstart > starttime then ps = 0 end
    if itemend   < endtime   then pe = itemlen end

    local takes = reaper.CountTakes(it)
    for t = 0, takes-1 do
      local take = reaper.GetTake(it, t)
      local envc = reaper.CountTakeEnvelopes(take)
      for e = 0, envc-1 do
        ProcessEnvelope(reaper.GetTakeEnvelope(take, e), ps, pe, cp, forcedValue)
      end
    end
  end

  CheckArmed = savedCheckArmed
end


--[[------------------------------[[--
                 MAIN
--]]------------------------------]]--

local function Main()
  -- Optional helper toggle override
  if HELPER_TOGGLE_CMD and HELPER_TOGGLE_CMD ~= "" then
    local cmd_id = reaper.NamedCommandLookup(HELPER_TOGGLE_CMD)
    if cmd_id ~= 0 then
      CheckEditCursor = (reaper.GetToggleCommandStateEx(0, cmd_id) == 1)
    end
  end

  local curpos = reaper.GetCursorPosition()

  -- 1) TIME SELECTION path
  local starttime, endtime = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if starttime ~= endtime then
    local tracks = {}
    if reaper.CountSelectedTracks(0) > 0 then
      for i = 0, reaper.CountSelectedTracks(0)-1 do
        tracks[#tracks+1] = reaper.GetSelectedTrack(0, i)
      end
    else
      for i = 0, reaper.CountTracks(0)-1 do
        tracks[#tracks+1] = reaper.GetTrack(0, i)
      end
    end

    local items, selitems = {}, {}
    for i = 1, #tracks do
      local tr = tracks[i]

      -- Gather items intersecting time selection
      local nItems = reaper.CountTrackMediaItems(tr)
      for j = 0, nItems-1 do
        local it    = reaper.GetTrackMediaItem(tr, j)
        local ist   = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local iend  = ist + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if (ist < starttime and iend > starttime) or (iend > endtime and ist < endtime) or (ist >= starttime and iend <= endtime) then
          items[#items+1] = it
          if reaper.IsMediaItemSelected(it) then selitems[#selitems+1] = it end
        end
      end

      -- Process track envelopes within TS
      local envc = reaper.CountTrackEnvelopes(tr)
      for e = 0, envc-1 do
        ProcessEnvelope(reaper.GetTrackEnvelope(tr, e), starttime, endtime, curpos, nil)
      end
    end

    if #selitems > 0 then
      ProcessItemEnvelopes(selitems, starttime, endtime, curpos, nil)
    elseif #items > 0 then
      ProcessItemEnvelopes(items, starttime, endtime, curpos, nil)
    end
    return
  end

  -- 2) RAZOR EDITS path
  if RazorEditSelectionExists() then
    local selections = GetRazorEdits()
    local now = reaper.GetCursorPosition()
    for i = 1, #selections do
      local a = selections[i]
      if a.isEnvelope and a.envelope then
        ProcessEnvelope(a.envelope, a.areaStart, a.areaEnd, now, nil)
      end
      if #a.items > 0 then
        ProcessItemEnvelopes(a.items, a.areaStart, a.areaEnd, now, nil)
      end
    end
    return
  end

  -- 3) ITEM SELECTION path
  local selCount = reaper.CountSelectedMediaItems(0)
  if selCount > 0 then
    local items = {}
    local now = reaper.GetCursorPosition()
    for i = 0, selCount-1 do
      local it = reaper.GetSelectedMediaItem(0, i)
      items[#items+1] = it
      local ist = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local iend = ist + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local tr = reaper.GetMediaItem_Track(it)
      local envc = reaper.CountTrackEnvelopes(tr)
      for e = 0, envc-1 do
        ProcessEnvelope(reaper.GetTrackEnvelope(tr, e), ist, iend, now, nil)
      end
    end
    -- For take envelopes: use item-local whole-range pass when TS not used
    ProcessItemEnvelopes(items, 1, 1, now, nil)
  end
end


--[[------------------------------[[--
              EXECUTION
--]]------------------------------]]--

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("GLIDE envelopes to selection/items", -1)
reaper.UpdateArrange()
