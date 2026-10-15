--[[
@description ReaTooled - Render and Archive to Lane
@version 1.4
@date 2026-03-08
@author Brendan Baker
@about
  Renders selected items in place (baking take FX to audio) while preserving
  the original items with their full FX chain intact on a new hidden archive lane.
  Archive lanes are timestamped and named with the baked FX chain.
  Only the main render lane remains visible and plays. Mutes archived items to save CPU.

  IMPORTANT - For rendered files to be named with FX chain info:
  In REAPER's Render to File dialog, set the filename pattern to use $take as the token.
  The script names each rendered take after rendering so the output file will automatically
  be named e.g. "Guitar - EQ2 > Decapitator > H-Reverb.wav"

CHANGELOG
v1.4
  - Removed vowel and symbol stripping from FX names - now shows full readable short name
  - Removed stripVowelsAndSymbols function entirely
  - FX names now strip only format prefix (VST3, AU, JS etc) and vendor in parens
v1.3
  - Fixed blank lane appearing between render lane and archive lanes on first run
  - Removed forced minimum lane count of 2 which was causing the blank lane
v1.2
  - Simplified rendered take naming - original take name never touched
  - Rendered take renamed cleanly after crop using original name + FX chain
  - Added $take render filename note to header
v1.1
  - Fixed lane name truncation by using compressed timestamp format
  - Fixed multiple items on same track now sharing one archive lane per run
  - FX names appended to rendered item name
  - Falls back to track name if item has no name
v1.0
  - Initial release
--]]

-- Get short FX name by stripping format prefix and vendor
local function getShortFXName(name)
  name = name:gsub("^[%a%d]+:%s*", "")   -- strip "VST3: " "VST: " "AU: " "JS: " etc.
  name = name:gsub("%s*%(.*%)%s*$", "")  -- strip "(Vendor)"
  name = name:match("^%s*(.-)%s*$")      -- trim whitespace
  return name
end

-- Build FX chain string from take FX (no truncation)
local function buildFXString(take)
  local fxCount = reaper.TakeFX_GetCount(take)
  if fxCount == 0 then return "noFX" end

  local names = {}
  for i = 0, fxCount - 1 do
    local _, fxName = reaper.TakeFX_GetFXName(take, i, "")
    table.insert(names, getShortFXName(fxName))
  end

  return table.concat(names, " > ")
end

-- Copy take FX chain from one take to another
local function copyTakeFX(srcTake, dstTake)
  local fxCount = reaper.TakeFX_GetCount(srcTake)
  for i = 0, fxCount - 1 do
    reaper.TakeFX_CopyToTake(srcTake, i, dstTake, i, false)
  end
end

-- Hide all lanes except lane 0, set track to show/play only one lane
local function hideArchiveLanes(track)
  local laneCount = reaper.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES")
  for i = 1, laneCount - 1 do
    reaper.SetMediaTrackInfo_Value(track, "I_FIXEDLANESIZE_" .. i, 0)
    local _, currentName = reaper.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. i, "", false)
    reaper.GetSetMediaTrackInfo_String(track, "P_LANENAME:" .. i, currentName, true)
  end
  -- Ensure lane 0 is visible
  reaper.SetMediaTrackInfo_Value(track, "I_FIXEDLANESIZE_0", 1)
  -- Set track to show and play only one fixed item lane
  reaper.SetOnlyTrackSelected(track)
  reaper.Main_OnCommand(43098, 0)
end

-- Get item base name, falling back to track name
local function getItemBaseName(item, take, track)
  local _, takeName = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  if takeName and takeName ~= "" then
    return takeName
  end
  local _, trackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if trackName and trackName ~= "" then
    return trackName
  end
  return "Item"
end

-- Main
local function main()
  local itemCount = reaper.CountSelectedMediaItems(0)
  if itemCount == 0 then
    reaper.ShowMessageBox("No items selected.", "ReaTooled - Render and Archive to Lane", 0)
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Compressed timestamp e.g. 260308-1432
  local timestamp = os.date("%y%m%d-%H%M")

  -- Collect items first to avoid selection mutation during loop
  local items = {}
  for i = 0, itemCount - 1 do
    items[i] = reaper.GetSelectedMediaItem(0, i)
  end

  -- Pre-calculate new archive lane index per track for this run
  -- so all items on the same track share one archive lane
  local trackLaneMap = {}
  for i = 0, itemCount - 1 do
    local item = items[i]
    local track = reaper.GetMediaItemTrack(item)
    local trackGUID = reaper.GetTrackGUID(track)
    if not trackLaneMap[trackGUID] then
      local laneCount = reaper.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES")
      local newLaneIndex = laneCount
      reaper.SetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES", laneCount + 1)
      trackLaneMap[trackGUID] = { track = track, laneIndex = newLaneIndex, laneName = nil }
    end
  end

  -- Collect processed tracks for hideArchiveLanes
  local processedTracks = {}

  for i = 0, itemCount - 1 do
    local item = items[i]
    local track = reaper.GetMediaItemTrack(item)
    local trackGUID = reaper.GetTrackGUID(track)
    local activeTake = reaper.GetActiveTake(item)

    if activeTake then

      -- Read original name and build FX string upfront before anything is touched
      local originalName = getItemBaseName(item, activeTake, track)
      local fxString = buildFXString(activeTake)
      local renderedName = originalName .. " - " .. fxString

      -- Build lane name (only set once per track per run, using first item's FX)
      if not trackLaneMap[trackGUID].laneName then
        trackLaneMap[trackGUID].laneName = timestamp .. " | " .. fxString
      end

      local newLaneIndex = trackLaneMap[trackGUID].laneIndex

      -- Duplicate item onto archive lane
      local newItem = reaper.AddMediaItemToTrack(track)
      local newTake = reaper.AddTakeToMediaItem(newItem)

      -- Copy audio source from active take
      local source = reaper.GetMediaItemTake_Source(activeTake)
      reaper.SetMediaItemTake_Source(newTake, source)

      -- Copy item properties
      reaper.SetMediaItemInfo_Value(newItem, "D_POSITION",
        reaper.GetMediaItemInfo_Value(item, "D_POSITION"))
      reaper.SetMediaItemInfo_Value(newItem, "D_LENGTH",
        reaper.GetMediaItemInfo_Value(item, "D_LENGTH"))
      reaper.SetMediaItemInfo_Value(newItem, "D_SNAPOFFSET",
        reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET"))
      reaper.SetMediaItemInfo_Value(newItem, "D_VOL",
        reaper.GetMediaItemInfo_Value(item, "D_VOL"))
      reaper.SetMediaItemInfo_Value(newItem, "D_PAN",
        reaper.GetMediaItemInfo_Value(item, "D_PAN"))
      reaper.SetMediaItemInfo_Value(newItem, "D_FADEINLEN",
        reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN"))
      reaper.SetMediaItemInfo_Value(newItem, "D_FADEOUTLEN",
        reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"))
      reaper.SetMediaItemInfo_Value(newItem, "I_FIXEDLANE", newLaneIndex)

      -- Mute archive item so it uses no CPU
      reaper.SetMediaItemInfo_Value(newItem, "B_MUTE", 1)

      -- Copy take FX chain to archive item so FX state is preserved
      copyTakeFX(activeTake, newTake)

      -- Name the archive take with timestamp and FX chain
      local archiveTakeName = trackLaneMap[trackGUID].laneName
      reaper.GetSetMediaItemTakeInfo_String(newTake, "P_NAME", archiveTakeName, true)

      -- Select only this item for rendering
      reaper.SelectAllMediaItems(0, false)
      reaper.SetMediaItemSelected(item, true)

      -- Render item as new take (bakes take FX)
      reaper.Main_OnCommand(40209, 0)
      -- Crop to active take (removes pre-render take, original name untouched)
      reaper.Main_OnCommand(40131, 0)

      -- Rendered take is now active - rename it with original name + FX chain
      local renderedTake = reaper.GetActiveTake(item)
      if renderedTake then
        reaper.GetSetMediaItemTakeInfo_String(renderedTake, "P_NAME", renderedName, true)
      end

      -- Mark track for lane cleanup
      processedTracks[trackGUID] = track

    end
  end

  -- Set lane names per track
  for trackGUID, data in pairs(trackLaneMap) do
    if data.laneName then
      reaper.GetSetMediaTrackInfo_String(data.track,
        "P_LANENAME:" .. data.laneIndex, data.laneName, true)
    end
  end

  -- Hide archive lanes and set single lane mode once per track
  for _, track in pairs(processedTracks) do
    hideArchiveLanes(track)
  end

  -- Restore original track and item selection
  reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
  for i = 0, itemCount - 1 do
    local track = reaper.GetMediaItemTrack(items[i])
    reaper.SetTrackSelected(track, true)
    reaper.SetMediaItemSelected(items[i], true)
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("ReaTooled - Render and Archive to Lane", -1)
end

main()
