-- Define the command ID for normalizing items
local commandID = 42463  -- Command ID for "Item properties: Normalize items using most recent settings (common gain)"

-- Function to run command on new items
function RunCommandOnNewItem(item, commandID)
    if commandID ~= nil and commandID ~= 0 then
        -- Check if the item is selected
        local isNew = reaper.GetMediaItemInfo_Value(item, "B_UISEL")
        if isNew == 1 then
            -- Run the command to normalize item
            reaper.Main_OnCommand(commandID, 0)  -- Normalize item using specified command ID
        end
    end
end

-- Define the hook function to detect new items
function onItemAdd(commandID)
    local project = 0 -- 0 for current project
    local num_items = reaper.CountMediaItems(project)
    if num_items > 0 then
        local item = reaper.GetMediaItem(project, num_items - 1) -- Get the last item added
        if item then
            RunCommandOnNewItem(item, commandID)
        end
    end
end

-- Function to run command on new files added through drag and drop
function RunCommandOnNewFiles(commandID)
    local last_file_count = reaper.CountMediaItems(0)
    reaper.defer(function()
        local current_file_count = reaper.CountMediaItems(0)
        if current_file_count > last_file_count then
            onItemAdd(commandID)
            last_file_count = current_file_count
        end
        reaper.defer(RunCommandOnNewFiles, commandID)
    end)
end

-- Call the function to set the hook for new items
function SetItemHook(commandID)
    local last_item_count = reaper.CountMediaItems(0)
    reaper.defer(function()
        local current_item_count = reaper.CountMediaItems(0)
        if current_item_count > tonumber(last_item_count) then
            onItemAdd(commandID)
            last_item_count = current_item_count
        end
        reaper.defer(SetItemHook, commandID)
    end)
end

-- Call the functions to set the hooks
SetItemHook(commandID)
RunCommandOnNewFiles(commandID)

-- Function to remove the hooks
function RemoveHooks()
    -- No explicit removal needed as hooks are implemented with deferred functions
end

-- Optionally, to remove the hooks when script ends or when not needed
-- Call RemoveHooks() when you want to stop the script from checking for new items or files

