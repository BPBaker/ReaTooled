-- Script to back up the current key bindings
local function backup_key_bindings()
    local kb_file = reaper.GetResourcePath() .. "/reaper-kb.ini"
    local backup_file = kb_file .. ".backup"

    -- Check if a backup already exists
    if reaper.file_exists(backup_file) then
        local choice = reaper.ShowMessageBox(
            "A backup already exists. Overwrite it?", 
            "Backup Exists", 
            4 -- Yes/No
        )
        if choice ~= 6 then -- User selects 'No' or cancels
            reaper.ShowConsoleMsg("Backup canceled.\n")
            return
        end
    end

    -- Open the current key bindings file
    local input_file = io.open(kb_file, "r")
    if not input_file then
        reaper.ShowConsoleMsg("Failed to open reaper-kb.ini for backup.\n")
        return
    end

    -- Create the backup file
    local output_file = io.open(backup_file, "w")
    if not output_file then
        reaper.ShowConsoleMsg("Failed to create backup file.\n")
        input_file:close()
        return
    end

    -- Copy contents
    for line in input_file:lines() do
        output_file:write(line, "\n")
    end

    input_file:close()
    output_file:close()
    reaper.ShowConsoleMsg("Backup created: " .. backup_file .. "\n")
    reaper.ShowMessageBox("Backup completed successfully!", "Backup Complete", 0)
end

backup_key_bindings()

