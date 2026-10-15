-- @description ReaTooled - Razor Edit Group Sync (Preserve Area, Envelope-Aware)
-- @version 1.1
-- @date 2025.04.24
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Mirrors razor edits across grouped items or envelopes.
--   # If razor is on envelope, it only copies to same envelope on grouped tracks.
--   # If razor intersects items in a group, mirrors the edit to all grouped tracks.

local function GetRazorEdits()
  local edits = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, str = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
    for s, e, guid in string.gmatch(str, '(%d+%.%d*) (%d+%.%d*) "(.-)"') do
      table.insert(edits, {
        start = tonumber(s),
        end_ = tonumber(e),
        track = track,
        guid = guid
      })
    end
  end
  return edits
end

local function IsEnvelopeGuid(track, guid)
  for j = 0, reaper.CountTrackEnvelopes(track) - 1 do
    local env = reaper.GetTrackEnvelope(track, j)
    local env_guid = reaper.GetTrackEnvelopeInfo_Value(env, "GUID")
    if env_guid and env_guid:lower():find(guid:lower(), 1, true) then
      return env
    end
  end
  return nil
end

local function GetItemGroupIDAtPosition(track, start_pos, end_pos)
  local itemCount = reaper.CountTrackMediaItems(track)
  for i = 0, itemCount - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local itemEnd = pos + len
    if not (itemEnd <= start_pos or pos >= end_pos) then
      local groupID = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")
      if groupID > 0 then return groupID end
    end
  end
  return nil
end

local function ClearAllRazorEdits()
  for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', true)
  end
end

local function ApplyGroupedRazorEdits()
  local edits = GetRazorEdits()
  local newEditsPerTrack = {}

  for _, edit in ipairs(edits) do
    local is_envelope = IsEnvelopeGuid(edit.track, edit.guid)
    if is_envelope then
      -- Razor is on envelope: find envelope on grouped tracks
      for t = 0, reaper.CountTracks(0) - 1 do
        local other_track = reaper.GetTrack(0, t)
        if other_track ~= edit.track then
          for j = 0, reaper.CountTrackEnvelopes(other_track) - 1 do
            local env = reaper.GetTrackEnvelope(other_track, j)
            local guid = reaper.GetTrackEnvelopeInfo_Value(env, "GUID")
            if guid == edit.guid then
              local str = string.format("%f %f \"%s\" ", edit.start, edit.end_, guid)
              newEditsPerTrack[other_track] = (newEditsPerTrack[other_track] or "") .. str
            end
          end
        end
      end
      -- Always re-apply to original envelope track too
      local str = string.format("%f %f \"%s\" ", edit.start, edit.end_, edit.guid)
      newEditsPerTrack[edit.track] = (newEditsPerTrack[edit.track] or "") .. str

    else
      -- Razor is on item lane: sync across grouped items
      local groupID = GetItemGroupIDAtPosition(edit.track, edit.start, edit.end_)
      if groupID then
        for i = 0, reaper.CountMediaItems(0) - 1 do
          local item = reaper.GetMediaItem(0, i)
          if reaper.GetMediaItemInfo_Value(item, "I_GROUPID") == groupID then
            local tr = reaper.GetMediaItem_Track(item)
            local str = string.format("%f %f \"reatooled\" ", edit.start, edit.end_)
            newEditsPerTrack[tr] = (newEditsPerTrack[tr] or "") .. str
          end
        end
      else
        -- No group, just re-apply to same track
        local str = string.format("%f %f \"reatooled\" ", edit.start, edit.end_)
        newEditsPerTrack[edit.track] = (newEditsPerTrack[edit.track] or "") .. str
      end
    end
  end

  ClearAllRazorEdits()
  for tr, str in pairs(newEditsPerTrack) do
    reaper.GetSetMediaTrackInfo_String(tr, 'P_RAZOREDITS', str, true)
  end
end

local function Main()
  ApplyGroupedRazorEdits()
  reaper.defer(Main)
end

Main()

