--[[
-- @description ReaTooled - Set up ReaTooled
-- @version 2.0.1
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Sets up ReaTooled after ReaBoot (or ReaPack) has installed it
    Run it once. Everything is backed up first, to Data/ReaTooled/Backups.
    While REAPER is open it:
      - checks the extensions and scripts ReaTooled needs
      - merges the ReaTooled shortcuts into yours (asks about any conflicts)
      - applies saved script settings, cursors, menu sets, templates and FX chains
      - switches to the ReaTooled theme
      - adds ReaTooled to Scripts/__startup.lua and tells ReaPack to install
        every ReaTooled package
    Some files can only be changed while REAPER is closed (preferences, menus
    and toolbars, mouse modifiers, screensets, SWS settings). Those are
    prepared now, and a small helper writes them as soon as you quit REAPER.
    The helper doesn't reopen REAPER: open it again yourself.
-- CHANGELOG
-- v2.0.1 Checks for the configuration by its keymap file
-- v2.0 Applies the whole ReaTooled configuration (no Import configuration needed)
-- v1.0.4 TJF's Coalesce scripts replaced by ReaTooled's own
-- v1.0.3 Checks for TJF's two Coalesce volume scripts too
-- v1.0.2 Checks for Odedd's Project Archiver too
-- v1.0.1 Fixed the call that turns on auto-install in ReaPack
-- v1.0 Initial version
--]]

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local REPO_NAME = "ReaTooled"   -- must match the index name, never change it
local REPO_URL  = "https://raw.githubusercontent.com/BPBaker/ReaTooled/main/index.xml"

-- The ReaTooled keymap section (Main (alt-16) = 16)
local KEY_SECTION = 16

-- Extensions ReaTooled needs: { name, an API function that only exists when it's installed }
local EXTENSIONS = {
  { "SWS/S&M extension", "CF_GetSWSVersion" },
  { "js_ReaScriptAPI",   "JS_ReaScriptAPI_Version" },
  { "ReaImGui",          "ImGui_CreateContext" },
}

-- Folders copied from the configuration into REAPER's folder.
-- overwrite = false: a file the user already has with the same name is kept.
local FOLDERS = {
  { name = "Cursors",          overwrite = true  },
  { name = "MenuSets",         overwrite = true  },
  { name = "FXChains",         overwrite = false },
  { name = "ProjectTemplates", overwrite = false },
  { name = "TrackTemplates",   overwrite = false },
}

------------------------------------------------------------
-- (No need to edit below this line)
------------------------------------------------------------

local TITLE        = "Set up ReaTooled"
local SETUP_VER    = "2.0.1"
local RES          = reaper.GetResourcePath():gsub("\\", "/")
local CONFIG       = RES .. "/Data/ReaTooled/Config"
local PENDING      = RES .. "/Data/ReaTooled/Pending"
local BACKUP_ROOT  = RES .. "/Data/ReaTooled/Backups"
local FIRST_BACKUP = BACKUP_ROOT .. "/Before ReaTooled"
local HOOK_SCRIPT  = RES .. "/Scripts/ReaTooled/Startup/ReaTooled_Install startup hook.lua"
local IS_WIN       = reaper.GetOS():match("Win") ~= nil

------------------------------------------------------------
-- Files
------------------------------------------------------------

local function exists(path) return reaper.file_exists(path) end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*all")
  f:close()
  return d
end

local function write_file(path, data)
  local folder = path:match("^(.*)/[^/]+$")
  if folder then reaper.RecursiveCreateDirectory(folder, 0) end
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

local function copy_file(src, dst)
  local data = read_file(src)
  if not data then return false end
  return write_file(dst, data)
end

local function lines_of(text)
  local out = {}
  for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do out[#out + 1] = line end
  if out[#out] == "" then out[#out] = nil end
  return out
end

-- Every file under a folder, as paths relative to that folder
local function list_files(root, rel, out)
  out = out or {}
  local dir = rel and (root .. "/" .. rel) or root
  reaper.EnumerateFiles(dir, -1)
  reaper.EnumerateSubdirectories(dir, -1)
  local i = 0
  while true do
    local name = reaper.EnumerateFiles(dir, i)
    if not name then break end
    if name ~= ".DS_Store" then out[#out + 1] = rel and (rel .. "/" .. name) or name end
    i = i + 1
  end
  i = 0
  while true do
    local sub = reaper.EnumerateSubdirectories(dir, i)
    if not sub then break end
    list_files(root, rel and (rel .. "/" .. sub) or sub, out)
    i = i + 1
  end
  return out
end

------------------------------------------------------------
-- INI files: { pre = {lines before the first section}, order = {names}, sec = {name = {lines}} }
------------------------------------------------------------

local function ini_parse(text)
  local ini = { pre = {}, order = {}, sec = {} }
  local cur
  for _, line in ipairs(lines_of(text)) do
    local name = line:match("^%[(.-)%]%s*$")
    if name then
      cur = name
      if not ini.sec[cur] then
        ini.sec[cur] = {}
        ini.order[#ini.order + 1] = cur
      end
    elseif not line:match("^;") then
      if cur then
        if line ~= "" then table.insert(ini.sec[cur], line) end
      elseif line ~= "" then
        table.insert(ini.pre, line)
      end
    end
  end
  return ini
end

local function ini_text(ini)
  local out = {}
  for _, l in ipairs(ini.pre) do out[#out + 1] = l end
  for _, name in ipairs(ini.order) do
    if #out > 0 then out[#out + 1] = "" end
    out[#out + 1] = "[" .. name .. "]"
    for _, l in ipairs(ini.sec[name]) do out[#out + 1] = l end
  end
  return table.concat(out, "\n") .. "\n"
end

-- Replace whole sections of 'target' with the ones in 'patch'
-- (sections listed in key_merge are merged key by key instead)
local function ini_merge(target_text, patch_text, key_merge)
  local t, p = ini_parse(target_text or ""), ini_parse(patch_text or "")
  key_merge = key_merge or {}
  for _, name in ipairs(p.order) do
    if not t.sec[name] then
      t.sec[name] = {}
      t.order[#t.order + 1] = name
    end
    if key_merge[name] then
      local idx = {}
      for i, l in ipairs(t.sec[name]) do
        local k = l:match("^([^=]+)=")
        if k then idx[k] = i end
      end
      for _, l in ipairs(p.sec[name]) do
        local k = l:match("^([^=]+)=")
        if k and idx[k] then t.sec[name][idx[k]] = l else table.insert(t.sec[name], l) end
      end
    else
      t.sec[name] = p.sec[name]
    end
  end
  return ini_text(t)
end

------------------------------------------------------------
-- Native actions, found by exact name (command numbers are only a first guess)
------------------------------------------------------------

local function find_cmd(name, guess)
  if guess and reaper.kbd_getTextFromCmd(guess, 0) == name then return guess end
  for id = 1, 65535 do
    if reaper.kbd_getTextFromCmd(id, 0) == name then return id end
  end
  return nil
end

------------------------------------------------------------
-- The helper that finishes the job after REAPER quits
------------------------------------------------------------

local HELPER_SH = [=[
#!/bin/sh
# ReaTooled setup helper (macOS / Linux). Written by "Set up ReaTooled".
# Waits for REAPER to quit, then copies and merges the prepared files.
RES="$1"
PID="$2"
P="$RES/Data/ReaTooled/Pending"
LOG="$RES/Data/ReaTooled/setup_log.txt"

while kill -0 "$PID" 2>/dev/null; do sleep 1; done
sleep 2

MERGE_AWK='
function addkeys(s,   i, k) {
  for (i = 1; i <= kc[s]; i++) {
    k = keys[s, i]
    if (!((s SUBSEP k) in done)) { print val[s SUBSEP k]; done[s SUBSEP k] = 1 }
  }
}
BEGIN {
  sec = ""
  while ((getline line < PATCH) > 0) {
    sub(/\r$/, "", line)
    if (line ~ /^;/ || line == "") continue
    if (line ~ /^\[.*\]$/) {
      sec = substr(line, 2, length(line) - 2)
      if (!(sec in seen)) { seen[sec] = 1; order[++n] = sec }
      continue
    }
    eq = index(line, "=")
    if (eq == 0) continue
    k = substr(line, 1, eq - 1)
    if (!((sec SUBSEP k) in val)) keys[sec, ++kc[sec]] = k
    val[sec SUBSEP k] = line
  }
  close(PATCH)
  cur = ""
}
{
  sub(/\r$/, "")
  if ($0 ~ /^\[.*\]$/) {
    if (cur != "" && (cur in seen)) addkeys(cur)
    cur = substr($0, 2, length($0) - 2)
    present[cur] = 1
    print
    next
  }
  eq = index($0, "=")
  if (eq > 0 && (cur in seen)) {
    k = substr($0, 1, eq - 1)
    if ((cur SUBSEP k) in val) {
      if (!((cur SUBSEP k) in done)) { print val[cur SUBSEP k]; done[cur SUBSEP k] = 1 }
      next
    }
  }
  print
}
END {
  if (cur != "" && (cur in seen)) addkeys(cur)
  for (i = 1; i <= n; i++) {
    s = order[i]
    if (!(s in present)) { print ""; print "[" s "]"; addkeys(s) }
  }
}'

{
  echo "=== ReaTooled setup helper: $(date)"
  ok=1
  if [ -f "$P/copy.txt" ]; then
    while IFS= read -r rel || [ -n "$rel" ]; do
      [ -z "$rel" ] && continue
      mkdir -p "$(dirname "$RES/$rel")"
      if cp -f "$P/files/$rel" "$RES/$rel"; then echo "copied  $rel"; else echo "FAILED  copy $rel"; ok=0; fi
    done < "$P/copy.txt"
  fi
  if [ -f "$P/merge.txt" ]; then
    while IFS= read -r rel || [ -n "$rel" ]; do
      [ -z "$rel" ] && continue
      [ -f "$RES/$rel" ] || : > "$RES/$rel"
      if awk -v PATCH="$P/merge/$rel" "$MERGE_AWK" "$RES/$rel" > "$RES/$rel.rt_tmp" \
         && mv -f "$RES/$rel.rt_tmp" "$RES/$rel"; then
        echo "merged  $rel"
      else
        echo "FAILED  merge $rel"; ok=0; rm -f "$RES/$rel.rt_tmp"
      fi
    done < "$P/merge.txt"
  fi
  if [ "$ok" = 1 ]; then
    mv "$P" "$RES/Data/ReaTooled/Applied $(date +%Y-%m-%d_%H%M%S)"
    echo "done"
  else
    echo "Some files failed. They will be tried again the next time REAPER starts and quits."
  fi
} >> "$LOG" 2>&1
]=]

local HELPER_PS1 = [=[
# ReaTooled setup helper (Windows). Written by "Set up ReaTooled".
# Waits for REAPER to quit, then copies and merges the prepared files.
param([string]$Res, [string]$Exe)
$P   = Join-Path $Res "Data\ReaTooled\Pending"
$Log = Join-Path $Res "Data\ReaTooled\setup_log.txt"
$Utf8 = New-Object System.Text.UTF8Encoding $false

while (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Exe }) {
  Start-Sleep -Seconds 1
}
Start-Sleep -Seconds 2

function Merge-Ini([string]$target, [string]$patch) {
  $order = New-Object System.Collections.ArrayList
  $vals = @{}; $keyOrder = @{}
  $sec = ""
  foreach ($line in [IO.File]::ReadAllLines($patch, $Utf8)) {
    $line = $line.TrimEnd("`r")
    if ($line -eq "" -or $line.StartsWith(";")) { continue }
    if ($line -match '^\[(.*)\]$') {
      $sec = $Matches[1]
      if (-not $keyOrder.ContainsKey($sec)) { [void]$order.Add($sec); $keyOrder[$sec] = New-Object System.Collections.ArrayList }
      continue
    }
    $eq = $line.IndexOf("=")
    if ($eq -lt 1) { continue }
    $k = $line.Substring(0, $eq)
    if (-not $vals.ContainsKey("$sec`0$k")) { [void]$keyOrder[$sec].Add($k) }
    $vals["$sec`0$k"] = $line
  }
  $out = New-Object System.Collections.ArrayList
  $done = @{}; $present = @{}
  $cur = ""
  $lines = @()
  if (Test-Path -LiteralPath $target) { $lines = [IO.File]::ReadAllLines($target, $Utf8) }
  function Add-Keys($s) {
    foreach ($k in $keyOrder[$s]) {
      if (-not $done.ContainsKey("$s`0$k")) { [void]$out.Add($vals["$s`0$k"]); $done["$s`0$k"] = 1 }
    }
  }
  foreach ($line in $lines) {
    $line = $line.TrimEnd("`r")
    if ($line -match '^\[(.*)\]$') {
      if ($cur -ne "" -and $keyOrder.ContainsKey($cur)) { Add-Keys $cur }
      $cur = $Matches[1]; $present[$cur] = 1
      [void]$out.Add($line); continue
    }
    $eq = $line.IndexOf("=")
    if ($eq -gt 0 -and $keyOrder.ContainsKey($cur)) {
      $k = $line.Substring(0, $eq)
      if ($vals.ContainsKey("$cur`0$k")) {
        if (-not $done.ContainsKey("$cur`0$k")) { [void]$out.Add($vals["$cur`0$k"]); $done["$cur`0$k"] = 1 }
        continue
      }
    }
    [void]$out.Add($line)
  }
  if ($cur -ne "" -and $keyOrder.ContainsKey($cur)) { Add-Keys $cur }
  foreach ($s in $order) {
    if (-not $present.ContainsKey($s)) { [void]$out.Add(""); [void]$out.Add("[$s]"); Add-Keys $s }
  }
  [IO.File]::WriteAllLines($target, [string[]]$out, $Utf8)
}

$ok = $true
$log = New-Object System.Collections.ArrayList
[void]$log.Add("=== ReaTooled setup helper: " + (Get-Date))
$copyList = Join-Path $P "copy.txt"
if (Test-Path -LiteralPath $copyList) {
  foreach ($rel in [IO.File]::ReadAllLines($copyList, $Utf8)) {
    if ($rel -eq "") { continue }
    $r = $rel -replace '/', '\'
    $dst = Join-Path $Res $r
    try {
      New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
      Copy-Item -LiteralPath (Join-Path (Join-Path $P "files") $r) -Destination $dst -Force -ErrorAction Stop
      [void]$log.Add("copied  $rel")
    } catch { [void]$log.Add("FAILED  copy $rel : $_"); $ok = $false }
  }
}
$mergeList = Join-Path $P "merge.txt"
if (Test-Path -LiteralPath $mergeList) {
  foreach ($rel in [IO.File]::ReadAllLines($mergeList, $Utf8)) {
    if ($rel -eq "") { continue }
    $r = $rel -replace '/', '\'
    try {
      Merge-Ini (Join-Path $Res $r) (Join-Path (Join-Path $P "merge") $r)
      [void]$log.Add("merged  $rel")
    } catch { [void]$log.Add("FAILED  merge $rel : $_"); $ok = $false }
  }
}
if ($ok) {
  Rename-Item -LiteralPath $P -NewName ("Applied " + (Get-Date -Format "yyyy-MM-dd_HHmmss"))
  [void]$log.Add("done")
} else {
  [void]$log.Add("Some files failed. They will be tried again the next time REAPER starts and quits.")
}
[IO.File]::AppendAllLines($Log, [string[]]$log, $Utf8)
]=]

-- Starts the helper in the background. It waits for THIS REAPER to quit.
local function launch_helper()
  if IS_WIN then
    local ps1 = PENDING .. "/helper.ps1"
    if not write_file(ps1, HELPER_PS1) then return false end
    local exe = reaper.GetExePath():gsub("/", "\\") .. "\\reaper.exe"
    local cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ..
                ps1:gsub("/", "\\") .. '" -Res "' .. RES:gsub("/", "\\") .. '" -Exe "' .. exe .. '"'
    reaper.ExecProcess(cmd, -1)
  else
    local sh = PENDING .. "/helper.sh"
    if not write_file(sh, HELPER_SH) then return false end
    -- $PPID is REAPER itself (the shell os.execute starts is REAPER's child)
    os.execute('nohup /bin/sh "' .. sh .. '" "' .. RES .. '" "$PPID" >/dev/null 2>&1 &')
  end
  return true
end

-- The startup script uses this to restart a helper that never got to run
if _G.REATOOLED_RELAUNCH_HELPER then
  _G.REATOOLED_RELAUNCH_HELPER = nil
  if exists(PENDING .. "/copy.txt") or exists(PENDING .. "/merge.txt") then launch_helper() end
  return
end

local function msg(text, buttons)
  return reaper.ShowMessageBox(text, TITLE, buttons or 0)
end

------------------------------------------------------------
-- 1. Checks
------------------------------------------------------------

if not reaper.APIExists("ReaPack_AddSetRepository") then
  msg("ReaPack is not installed, so ReaTooled can't be set up.\n\n" ..
      "Install ReaTooled with the ReaBoot link from the guide, then run this again.")
  return
end

if not exists(CONFIG .. "/keymap.ini") then
  msg("The ReaTooled configuration isn't installed yet.\n\n" ..
      "Install ReaTooled with the ReaBoot link from the guide, or in ReaPack " ..
      "(Extensions > ReaPack > Browse packages) install \"ReaTooled Config\" and " ..
      "\"ReaTooled Themes\". Then run this again.")
  return
end
local CONFIG_VER = (read_file(CONFIG .. "/version.txt") or ""):match("[%d%.]+") or ""

local keymap_text = read_file(CONFIG .. "/keymap.ini") or ""

local missing = {}
for _, ext in ipairs(EXTENSIONS) do
  if not reaper.APIExists(ext[2]) then missing[#missing + 1] = "  " .. ext[1] end
end
-- Scripts by other developers that the shortcuts, menus and mouse modifiers use
for _, line in ipairs(lines_of(keymap_text)) do
  if line:match("^SCR ") then
    local path = line:match('"([^"]+)"%s*$') or line:match("(%S+)%s*$")
    if path and not path:match("^ReaTooled/") and not exists(RES .. "/Scripts/" .. path) then
      missing[#missing + 1] = "  " .. path:match("([^/]+)$")
    end
  end
end

local first_run = not exists(FIRST_BACKUP .. "/backup_info.txt")

local intro = "This sets up ReaTooled" .. (CONFIG_VER ~= "" and (" " .. CONFIG_VER) or "") .. ".\n\n" ..
  "1. Backs up your REAPER settings" ..
  (first_run and " (to Data/ReaTooled/Backups/Before ReaTooled)\n" or " (a new dated backup)\n") ..
  "2. Adds the ReaTooled shortcuts to yours (you choose if any clash)\n" ..
  "3. Applies the ReaTooled menus, toolbars, mouse modifiers, preferences,\n" ..
  "    theme, screensets and settings\n" ..
  "4. Adds ReaTooled to REAPER's startup and installs every ReaTooled script\n\n" ..
  "At the end you'll quit REAPER and open it again. Continue?"

if #missing > 0 then
  intro = "Some things ReaTooled uses are not installed:\n\n" ..
    table.concat(missing, "\n") ..
    "\n\nThe ReaTooled tools that use them won't work until they are. " ..
    "Installing with the ReaBoot link from the guide adds all of them.\n\n" ..
    "You can set up ReaTooled anyway and add these later.\n\n" .. intro
end

if msg(intro, 1) ~= 1 then return end   -- OK / Cancel

------------------------------------------------------------
-- 2. Backup
------------------------------------------------------------

local backup_dir = first_run and FIRST_BACKUP or (BACKUP_ROOT .. "/" .. os.date("%Y-%m-%d_%H%M%S"))
local backup_failed = {}

local function backup_file(rel)
  local src = RES .. "/" .. rel
  if exists(src) and not copy_file(src, backup_dir .. "/" .. rel) then
    backup_failed[#backup_failed + 1] = rel
  end
end

-- Every file in the resource folder, the startup script, and the folders we write into
reaper.EnumerateFiles(RES, -1)
do
  local i = 0
  while true do
    local name = reaper.EnumerateFiles(RES, i)
    if not name then break end
    if not name:lower():match("%.log$") then backup_file(name) end
    i = i + 1
  end
end
backup_file("Scripts/__startup.lua")
for _, rel in ipairs(list_files(RES .. "/ReaImGui")) do backup_file("ReaImGui/" .. rel) end
for _, f in ipairs(FOLDERS) do
  for _, rel in ipairs(list_files(CONFIG .. "/files/" .. f.name)) do
    backup_file(f.name .. "/" .. rel)   -- only the files we might replace
  end
end

if #backup_failed == 0 then
  write_file(backup_dir .. "/backup_info.txt",
    "ReaTooled backup\nDate: " .. os.date("%Y-%m-%d %H:%M:%S") ..
    "\nREAPER: " .. reaper.GetAppVersion() .. "\nReaTooled config: " .. CONFIG_VER .. "\n")
end
if #backup_failed > 0 or not exists(backup_dir .. "/backup_info.txt") then
  msg("The backup did not finish, so nothing was changed.\n\nCould not copy:\n  " ..
      table.concat(backup_failed, "\n  ") .. "\n\nBackup folder:\n" .. backup_dir)
  return
end

------------------------------------------------------------
-- 3. Keymap merge (asks about clashes)
------------------------------------------------------------

local function kb_fields(line)
  local out, i, n = {}, 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if c == " " or c == "\t" then
      i = i + 1
    elseif c == "#" then
      break
    elseif c == '"' then
      local j = line:find('"', i + 1, true) or (n + 1)
      out[#out + 1] = line:sub(i + 1, j - 1)
      i = j + 1
    else
      local j = line:find("[ \t]", i) or (n + 1)
      out[#out + 1] = line:sub(i, j - 1)
      i = j
    end
  end
  return out
end

local function norm_id(id)
  if not id or id == "" then return id end
  if id:match("^%d+$") then return id end
  return (id:sub(1, 1) == "_") and id or ("_" .. id)
end

-- What the user sees for a shortcut ("Cmd+Opt+K"), taken from REAPER's own comment
local function key_label(line)
  local keys = line:match("#%s*[^:]+:%s*(.-)%s*:")
  if keys and keys ~= "" then return keys end
  local f = kb_fields(line)
  return "key " .. tostring(f[3]) .. " (modifiers " .. tostring(f[2]) .. ")"
end

local user_kb_text = read_file(RES .. "/reaper-kb.ini") or ""
local user_lines = lines_of(user_kb_text)

local our_names = {}   -- command ID -> name, for the clash prompts
local our_scr, our_act, our_key = {}, {}, {}
for _, line in ipairs(lines_of(keymap_text)) do
  if not line:match("^;") and line ~= "" then
    local f = kb_fields(line)
    if f[1] == "SCR" then
      our_scr[#our_scr + 1] = { id = norm_id(f[4]), line = line }
      our_names[norm_id(f[4])] = f[5]
    elseif f[1] == "ACT" then
      our_act[#our_act + 1] = { id = norm_id(f[4]), line = line }
      our_names[norm_id(f[4])] = f[5]
    elseif f[1] == "KEY" then
      our_key[#our_key + 1] = { k = f[2] .. "|" .. f[3] .. "|" .. f[5], cmd = f[4], line = line }
    end
  end
end

local user_scr, user_act, user_key = {}, {}, {}
for i, line in ipairs(user_lines) do
  local f = kb_fields(line)
  if f[1] == "SCR" then user_scr[norm_id(f[4])] = i
  elseif f[1] == "ACT" then user_act[norm_id(f[4])] = i
  elseif f[1] == "KEY" then user_key[f[2] .. "|" .. f[3] .. "|" .. f[5]] = { i = i, cmd = f[4] } end
end

local function command_name(cmd)
  if our_names[norm_id(cmd)] then return our_names[norm_id(cmd)] end
  local id = tonumber(cmd) or reaper.NamedCommandLookup(cmd)
  local name = (id and id ~= 0) and reaper.kbd_getTextFromCmd(id, 0) or ""
  return name ~= "" and name or cmd
end

local replace_line, add_scr, add_act, add_key, conflicts = {}, {}, {}, {}, {}
for _, s in ipairs(our_scr) do
  if not user_scr[s.id] then add_scr[#add_scr + 1] = s.line end
end
for _, a in ipairs(our_act) do
  if user_act[a.id] then replace_line[user_act[a.id]] = a.line else add_act[#add_act + 1] = a.line end
end
for _, k in ipairs(our_key) do
  local u = user_key[k.k]
  if not u then
    add_key[#add_key + 1] = k.line
  elseif u.cmd ~= k.cmd then
    conflicts[#conflicts + 1] = { k = k, u = u }
  end
end

local use_ours, kept = 0, 0
if #conflicts > 0 then
  local how = msg(#conflicts .. " ReaTooled shortcut(s) use keys you already use for something else " ..
    "(in the ReaTooled keymap section only).\n\n" ..
    "YES = choose one by one\nNO = use ReaTooled's for all of them\nCANCEL = keep yours for all of them",
    3)
  local all = nil
  if how == 7 then all = true elseif how ~= 6 then all = false end
  for n, c in ipairs(conflicts) do
    local ours = all
    if ours == nil then
      local r = msg(string.format("Clash %d of %d\n\nShortcut: %s\n\nYours:      %s\nReaTooled: %s\n\n" ..
        "YES = use ReaTooled's\nNO = keep yours\nCANCEL = decide all the rest at once",
        n, #conflicts, key_label(c.k.line), command_name(c.u.cmd), command_name(c.k.cmd)), 3)
      if r == 6 then
        ours = true
      elseif r == 7 then
        ours = false
      else
        all = (msg("For the remaining " .. (#conflicts - n + 1) .. " clash(es):\n\n" ..
                   "YES = use ReaTooled's\nNO = keep yours", 4) == 6)
        ours = all
      end
    end
    if ours then
      replace_line[c.u.i] = c.k.line
      use_ours = use_ours + 1
    else
      kept = kept + 1
    end
  end
end

-- Build the new reaper-kb.ini: user's lines (with replacements), then new
-- script and custom action lines before the first shortcut, then new shortcuts
local kb_out, inserted = {}, false
local function insert_defs()
  for _, l in ipairs(add_scr) do kb_out[#kb_out + 1] = l end
  for _, l in ipairs(add_act) do kb_out[#kb_out + 1] = l end
  inserted = true
end
for i, line in ipairs(user_lines) do
  if not inserted and line:match("^KEY ") then insert_defs() end
  kb_out[#kb_out + 1] = replace_line[i] or line
end
if not inserted then insert_defs() end
for _, l in ipairs(add_key) do kb_out[#kb_out + 1] = l end

------------------------------------------------------------
-- 4. Prepare the files that are written after REAPER quits
------------------------------------------------------------

local copies, merges = {}, {}
local function stage_copy(rel, data)
  if write_file(PENDING .. "/files/" .. rel, data) then copies[#copies + 1] = rel end
end
local function stage_merge(rel, data)
  if write_file(PENDING .. "/merge/" .. rel, data) then merges[#merges + 1] = rel end
end

stage_copy("reaper-kb.ini", table.concat(kb_out, "\n") .. "\n")

local function staged_section_merge(target, config_file, key_merge)
  local patch = read_file(CONFIG .. "/" .. config_file)
  if patch then
    stage_copy(target, ini_merge(read_file(RES .. "/" .. target) or "", patch, key_merge))
  end
end
staged_section_merge("reaper-menu.ini",        "menus.ini")
staged_section_merge("reaper-mouse.ini",       "mouse.ini", { hasimported = true })
staged_section_merge("reaper-screensets.ini",  "screensets.ini")
staged_section_merge("reaper-themeconfig.ini", "themeconfig.ini")

-- ReaImGui window settings (docked script windows)
for _, rel in ipairs(list_files(CONFIG .. "/files/ReaImGui")) do
  local data = read_file(CONFIG .. "/files/ReaImGui/" .. rel)
  if data then stage_copy("ReaImGui/" .. rel, data) end
end

-- Preferences (reaper.ini), merged key by key, plus the theme
local theme = (read_file(CONFIG .. "/theme.txt") or ""):match("^%s*(.-)%s*$")
do
  local prefs = { "[REAPER]" }
  for _, name in ipairs({ "prefs.ini", "prefs_offline.ini" }) do
    for _, l in ipairs(lines_of(read_file(CONFIG .. "/" .. name))) do
      if l:match("^[^;].*=") then prefs[#prefs + 1] = l end
    end
  end
  if theme ~= "" and exists(RES .. "/ColorThemes/" .. theme) then prefs[#prefs + 1] = "ui_img=" .. theme end
  stage_merge("reaper.ini", table.concat(prefs, "\n") .. "\n")
end

-- Extension settings (SWS etc.), merged key by key
for _, rel in ipairs(list_files(CONFIG .. "/sws")) do
  local data = read_file(CONFIG .. "/sws/" .. rel)
  if data then stage_merge(rel, data) end
end

write_file(PENDING .. "/copy.txt", table.concat(copies, "\n") .. "\n")
write_file(PENDING .. "/merge.txt", table.concat(merges, "\n") .. "\n")
write_file(PENDING .. "/info.txt", "Prepared by Set up ReaTooled " .. SETUP_VER .. " on " ..
  os.date("%Y-%m-%d %H:%M:%S") .. " (config " .. CONFIG_VER .. ")\n")

------------------------------------------------------------
-- 5. Applied now, while REAPER runs
------------------------------------------------------------

-- Saved script settings
local ext_count = 0
do
  local ext = ini_parse(read_file(CONFIG .. "/extstate.ini") or "")
  for _, section in ipairs(ext.order) do
    for _, l in ipairs(ext.sec[section]) do
      local k, v = l:match("^([^=]+)=(.*)$")
      if k then
        reaper.SetExtState(section, k, v, true)
        ext_count = ext_count + 1
      end
    end
  end
end

-- Cursors, menu sets, templates, FX chains
local copied, kept_files = 0, 0
for _, f in ipairs(FOLDERS) do
  for _, rel in ipairs(list_files(CONFIG .. "/files/" .. f.name)) do
    local dst = RES .. "/" .. f.name .. "/" .. rel
    if exists(dst) and not f.overwrite then
      kept_files = kept_files + 1
    elseif copy_file(CONFIG .. "/files/" .. f.name .. "/" .. rel, dst) then
      copied = copied + 1
    end
  end
end

-- Theme (so it shows right away; reaper.ini gets it after the restart too)
if theme ~= "" and exists(RES .. "/ColorThemes/" .. theme) and reaper.OpenColorThemeFile then
  reaper.OpenColorThemeFile(RES .. "/ColorThemes/" .. theme)
end

-- Startup block in Scripts/__startup.lua
local hook_note
if exists(HOOK_SCRIPT) then
  _G.REATOOLED_SETUP = {}
  local ran, err = pcall(dofile, HOOK_SCRIPT)
  local result = _G.REATOOLED_SETUP
  _G.REATOOLED_SETUP = nil
  if ran and result.ok then
    hook_note = "ReaTooled was added to REAPER's startup."
  else
    hook_note = "ReaTooled could NOT be added to REAPER's startup: " ..
      tostring(ran and result.result or err) ..
      "\nRun 'Script: ReaTooled_Install startup hook.lua' from the Actions list to try again."
  end
else
  hook_note = "ReaTooled could NOT be added to REAPER's startup (missing " .. HOOK_SCRIPT .. ")."
end

-- ReaPack: install every ReaTooled package, now and when new ones are added
local repo_ok = reaper.ReaPack_AddSetRepository(REPO_NAME, REPO_URL, true, 1, "")
if repo_ok then reaper.ReaPack_ProcessQueue(true) end

reaper.SetExtState("ReaTooled", "SetupVersion", SETUP_VER, true)
reaper.SetExtState("ReaTooled", "LoadScreensetOnce", "1", true)

------------------------------------------------------------
-- 6. Start the helper, then tell the user what's left
------------------------------------------------------------

local helper_ok = launch_helper()

local summary = {
  "ReaTooled is almost ready.",
  "",
  "Your settings were backed up to:\n" .. backup_dir,
  "",
  "Shortcuts: " .. #add_key .. " added" ..
    (#conflicts > 0 and (", " .. use_ours .. " clash(es) set to ReaTooled's, " .. kept .. " kept as yours") or "") .. ".",
  "Script settings: " .. ext_count .. ". Files: " .. copied .. " copied" ..
    (kept_files > 0 and (", " .. kept_files .. " of your own templates/FX chains kept") or "") .. ".",
  hook_note,
  "",
  "WHAT TO DO NEXT",
}
if repo_ok then
  summary[#summary + 1] = "1. When you click OK, ReaPack downloads the rest of ReaTooled. Wait until it's finished."
else
  summary[#summary + 1] = "1. Install the rest of ReaTooled: Extensions > ReaPack > Manage repositories, " ..
    "right-click ReaTooled > Install all packages in this repository."
end
if helper_ok then
  summary[#summary + 1] = "2. Quit REAPER (File > Quit). ReaTooled finishes setting up as REAPER closes."
  summary[#summary + 1] = "3. Open REAPER again."
else
  summary[#summary + 1] = "2. The finishing step couldn't be prepared (no permission to write in " ..
    PENDING .. "). Please contact support."
end

msg(table.concat(summary, "\n"))

if repo_ok then
  local sync = reaper.NamedCommandLookup("_REAPACK_SYNC")
  if sync ~= 0 then reaper.Main_OnCommand(sync, 0) end
end
