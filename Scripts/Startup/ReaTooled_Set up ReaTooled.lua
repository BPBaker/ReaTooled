--[[
-- @description ReaTooled - Set up ReaTooled
-- @version 2.2.7
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Sets up ReaTooled after ReaBoot (or ReaPack) has installed it
    Run it once. Everything is backed up first, to Data/ReaTooled/Backups.
    While REAPER is open it:
      - checks the extensions and scripts ReaTooled needs
      - merges the ReaTooled shortcuts into yours (a window shows any clashes)
      - applies saved script settings, cursors, menu sets, templates and FX chains
      - switches to the ReaTooled theme
      - adds ReaTooled to Scripts/__startup.lua and tells ReaPack to install
        every ReaTooled package
    Some files can only be changed while REAPER is closed (preferences, menus
    and toolbars, mouse modifiers, screensets, SWS settings). Those are
    prepared now, and a small helper writes them as soon as you quit REAPER.
    When you click OK at the end, REAPER quits, the helper writes those files,
    and the same copy of REAPER opens again by itself.
-- CHANGELOG
-- v2.2.7 Shortcut clashes are shown together in one window instead of Yes/No/Cancel
--        boxes: each row says "Keep yours" or "Update to ReaTooled's" (Keep yours is
--        the default), any row can be changed until Continue, and the shortcut that loses
--        its key can be given another one there. The final message lists ReaTooled actions
--        left without a shortcut. Without ReaImGui every clashing key is kept as yours.
--        ReaSmoothPlayhead is no longer installed by ReaBoot: Set up adds its ReaPack
--        repository, so it's installed with the rest after the restart, once the ReaTooled
--        theme is in place (an earlier unsaved theme made it report "unsaved changes").
--        Font settings left in reaper.ini by an earlier theme are removed, so the ReaTooled
--        theme's own fonts apply (they're in the backup, and Restore puts them back)
-- v2.2.6 No mousewheel question during setup: the suggested direction for ReaTooled's
--        wheel scripts is saved (from natural scrolling and REAPER's vertical scroll
--        direction), and "Scrolling and zooming" opens once after REAPER restarts so
--        it can be tried and changed there. The theme is no longer switched while REAPER is
--        running (it's selected for the restart), so ReaSmoothPlayhead doesn't report
--        "unsaved changes" during setup. Upgrading from an earlier ReaTooled: shortcuts that
--        still match what that release installed are updated without asking, and old
--        ReaTooled-section shortcuts the current release doesn't use are removed (only if
--        unchanged); only clashes with the user's own shortcuts are asked about.
-- v2.2.5 Adds ReaTooled's MIDI editor shortcuts (clashes are asked about like the others,
--        with the real action names); reads the REAPER window size from [reaper] in any
--        case; clears anything left over from an unfinished
--        setup or restore before preparing its own files
--        Asks which mousewheel direction ReaTooled's wheel scripts should use (on a Mac
--        it checks whether natural scrolling is on and suggests that); keeps the
--        user's choice when Set up runs again
-- v2.2.4 On a brand-new REAPER the window size is added to the ReaTooled screenset
--        after REAPER quits, so the layout always loads (no more screenset note)
-- v2.2.3 Shorter first message
-- v2.2.2 Shorter final message (details in Data/ReaTooled/setup_report.txt); shows
--        "ReaTooled v3..."; preferences merge into [reaper] whatever its case
-- v2.2.1 Keeps the user's REAPER window size and position when the ReaTooled
--        screenset loads (worked out in the background, nothing is saved)
-- v2.2 Saves a record of exactly what it changed (with the backup), so
--      Restore can remove ReaTooled but keep the user's later changes
-- v2.1.2 The helper can also remove files (used by Restore settings from a backup)
-- v2.1.1 Also applies the floating toolbar window settings
-- v2.1 Quits REAPER and reopens the same copy when you click OK; the ReaPack
--      download moves to the first start after setup
-- v2.0.2 Selects the ReaTooled theme properly (lastthemefn5), and reports it
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

-- reaper.ini font settings that belong to the theme
local THEME_FONT_KEYS = { "lb_font", "lb_font2", "mi_font", "tl_font", "trans_font" }
for i = 0, 15 do THEME_FONT_KEYS[#THEME_FONT_KEYS + 1] = "user_font" .. i end

-- ReaSmoothPlayhead: installed through ReaPack after setup instead of by ReaBoot, so it
-- first starts with the ReaTooled theme in place (with an unsaved theme it turns itself off)
local SMOOTH_REPO_NAME = "ReaSmoothPlayhead"   -- the repository's index name
local SMOOTH_REPO_URL  = "https://raw.githubusercontent.com/Sakhnovkrg/ReaSmoothPlayheadReapack/main/index.xml"

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
local SETUP_VER    = "2.2.7"
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
RELAUNCH="$3"
P="$RES/Data/ReaTooled/Pending"
LOG="$RES/Data/ReaTooled/setup_log.txt"

# Which REAPER is this exactly? (so a portable copy reopens as itself)
EXE=""
if [ -r "/proc/$PID/exe" ]; then
  EXE="$(readlink "/proc/$PID/exe")"
else
  EXE="$(ps -o comm= -p "$PID" 2>/dev/null)"
fi

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
      name = substr(line, 2, length(line) - 2)
      sec = tolower(name)   # REAPER ignores case in section names ([reaper] = [REAPER])
      if (!(sec in seen)) { seen[sec] = 1; order[++n] = sec; shown[sec] = name }
      continue
    }
    if (substr(line, 1, 8) == "!delete ") { del[sec SUBSEP substr(line, 9)] = 1; continue }
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
    cur = tolower(substr($0, 2, length($0) - 2))
    present[cur] = 1
    print
    next
  }
  eq = index($0, "=")
  if (eq > 0 && (cur in seen)) {
    k = substr($0, 1, eq - 1)
    if ((cur SUBSEP k) in del) next
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
    if (!(s in present)) { print ""; print "[" shown[s] "]"; addkeys(s) }
  }
}'

WINDOW_AWK='
BEGIN {
  insec = 0
  while ((getline l < INI) > 0) {
    sub(/\r$/, "", l)
    if (l ~ /^\[/) { insec = (tolower(l) ~ /^\[reaper\]/) }
    else if (insec) { eq = index(l, "="); if (eq > 0) v[substr(l, 1, eq - 1)] = substr(l, eq + 1) }
  }
  close(INI)
  ok = (v["wnd_w"] + 0 > 100 && v["wnd_h"] + 0 > 100)
  if (ok) {
    x = v["wnd_x"] + 0; y = v["wnd_y"] + 0
    n[1] = x; n[2] = y; n[3] = x + v["wnd_w"]; n[4] = y + v["wnd_h"]
    hex = ""; sum = 0
    for (i = 1; i <= 4; i++) {
      q = n[i]; if (q < 0) q += 4294967296
      for (j = 0; j < 4; j++) { b = q % 256; hex = hex sprintf("%02X", b); sum += b; q = int(q / 256) }
    }
    hex = hex sprintf("%02X", sum % 256)
    st = (v["wnd_state"] == "" ? 0 : v["wnd_state"])
  }
}
function add() { if (cur == "sset0" && ok && !has) { print "mainwnd_rect=" hex; print "mainwnd_status=" st; has = 1 } }
{ sub(/\r$/, "") }
/^\[/ { add(); cur = substr($0, 2, length($0) - 2); has = 0; print; next }
cur == "sset0" && /^mainwnd_rect=/ { has = 1 }
{ print }
END { add() }'

{
  echo "=== ReaTooled setup helper: $(date)"
  ok=1
  if [ -f "$P/remove.txt" ]; then
    while IFS= read -r rel || [ -n "$rel" ]; do
      [ -z "$rel" ] && continue
      if [ ! -e "$RES/$rel" ] || rm -f "$RES/$rel"; then echo "removed $rel"; else echo "FAILED  remove $rel"; ok=0; fi
    done < "$P/remove.txt"
  fi
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
  if [ -f "$P/screenset_window.txt" ]; then
    # REAPER has just saved its window size (wnd_x/y/w/h in reaper.ini): put
    # it into screenset #1, as left/top/right/bottom 4-byte numbers + check byte
    S="$RES/reaper-screensets.ini"
    if [ -f "$S" ] && awk -v INI="$RES/reaper.ini" "$WINDOW_AWK" "$S" > "$S.rt_tmp" && mv -f "$S.rt_tmp" "$S"; then
      echo "window size added to screenset #1"
    else
      rm -f "$S.rt_tmp"; echo "could not add the window size to screenset #1"
    fi
  fi
  if [ "$ok" = 1 ]; then
    mv "$P" "$RES/Data/ReaTooled/Applied $(date +%Y-%m-%d_%H%M%S)"
    echo "done"
  else
    echo "Some files failed. They will be tried again the next time REAPER starts and quits."
  fi
  if [ "$RELAUNCH" = 1 ]; then
    case "$EXE" in
      *.app/Contents/MacOS/*)
        APP="${EXE%%.app/Contents/MacOS/*}.app"
        echo "reopening $APP"
        open -n "$APP" ;;
      /*)
        echo "reopening $EXE"
        nohup "$EXE" >/dev/null 2>&1 & ;;
      *)
        echo "could not tell which REAPER to reopen ($EXE) - please open it yourself" ;;
    esac
  fi
} >> "$LOG" 2>&1
]=]

local HELPER_PS1 = [=[
# ReaTooled setup helper (Windows). Written by "Set up ReaTooled".
# Waits for REAPER to quit, then copies and merges the prepared files.
param([string]$Res, [string]$Exe, [string]$Relaunch = "0")
$P   = Join-Path $Res "Data\ReaTooled\Pending"
$Log = Join-Path $Res "Data\ReaTooled\setup_log.txt"
$Utf8 = New-Object System.Text.UTF8Encoding $false

while (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Exe }) {
  Start-Sleep -Seconds 1
}
Start-Sleep -Seconds 2

function Merge-Ini([string]$target, [string]$patch) {
  $order = New-Object System.Collections.ArrayList
  $vals = @{}; $keyOrder = @{}; $dels = @{}
  $sec = ""
  foreach ($line in [IO.File]::ReadAllLines($patch, $Utf8)) {
    $line = $line.TrimEnd("`r")
    if ($line -eq "" -or $line.StartsWith(";")) { continue }
    if ($line -match '^\[(.*)\]$') {
      $sec = $Matches[1]
      if (-not $keyOrder.ContainsKey($sec)) { [void]$order.Add($sec); $keyOrder[$sec] = New-Object System.Collections.ArrayList }
      continue
    }
    if ($line.StartsWith("!delete ")) { $dels["$sec`0" + $line.Substring(8)] = 1; continue }
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
      if ($dels.ContainsKey("$cur`0$k")) { continue }
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
$removeList = Join-Path $P "remove.txt"
if (Test-Path -LiteralPath $removeList) {
  foreach ($rel in [IO.File]::ReadAllLines($removeList, $Utf8)) {
    if ($rel -eq "") { continue }
    $dst = Join-Path $Res ($rel -replace '/', '\')
    try {
      if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force -ErrorAction Stop }
      [void]$log.Add("removed $rel")
    } catch { [void]$log.Add("FAILED  remove $rel : $_"); $ok = $false }
  }
}
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
$winFlag = Join-Path $P "screenset_window.txt"
$ss = Join-Path $Res "reaper-screensets.ini"
if ((Test-Path -LiteralPath $winFlag) -and (Test-Path -LiteralPath $ss)) {
  # REAPER has just saved its window size: put it into screenset #1
  try {
    $v = @{}; $inSec = $false
    foreach ($l in [IO.File]::ReadAllLines((Join-Path $Res "reaper.ini"), $Utf8)) {
      if ($l -match '^\[(.*)\]') { $inSec = ($Matches[1] -eq "reaper") }
      elseif ($inSec -and $l.IndexOf("=") -gt 0) { $v[$l.Substring(0, $l.IndexOf("="))] = $l.Substring($l.IndexOf("=") + 1) }
    }
    if ([int]$v["wnd_w"] -gt 100 -and [int]$v["wnd_h"] -gt 100) {
      $x = [int]$v["wnd_x"]; $y = [int]$v["wnd_y"]
      $bytes = @()
      foreach ($n in @($x, $y, ($x + [int]$v["wnd_w"]), ($y + [int]$v["wnd_h"]))) { $bytes += [BitConverter]::GetBytes([int32]$n) }
      $sum = 0; foreach ($b in $bytes) { $sum += $b }
      $hex = (($bytes | ForEach-Object { $_.ToString("X2") }) -join "") + ($sum % 256).ToString("X2")
      $state = if ($v["wnd_state"]) { $v["wnd_state"] } else { "0" }
      $out = New-Object System.Collections.ArrayList
      $cur = ""; $has = $false
      $addRect = { if ($cur -eq "sset0" -and -not $has) { [void]$out.Add("mainwnd_rect=$hex"); [void]$out.Add("mainwnd_status=$state"); $script:has = $true } }
      foreach ($l in [IO.File]::ReadAllLines($ss, $Utf8)) {
        if ($l -match '^\[(.*)\]') { & $addRect; $cur = $Matches[1]; $has = $false; [void]$out.Add($l); continue }
        if ($cur -eq "sset0" -and $l.StartsWith("mainwnd_rect=")) { $has = $true }
        [void]$out.Add($l)
      }
      & $addRect
      [IO.File]::WriteAllLines($ss, [string[]]$out, $Utf8)
      [void]$log.Add("window size added to screenset #1")
    }
  } catch { [void]$log.Add("could not add the window size to screenset #1: $_") }
}
if ($ok) {
  Rename-Item -LiteralPath $P -NewName ("Applied " + (Get-Date -Format "yyyy-MM-dd_HHmmss"))
  [void]$log.Add("done")
} else {
  [void]$log.Add("Some files failed. They will be tried again the next time REAPER starts and quits.")
}
if ($Relaunch -eq "1" -and (Test-Path -LiteralPath $Exe)) {
  [void]$log.Add("reopening $Exe")
  Start-Process -FilePath $Exe -WorkingDirectory (Split-Path $Exe)
}
[IO.File]::AppendAllLines($Log, [string[]]$log, $Utf8)
]=]

-- Starts the helper in the background. It waits for THIS REAPER to quit.
local function launch_helper(relaunch)
  local r = relaunch and "1" or "0"
  if IS_WIN then
    local ps1 = PENDING .. "/helper.ps1"
    if not write_file(ps1, HELPER_PS1) then return false end
    local exe = reaper.GetExePath():gsub("/", "\\") .. "\\reaper.exe"
    local cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' ..
                ps1:gsub("/", "\\") .. '" -Res "' .. RES:gsub("/", "\\") .. '" -Exe "' .. exe .. '" -Relaunch ' .. r
    reaper.ExecProcess(cmd, -1)
  else
    local sh = PENDING .. "/helper.sh"
    if not write_file(sh, HELPER_SH) then return false end
    -- $PPID is REAPER itself (the shell os.execute starts is REAPER's child)
    os.execute('nohup /bin/sh "' .. sh .. '" "' .. RES .. '" "$PPID" ' .. r .. ' >/dev/null 2>&1 &')
  end
  return true
end

-- Other ReaTooled scripts use this to start the helper for files they prepared
-- in Pending: the startup script (a helper that never got to run) and
-- Restore settings from a backup ({ relaunch = true } reopens REAPER).
if _G.REATOOLED_RELAUNCH_HELPER then
  local opt = _G.REATOOLED_RELAUNCH_HELPER
  _G.REATOOLED_RELAUNCH_HELPER = nil
  if exists(PENDING .. "/copy.txt") or exists(PENDING .. "/merge.txt") or exists(PENDING .. "/remove.txt") then
    local started = launch_helper(type(opt) == "table" and opt.relaunch)
    if type(opt) == "table" then opt.started = started end
  end
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

local intro = "Set up ReaTooled" .. (CONFIG_VER ~= "" and (" v" .. CONFIG_VER) or "") .. " now?\n\n" ..
  "Your current settings are backed up first. If any ReaTooled shortcuts clash with " ..
  "yours, you choose which to keep, then REAPER restarts."

if #missing > 0 then
  intro = "Some things ReaTooled uses are not installed:\n\n" ..
    table.concat(missing, "\n") ..
    "\n\nThe tools that use them won't work until they're installed " ..
    "(the ReaBoot link from the guide adds them all).\n\n" .. intro
end

if msg(intro, 1) ~= 1 then return end   -- OK / Cancel

------------------------------------------------------------
-- 1b. Mousewheel direction for ReaTooled's wheel scripts (zoom, pitch,
-- take volume, peaks gain). Nothing is asked here: the suggested direction is
-- saved, and "Scrolling and zooming" opens once after REAPER restarts so the
-- user can try it and change it. REAPER's own scroll settings are not changed.
-- Already chosen (Set up run before, or toggled) -> kept as it is.
------------------------------------------------------------

local wheel_invert = reaper.GetExtState("ReaTooled", "WheelInvert")
local wheel_note
if wheel_invert == "0" or wheel_invert == "1" then
  wheel_note = "kept as you had it"
else
  -- macOS natural scrolling is the global setting com.apple.swipescrolldirection
  -- (missing = macOS default, which is natural scrolling on)
  local natural = false
  if reaper.GetOS():match("^OSX") or reaper.GetOS():match("^macOS") then
    local out = reaper.ExecProcess('/usr/bin/defaults read -g com.apple.swipescrolldirection', 3000) or ""
    local code, value = out:match("^(%-?%d+)\n(.*)$")
    if code == "0" then natural = (value or ""):match("%d") ~= "0" else natural = true end
  end
  -- REAPER's "Reverse vertical scroll" (multitouch & 512) flips the wheel too
  local ok, mt = reaper.get_config_var_string("multitouch")
  local vrev = (math.floor(tonumber(ok and mt or "") or 0) & 512) ~= 0
  wheel_invert = (natural ~= vrev) and "1" or "0"
  wheel_note = "suggested from " .. (natural and "natural" or "standard") .. " scrolling" ..
    (vrev and " and REAPER's reversed vertical scroll" or "")
end

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
  local f = kb_fields(line)
  local midi = tonumber(f[5]) ~= KEY_SECTION and "MIDI editor: " or ""
  local keys = line:match("#%s*[^:]+:%s*(.-)%s*:")
  if keys and keys ~= "" then return midi .. keys end
  return midi .. "key " .. tostring(f[3]) .. " (modifiers " .. tostring(f[2]) .. ")"
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

local function command_name(cmd, line)
  if our_names[norm_id(cmd)] then return our_names[norm_id(cmd)] end
  -- REAPER writes the action's name at the end of each shortcut line
  -- ("# Section : Keys : [OVERRIDE DEFAULT : ]Name"; names use ": " without a space before)
  local comment = line and line:match("#%s*(.*)$")
  if comment then
    local parts = {}
    for part in (comment .. " : "):gmatch("(.-) : ") do parts[#parts + 1] = part end
    local i = 3
    if parts[i] == "OVERRIDE DEFAULT" then i = i + 1 end
    local named = parts[i] and table.concat(parts, " : ", i):match("^%s*(.-)%s*$")
    if named and named ~= "" and named ~= "DISABLED DEFAULT" then return named end
  end
  local f = line and kb_fields(line) or {}
  local section = 0
  if tonumber(f[5]) and tonumber(f[5]) ~= KEY_SECTION and reaper.SectionFromUniqueID then
    section = reaper.SectionFromUniqueID(tonumber(f[5])) or 0
  end
  local id = tonumber(cmd) or reaper.NamedCommandLookup(cmd)
  local name = (id and id ~= 0) and reaper.kbd_getTextFromCmd(id, section) or ""
  return name ~= "" and name or cmd
end

-- Shortcuts earlier ReaTooled releases installed ("modifiers|key|section" -> command IDs).
-- A user shortcut that still matches one of them wasn't the user's choice.
local LEGACY = {}
do
  local path = RES .. "/Scripts/ReaTooled/Startup/ReaTooled_Earlier shortcuts.lua"
  if exists(path) then
    local ok, t = pcall(dofile, path)
    if ok and type(t) == "table" then LEGACY = t end
  end
end
local function from_earlier_release(key, cmd)
  return LEGACY[key] ~= nil and LEGACY[key][norm_id(cmd)] == true
end

local replace_line, add_scr, add_act, add_key, conflicts = {}, {}, {}, {}, {}
local remove_line, legacy_updated, legacy_removed = {}, 0, 0
for _, s in ipairs(our_scr) do
  if not user_scr[s.id] then add_scr[#add_scr + 1] = s.line end
end
for _, a in ipairs(our_act) do
  if user_act[a.id] then replace_line[user_act[a.id]] = a.line else add_act[#add_act + 1] = a.line end
end
local midi_conflicts = 0
for _, k in ipairs(our_key) do
  local u = user_key[k.k]
  if not u then
    add_key[#add_key + 1] = k.line
  elseif norm_id(u.cmd) ~= norm_id(k.cmd) then
    if from_earlier_release(k.k, u.cmd) then
      -- an earlier ReaTooled's shortcut, unchanged by the user: update it
      replace_line[u.i] = k.line
      legacy_updated = legacy_updated + 1
    else
      conflicts[#conflicts + 1] = { k = k, u = u }
      if tonumber(k.k:match("([^|]+)$")) ~= KEY_SECTION then midi_conflicts = midi_conflicts + 1 end
    end
  end
end

-- Old ReaTooled-section shortcuts the current release doesn't use (scripts it
-- replaced, keys it unmapped): removed, but only if the user hasn't changed them.
-- REAPER's main section and global hotkeys are left alone.
do
  local ours_keys = {}
  for _, k in ipairs(our_key) do ours_keys[k.k] = true end
  for key, u in pairs(user_key) do
    if not ours_keys[key] and tonumber(key:match("([^|]+)$")) == KEY_SECTION
       and from_earlier_release(key, u.cmd) then
      remove_line[u.i] = true
      legacy_removed = legacy_removed + 1
    end
  end
end

------------------------------------------------------------
-- 3b. Clashes: one window lists them all. Each starts on "Keep yours";
-- any row can be changed until Continue, and the shortcut that loses its key
-- can be given another one.
------------------------------------------------------------

local use_ours, kept, rekeyed = 0, 0, 0
local left_without = {}    -- ReaTooled actions left without a shortcut (names)
local gave_away = {}       -- the user's actions whose key went to ReaTooled (names)

local function short_name(name)
  return ((name or ""):gsub("^Script: ", ""):gsub("%.lua$", ""))
end

for _, c in ipairs(conflicts) do
  c.key_text   = key_label(c.k.line)
  c.yours_name = short_name(command_name(c.u.cmd, user_lines[c.u.i]))
  c.ours_name  = short_name(command_name(c.k.cmd, c.k.line))
  c.update     = false   -- default: keep yours
  c.section    = c.k.k:match("([^|]+)$")
  -- Another key can only be given to keyboard shortcuts (not mousewheel or MIDI)
  c.keyboard   = (tonumber(c.k.k:match("^([^|]+)")) or 255) < 128
end

-- Keys a new shortcut can't use: everything in the merged shortcut list
local function owner_of(kstr, except_row, except_side)
  for _, c in ipairs(conflicts) do
    if c.k.k == kstr then return c.update and c.ours_name or c.yours_name end
  end
  for _, k in ipairs(our_key) do
    if k.k == kstr then return short_name(command_name(k.cmd, k.line)) end
  end
  local u = user_key[kstr]
  if u and not remove_line[u.i] then return short_name(command_name(u.cmd, user_lines[u.i])) end
  for _, c in ipairs(conflicts) do
    for _, side in ipairs({ "alt_ours", "alt_yours" }) do
      local a = c[side]
      if a and a.k == kstr and not (c == except_row and side == except_side) then
        -- only the side that is in use counts
        if (side == "alt_ours" and not c.update) or (side == "alt_yours" and c.update) then
          return side == "alt_ours" and c.ours_name or c.yours_name
        end
      end
    end
  end
end

local function apply_choices()
  for _, c in ipairs(conflicts) do
    local alt
    if c.update then
      replace_line[c.u.i] = c.k.line
      use_ours = use_ours + 1
      alt = c.alt_yours
      if alt then
        add_key[#add_key + 1] = string.format("KEY %d %d %s %s", alt.flags, alt.key, c.u.cmd, c.section)
      else
        gave_away[#gave_away + 1] = c.yours_name
      end
    else
      kept = kept + 1
      alt = c.alt_ours
      if alt then
        add_key[#add_key + 1] = string.format("KEY %d %d %s %s", alt.flags, alt.key, c.k.cmd, c.section)
      else
        left_without[#left_without + 1] = c.ours_name
      end
    end
    if alt then rekeyed = rekeyed + 1 end
  end
end

-- The rest of the setup (defined below), run after the clashes are settled
local finish_setup
local clash_fallback = false   -- true when ReaImGui is missing (every clashing key stays yours)

local function clash_window()
  if not reaper.ImGui_GetBuiltinPath then return false end
  package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
  local ok, ImGui = pcall(function() return require "imgui" "0.9" end)
  if not ok or not ImGui then return false end

  local IS_MAC = not IS_WIN and (reaper.GetOS():match("^OSX") or reaper.GetOS():match("^macOS")) ~= nil

  -- Keys that can be chosen, with REAPER's own codes (as in reaper-kb.ini)
  local KEYS = {}
  local function add(name, code, label) if ImGui["Key_" .. name] then KEYS[#KEYS + 1] = { ImGui["Key_" .. name], code, label } end end
  for i = 0, 25 do local ch = string.char(65 + i); add(ch, 65 + i, ch) end
  for i = 0, 9 do add(tostring(i), 48 + i, tostring(i)) end
  for i = 1, 24 do add("F" .. i, 111 + i, "F" .. i) end
  for i = 0, 9 do add("Keypad" .. i, 96 + i, "NumPad " .. i) end
  add("KeypadDecimal", 110, "NumPad ."); add("KeypadDivide", 111, "NumPad /")
  add("KeypadMultiply", 106, "NumPad *"); add("KeypadSubtract", 109, "NumPad -")
  add("KeypadAdd", 107, "NumPad +"); add("KeypadEnter", 32781, "NumPad Enter")
  add("Space", 32, "Space"); add("Enter", 13, "Return"); add("Tab", 9, "Tab")
  add("Backspace", 8, "Backspace"); add("Delete", 32814, "Delete"); add("Insert", 32813, "Insert")
  add("Home", 32804, "Home"); add("End", 32803, "End")
  add("PageUp", 32801, "Page Up"); add("PageDown", 32802, "Page Down")
  add("LeftArrow", 32805, "Left"); add("UpArrow", 32806, "Up")
  add("RightArrow", 32807, "Right"); add("DownArrow", 32808, "Down")
  -- REAPER saves these by the character they type, which depends on the keyboard
  -- layout, so they can't be chosen here (they can in the Actions list)
  local CHAR_KEYS = {}
  for _, n in ipairs({ "Apostrophe", "Comma", "Minus", "Period", "Slash", "Semicolon", "Equal",
                       "LeftBracket", "Backslash", "RightBracket", "GraveAccent" }) do
    if ImGui["Key_" .. n] then CHAR_KEYS[#CHAR_KEYS + 1] = ImGui["Key_" .. n] end
  end

  -- REAPER's modifier bits: 4 Shift, 8 Cmd (Ctrl on Windows), 16 Opt (Alt), 32 Control (Win)
  local function down(ctx, a, b) return ImGui.IsKeyDown(ctx, a) or ImGui.IsKeyDown(ctx, b) end
  local function mods_now(ctx)
    local m = 0
    if down(ctx, ImGui.Key_LeftShift, ImGui.Key_RightShift) then m = m | 4 end
    if down(ctx, ImGui.Key_LeftAlt, ImGui.Key_RightAlt) then m = m | 16 end
    local ctrl  = down(ctx, ImGui.Key_LeftCtrl, ImGui.Key_RightCtrl)     -- Control key
    local super = down(ctx, ImGui.Key_LeftSuper, ImGui.Key_RightSuper)   -- Cmd / Windows key
    if IS_MAC then
      if super then m = m | 8 end
      if ctrl then m = m | 32 end
    else
      if ctrl then m = m | 8 end
      if super then m = m | 32 end
    end
    return m
  end
  local function mods_label(m)
    local parts = {}
    if IS_MAC then
      if m & 8 ~= 0 then parts[#parts + 1] = "Cmd" end
      if m & 16 ~= 0 then parts[#parts + 1] = "Opt" end
      if m & 4 ~= 0 then parts[#parts + 1] = "Shift" end
      if m & 32 ~= 0 then parts[#parts + 1] = "Control" end
    else
      if m & 8 ~= 0 then parts[#parts + 1] = "Ctrl" end
      if m & 16 ~= 0 then parts[#parts + 1] = "Alt" end
      if m & 4 ~= 0 then parts[#parts + 1] = "Shift" end
      if m & 32 ~= 0 then parts[#parts + 1] = "Win" end
    end
    return #parts > 0 and (table.concat(parts, "+") .. "+") or ""
  end

  local ctx = ImGui.CreateContext(TITLE)
  local font = ImGui.CreateFont("sans-serif", 14)
  local font_b = ImGui.CreateFont("sans-serif", 15, ImGui.FontFlags_Bold)
  ImGui.Attach(ctx, font); ImGui.Attach(ctx, font_b)

  local C_ACCENT, C_ACCENT_H, C_ACCENT_A = 0x2F7FD6FF, 0x3A8FE8FF, 0x2669B3FF
  local C_RESULT, C_NOTE, C_WARN = 0x8FC3FFFF, 0x8A8A8AFF, 0xE8A33AFF
  local W = 600
  local LABEL_X = 110
  local CHILD_BORDER = ImGui.ChildFlags_Borders or ImGui.ChildFlags_Border or 1

  local capture        -- { row = c, side = "alt_ours"/"alt_yours", start = time }
  local capture_msg    -- text under the row being recorded
  local first_frame, outcome = true, nil   -- outcome: "continue" / "cancel"

  local function note(text, col)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col or C_NOTE)
    ImGui.PushTextWrapPos(ctx, W); ImGui.TextWrapped(ctx, text); ImGui.PopTextWrapPos(ctx)
    ImGui.PopStyleColor(ctx)
  end
  local function labeled(label, text)
    ImGui.TextDisabled(ctx, label); ImGui.SameLine(ctx, LABEL_X)
    ImGui.PushTextWrapPos(ctx, W - 16); ImGui.TextWrapped(ctx, text); ImGui.PopTextWrapPos(ctx)
  end
  local function accent_button(label, w)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C_ACCENT)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C_ACCENT_H)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C_ACCENT_A)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFFFFFF)
    local pressed = ImGui.Button(ctx, label, w, 0)
    ImGui.PopStyleColor(ctx, 4)
    return pressed
  end

  -- While recording: the next key pressed (with its modifiers) becomes the shortcut
  local function record()
    ImGui.SetNextFrameWantCaptureKeyboard(ctx, true)   -- keys don't reach REAPER meanwhile
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then capture, capture_msg = nil, nil; return end
    local m = mods_now(ctx)
    for _, k in ipairs(CHAR_KEYS) do
      if ImGui.IsKeyPressed(ctx, k, false) then
        capture_msg = "Keys like , . / ; [ ] can't be chosen here. Press another key, or give it one in the Actions list after setup."
        return
      end
    end
    for _, k in ipairs(KEYS) do
      if ImGui.IsKeyPressed(ctx, k[1], false) then
        if (m & 4) ~= 0 and k[2] >= 48 and k[2] <= 57 then
          capture_msg = "Shift with a number key can't be chosen here. Press another key, or give it one in the Actions list after setup."
          return
        end
        local flags = 1 | m
        local kstr = flags .. "|" .. k[2] .. "|" .. capture.row.section
        local label = mods_label(m) .. k[3]
        local who = owner_of(kstr, capture.row, capture.side)
        if who then
          capture_msg = label .. " is already used by \"" .. who .. "\". Press another key."
          return
        end
        capture.row[capture.side] = { flags = flags, key = k[2], k = kstr, label = label }
        capture, capture_msg = nil, nil
        return
      end
    end
  end

  local function row(n, c)
    ImGui.PushID(ctx, n)
    ImGui.PushFont(ctx, font_b); ImGui.Text(ctx, c.key_text); ImGui.PopFont(ctx)
    labeled("Yours now", c.yours_name)
    labeled("ReaTooled's", c.ours_name)
    if ImGui.RadioButton(ctx, "Keep yours", not c.update) then c.update = false end
    ImGui.SameLine(ctx, 0, 18)
    if ImGui.RadioButton(ctx, "Update to ReaTooled's", c.update) then c.update = true end

    if c.keyboard then
      local side = c.update and "alt_yours" or "alt_ours"
      local who = c.update and "yours" or "ReaTooled's"
      local recording = capture and capture.row == c and capture.side == side
      ImGui.SameLine(ctx, 0, 18)
      if recording then
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_WARN)
        ImGui.Text(ctx, "Press the new key now (Esc to stop)")
        ImGui.PopStyleColor(ctx)
      elseif c[side] then
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C_RESULT)
        ImGui.Text(ctx, (c.update and "Yours" or "ReaTooled's") .. " moves to " .. c[side].label)
        ImGui.PopStyleColor(ctx)
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Change") then capture, capture_msg = { row = c, side = side }, nil end
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Remove") then c[side] = nil end
      else
        if ImGui.SmallButton(ctx, "Give " .. who .. " another key...") then capture, capture_msg = { row = c, side = side }, nil end
      end
      if recording and capture_msg then note(capture_msg, C_WARN) end
    end
    ImGui.PopID(ctx)
  end

  local function counts()
    local keep, upd, moved = 0, 0, 0
    for _, c in ipairs(conflicts) do
      if c.update then upd = upd + 1 else keep = keep + 1 end
      if (c.update and c.alt_yours) or (not c.update and c.alt_ours) then moved = moved + 1 end
    end
    return keep, upd, moved
  end

  local function frame()
    ImGui.PushFont(ctx, font)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 14)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 8, 5)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8, 7)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 6)
    if first_frame then
      local cx, cy = ImGui.Viewport_GetCenter(ImGui.GetMainViewport(ctx))
      ImGui.SetNextWindowPos(ctx, cx, cy, ImGui.Cond_Appearing, 0.5, 0.5)
      ImGui.SetNextWindowFocus(ctx)
    end

    local flags = ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoDocking
    local visible, open = ImGui.Begin(ctx, TITLE .. " - shortcuts", true, flags)
    if visible then
      if capture then record() end
      ImGui.PushFont(ctx, font_b); ImGui.Text(ctx, "Shortcut clashes"); ImGui.PopFont(ctx)
      ImGui.SameLine(ctx)
      ImGui.SetCursorPosX(ctx, W + 16 - ImGui.CalcTextSize(ctx, "ReaTooled"))
      ImGui.TextDisabled(ctx, "ReaTooled")
      ImGui.Separator(ctx)
      note((#conflicts == 1 and "1 ReaTooled shortcut uses a key" or (#conflicts .. " ReaTooled shortcuts use keys")) ..
        " you already use for something else. Choose what each key should do. Nothing changes until you press Continue.", 0xD0D0D0FF)
      if legacy_updated > 0 then
        note("Shortcuts from your earlier ReaTooled (" .. legacy_updated .. ") were updated automatically.")
      end
      ImGui.Dummy(ctx, 0, 2)

      local h = math.min(#conflicts * 118, 420)
      if ImGui.BeginChild(ctx, "rows", W, h, CHILD_BORDER) then
        for n, c in ipairs(conflicts) do
          if n > 1 then ImGui.Separator(ctx) end
          row(n, c)
        end
        ImGui.EndChild(ctx)
      end

      if ImGui.Button(ctx, "Keep all of mine") then
        for _, c in ipairs(conflicts) do c.update = false end
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Update all to ReaTooled's") then
        for _, c in ipairs(conflicts) do c.update = true end
      end
      local keep, upd, moved = counts()
      ImGui.SameLine(ctx)
      ImGui.SetCursorPosX(ctx, W + 16 - ImGui.CalcTextSize(ctx, "Keeping 00, updating 00, another key 00"))
      ImGui.TextDisabled(ctx, string.format("Keeping %d, updating %d%s", keep, upd,
        moved > 0 and (", another key " .. moved) or ""))
      ImGui.Dummy(ctx, 0, 2)
      note("Changed your mind later? Run \"Set up ReaTooled\" again: keys you kept are offered again. " ..
        "\"Restore settings from a backup\" brings back shortcuts you replaced. You can also change any " ..
        "shortcut in the Actions list.")
      ImGui.Separator(ctx)

      local w1, w2 = 110, 110
      ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, W - w1 - w2 - 8))
      if ImGui.Button(ctx, "Cancel setup", w1, 0) then outcome = "cancel" end
      ImGui.SameLine(ctx)
      if accent_button("Continue", w2) then outcome = "continue" end
      ImGui.End(ctx)
    end
    ImGui.PopStyleVar(ctx, 5)
    ImGui.PopFont(ctx)
    first_frame = false
    if not open then outcome = "cancel" end
  end

  local function loop()
    frame()
    if outcome == "continue" then
      apply_choices()
      reaper.defer(finish_setup)   -- after the window has closed
      return
    elseif outcome == "cancel" then
      reaper.defer(function()
        msg("Setup cancelled. Nothing was changed.\n\n" ..
            "Run \"Set up ReaTooled\" again whenever you're ready.")
      end)
      return
    end
    reaper.defer(loop)
  end
  reaper.defer(loop)
  return true
end

finish_setup = function()
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
    if not remove_line[i] then kb_out[#kb_out + 1] = replace_line[i] or line end
  end
  if not inserted then insert_defs() end
  for _, l in ipairs(add_key) do kb_out[#kb_out + 1] = l end

  ------------------------------------------------------------
  -- 4. Prepare the files that are written after REAPER quits
  ------------------------------------------------------------

  -- Anything left over from an earlier setup or restore that didn't finish
  for _, f in ipairs({ "copy.txt", "merge.txt", "remove.txt", "restore.txt", "info.txt", "screenset_window.txt" }) do
    os.remove(PENDING .. "/" .. f)
  end

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
  -- Screensets. The ReaTooled screenset ships without a main window size and
  -- position (they'd be the developer's screen). REAPER needs one, so this
  -- writes the user's own, from REAPER's own record of its window (wnd_x,
  -- wnd_y, wnd_w, wnd_h in reaper.ini), in the screenset's format: left, top,
  -- right, bottom as 4-byte numbers, then a check byte (the sum of the others).
  local screensets_patch = read_file(CONFIG .. "/screensets.ini")
  local screenset_needs_window = false
  do
    local function cfg(key)
      local ok, v = reaper.get_config_var_string(key)
      if ok and tonumber(v) then return math.floor(tonumber(v)) end
      local ini = ini_parse(read_file(RES .. "/reaper.ini") or "")
      for name, lines in pairs(ini.sec) do
        if name:lower() == "reaper" then   -- [REAPER] or [reaper] (macOS)
          for _, l in ipairs(lines) do
            local k, val = l:match("^([^=]+)=(.*)$")
            if k == key and tonumber(val) then return math.floor(tonumber(val)) end
          end
        end
      end
    end
    local x, y, w, h = cfg("wnd_x"), cfg("wnd_y"), cfg("wnd_w"), cfg("wnd_h")
    local rect, status
    if x and y and w and h and w > 100 and h > 100 then
      local bytes, sum = {}, 0
      for _, n in ipairs({ x, y, x + w, y + h }) do
        if n < 0 then n = n + 4294967296 end
        for _ = 1, 4 do
          local byte = n % 256
          bytes[#bytes + 1] = string.format("%02X", byte)
          sum = sum + byte
          n = (n - byte) // 256
        end
      end
      rect = table.concat(bytes) .. string.format("%02X", sum % 256)
      status = tostring(cfg("wnd_state") or 0)
    end
    if screensets_patch and rect then
      local p = ini_parse(screensets_patch)
      for _, name in ipairs(p.order) do
        if name:match("^sset%d+$") then
          local lines = {}
          for _, l in ipairs(p.sec[name]) do
            if not l:match("^mainwnd_rect=") and not l:match("^mainwnd_status=") then lines[#lines + 1] = l end
          end
          table.insert(lines, 1, "mainwnd_rect=" .. rect)
          table.insert(lines, 2, "mainwnd_status=" .. (status or "0"))
          p.sec[name] = lines
        end
      end
      screensets_patch = ini_text(p)
    elseif screensets_patch then
      -- A brand-new REAPER hasn't saved its window size yet (it does that when
      -- it quits). The helper adds it to the screenset right after REAPER quits.
      screenset_needs_window = true
    end
  end
  if screensets_patch then
    stage_copy("reaper-screensets.ini", ini_merge(read_file(RES .. "/reaper-screensets.ini") or "", screensets_patch))
  end
  staged_section_merge("reaper-themeconfig.ini", "themeconfig.ini")

  -- ReaImGui window settings (docked script windows)
  for _, rel in ipairs(list_files(CONFIG .. "/files/ReaImGui")) do
    local data = read_file(CONFIG .. "/files/ReaImGui/" .. rel)
    if data then stage_copy("ReaImGui/" .. rel, data) end
  end

  -- Preferences (reaper.ini), merged key by key, plus the theme
  local prefs_patch
  local theme = (read_file(CONFIG .. "/theme.txt") or ""):match("^%s*(.-)%s*$")
  do
    local prefs = { "[REAPER]" }
    for _, name in ipairs({ "prefs.ini", "prefs_offline.ini" }) do
      for _, l in ipairs(lines_of(read_file(CONFIG .. "/" .. name))) do
        if l:match("^[^;].*=") then prefs[#prefs + 1] = l end
      end
    end
    if theme ~= "" and exists(RES .. "/ColorThemes/" .. theme) then
      -- lastthemefn5 is the theme REAPER loads at startup (full path);
      -- ui_img is the image set that goes with it
      local full = RES .. "/ColorThemes/" .. theme
      if IS_WIN then full = full:gsub("/", "\\") end
      prefs[#prefs + 1] = "lastthemefn5=" .. full
      prefs[#prefs + 1] = "ui_img=" .. theme
      -- Fonts belong to the theme. Font lines left in reaper.ini by an earlier theme
      -- (e.g. ReaTooled v2.6.1's, which was never saved as a theme file) would override
      -- the new theme's fonts, so they go (the backup keeps them for Restore).
      for _, k in ipairs(THEME_FONT_KEYS) do prefs[#prefs + 1] = "!delete " .. k end
    end
    -- Whole reaper.ini sections (floating toolbar windows), merged key by key too
    local extra = read_file(CONFIG .. "/reaper_sections.ini")
    if extra then
      for _, l in ipairs(lines_of(extra)) do
        if not l:match("^;") then prefs[#prefs + 1] = l end
      end
    end
    prefs_patch = table.concat(prefs, "\n") .. "\n"
    stage_merge("reaper.ini", prefs_patch)
  end

  -- Extension settings (SWS etc.), merged key by key
  local sws_patches = {}
  for _, rel in ipairs(list_files(CONFIG .. "/sws")) do
    local data = read_file(CONFIG .. "/sws/" .. rel)
    if data then
      stage_merge(rel, data)
      sws_patches[rel] = data
    end
  end

  write_file(PENDING .. "/copy.txt", table.concat(copies, "\n") .. "\n")
  write_file(PENDING .. "/merge.txt", table.concat(merges, "\n") .. "\n")
  if screenset_needs_window then
    write_file(PENDING .. "/screenset_window.txt", "Add the REAPER window size to screenset #1 after REAPER quits\n")
  end
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
          if section == "ReaTooled" and k == "WheelInvert" then v = wheel_invert end
          reaper.SetExtState(section, k, v, true)
          ext_count = ext_count + 1
        end
      end
    end
    reaper.SetExtState("ReaTooled", "WheelInvert", wheel_invert, true)   -- even if the config has none
  end

  -- Cursors, menu sets, templates, FX chains
  local copied, kept_files, folder_copied = 0, 0, {}
  for _, f in ipairs(FOLDERS) do
    for _, rel in ipairs(list_files(CONFIG .. "/files/" .. f.name)) do
      local dst = RES .. "/" .. f.name .. "/" .. rel
      if exists(dst) and not f.overwrite then
        kept_files = kept_files + 1
      elseif copy_file(CONFIG .. "/files/" .. f.name .. "/" .. rel, dst) then
        copied = copied + 1
        folder_copied[#folder_copied + 1] = f.name .. "/" .. rel
      end
    end
  end

  -- Theme: selected through reaper.ini (lastthemefn5 above), so it appears when REAPER
  -- restarts. Not switched while REAPER is running: ReaSmoothPlayhead would see a theme
  -- change in the middle of setup and turn itself off ("your theme has unsaved changes").
  local theme_note
  if theme == "" then
    theme_note = "Theme: none in the configuration."
  elseif not exists(RES .. "/ColorThemes/" .. theme) then
    theme_note = "Theme NOT applied: " .. theme .. " isn't in ColorThemes/. Install the " ..
      "\"ReaTooled Themes\" package in ReaPack, then run Set up again."
  else
    theme_note = "Theme: " .. theme:gsub("%.ReaperThemeZip$", ""):gsub("%.ReaperTheme$", "") ..
      " (selected when REAPER restarts)"
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
  -- ReaSmoothPlayhead too (installed on the next ReaPack sync, after the restart).
  -- Already installed some other way: adding its repository again changes nothing.
  reaper.ReaPack_AddSetRepository(SMOOTH_REPO_NAME, SMOOTH_REPO_URL, true, 1, "")
  if repo_ok then reaper.ReaPack_ProcessQueue(true) end

  reaper.SetExtState("ReaTooled", "SetupVersion", SETUP_VER, true)
  os.remove(RES .. "/Data/ReaTooled/starter_off.txt")   -- the ReaTooled Starter may start Set up again after a restore
  if screensets_patch then reaper.SetExtState("ReaTooled", "LoadScreensetOnce", "1", true) end
  if repo_ok then reaper.SetExtState("ReaTooled", "SyncOnce", "1", true) end
  reaper.SetExtState("ReaTooled", "ScrollingWindowOnce", "1", true)   -- "Scrolling and zooming" on the first start

  ------------------------------------------------------------
  -- 5b. The record of exactly what this setup changed, kept with the backup.
  -- "Restore settings from a backup" uses it to remove ReaTooled but keep
  -- what the user changed afterwards.
  ------------------------------------------------------------

  do
    local REC = backup_dir .. "/applied"
    -- Settings merged one by one (key=value)
    write_file(REC .. "/keys/reaper.ini", prefs_patch or "")
    for rel, data in pairs(sws_patches) do write_file(REC .. "/keys/" .. rel, data) end
    do  -- what was really applied: the config's script settings with the mousewheel choice
      local ext_text = read_file(CONFIG .. "/extstate.ini") or ""
      local found
      ext_text = ext_text:gsub("\nWheelInvert=[^\n]*", function() found = true; return "\nWheelInvert=" .. wheel_invert end)
      if not found then
        if ext_text:find("%[ReaTooled%]") then
          ext_text = ext_text:gsub("%[ReaTooled%]\n", "[ReaTooled]\nWheelInvert=" .. wheel_invert .. "\n", 1)
        else
          ext_text = ext_text .. "\n[ReaTooled]\nWheelInvert=" .. wheel_invert .. "\n"
        end
      end
      write_file(REC .. "/keys/reaper-extstate.ini", ext_text)
    end
    -- Whole sections replaced (menus/toolbars, screensets, theme settings);
    -- mouse modifier contexts are restored one modifier at a time, so they
    -- go with the key-by-key settings
    for target, name in pairs({ ["reaper-menu.ini"] = "menus.ini", ["reaper-themeconfig.ini"] = "themeconfig.ini" }) do
      local data = read_file(CONFIG .. "/" .. name)
      if data then write_file(REC .. "/sections/" .. target, data) end
    end
    if screensets_patch then write_file(REC .. "/sections/reaper-screensets.ini", screensets_patch) end
    local mouse = read_file(CONFIG .. "/mouse.ini")
    if mouse then write_file(REC .. "/keys/reaper-mouse.ini", mouse) end
    -- Shortcuts: "+ line" = added, "- old" then "= new" = replaced
    local kb = {}
    for _, l in ipairs(add_key) do kb[#kb + 1] = "+ " .. l end
    for i, l in pairs(replace_line) do
      kb[#kb + 1] = "- " .. user_lines[i]
      kb[#kb + 1] = "= " .. l
    end
    -- "x line" = an earlier ReaTooled shortcut that was removed
    for i in pairs(remove_line) do kb[#kb + 1] = "x " .. user_lines[i] end
    write_file(REC .. "/kb.txt", table.concat(kb, "\n") .. "\n")
    -- Whole files written (ReaImGui windows, cursors, templates ...)
    local files = {}
    for _, rel in ipairs(list_files(CONFIG .. "/files/ReaImGui")) do files[#files + 1] = "ReaImGui/" .. rel end
    for _, rel in ipairs(folder_copied) do files[#files + 1] = rel end
    for _, rel in ipairs(files) do
      local src = (rel:match("^ReaImGui/") and (CONFIG .. "/files/" .. rel)) or (RES .. "/" .. rel)
      copy_file(src, REC .. "/files/" .. rel)
    end
    write_file(REC .. "/files.txt", table.concat(files, "\n") .. "\n")
    write_file(REC .. "/record.txt", "ReaTooled setup record 1\nSet up " .. SETUP_VER ..
      "\nConfig " .. CONFIG_VER .. "\nDate: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
  end

  ------------------------------------------------------------
  -- 6. Start the helper, then tell the user what's left
  ------------------------------------------------------------

  -- The details go in a report file; the message only says what matters
  local details = {
    "ReaTooled setup, " .. os.date("%Y-%m-%d %H:%M:%S") .. " (Set up " .. SETUP_VER .. ", config " .. CONFIG_VER .. ")",
    "Backup of your settings: " .. backup_dir,
    "Shortcuts: " .. #add_key .. " added" ..
      (legacy_updated > 0 and (", " .. legacy_updated .. " from an earlier ReaTooled updated") or "") ..
      (legacy_removed > 0 and (", " .. legacy_removed .. " old ReaTooled shortcut(s) removed") or "") ..
      (#conflicts > 0 and (", " .. use_ours .. " clash(es) set to ReaTooled's, " .. kept .. " kept as yours") or "") ..
      (rekeyed > 0 and (", " .. rekeyed .. " given another key") or "") ..
      (midi_conflicts > 0 and (" (" .. midi_conflicts .. " of the clashes in the MIDI editor)") or "") .. ".",
    "Script settings: " .. ext_count .. ". Files: " .. copied .. " copied" ..
      (kept_files > 0 and (", " .. kept_files .. " of your own templates/FX chains kept") or "") .. ".",
    theme_note,
    "Screenset: the ReaTooled layout opens on the first start (your REAPER window keeps its size and place)" ..
      (screenset_needs_window and "; the window size is added when REAPER quits." or "."),
    hook_note,
    "Mousewheel: ReaTooled's wheel scripts set to " .. (wheel_invert == "1" and "Reversed" or "Standard") .. " (" .. wheel_note .. "); \"Scrolling and zooming\" opens on the first start.",
  }
  if #left_without > 0 then
    details[#details + 1] = "ReaTooled actions without a shortcut (you kept your own key): " .. table.concat(left_without, "; ")
  end
  if #gave_away > 0 then
    details[#details + 1] = "Your actions now without a shortcut (their key went to ReaTooled): " .. table.concat(gave_away, "; ")
  end
  if clash_fallback then
    details[#details + 1] = "ReaImGui isn't installed, so the shortcut clashes weren't shown: every clashing key was kept as yours."
  end
  write_file(RES .. "/Data/ReaTooled/setup_report.txt", table.concat(details, "\n") .. "\n")

  -- Only problems are shown
  local problems = {}
  if theme_note:find("NOT", 1, true) then problems[#problems + 1] = theme_note end
  if hook_note:find("NOT", 1, true) then problems[#problems + 1] = hook_note end
  if clash_fallback then
    problems[#problems + 1] = #conflicts .. " ReaTooled shortcut(s) clash with yours. ReaImGui isn't installed, so " ..
      "yours were kept. Install ReaImGui and run \"Set up ReaTooled\" again to choose."
  end
  local problem_text = #problems > 0 and ("\n\nPlease note:\n" .. table.concat(problems, "\n")) or ""

  -- ReaTooled actions left without a key, so nobody wonders where they went
  local skipped_text = ""
  if #left_without > 0 and not clash_fallback then
    local shown = {}
    for i = 1, math.min(#left_without, 8) do shown[#shown + 1] = "  " .. left_without[i] end
    if #left_without > 8 then shown[#shown + 1] = "  and " .. (#left_without - 8) .. " more (listed in Data/ReaTooled/setup_report.txt)" end
    skipped_text = "\n\nThese ReaTooled actions have no shortcut, because you kept your own keys:\n" ..
      table.concat(shown, "\n") ..
      "\nGive them keys in the Actions list, or run \"Set up ReaTooled\" again to choose differently."
  end

  local quit_cmd = find_cmd("File: Quit REAPER", 40004)
  local restart_now = false
  if quit_cmd then
    restart_now = (msg("ReaTooled is set up. Click OK to restart REAPER and finish." ..
      "\n\nWhen REAPER reopens, a small window lets you try scrolling and zooming, and adjust them if you like." ..
      problem_text .. skipped_text ..
      "\n\nYour old settings were backed up to:\n" .. backup_dir ..
      "\n\nTo undo, run \"Restore settings from a backup\".", 1) == 1)
  else
    msg("ReaTooled is set up. Quit REAPER and open it again to finish." ..
      "\n\nWhen REAPER reopens, a small window lets you try scrolling and zooming, and adjust them if you like." .. problem_text .. skipped_text ..
      "\n\nYour old settings were backed up to:\n" .. backup_dir)
  end

  if not launch_helper(restart_now) then
    msg("The finishing step couldn't be prepared (no permission to write in\n" .. PENDING ..
        ").\n\nPlease contact support.")
    return
  end

  if restart_now then reaper.Main_OnCommand(quit_cmd, 0) end
end

if #conflicts > 0 then
  if not clash_window() then
    -- No ReaImGui: nothing is asked, every clashing key stays yours
    clash_fallback = true
    apply_choices()
    finish_setup()
  end
else
  finish_setup()
end
