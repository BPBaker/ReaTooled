--@description ReaTooled: Set Envelope Point Value (Interactive)
--@version 1.3
--@changelog
--  v1.3 - Fix: ensure SetPointsInRange is defined before use; robust function ordering
--  v1.2 - Fix: proper fader-scaled handling (convert dB -> amplitude, then ScaleToEnvelopeMode)
--  v1.1 - Earlier unit helpers (superseded by scaling-aware approach)
--  v1.0 - Initial public release
--@author Brendan Baker (ReaTooled)
--@website https://brendanpatrickbaker.com/reatooled/
--@about
--  Set the value of many envelope points at once (priority: Selected points → Razor envelope areas → Time Selection).
--  Values are interpreted per envelope scaling:
--    • Fader-scaled Volume (track/take/send): enter dB (e.g., -12, 0, +3)
--      -> internally converted to amplitude then to raw via ScaleToEnvelopeMode.
--    • Other envelopes: written as entered (e.g., 0..1 for normalized FX params).
--  Supports Automation Items; no SWS required.

--------------------------------------
-- USER SETTINGS
--------------------------------------
local CheckArmed      = false
local RequireVisible  = true
local IncludeTakesTS  = true
local ExtSection      = "REATOOLED_SETENVPOINTVAL"
local ExtKeyLastValue = "LastValue"

--------------------------------------
-- HELPERS (ordering matters)
--------------------------------------
local function RazorEditSelectionExists()
  for i = 0, reaper.CountTracks(0)-1 do
    local _, x = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0,i), "P_RAZOREDITS", "", false)
    if x ~= "" then return true end
  end
  return false
end

local function EnvelopePassesFilters(env)
  if not env then return false end
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok then return true end
  if CheckArmed and chunk:match("\nARM%s+0") then return false end
  if RequireVisible and (chunk:match("\nVIS%s+([01])") ~= "1") then return false end
  return true
end

-- Return raw value suitable for SetEnvelopePointEx from a user-entered value.
-- For fader-scaled "Volume" envelopes: interpret user_value as dB, convert to amplitude, then scale.
local function to_raw_for_env(env, user_value)
  local mode = reaper.GetEnvelopeScalingMode(env) or 0
  if mode == 1 then
    local ok, name = reaper.GetEnvelopeName(env)
    name = (ok and name or ""):lower()
    if name:find("volume") then
      local amp
      if user_value <= -150 then amp = 0.0 else amp = 10^(user_value / 20.0) end
      return reaper.ScaleToEnvelopeMode(1, amp)
    end
    -- Other fader-scaled types (rare): assume user_value already in display units
    return reaper.ScaleToEnvelopeMode(1, user_value)
  else
    return user_value
  end
end

local function ForEachAutomationContext(env, ps, pe, fn)
  local list = {}
  local nAI = reaper.CountAutomationItems(env)
  local addBase = true
  for i = 0, nAI-1 do
    local s = reaper.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
    local e = s + reaper.GetSetAutomationItemInfo(env, i, "D_LENGTH", 0, false)
    if (s >= ps and s < pe) or (e > ps and e <= pe) or (s < ps and e > pe) then
      if s < ps and e > pe then addBase = false end
      list[#list+1] = i
    end
  end
  if addBase then table.insert(list, 1, -1) end

  for _, ai in ipairs(list) do
    local ai_ps, ai_pe = ps, pe
    if ai ~= -1 then
      local s = reaper.GetSetAutomationItemInfo(env, ai, "D_POSITION", 0, false)
      local e = s + reaper.GetSetAutomationItemInfo(env, ai, "D_LENGTH", 0, false)
      if s > ai_ps then ai_ps = s end
      if e < ai_pe then ai_pe = e end
    end
    fn(env, ai, ai_ps, ai_pe)
  end
end

-- DEFINED BEFORE USE: used by both Razor and TimeSelection paths
local function SetPointsInRange(env, ps, pe, user_value)
  if not EnvelopePassesFilters(env) then return end
  local raw_val = to_raw_for_env(env, user_value)
  ForEachAutomationContext(env, ps, pe, function(e, ai, a, b)
    local cnt = reaper.CountEnvelopePointsEx(e, ai)
    if cnt == 0 then return end
    for i = 0, cnt-1 do
      local ok, t = reaper.GetEnvelopePointEx(e, ai, i)
      if ok and t >= a and t <= b then
        local _, _, _, shape, ten, sel = reaper.GetEnvelopePointEx(e, ai, i)
        reaper.SetEnvelopePointEx(e, ai, i, t, raw_val, shape, ten, sel, true)
      end
    end
    reaper.Envelope_SortPointsEx(e, ai)
  end)
end

local function AnySelectedEnvelopePoints()
  local out = {}
  for t = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, t)
    for e = 0, reaper.CountTrackEnvelopes(tr)-1 do
      local env = reaper.GetTrackEnvelope(tr, e)
      if EnvelopePassesFilters(env) then
        local baseCnt = reaper.CountEnvelopePointsEx(env, -1)
        for i = 0, baseCnt-1 do
          local ok, _, _, _, _, sel = reaper.GetEnvelopePointEx(env, -1, i)
          if ok and sel then out[#out+1] = {env=env, ai=-1, idx=i} end
        end
        local nAI = reaper.CountAutomationItems(env)
        for ai = 0, nAI-1 do
          local cnt = reaper.CountEnvelopePointsEx(env, ai)
          for i = 0, cnt-1 do
            local ok, _, _, _, _, sel = reaper.GetEnvelopePointEx(env, ai, i)
            if ok and sel then out[#out+1] = {env=env, ai=ai, idx=i} end
          end
        end
      end
    end
  end
  return out
end

local function SetSelectedPointsToValue(user_value)
  local list = AnySelectedEnvelopePoints()
  if #list == 0 then return false end
  local groups = {}
  for _, pt in ipairs(list) do
    local key = tostring(pt.env) .. "|" .. pt.ai
    groups[key] = groups[key] or {env=pt.env, ai=pt.ai, idxs={}}
    table.insert(groups[key].idxs, pt.idx)
  end
  for _, g in pairs(groups) do
    local raw_val = to_raw_for_env(g.env, user_value)
    for _, idx in ipairs(g.idxs) do
      local ok, t, _, sh, te, sel = reaper.GetEnvelopePointEx(g.env, g.ai, idx)
      if ok then reaper.SetEnvelopePointEx(g.env, g.ai, idx, t, raw_val, sh, te, sel, true) end
    end
    reaper.Envelope_SortPointsEx(g.env, g.ai)
  end
  return true
end

local function GetRazorEnvelopeAreas()
  local areas = {}
  for i = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, i)
    local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if s ~= "" then
      local toks = {}; for w in s:gmatch("%S+") do toks[#toks+1] = w end
      local j = 1
      while j <= #toks do
        local a = tonumber(toks[j]); local b = tonumber(toks[j+1]); local guid = toks[j+2]
        if guid ~= '""' then
          local env = reaper.GetTrackEnvelopeByChunkName(tr, guid:sub(2,-2))
          if EnvelopePassesFilters(env) then areas[#areas+1] = {env=env, a=a, b=b} end
        end
        j = j + 3
      end
    end
  end
  return areas
end

local function TimeSelection()
  local a, b = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if a ~= b then return a, b end
end

local function ItemsIntersectTS(a, b, tr)
  local list = {}
  local n = reaper.CountTrackMediaItems(tr)
  for i = 0, n-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local e   = pos + len
    if (pos < b and e > a) then list[#list+1] = it end
  end
  return list
end

--------------------------------------
-- MAIN
--------------------------------------
local function main()
  local last = reaper.GetExtState(ExtSection, ExtKeyLastValue)
  if last == "" then last = "0" end
  local ok, ret = reaper.GetUserInputs("ReaTooled: Set Envelope Point Value", 1, "Value (e.g. -12 for dB on Volume):", last)
  if not ok then return end
  local user_value = tonumber(ret)
  if not user_value then reaper.MB("Invalid number.", "ReaTooled", 0); return end
  reaper.SetExtState(ExtSection, ExtKeyLastValue, tostring(user_value), true)

  reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)

  if SetSelectedPointsToValue(user_value) then
    reaper.PreventUIRefresh(-1); reaper.Undo_EndBlock("ReaTooled: Set selected envelope points", -1); reaper.UpdateArrange(); return
  end

  if RazorEditSelectionExists() then
    local areas = GetRazorEnvelopeAreas()
    for _, a in ipairs(areas) do SetPointsInRange(a.env, a.a, a.b, user_value) end
    reaper.PreventUIRefresh(-1); reaper.Undo_EndBlock("ReaTooled: Set envelope points in Razor", -1); reaper.UpdateArrange(); return
  end

  local tsA, tsB = TimeSelection()
  if tsA and tsB then
    local tracks = {}
    if reaper.CountSelectedTracks(0) > 0 then
      for i = 0, reaper.CountSelectedTracks(0)-1 do tracks[#tracks+1] = reaper.GetSelectedTrack(0, i) end
    else
      for i = 0, reaper.CountTracks(0)-1 do tracks[#tracks+1] = reaper.GetTrack(0, i) end
    end
    for _, tr in ipairs(tracks) do
      for e = 0, reaper.CountTrackEnvelopes(tr)-1 do
        local env = reaper.GetTrackEnvelope(tr, e)
        SetPointsInRange(env, tsA, tsB, user_value)
      end
      if IncludeTakesTS then
        local items = ItemsIntersectTS(tsA, tsB, tr)
        for _, it in ipairs(items) do
          local ist = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          for tk = 0, reaper.CountTakes(it)-1 do
            local take = reaper.GetTake(it, tk)
            for ev = 0, reaper.CountTakeEnvelopes(take)-1 do
              local env = reaper.GetTakeEnvelope(take, ev)
              SetPointsInRange(env, tsA - ist, tsB - ist, user_value)
            end
          end
        end
      end
    end
    reaper.PreventUIRefresh(-1); reaper.Undo_EndBlock("ReaTooled: Set envelope points in Time Selection", -1); reaper.UpdateArrange(); return
  end

  reaper.PreventUIRefresh(-1); reaper.Undo_EndBlock("ReaTooled: Set Envelope Point Value (no targets)", -1)
end

main()
