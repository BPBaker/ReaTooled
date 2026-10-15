--[[
    Description: Toggle through different item view modes:
        1. Normal Peaks
        2. Normal Peaks + LUFS-S Graph
        3. Spectral Peaks
        4. Spectrogram
        5. Peaks + Spectrogram (overlap OFF)
        6. Peaks + Spectrogram (overlap ON)
    Instructions:
        - Run the script to cycle through different item view modes for selected items
        - Each time you run the script, it will switch to the next view mode
        - Modes 5 and 6 both use Peaks + Spectrogram (42295); the difference is
          "Spectrogram: Overlap peaks and spectrogram when in peaks+spectrogram mode" (43805)
]]

-- Command ID for "Spectrogram: Overlap peaks and spectrogram when in peaks+spectrogram mode"
local OVERLAP_CMD = 43805

-- Define the list of item view modes to cycle through
-- overlap = nil   -> mode doesn't care about the overlap setting
-- overlap = false -> overlap must be OFF
-- overlap = true  -> overlap must be ON
local itemViewModes = {
    { name = "Normal Peaks",                       commandID = 42301 },
    { name = "Normal Peaks + LUFS-S Graph",        commandID = 43148 },
    { name = "Spectral Peaks",                     commandID = 42073 },
    { name = "Spectrogram",                        commandID = 42294 },
    { name = "Peaks + Spectrogram",                commandID = 42295, overlap = false },
    { name = "Peaks + Spectrogram (Overlapped)",   commandID = 42295, overlap = true },
}

local function isOn(commandID)
    return reaper.GetToggleCommandState(commandID) > 0
end

-- Function to get the current item view mode index
local function getCurrentItemViewModeIndex()
    local overlapOn = isOn(OVERLAP_CMD)
    for i, viewMode in ipairs(itemViewModes) do
        if isOn(viewMode.commandID) then
            if viewMode.overlap == nil or viewMode.overlap == overlapOn then
                return i
            end
        end
    end
    -- If none of the known modes are active, default to the first one
    return 1
end

-- Make sure the overlap option matches the requested state
local function setOverlap(state)
    if isOn(OVERLAP_CMD) ~= state then
        reaper.Main_OnCommand(OVERLAP_CMD, 0)
    end
end

-- Function to toggle to the next item view mode
local function toggleNextItemViewMode()
    local currentIndex = getCurrentItemViewModeIndex()
    local nextIndex = currentIndex + 1
    if nextIndex > #itemViewModes then
        nextIndex = 1
    end
    local nextMode = itemViewModes[nextIndex]

    -- Switch view mode (skip if already active, e.g. going from mode 5 to 6,
    -- so we don't toggle Peaks + Spectrogram back off)
    if not isOn(nextMode.commandID) then
        reaper.Main_OnCommand(nextMode.commandID, 0)
    end

    -- Set the overlap option for modes that care about it
    if nextMode.overlap ~= nil then
        setOverlap(nextMode.overlap)
    end

    reaper.UpdateArrange()
    reaper.defer(function() end) -- Prevent REAPER from creating an undo point / stopping prematurely
    --reaper.ShowConsoleMsg("Item View Mode: " .. nextMode.name .. "\n")
end

-- Toggle to the next item view mode
toggleNextItemViewMode()
