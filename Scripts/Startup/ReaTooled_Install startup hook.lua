--[[
-- @description ReaTooled - Install startup hook
-- @version 1.0
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
    # Adds or removes ReaTooled's block in Scripts/__startup.lua
    Leaves everything else in the file alone, so a user's own startup
    code keeps working. Backs the file up before every change, to
    Data/ReaTooled/Backups/startup/.
    Also disables the lines from the old ReaTooled __startup.lua (v1.x),
    so nothing launches twice.
--]]

local RES        = reaper.GetResourcePath():gsub("\\", "/")
local STARTUP    = RES .. "/Scripts/__startup.lua"
local BACKUP_DIR = RES .. "/Data/ReaTooled/Backups/startup"
local TITLE      = "ReaTooled startup hook"

local BEGIN_MARK = "-- >>> ReaTooled startup"
local END_MARK   = "-- <<< ReaTooled startup <<<"

local BLOCK = {
  "-- >>> ReaTooled startup (added by the ReaTooled installer - delete this block to disable) >>>",
  "do",
  '  local f = reaper.GetResourcePath() .. "/Scripts/ReaTooled/Startup/ReaTooled_Startup.lua"',
  "  if reaper.file_exists(f) then pcall(dofile, f) end",
  "end",
  END_MARK,
}

-- Command IDs launched by the old ReaTooled __startup.lua (v1.x)
local OLD_IDS = {
  "_RS28b2f63ccd2b4bcf1f44d9a3a17d59a2212aa5be", -- Recall ReaTooled Button States
  "_RS758705a4680c728ce012a14e6d90afa92b95b555", -- Synch razor areas on grouped items
  "_RSa6389ff858fd433deebc5e57f089985501608ea9", -- Link razor area and item selection
  "_RSe798c955e1c0823f30436ff5d366b9dce0c96e64", -- At loop end, move cursor...
  "_RS5e85a066efd01fde2482832bf4a3502dce0427b6", -- Default Multi Tool (Smart)
  "_RS4db278d8e4b6bb56b0e13d75ab3923d6115e4cc3", -- Grid and Nudge Settings
}
local DISABLED_PREFIX = "-- [disabled by ReaTooled installer] "

------------------------------------------------------------

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*all")
  f:close()
  return data
end

local function write_file(path, data)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

local function split_lines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do out[#out + 1] = line end
  if out[#out] == "" then out[#out] = nil end
  return out
end

local function backup(text)
  reaper.RecursiveCreateDirectory(BACKUP_DIR, 0)
  local path = BACKUP_DIR .. "/__startup_" .. os.date("%Y-%m-%d_%H%M%S") .. ".lua"
  return write_file(path, text) and path or nil
end

-- Removes every ReaTooled block (from a BEGIN_MARK line to an END_MARK line)
local function remove_block(lines)
  local out, inside, found = {}, false, false
  for _, line in ipairs(lines) do
    if not inside and line:find(BEGIN_MARK, 1, true) then
      inside, found = true, true
    elseif inside then
      if line:find(END_MARK, 1, true) then inside = false end
    else
      out[#out + 1] = line
    end
  end
  -- drop blank lines left at the end
  while #out > 0 and out[#out]:match("^%s*$") do out[#out] = nil end
  return out, found
end

-- Every script ID registered from Scripts/ReaTooled/, read from reaper-kb.ini.
-- Catches old startup lines for any ReaTooled script, not just the known ones.
local function reatooled_ids()
  local ids = {}
  for _, id in ipairs(OLD_IDS) do ids[id] = true end
  local kb = read_file(RES .. "/reaper-kb.ini")
  if kb then
    for line in (kb .. "\n"):gmatch("(.-)\r?\n") do
      if line:match("^SCR%s") then
        local id, rest = line:match("^SCR%s+%S+%s+%S+%s+(%S+)%s+(.*)$")
        if id and rest and rest:gsub("\\", "/"):lower():find("reatooled/", 1, true) then
          ids[(id:sub(1, 1) == "_") and id or ("_" .. id)] = true
        end
      end
    end
  end
  return ids
end

-- Comments out active lines (outside the ReaTooled block) that launch
-- ReaTooled scripts, so nothing runs twice
local function disable_old(lines)
  local ids = reatooled_ids()
  local count = 0
  for i, line in ipairs(lines) do
    if not line:match("^%s*%-%-") then
      for token in line:gmatch("_?RS%x+") do
        local id = (token:sub(1, 1) == "_") and token or ("_" .. token)
        if ids[id] then
          lines[i] = DISABLED_PREFIX .. line
          count = count + 1
          break
        end
      end
    end
  end
  return lines, count
end

------------------------------------------------------------

local choice = reaper.ShowMessageBox(
  "YES = add or update the ReaTooled startup block\n" ..
  "NO = remove the ReaTooled startup block\n\n" ..
  "Everything else in __startup.lua is left as it is, and the file is backed up first.",
  TITLE, 3)  -- Yes / No / Cancel

if choice ~= 6 and choice ~= 7 then return end

local text = read_file(STARTUP)
local eol = (text and text:find("\r\n", 1, true)) and "\r\n" or "\n"
local lines = text and split_lines(text) or {}

local backup_path = nil
if text and #text > 0 then
  backup_path = backup(text)
  if not backup_path then
    reaper.ShowMessageBox("Could not back up __startup.lua, so nothing was changed.", TITLE, 0)
    return
  end
end

local had_block
lines, had_block = remove_block(lines)

local summary
if choice == 6 then
  local disabled
  lines, disabled = disable_old(lines)
  -- Put the block at the TOP of the file: if the user's own code below has
  -- an error or an early 'return', ReaTooled still starts. The pcall inside
  -- the block means a ReaTooled error can't stop their code either.
  local new_lines = {}
  for _, l in ipairs(BLOCK) do new_lines[#new_lines + 1] = l end
  if #lines > 0 then new_lines[#new_lines + 1] = "" end
  for _, l in ipairs(lines) do new_lines[#new_lines + 1] = l end
  lines = new_lines
  summary = (had_block and "Updated" or "Added") .. " the ReaTooled startup block."
  if disabled > 0 then
    summary = summary .. "\nDisabled " .. disabled .. " line(s) from the old ReaTooled startup script."
  end
  summary = summary .. "\n\nRestart REAPER for it to take effect."
else
  if not had_block then
    reaper.ShowMessageBox("There is no ReaTooled startup block in __startup.lua. Nothing was changed.", TITLE, 0)
    return
  end
  summary = "Removed the ReaTooled startup block.\n\nRestart REAPER for it to take effect."
end

local new_text = (#lines > 0) and (table.concat(lines, eol) .. eol) or ""
if not write_file(STARTUP, new_text) then
  reaper.ShowMessageBox("Could not write __startup.lua. Nothing was changed.", TITLE, 0)
  return
end

if backup_path then
  summary = summary .. "\n\nBackup of the previous file:\n" .. backup_path
end
reaper.ShowMessageBox(summary, TITLE, 0)
