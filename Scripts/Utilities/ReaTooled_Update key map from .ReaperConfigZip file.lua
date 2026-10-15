-- Backup the existing key bindings
local function backup_current_kb()
    local kb_file = reaper.GetResourcePath() .. "/reaper-kb.ini"
    local backup_file = kb_file .. ".backup"
    
    local input_file = io.open(kb_file, "r")
    if not input_file then
        return false
    end
    
    local output_file = io.open(backup_file, "w")
    if not output_file then
        input_file:close()
        return false
    end
    
    -- Copy file contents
    for line in input_file:lines() do
        output_file:write(line, "\n")
    end
    
    input_file:close()
    output_file:close()
    return true
end

-- Extract reaper-kb.ini from .ReaperConfigZip
local function extract_kb_from_config(config_path)
    -- Determine the output directory (temporary directory in the same location as the zip file)
    local parent_dir = config_path:match("^(.+/)") or "./"
    local temp_dir = parent_dir .. "temp_kb_extraction"

    -- Create the temp directory
    local mkdir_cmd = 'mkdir "' .. temp_dir .. '"'
    local mkdir_result = os.execute(mkdir_cmd)

    if mkdir_result ~= 0 and mkdir_result ~= true then
        return nil, nil
    end

    -- Unzip the file
    local unzip_cmd = 'unzip -o "' .. config_path .. '" -d "' .. temp_dir .. '"'
    local unzip_pipe = io.popen(unzip_cmd)
    if unzip_pipe then
        unzip_pipe:read("*all")
        unzip_pipe:close()
    else
        return nil, temp_dir
    end

    local kb_file = temp_dir .. "/reaper-kb.ini"
    local extracted_file = io.open(kb_file, "r")
    if extracted_file then
        extracted_file:close()
        return kb_file, temp_dir
    else
        return nil, temp_dir
    end
end

-- Clean up temporary directory
local function cleanup_temp_dir(temp_dir)
    if temp_dir and temp_dir ~= "" then
        os.execute('rm -rf "' .. temp_dir .. '"') -- Remove temp directory
    end
end

-- Update the existing key bindings file with the extracted one
local function update_key_bindings(new_kb_path)
    local user_kb_path = reaper.GetResourcePath() .. "/reaper-kb.ini"
    
    -- Backup the existing key bindings file
    if not backup_current_kb() then
        reaper.ShowMessageBox("Failed to back up the existing key bindings file.", "Error", 0)
        return false
    end

    -- Replace the user's key bindings with the new key bindings
    local input_file = io.open(new_kb_path, "r")
    if not input_file then
        reaper.ShowMessageBox("Failed to open the new key bindings file.", "Error", 0)
        return false
    end

    local output_file = io.open(user_kb_path, "w")
    if not output_file then
        input_file:close()
        reaper.ShowMessageBox("Failed to write to the key bindings file.", "Error", 0)
        return false
    end

    for line in input_file:lines() do
        output_file:write(line, "\n")
    end

    input_file:close()
    output_file:close()

    return true
end

-- Main function
local function update_key_map()
    -- Prompt the user with instructions
    reaper.ShowMessageBox(
        "Please select the .ReaperConfigZip file containing a key map to be imported.",
        "Select Configuration File", 
        0
    )
    
    -- Prompt user to select the ReaTooled .ReaperConfigZip file
    local retval, config_path = reaper.GetUserFileNameForRead("", "Select ReaTooled.ReaperConfigZip", "*.ReaperConfigZip")
    if not retval then
        return
    end

    -- Extract reaper-kb.ini from the selected configuration file
    local new_kb_path, temp_dir = extract_kb_from_config(config_path)
    if not new_kb_path then
        cleanup_temp_dir(temp_dir)
        return
    end

    -- Update the key bindings
    if update_key_bindings(new_kb_path) then
        local update_choice = reaper.ShowMessageBox(
            "Key bindings updated successfully! REAPER must restart to reload the updated key map.\nWould you like to restart REAPER now?",
            "Update Complete", 4)

        if update_choice == 6 then -- User chooses 'Yes'
            reaper.Main_OnCommand(40004, 0) -- REAPER action: Quit REAPER
        end
    else
        reaper.ShowMessageBox("Failed to update key bindings.", "Error", 0)
    end

    -- Clean up temporary directory
    cleanup_temp_dir(temp_dir)
end

-- Execute the main function
update_key_map()
