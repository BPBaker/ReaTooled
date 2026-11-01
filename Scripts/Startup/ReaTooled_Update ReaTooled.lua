--[[
-- @description ReaTooled - Update ReaTooled
-- @version 1.0
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Updates ReaTooled in one step
    Checks GitHub for the newest ReaTooled release. If there is one, ReaPack downloads
    it, then "Set up ReaTooled" applies it in update mode: your own shortcuts, toolbar
    changes and settings are kept, shortcut clashes are asked about, your window layout
    and screensets are left alone, and everything is backed up first. REAPER restarts
    at the end.
    Also run by ReaTooled's startup once a day (quietly): if a newer release is out, it
    asks whether to update now.
    CHANGELOG
    v1.0 Initial version
--]]

local TITLE       = "Update ReaTooled"
local VERSION_URL = "https://raw.githubusercontent.com/BPBaker/ReaTooled/main/Data/ReaTooled/Config/version.txt"
local REPO_NAME   = "ReaTooled"
local REPO_URL    = "https://raw.githubusercontent.com/BPBaker/ReaTooled/main/index.xml"
local SYNC_WAIT   = 300   -- seconds to wait for ReaPack's download

local RES     = reaper.GetResourcePath():gsub("\\", "/")
local CONFIG  = RES .. "/Data/ReaTooled/Config"
local BACKUPS = RES .. "/Data/ReaTooled/Backups"
local SETUP   = RES .. "/Scripts/ReaTooled/Startup/ReaTooled_Set up ReaTooled.lua"
local IS_WIN  = reaper.GetOS():match("Win") ~= nil

-- Started by ReaTooled's startup (once a day): quiet unless there's an update
local QUIET = _G.REATOOLED_UPDATE_CHECK == true
_G.REATOOLED_UPDATE_CHECK = nil

local function msg(text, buttons) return reaper.ShowMessageBox(text, TITLE, buttons or 0) end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*all")
  f:close()
  return d
end

local function parts(v)
  local t = {}
  for n in (v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
  return t
end
local function newer(a, b)   -- is version a newer than b?
  local x, y = parts(a), parts(b)
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p > q end
  end
  return false
end

-- The release ReaPack has downloaded (the configuration package)
local function downloaded()
  return (read_file(CONFIG .. "/version.txt") or ""):match("[%d%.]+")
end

-- The release last applied (the newest setup/update record)
local function applied()
  local best_key, best_ver
  reaper.EnumerateSubdirectories(BACKUPS, -1)
  local i = 0
  while true do
    local d = reaper.EnumerateSubdirectories(BACKUPS, i)
    if not d then break end
    local rec = read_file(BACKUPS .. "/" .. d .. "/applied/record.txt")
    if rec then
      local key = (d == "Before ReaTooled") and "0000" or d
      if not best_key or key > best_key then best_key, best_ver = key, rec:match("\nConfig ([%d%.]+)") end
    end
    i = i + 1
  end
  return best_ver
end

-- curl ships with macOS and Windows 10/11 (and nearly every Linux)
local function curl_cmd()
  return (IS_WIN and "curl.exe" or "curl") .. ' -sL -m 10 "' .. VERSION_URL .. '"'
end
local function parse_remote(out)
  -- ExecProcess: the exit code, a newline, then the output
  local code, body = (out or ""):match("^(%-?%d+)\n(.*)$")
  if code ~= "0" then return nil end
  return (body or ""):match("^%s*(%d+%.[%d%.]+)%s*$")
end

------------------------------------------------------------
-- Applying: Set up ReaTooled in update mode
------------------------------------------------------------

local function apply_update()
  if not reaper.file_exists(SETUP) then
    msg("\"Set up ReaTooled\" is missing, so the update can't be applied.\n\n" .. SETUP)
    return
  end
  _G.REATOOLED_UPDATE = "confirmed"   -- (asked already: Set up skips its own first question)
  local ok, err = pcall(dofile, SETUP)
  _G.REATOOLED_UPDATE = nil
  if not ok then msg("The update couldn't be applied:\n\n" .. tostring(err)) end
end

-- ReaPack downloads the new release; once its configuration has arrived, it's applied
local function download_then_apply(remote)
  if not reaper.APIExists("ReaPack_AddSetRepository") then
    msg("ReaPack isn't installed, so the update can't be downloaded.")
    return
  end
  -- (the ReaTooled repository on, installing everything in it)
  reaper.ReaPack_AddSetRepository(REPO_NAME, REPO_URL, true, 1, "")
  local sync = reaper.NamedCommandLookup("_REAPACK_SYNC")
  if sync == 0 then msg("ReaPack's \"Synchronize packages\" wasn't found.") return end
  reaper.Main_OnCommand(sync, 0)
  local start = reaper.time_precise()
  local function wait()
    local have = downloaded()
    if have and not newer(remote, have) then
      reaper.defer(apply_update)   -- (after ReaPack's window has had a moment to finish)
      return
    end
    if reaper.time_precise() - start > SYNC_WAIT then
      msg("ReaPack hasn't finished downloading ReaTooled v" .. remote .. " yet.\n\n" ..
          "When it's done, run \"Update ReaTooled\" again to apply it.")
      return
    end
    reaper.defer(wait)
  end
  reaper.defer(wait)
end

------------------------------------------------------------
-- Deciding
------------------------------------------------------------

local function decide(remote)
  local have, done = downloaded(), applied()
  local current = done or have or "?"
  if remote and newer(remote, have or "0") then
    local a = msg("ReaTooled v" .. remote .. " is available (you have v" .. current .. ").\n\n" ..
      "Update now? It's downloaded, your settings are backed up, your own changes and window " ..
      "layout are kept, and REAPER restarts at the end.", 4)   -- Yes / No
    if a == 6 then download_then_apply(remote) end
  elseif have and done and newer(have, done) then
    -- downloaded already (ReaPack synced) but not applied yet
    local a = msg("ReaTooled v" .. have .. " has been downloaded but isn't applied yet (you have v" .. done .. ").\n\n" ..
      "Update now? Your settings are backed up, your own changes and window layout are kept, " ..
      "and REAPER restarts at the end.", 4)
    if a == 6 then apply_update() end
  elseif not QUIET then
    if remote then
      msg("ReaTooled is up to date (v" .. current .. ").")
    else
      msg("Couldn't reach GitHub to check for a newer ReaTooled (no internet connection?).\n\n" ..
          "You have v" .. current .. ".")
    end
  end
end

if QUIET then
  -- In the background: curl runs without REAPER waiting; its answer is read when it's done
  local tmp = (os.getenv(IS_WIN and "TEMP" or "TMPDIR") or "/tmp"):gsub("\\", "/"):gsub("/$", "") ..
              "/reatooled_latest_version.txt"
  os.remove(tmp)
  local cmd = (IS_WIN and "curl.exe" or "curl") .. ' -sL -m 10 -o "' .. tmp .. '" "' .. VERSION_URL .. '"'
  reaper.ExecProcess(cmd, -1)
  local start, last = reaper.time_precise(), nil
  local function poll()
    local text = read_file(tmp)
    -- (the same twice in a row: curl has finished writing it)
    local remote = text and text == last and text:match("^%s*(%d+%.[%d%.]+)%s*$")
    last = text
    if remote then
      os.remove(tmp)
      decide(remote)
    elseif reaper.time_precise() - start < 20 then
      reaper.defer(poll)
    else
      decide(nil)   -- (no answer: only a downloaded-but-not-applied update is mentioned)
    end
  end
  reaper.defer(poll)
else
  decide(parse_remote(reaper.ExecProcess(curl_cmd(), 15000)))
end
