-- @description ReaTooled - Merge backup key map with current key map
-- @version 1.0
-- @date 2025.01.03
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
--   This script compares the "reaper-kb.ini.backup" file created with the script "ReaTooled_Create backup key map.lua"
--   with the current key map saved in "reaper-kb.ini" and prompts the user to add any missing shortcuts from the backup.
--   v1.0 - initial release

-- Load REAPER API
local reaper = reaper

-- Define file paths
local resourcePath = reaper.GetResourcePath()
local newKbFilePath = resourcePath .. "/reaper-kb.ini"
local oldKbFilePath = resourcePath .. "/reaper-kb.ini.backup"

-- Generate a timestamped backup file name
local function generateTimestampedBackupName()
    local time = os.date("%Y%m%d%H%M%S")
    return resourcePath .. "/reaper-kb.ini.backup." .. time
end

-- Function to parse a binding line into shortcut and action text
local function parseBindingLine(line)
    -- Match KEY format
    local shortcut, actionText = line:match('KEY%s+[%d%s]+%s+_[%w_]+%s+[%d%s]+%s+#.*:%s([^:]+)%s:%s(.+)$')
    if shortcut and actionText then
        return shortcut, actionText
    end

    -- Match ACT format
    shortcut, actionText = line:match('ACT%s+[%d%s]+%s+"[^"]+"%s+"([^"]+)"%s+[^"%s]+$')
    if shortcut and actionText then
        return shortcut, actionText
    end

    -- Match SCR format
    shortcut, actionText = line:match('SCR%s+[%d%s]+%s+[%w_]+%s+"Custom:%s([^"]+)"%s+"([^"]+)"$')
    if shortcut and actionText then
        return shortcut, actionText
    end

    -- Match older or unstructured formats
    shortcut, actionText = line:match('KEY%s+[%d%s]+%s+#[^:]+:%s*([^:]+)%s*:%s*(.+)$')
    if shortcut and actionText then
        return shortcut, actionText
    end

    -- Match lines with custom commands and descriptions
    shortcut, actionText = line:match('KEY%s+[%d%s]+%s+"([^"]+)"%s+"([^"]+)"')
    if shortcut and actionText then
        return shortcut, actionText
    end

    -- Match lines with no shortcut but a description
    actionText = line:match('#.*:%s([^:]+)$')
    if actionText then
        return "No Shortcut", actionText
    end

    -- Log unrecognized lines for debugging
    reaper.ShowConsoleMsg("Failed to parse line: " .. (line or "nil") .. "\n")
    return "Unknown Shortcut", "Unknown Action"
end

-- Function to read a key bindings file
local function readKeyBindings(filePath)
    local file = io.open(filePath, "r")
    if not file then
        return nil, "Error: Cannot open the file: " .. filePath
    end

    local content = {}
    for line in file:lines() do
        table.insert(content, line)
    end
    file:close()
    return content, nil
end

-- Function to write key bindings to a file
local function writeKeyBindings(filePath, content)
    local file = io.open(filePath, "w")
    if not file then
        return false, "Error: Cannot write to file: " .. filePath
    end

    for _, line in ipairs(content) do
        file:write(line .. "\n")
    end
    file:close()
    return true, nil
end

-- Function to create a timestamped backup of the new key bindings file
local function createBackup(filePath)
    local backupFilePath = generateTimestampedBackupName()
    local success, err = os.rename(filePath, backupFilePath)
    if not success then
        reaper.ShowMessageBox("Failed to create a timestamped backup.\n\n" .. err, "Warning", 0)
        return false
    end
    return true
end

-- Function to find unique bindings in the old file not in the new file
local function findUniqueBindings(oldBindings, newBindings)
    local newSet = {}
    for _, line in ipairs(newBindings) do
        newSet[line] = true
    end

    local unique = {}
    for _, line in ipairs(oldBindings) do
        if not newSet[line] then
            table.insert(unique, line)
        end
    end

    return unique
end

-- Function to confirm adding unique bindings
local function confirmAndAddBindings(uniqueBindings, mergedBindings)
    for _, line in ipairs(uniqueBindings) do
        local shortcut, actionText = parseBindingLine(line)
        local message = "The current key map doesn't include your old shortcut:\n\nShortcut: " .. (shortcut or "Unknown") .. "\nAction: " .. (actionText or "Unknown") .. "\n\nAdd this binding to the updated file?"
        local choice = reaper.ShowMessageBox(message, "Add this back to the new key map?", 4)

        if choice == 6 then -- Yes button
            table.insert(mergedBindings, line)
        end
    end
end

-- Main Workflow
local oldBindings, err = readKeyBindings(oldKbFilePath)
if not oldBindings then
    reaper.ShowMessageBox("Failed to load old key bindings.\n\n" .. err, "Error", 0)
    return
end

local newBindings, err = readKeyBindings(newKbFilePath)
if not newBindings then
    reaper.ShowMessageBox("Failed to load new key bindings.\n\n" .. err, "Error", 0)
    return
end

local uniqueBindings = findUniqueBindings(oldBindings, newBindings)
if #uniqueBindings > 0 then
    local promptMessage = "There are " .. #uniqueBindings .. " shortcuts from the backup not present in the current key map.\n\nWould you like to add all of them at once?"
    local promptChoice = reaper.ShowMessageBox(promptMessage, "Choose an option", 3)

    if promptChoice == 6 then -- Add all at once
        for _, line in ipairs(uniqueBindings) do
            table.insert(newBindings, line)
        end
    elseif promptChoice == 7 then -- Go through one by one
        confirmAndAddBindings(uniqueBindings, newBindings)
    else -- Cancel operation
        reaper.ShowMessageBox("Operation canceled.", "Info", 0)
        return
    end
end

if not createBackup(newKbFilePath) then
    return
end

local success, err = writeKeyBindings(newKbFilePath, newBindings)
if not success then
    reaper.ShowMessageBox("Failed to save updated key bindings.\n\n" .. err, "Error", 0)
    return
end

reaper.ShowMessageBox("Key bindings updated successfully.", "Success", 0)

-- Prompt to restart REAPER
local restartChoice = reaper.ShowMessageBox("Key bindings have been updated. Do you want to restart REAPER now?", "Restart REAPER", 4)
if restartChoice == 6 then -- Yes button
    reaper.Main_OnCommand(40004, 0) -- Quit REAPER
end
