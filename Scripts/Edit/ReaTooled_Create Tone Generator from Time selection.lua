-- @description ReaTooled - Create Tone Generator from Time Selection
-- @version 1.0
-- @date 2024.06.17
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # This script creates an empty MIDI item from the time selection and ads a tone generator JS effect to the item -- good for "beeping out" sections of audio.
-- CHANGELOG


-- Get the current time selection
local time_sel_start, time_sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

-- Ensure a time selection is made
if time_sel_start == time_sel_end then
    reaper.ShowMessageBox("No time selection made", "Error", 0)
    return
end

-- Get the current track
local track = reaper.GetSelectedTrack(0, 0)

-- Ensure a track is selected
if track == nil then
    reaper.ShowMessageBox("No track selected", "Error", 0)
    return
end

-- Run the command to insert or extend MIDI items to fill time selection
reaper.Main_OnCommand(42069, 0)  

-- Run the command to select all items on selected tracks in the current time selection
reaper.Main_OnCommand(40718, 0)    

-- Get the selected item count
local selected_item_count = reaper.CountSelectedMediaItems(0)

-- Ensure an item is selected
if selected_item_count == 0 then
    reaper.ShowMessageBox("No MIDI item was selected", "Error", 0)  
    return
end

-- Add Tone Generator JS effect to the selected MIDI item
-- Tone Generator JSFX path is typically: 'JS:  Tone Generator'
local fx_name = "JS: Tone Generator"
for i = 0, selected_item_count - 1 do
    local midi_item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetMediaItemTake(midi_item, 0)  
    if take and reaper.TakeIsMIDI(take) then
        local fx_index = reaper.TakeFX_AddByName(take, fx_name, 1)
        if fx_index == -1 then
            reaper.ShowMessageBox("Could not add Tone Generator JSFX", "Error", 0)
        end
    else
        reaper.ShowMessageBox("Selected item is not a MIDI item", "Error", 0)
    end
end

-- Update the arrangement view
reaper.UpdateArrange()

