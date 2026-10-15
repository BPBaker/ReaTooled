-- Variable to store the last detected selection state and shuffle region info
local lastSelectedItems = {}
local lastRegionStart, lastRegionEnd = nil, nil

-- Function to get the currently selected items and their position/length
function getSelectedItemsRange()
    local numSelected = reaper.CountSelectedMediaItems(0)
    if numSelected == 0 then
        return nil, nil, {} -- No items selected
    end

    local itemStart = nil
    local itemEnd = nil
    local selectedItems = {}

    for i = 0, numSelected - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        table.insert(selectedItems, item)
        local start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local finish = start + length

        if not itemStart or start < itemStart then
            itemStart = start
        end
        if not itemEnd or finish > itemEnd then
            itemEnd = finish
        end
    end

    return itemStart, itemEnd, selectedItems
end

-- Function to compare two item selection states
function hasSelectionChanged(currentItems, lastItems)
    if #currentItems == 0 and #lastItems > 0 then
        return true -- Transition from selected to no items selected
    end
    if #currentItems ~= #lastItems then
        return true
    end
    for i = 1, #currentItems do
        if currentItems[i] ~= lastItems[i] then
            return true
        end
    end
    return false
end

-- Function to remove all "SHUFFLE" regions
function removeAllShuffleRegions()
    local retval, numMarkers, numRegions = reaper.CountProjectMarkers(0)
    if retval and (numMarkers + numRegions) > 0 then
        for i = numMarkers + numRegions - 1, 0, -1 do
            local retval, isRegion, pos, rgnEnd, name, markerIndex = reaper.EnumProjectMarkers3(0, i)
            if retval and isRegion and string.lower(name or "") == "shuffle" then
                reaper.DeleteProjectMarker(0, markerIndex, true) -- true: it's a region
            end
        end
    end
end

-- Function to create or move a "SHUFFLE" region
function createOrMoveShuffleRegion(startTime, endTime)
    if startTime and endTime then
        if startTime ~= lastRegionStart or endTime ~= lastRegionEnd then
            removeAllShuffleRegions() -- Ensure no residual regions exist
            reaper.AddProjectMarker2(
                0, -- Project index
                true, -- Is region
                startTime, -- Region start
                endTime, -- Region end
                "SHUFFLE", -- Label
                -1, -- Region ID (-1 for new)
                reaper.ColorToNative(255, 0, 0) | 0x1000000 -- Red color
            )
            lastRegionStart, lastRegionEnd = startTime, endTime
        end
    end
end

-- Main function to monitor item selection and manage regions
function updateShuffleRegion()
    local startTime, endTime, currentSelectedItems = getSelectedItemsRange()

    if #currentSelectedItems > 0 then
        -- Create or move the "SHUFFLE" region dynamically
        createOrMoveShuffleRegion(startTime, endTime)
    else
        -- Remove the "SHUFFLE" region if no items are selected
        removeAllShuffleRegions()
        lastRegionStart, lastRegionEnd = nil, nil
    end

    -- Update the stored selection state
    lastSelectedItems = currentSelectedItems

    -- Defer to keep the script running
    reaper.defer(updateShuffleRegion)
end

-- Initialize and run the script
updateShuffleRegion()
