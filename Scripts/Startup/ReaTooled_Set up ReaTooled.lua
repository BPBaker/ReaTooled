--[[
-- @description ReaTooled - Set up ReaTooled
-- @version 1.0
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Sets up ReaTooled after ReaBoot (or ReaPack) has installed it
    Run this once from the Actions list. It:
      1. Checks that the extensions and the scripts by other developers
         that ReaTooled uses are installed
      2. Backs up your REAPER settings (the first time, to
         Data/ReaTooled/Backups/Before ReaTooled)
      3. Tells ReaPack to install every ReaTooled package, now and
         whenever new ones are added
      4. Adds the ReaTooled block to Scripts/__startup.lua
    Then it tells you how to import the ReaTooled configuration.
    Safe to run again: later runs make a new dated backup and update
    the startup block.
-- CHANGELOG
-- v1.0 Initial version
--]]

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local REPO_NAME = "ReaTooled"   -- must match the index name, never change it
local REPO_URL  = "https://raw.githubusercontent.com/BPBaker/ReaTooled/main/index.xml"

-- The configuration file buyers download (named in the last message)
local CONFIG_FILE = "ReaTooled.ReaperConfigZip"

-- Extensions ReaTooled needs: { name, an API function that only exists when it's installed }
local EXTENSIONS = {
  { "SWS/S&M extension", "CF_GetSWSVersion" },
  { "js_ReaScriptAPI",   "JS_ReaScriptAPI_Version" },
  { "ReaImGui",          "ImGui_CreateContext" },
}

-- Scripts by other developers, relative to REAPER's Scripts folder
local OUTSIDE_SCRIPTS = {
  "ReaTeam Scripts/Cursor/Place play cursor into view (when playing) or Center edit cursor (when stopped).eel",
  "ReaTeam Scripts/Items Editing/az_Fade tool (work on context of mouse, razor or time selection).lua",
  "ReaTeam Scripts/Items Editing/az_Open item copy in primary external editor with handles.lua",
  "ReaTeam Scripts/Items Editing/rodilab_Duplicate items or tracks (depending on focus and time selection).lua",
  "ReaTeam Scripts/Items Properties/rodilab_Loop section of audiomidi item source within time selection, if any.lua",
  "ReaTeam Scripts/Various/rodilab_Color palette.lua",
  "X-Raym Scripts/Envelopes/On Tracks/X-Raym_Add envelope points at time selection edges from center to center preserving edges.lua",
  "X-Raym Scripts/FX/X-Raym_Set selected tracks FX parameter value from last focused FX last touch parameter.lua",
  "X-Raym Scripts/Items Editing/X-Raym_Move selected items to end of previous items on all visible tracks.lua",
  "X-Raym Scripts/Items Editing/X-Raym_Move selected items to next item on all visible tracks.lua",
  "X-Raym Scripts/Razor Edit/X-Raym_Set selected tracks razor edit area to time selection.lua",
  "MPL Scripts/FX/mpl_Add 0.01 to normalized last touched parameter.lua",
  "MPL Scripts/FX/mpl_Subtract 0.01 from normalized last touched parameter.lua",
  "MPL Scripts/Various/mpl_ImportSessionData.lua",
  "TJF Scripts/Editing/Reverse/TJF Non Destructive Reverse Time selection.lua",
  "TJF Scripts/Editing/Takes/TJF Toggle Mute (Match First Selected).lua",
  "TJF Scripts/Editing/TJF Toggle Item Lock (matches first item).lua",
  "TJF Scripts/Envelopes or Automation/TJF Write Punch ALL envelopes to Time, RazorEdit, or Item Selection.lua",
  "TJF Scripts/Session Navigation/TJF Decrease Selected Track Heights.lua",
  "TJF Scripts/Session Navigation/TJF Increase Selected Track Heights.lua",
}

------------------------------------------------------------

local TITLE        = "Set up ReaTooled"
local SETUP_VER    = "1.0"
local RES          = reaper.GetResourcePath():gsub("\\", "/")
local BACKUP_ROOT  = RES .. "/Data/ReaTooled/Backups"
local FIRST_BACKUP = BACKUP_ROOT .. "/Before ReaTooled"
local HOOK_SCRIPT  = RES .. "/Scripts/ReaTooled/Startup/ReaTooled_Install startup hook.lua"

local function msg(text, buttons)
  return reaper.ShowMessageBox(text, TITLE, buttons or 0)
end

local function exists(path)
  return reaper.file_exists(path)
end

local function copy_file(src, dst)
  local fin = io.open(src, "rb")
  if not fin then return false end
  local data = fin:read("*all")
  fin:close()
  local fout = io.open(dst, "wb")
  if not fout then return false end
  fout:write(data)
  fout:close()
  return true
end

------------------------------------------------------------
-- 1. Check what's installed
------------------------------------------------------------

if not reaper.APIExists("ReaPack_AddSetRepository") then
  msg("ReaPack is not installed, so ReaTooled can't be set up.\n\n" ..
      "Install ReaTooled with the ReaBoot link from the guide, or install " ..
      "ReaPack from reapack.com, restart REAPER and run this again.")
  return
end

local missing = {}
for _, ext in ipairs(EXTENSIONS) do
  if not reaper.APIExists(ext[2]) then missing[#missing + 1] = "  " .. ext[1] end
end
for _, rel in ipairs(OUTSIDE_SCRIPTS) do
  if not exists(RES .. "/Scripts/" .. rel) then
    missing[#missing + 1] = "  " .. rel:match("([^/]+)$")
  end
end

local first_run = not exists(FIRST_BACKUP .. "/backup_info.txt")

------------------------------------------------------------
-- Confirm
------------------------------------------------------------

local intro = "This will:\n\n" ..
  "1. Back up your REAPER settings" ..
  (first_run and " (to Data/ReaTooled/Backups/Before ReaTooled)\n" or " (a new dated backup)\n") ..
  "2. Tell ReaPack to install every ReaTooled script\n" ..
  "3. Add ReaTooled to REAPER's startup script (your own startup code is kept)\n\n" ..
  "Nothing else is changed. Continue?"

if #missing > 0 then
  intro = "Some things ReaTooled uses are not installed:\n\n" ..
    table.concat(missing, "\n") ..
    "\n\nThe ReaTooled tools that use them won't work until they are. " ..
    "Installing with the ReaBoot link from the guide adds all of them.\n\n" ..
    "You can set up ReaTooled anyway and add these later.\n\n" .. intro
end

if msg(intro, 1) ~= 1 then return end   -- OK / Cancel

------------------------------------------------------------
-- 2. Back up
------------------------------------------------------------

local function backup_to(dir)
  reaper.RecursiveCreateDirectory(dir, 0)
  local copied, failed = 0, {}

  -- Every file in the resource folder (reaper.ini, reaper-kb.ini, menus,
  -- mouse modifiers, screensets, S&M.ini, reapack.ini ...)
  reaper.EnumerateFiles(RES, -1)  -- refresh REAPER's file list cache
  local i = 0
  while true do
    local name = reaper.EnumerateFiles(RES, i)
    if not name then break end
    if not name:lower():match("%.log$") then
      if copy_file(RES .. "/" .. name, dir .. "/" .. name) then
        copied = copied + 1
      else
        failed[#failed + 1] = name
      end
    end
    i = i + 1
  end

  -- The user's startup script
  local startup = RES .. "/Scripts/__startup.lua"
  if exists(startup) then
    reaper.RecursiveCreateDirectory(dir .. "/Scripts", 0)
    if copy_file(startup, dir .. "/Scripts/__startup.lua") then
      copied = copied + 1
    else
      failed[#failed + 1] = "Scripts/__startup.lua"
    end
  end

  local info = io.open(dir .. "/backup_info.txt", "wb")
  if info then
    info:write("ReaTooled backup\n",
      "Date: ", os.date("%Y-%m-%d %H:%M:%S"), "\n",
      "REAPER: ", reaper.GetAppVersion(), "\n",
      "Files: ", copied, "\n")
    info:close()
  else
    failed[#failed + 1] = "backup_info.txt"
  end

  return #failed == 0, failed
end

local backup_dir = first_run and FIRST_BACKUP or (BACKUP_ROOT .. "/" .. os.date("%Y-%m-%d_%H%M%S"))
local backed_up, failed = backup_to(backup_dir)
if not backed_up then
  msg("The backup did not finish, so nothing was changed.\n\n" ..
      "Could not copy:\n  " .. table.concat(failed, "\n  ") ..
      "\n\nBackup folder:\n" .. backup_dir)
  return
end

------------------------------------------------------------
-- 3. ReaPack: install every ReaTooled package
------------------------------------------------------------

-- autoInstall = 1: when ReaPack synchronizes, it installs any ReaTooled
-- package that isn't installed yet (now, and new scripts added later).
local repo_ok, repo_err = reaper.ReaPack_AddSetRepository(REPO_NAME, REPO_URL, true, 1, true, "")
local repo_note
if repo_ok then
  repo_note = "ReaPack will install every ReaTooled script."
else
  repo_note = "Could not update the ReaTooled repository in ReaPack" ..
    (repo_err and repo_err ~= "" and (" (" .. repo_err .. ")") or "") .. ".\n" ..
    "Install the scripts by hand: Extensions > ReaPack > Manage repositories, " ..
    "right-click ReaTooled > Install all packages in this repository."
end

------------------------------------------------------------
-- 4. Startup hook
------------------------------------------------------------

local hook_note
if exists(HOOK_SCRIPT) then
  _G.REATOOLED_SETUP = {}
  local ran, err = pcall(dofile, HOOK_SCRIPT)
  local result = _G.REATOOLED_SETUP
  _G.REATOOLED_SETUP = nil
  if ran and result.ok then
    hook_note = result.result or "Added the ReaTooled startup block."
  else
    hook_note = "The startup block was NOT added: " ..
      tostring(ran and result.result or err) ..
      "\nRun 'ReaTooled - Install startup hook' from the Actions list to try again."
  end
else
  hook_note = "The startup block was NOT added: could not find\n" .. HOOK_SCRIPT
end

reaper.SetExtState("ReaTooled", "SetupVersion", SETUP_VER, true)

------------------------------------------------------------
-- Done: what's left for the user
------------------------------------------------------------

msg("ReaTooled is almost ready.\n\n" ..
  "Your settings were backed up to:\n" .. backup_dir .. "\n\n" ..
  repo_note .. "\n" ..
  hook_note .. "\n\n" ..
  "WHAT TO DO NEXT\n\n" ..
  (repo_ok and "1. When you click OK, ReaPack downloads the ReaTooled scripts. " ..
               "Wait until it says it's finished.\n" or
               "1. Install the ReaTooled scripts as described above.\n") ..
  "2. Open Options > Preferences > General and click Import configuration.\n" ..
  "3. Choose " .. CONFIG_FILE .. " (the file you downloaded with your purchase) and import it.\n" ..
  "4. Restart REAPER.")

-- Start the download after the message, so ReaPack's window isn't hidden behind it
if repo_ok then
  local sync = reaper.NamedCommandLookup("_REAPACK_SYNC")
  if sync ~= 0 then reaper.Main_OnCommand(sync, 0) end
end
