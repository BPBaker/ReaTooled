local CMD_ID_1 = reaper.NamedCommandLookup("_RS21aa0b14cf72a27be535d32efe0d05513523aec9")
local CMD_ID_2 = reaper.NamedCommandLookup("_RSd77ea649952c67db183a19cece290cf3e1b3d49d")
local CMD_ID_3 = reaper.NamedCommandLookup("_RSb08c9a159d1a7537eda8df72b777b1cc4c9422e8")
local CMD_ID_4 = reaper.NamedCommandLookup("_RSc2c7d733888679038b4a4341074dc703d0f7f9c2")
local CMD_ID_7 = reaper.NamedCommandLookup("_RS5e85a066efd01fde2482832bf4a3502dce0427b6")

    -- Set toolbar button states for additional scripts/buttons
    reaper.SetToggleCommandState(0, CMD_ID_1, 0) -- Turn off button 1
    reaper.SetToggleCommandState(0, CMD_ID_2, 1) -- Turn off button 2
    reaper.SetToggleCommandState(0, CMD_ID_3, 1) -- Turn off button 3
    reaper.SetToggleCommandState(0, CMD_ID_4, 1) -- Turn off button 4
    reaper.SetToggleCommandState(0, CMD_ID_7, 7) -- Turn off button 7
    reaper.RefreshToolbar(0)
