--[[
-- @description ReaTooled - Restore settings from a backup
-- @version 1.1.4
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Puts your REAPER settings back the way they were in a ReaTooled backup
    "Set up ReaTooled" backs up your settings before it changes anything
    (the first time to Data/ReaTooled/Backups/Before ReaTooled). This script
    lets you pick one of those backups and puts back everything Set up
    changes: shortcuts, menus and toolbars, mouse modifiers, preferences and
    theme, screensets, script settings, SWS settings, the startup script, and
    the cursors, menu sets, templates and FX chains ReaTooled added.
    Your plugins and plugin lists, projects, ReaPack and the installed
    scripts are never touched.
    For a backup made by Set up 2.2 or later you can also choose to remove
    only ReaTooled's changes and keep everything you changed after setup.
    Your current settings are backed up first, so a restore can be undone by
    restoring that backup. REAPER quits, the files are put back, and the same
    copy of REAPER opens again.
-- CHANGELOG
-- v1.1.4 "Keep my later changes" also puts back earlier ReaTooled shortcuts that Set up
--        removed when upgrading (if their key is still free)
-- v1.1.3 "Keep my later changes" now also puts back your window layout (docked
--        windows, dockers, toolbars) and your screensets as they were before ReaTooled;
--        fixed settings in [reaper] (lowercase, as on macOS) counting as "you changed it";
--        also restores reaper-wndpos.ini; puts your own theme back whenever a ReaTooled
--        theme is still selected (even if REAPER wrote its path differently)
-- v1.1.2 Ignores the REAPER window size when checking whether you changed the screenset
-- v1.1.1 Stops the ReaTooled Starter extension from starting Set up again after a restore
-- v1.1 New choice: remove ReaTooled but keep the changes you made after setup
-- v1.0 Initial version
--]]

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

-- Files in REAPER's folder that "Set up ReaTooled" changes. Only these are
-- restored (plugin lists, reapack.ini and everything else are left alone).
local RESTORE_FILES = {
  "reaper.ini", "reaper-kb.ini", "reaper-menu.ini", "reaper-mouse.ini",
  "reaper-screensets.ini", "reaper-themeconfig.ini", "reaper-extstate.ini", "reaper-wndpos.ini",
  "S&M.ini", "sws-autocoloricon.ini", "Xenakios_Commands.ini", "BR.ini",
  "S&M_Cyclactions.ini",
  "Scripts/__startup.lua",
}

-- Folders ReaTooled copies files into. Only the files the ReaTooled
-- configuration has are restored or removed; the user's others are left alone.
local RESTORE_FOLDERS = {
  "ReaImGui", "Cursors", "MenuSets", "FXChains", "ProjectTemplates", "TrackTemplates",
}

------------------------------------------------------------

local TITLE       = "Restore ReaTooled backup"
local RES         = reaper.GetResourcePath():gsub("\\", "/")
local CONFIG      = RES .. "/Data/ReaTooled/Config"
local PENDING     = RES .. "/Data/ReaTooled/Pending"
local BACKUP_ROOT = RES .. "/Data/ReaTooled/Backups"
local SETUP       = RES .. "/Scripts/ReaTooled/Startup/ReaTooled_Set up ReaTooled.lua"
local EEL_STARTUP = "Scripts/__startup.eel"
local EEL_MARK    = "ReaTooled first run"   -- in the __startup.eel the config zip adds

local function msg(text, buttons) return reaper.ShowMessageBox(text, TITLE, buttons or 0) end
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

local function find_cmd(name, guess)
  if guess and reaper.kbd_getTextFromCmd(guess, 0) == name then return guess end
  for id = 1, 65535 do
    if reaper.kbd_getTextFromCmd(id, 0) == name then return id end
  end
  return nil
end

------------------------------------------------------------
-- Checks
------------------------------------------------------------

if not exists(SETUP) then
  msg("Could not find \"Set up ReaTooled\", which this needs to finish the restore:\n" .. SETUP ..
      "\n\nReinstall ReaTooled in ReaPack and try again.")
  return
end

if exists(PENDING .. "/copy.txt") or exists(PENDING .. "/merge.txt") or exists(PENDING .. "/remove.txt") then
  msg("ReaTooled still has unfinished changes waiting for REAPER to restart.\n\n" ..
      "Quit REAPER and open it again first, then run this again.")
  return
end

------------------------------------------------------------
-- Pick a backup
------------------------------------------------------------

local backups = {}
reaper.EnumerateSubdirectories(BACKUP_ROOT, -1)
do
  local i = 0
  while true do
    local name = reaper.EnumerateSubdirectories(BACKUP_ROOT, i)
    if not name then break end
    local info = read_file(BACKUP_ROOT .. "/" .. name .. "/backup_info.txt")
    if info then
      backups[#backups + 1] = { name = name, date = info:match("Date:%s*([^\r\n]+)") or "" }
    end
    i = i + 1
  end
end

if #backups == 0 then
  msg("There are no ReaTooled backups in:\n" .. BACKUP_ROOT ..
      "\n\n(\"Set up ReaTooled\" makes one before it changes anything.)")
  return
end

-- "Before ReaTooled" first, then the newest first
table.sort(backups, function(a, b)
  if a.name == "Before ReaTooled" then return b.name ~= "Before ReaTooled" end
  if b.name == "Before ReaTooled" then return false end
  return a.date > b.date
end)

local chosen
if #backups == 1 then
  chosen = backups[1]
else
  local items = {}
  for i, b in ipairs(backups) do
    local label = b.name .. ((b.date ~= "" and not b.name:find(b.date:sub(1, 10), 1, true))
      and ("  (" .. b.date .. ")") or "")
    items[i] = label:gsub("[|!#<>]", " ")
  end
  local x, y = reaper.GetMousePosition()
  gfx.init(TITLE, 0, 0, 0, x, y)
  gfx.x, gfx.y = gfx.screentoclient(x, y)
  local pick = gfx.showmenu("#Restore which backup?|" .. table.concat(items, "|"))
  gfx.quit()
  if pick < 2 then return end
  chosen = backups[pick - 1]
end

local SRC = BACKUP_ROOT .. "/" .. chosen.name

------------------------------------------------------------
-- INI files: { pre = {...}, order = {names}, sec = {name = {lines}} }
------------------------------------------------------------

local function lines_of(text)
  local out = {}
  for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do out[#out + 1] = line end
  if out[#out] == "" then out[#out] = nil end
  return out
end

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
    if ini.sec[name] then
      if #out > 0 then out[#out + 1] = "" end
      out[#out + 1] = "[" .. name .. "]"
      for _, l in ipairs(ini.sec[name]) do out[#out + 1] = l end
    end
  end
  return table.concat(out, "\n") .. "\n"
end

-- { section = { key = value } } (later lines win)
local function ini_values(text)
  local ini, out = ini_parse(text), {}
  for _, name in ipairs(ini.order) do
    out[name] = out[name] or {}
    for _, l in ipairs(ini.sec[name]) do
      local k, v = l:match("^([^=]+)=(.*)$")
      if k then out[name][k] = v end
    end
  end
  return out
end

local cache = {}
local function values_of(path)
  if cache[path] == nil then cache[path] = ini_values(read_file(path) or "") end
  return cache[path]
end

local function same_value(a, b)
  if a == b then return true end
  if a == nil or b == nil then return false end
  local na, nb = tonumber(a), tonumber(b)
  if na and nb then return math.abs(na - nb) <= 1e-9 * math.max(1, math.abs(na), math.abs(nb)) end
  return (a:match("^%s*(.-)%s*$")) == (b:match("^%s*(.-)%s*$"))
end

local function same_lines(a, b)
  if not a or not b then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do
    if (a[i]:match("^%s*(.-)%s*$")) ~= (b[i]:match("^%s*(.-)%s*$")) then return false end
  end
  return true
end

------------------------------------------------------------
-- The plan: files to write, files to remove, settings to merge
------------------------------------------------------------

local plan = {
  copies  = {},   -- { rel, data }   written whole after REAPER quits
  remove  = {},   -- rel             removed after REAPER quits
  merges  = {},   -- rel -> patch    merged key by key after REAPER quits
  ext     = {},   -- { section, key, value or nil }  script settings, applied now
  touched = {},   -- rel -> true     backed up before anything changes
  report  = {},
}
local function touch(rel) plan.touched[rel] = true end
local function plan_copy(rel, data) plan.copies[#plan.copies + 1] = { rel, data }; touch(rel) end
local function plan_remove(rel) plan.remove[#plan.remove + 1] = rel; touch(rel) end
local function report(line) plan.report[#plan.report + 1] = line end

local function startup_eel()
  if exists(SRC .. "/" .. EEL_STARTUP) then
    plan_copy(EEL_STARTUP, read_file(SRC .. "/" .. EEL_STARTUP))
  elseif (read_file(RES .. "/" .. EEL_STARTUP) or ""):find(EEL_MARK, 1, true) then
    plan_remove(EEL_STARTUP)
  end
end

------------------------------------------------------------
-- A. Put everything back exactly as it was in the backup
------------------------------------------------------------

local function plan_full()
  local function consider(rel)
    if exists(SRC .. "/" .. rel) then
      plan_copy(rel, read_file(SRC .. "/" .. rel))
    elseif exists(RES .. "/" .. rel) then
      plan_remove(rel)
    end
  end
  for _, rel in ipairs(RESTORE_FILES) do consider(rel) end
  -- In the folders, only the files that come with the ReaTooled configuration
  -- (the user's other script windows, templates etc. stay as they are). A
  -- backup made by a restore holds exactly the files that restore changed, so
  -- all of its files count too.
  local made_by_restore = (read_file(SRC .. "/backup_info.txt") or ""):find("before restoring", 1, true)
  local seen = {}
  for _, folder in ipairs(RESTORE_FOLDERS) do
    local roots = { CONFIG .. "/files/" .. folder }
    if made_by_restore then roots[2] = SRC .. "/" .. folder end
    for _, root in ipairs(roots) do
      for _, rel in ipairs(list_files(root)) do
        local full = folder .. "/" .. rel
        if not seen[full] then
          seen[full] = true
          consider(full)
        end
      end
    end
  end
  startup_eel()
end

------------------------------------------------------------
-- B. Remove ReaTooled, keep the user's later changes
--
-- Each setup saved a record (Backups/<name>/applied) of what it set. For
-- every setting ReaTooled set:
--   still ReaTooled's value  -> back to the value before that setup
--   changed since            -> the user's change, kept
-- Settings ReaTooled never touched are left alone.
------------------------------------------------------------

local function record_of(b) return BACKUP_ROOT .. "/" .. b.name .. "/applied" end
local function has_record(b) return exists(record_of(b) .. "/record.txt") end

-- The setups from the chosen backup on, oldest first
local records = {}
for _, b in ipairs(backups) do
  if has_record(b) and (b == chosen or b.date >= chosen.date) then records[#records + 1] = b end
end
table.sort(records, function(a, b) return a.date < b.date end)

-- The window layout (which windows are open, docked and where, the dockers,
-- toolbars) lives in reaper.ini. Loading the ReaTooled screenset changes it, and
-- REAPER rewrites it all the time, so it is never "your change": removing
-- ReaTooled always puts back the layout from before that setup.
local LAYOUT_MAIN = { "^dock", "_dock$", "_dock_pos$", "_vis$", "^toppane", "^leftpanewid", "^fsautohidedock$", "^wnd_state$" }
local LAYOUT_WINDOW_KEYS = { dock = true, wnd_vis = true, docked = true, visible = true }
local function layout_section(sec)
  local l = sec:lower()
  return l == "reaperdockpref" or l:match("^toolbar:%d+$") ~= nil
end
local function is_layout(sec, key)
  if sec:lower() == "reaper" then
    for _, p in ipairs(LAYOUT_MAIN) do if key:match(p) then return true end end
    return false
  end
  return layout_section(sec) or LAYOUT_WINDOW_KEYS[key] == true
end

-- Patch lines that make reaper.ini's layout exactly the backup's
local function layout_patch(backup_ini_path)
  local base = values_of(backup_ini_path)
  local cur = values_of(RES .. "/reaper.ini")
  local function lower_map(t) local m = {} for name, kv in pairs(t) do m[name:lower()] = { name = name, kv = kv } end return m end
  local b, c = lower_map(base), lower_map(cur)
  local names = {}
  for l in pairs(b) do names[l] = true end
  for l in pairs(c) do names[l] = true end
  local sorted = {}
  for l in pairs(names) do sorted[#sorted + 1] = l end
  table.sort(sorted)
  local out, n = {}, 0
  for _, l in ipairs(sorted) do
    local bk = b[l] and b[l].kv or {}
    local ck = c[l] and c[l].kv or {}
    local name = (c[l] or b[l]).name
    local lines, keys = {}, {}
    for k in pairs(bk) do keys[k] = true end
    for k in pairs(ck) do keys[k] = true end
    local klist = {}
    for k in pairs(keys) do klist[#klist + 1] = k end
    table.sort(klist)
    for _, k in ipairs(klist) do
      if is_layout(name, k) and not same_value(ck[k], bk[k]) then
        lines[#lines + 1] = bk[k] and (k .. "=" .. bk[k]) or ("!delete " .. k)
      end
    end
    if #lines > 0 then
      out[#out + 1] = "[" .. name .. "]"
      for _, x in ipairs(lines) do out[#out + 1] = x end
      n = n + #lines
    end
  end
  return table.concat(out, "\n"), n
end

local function plan_keep()
  local kept, reverted = 0, 0
  local kept_names = {}

  -- 1. Settings merged key by key: preferences, SWS settings, mouse modifiers,
  --    script settings. item[target][section][key] = { rt = value, base = value }
  local items, order = {}, {}
  for _, b in ipairs(records) do
    for _, rel in ipairs(list_files(record_of(b) .. "/keys")) do
      if not items[rel] then items[rel] = {}; order[#order + 1] = rel end
      local rt = values_of(record_of(b) .. "/keys/" .. rel)
      local base = values_of(BACKUP_ROOT .. "/" .. b.name .. "/" .. rel)
      for sec, kv in pairs(rt) do
        local t = items[rel][sec]
        if not t then
          t = {}
          items[rel][sec] = t
          -- Mouse modifier contexts were replaced whole: modifiers that were
          -- there before and that ReaTooled's context doesn't have count too
          if rel == "reaper-mouse.ini" and sec ~= "hasimported" then
            for k, v in pairs(base[sec] or {}) do t[k] = { base = v } end
          end
        end
        if rel == "reaper-mouse.ini" and sec ~= "hasimported" then
          for _, it in pairs(t) do it.rt = nil end   -- this setup replaced the whole context again
        end
        for k, v in pairs(kv) do
          if not t[k] then t[k] = { base = (base[sec] or {})[k] } end
          t[k].rt = v
        end
      end
    end
  end

  local current_file = {}
  local function current(rel, sec, key)
    if rel == "reaper-extstate.ini" then
      if reaper.HasExtState(sec, key) then return reaper.GetExtState(sec, key) end
      return nil
    end
    if rel == "reaper.ini" and sec:lower() == "reaper" then
      local ok, v = reaper.get_config_var_string(key)
      if ok then return v end
    end
    if not current_file[rel] then
      -- section names in any case ([reaper] on macOS = [REAPER])
      current_file[rel] = {}
      for name, kv in pairs(values_of(RES .. "/" .. rel)) do
        local t = current_file[rel][name:lower()] or {}
        for k, v in pairs(kv) do t[k] = v end
        current_file[rel][name:lower()] = t
      end
    end
    return (current_file[rel][sec:lower()] or {})[key]
  end

  for _, rel in ipairs(order) do
    local patch = {}
    local secs = {}
    for sec in pairs(items[rel]) do secs[#secs + 1] = sec end
    table.sort(secs)
    for _, sec in ipairs(secs) do
      local lines = {}
      local keys = {}
      for k in pairs(items[rel][sec]) do keys[#keys + 1] = k end
      table.sort(keys)
      for _, k in ipairs(keys) do
        local it = items[rel][sec][k]
        local cur_v = current(rel, sec, k)
        -- The theme: still ReaTooled's whenever a ReaTooled theme is selected
        -- (REAPER may write the path differently from Set up)
        local theme_key = rel == "reaper.ini" and sec:lower() == "reaper" and (k == "lastthemefn5" or k == "ui_img")
        if theme_key then
          if k == "lastthemefn5" and reaper.GetLastColorThemeFile then
            cur_v = reaper.GetLastColorThemeFile() or cur_v
          end
          if cur_v and cur_v:find("ReaTooled", 1, true) then cur_v = it.rt end
        end
        if rel == "reaper.ini" and is_layout(sec, k) then
          -- the window layout is put back below
        elseif same_value(cur_v, it.rt) then
          if not same_value(it.rt, it.base) then
            reverted = reverted + 1
            if rel == "reaper-extstate.ini" then
              plan.ext[#plan.ext + 1] = { sec, k, it.base }
            elseif it.base then
              lines[#lines + 1] = k .. "=" .. it.base
            else
              lines[#lines + 1] = "!delete " .. k
            end
          end
        else
          kept = kept + 1
          report("kept (you changed it)   " .. rel .. "  [" .. sec .. "] " .. k)
        end
      end
      if #lines > 0 then
        patch[#patch + 1] = "[" .. sec .. "]"
        for _, l in ipairs(lines) do patch[#patch + 1] = l end
      end
    end
    if #patch > 0 and rel ~= "reaper-extstate.ini" then
      plan.merges[rel] = table.concat(patch, "\n") .. "\n"
      touch(rel)
    end
  end

  -- 1b. The window layout from before ReaTooled (see LAYOUT_MAIN)
  do
    local backup_ini = BACKUP_ROOT .. "/" .. records[1].name .. "/reaper.ini"
    if exists(backup_ini) then
      local patch, n = layout_patch(backup_ini)
      if n > 0 then
        plan.merges["reaper.ini"] = (plan.merges["reaper.ini"] or "") .. patch .. "\n"
        touch("reaper.ini")
        reverted = reverted + 1
        report("put back   your window layout (" .. n .. " setting(s) in reaper.ini)")
      end
    end
  end
  if exists(RES .. "/reaper-extstate.ini") then touch("reaper-extstate.ini") end

  -- 2. Whole sections: menus and toolbars, screensets, theme settings
  local sec_items, sec_order = {}, {}
  for _, b in ipairs(records) do
    for _, rel in ipairs(list_files(record_of(b) .. "/sections")) do
      if not sec_items[rel] then sec_items[rel] = {}; sec_order[#sec_order + 1] = rel end
      local rt = ini_parse(read_file(record_of(b) .. "/sections/" .. rel) or "")
      local base = ini_parse(read_file(BACKUP_ROOT .. "/" .. b.name .. "/" .. rel) or "")
      for _, sec in ipairs(rt.order) do
        local it = sec_items[rel][sec]
        if not it then
          it = { base = base.sec[sec] }
          sec_items[rel][sec] = it
        end
        it.rt = rt.sec[sec]
      end
    end
  end
  for _, rel in ipairs(sec_order) do
    local cur = ini_parse(read_file(RES .. "/" .. rel) or "")
    local changed = false
    local names = {}
    for sec in pairs(sec_items[rel]) do names[#names + 1] = sec end
    table.sort(names)
    for _, sec in ipairs(names) do
      local it = sec_items[rel][sec]
      -- The REAPER window size in a screenset is added after setup (and changes
      -- with the window), so it doesn't count as a change
      local function plain(lines)
        if not lines or rel ~= "reaper-screensets.ini" then return lines end
        local out = {}
        for _, l in ipairs(lines) do if not l:match("^mainwnd_") then out[#out + 1] = l end end
        return out
      end
      -- ReaTooled's screenset slots always go back to yours: the layout they
      -- hold is ReaTooled's, and REAPER rewrites them when they're loaded
      if rel == "reaper-screensets.ini" or same_lines(plain(cur.sec[sec]), plain(it.rt)) then
        if not same_lines(it.rt, it.base) then
          if it.base then
            if not cur.sec[sec] then cur.order[#cur.order + 1] = sec end
            cur.sec[sec] = it.base
          else
            cur.sec[sec] = nil
          end
          changed = true
          reverted = reverted + 1
        end
      else
        kept = kept + 1
        report("kept (you changed it)   " .. rel .. "  [" .. sec .. "]")
        if rel == "reaper-menu.ini" then kept_names[#kept_names + 1] = sec end
      end
    end
    if changed then plan_copy(rel, ini_text(cur)) end
  end

  -- 3. Shortcuts
  do
    local kb = lines_of(read_file(RES .. "/reaper-kb.ini") or "")
    local function norm(l) return (l:gsub("%s+", " "):match("^%s*(.-)%s*$")) end
    local function find(l)
      local n = norm(l)
      for i, x in ipairs(kb) do if norm(x) == n then return i end end
    end
    local changed = false
    for r = #records, 1, -1 do
      local lines = lines_of(read_file(record_of(records[r]) .. "/kb.txt") or "")
      local i = 1
      while i <= #lines do
        local l = lines[i]
        if l:sub(1, 2) == "+ " then
          local at = find(l:sub(3))
          if at then table.remove(kb, at); changed = true; reverted = reverted + 1
          else kept = kept + 1; report("kept (you changed it)   shortcut " .. l:sub(3)) end
          i = i + 1
        elseif l:sub(1, 2) == "x " then
          -- an earlier ReaTooled shortcut Set up removed: back, unless that key is taken now
          local old = l:sub(3)
          local f = {}
          for w in old:gmatch("%S+") do f[#f + 1] = w; if #f == 5 then break end end
          local taken = false
          if f[1] == "KEY" then
            for _, x in ipairs(kb) do
              local g = {}
              for w in x:gmatch("%S+") do g[#g + 1] = w; if #g == 5 then break end end
              if g[1] == "KEY" and g[2] == f[2] and g[3] == f[3] and g[5] == f[5] then taken = true; break end
            end
          end
          if not taken and not find(old) then
            kb[#kb + 1] = old; changed = true; reverted = reverted + 1
          elseif taken then
            kept = kept + 1; report("kept (key now used)     shortcut " .. old)
          end
          i = i + 1
        elseif l:sub(1, 2) == "- " and lines[i + 1] and lines[i + 1]:sub(1, 2) == "= " then
          local at = find(lines[i + 1]:sub(3))
          if at then kb[at] = l:sub(3); changed = true; reverted = reverted + 1
          else kept = kept + 1; report("kept (you changed it)   shortcut " .. lines[i + 1]:sub(3)) end
          i = i + 2
        else
          i = i + 1
        end
      end
    end
    if changed then plan_copy("reaper-kb.ini", table.concat(kb, "\n") .. "\n") end
  end

  -- 4. Whole files (ReaImGui windows, cursors, menu sets, templates, FX chains)
  do
    local f_items, f_order = {}, {}
    for _, b in ipairs(records) do
      for _, rel in ipairs(lines_of(read_file(record_of(b) .. "/files.txt") or "")) do
        if rel ~= "" then
          if not f_items[rel] then
            f_items[rel] = { base = BACKUP_ROOT .. "/" .. b.name .. "/" .. rel }
            f_order[#f_order + 1] = rel
          end
          f_items[rel].rt = read_file(record_of(b) .. "/files/" .. rel)
        end
      end
    end
    for _, rel in ipairs(f_order) do
      local it = f_items[rel]
      local cur = read_file(RES .. "/" .. rel)
      if cur ~= nil and cur == it.rt then
        local base = read_file(it.base)
        if base then
          if base ~= cur then plan_copy(rel, base); reverted = reverted + 1 end
        else
          plan_remove(rel); reverted = reverted + 1
        end
      elseif cur ~= nil then
        kept = kept + 1
        report("kept (you changed it)   " .. rel)
      end
    end
  end

  -- 5. The ReaTooled block in Scripts/__startup.lua (the rest is the user's)
  do
    local rel = "Scripts/__startup.lua"
    local text = read_file(RES .. "/" .. rel)
    if text then
      local out, inside, found, after = {}, false, false, false
      for _, line in ipairs(lines_of(text)) do
        if not inside and line:find("-- >>> ReaTooled startup", 1, true) then
          inside, found = true, true
        elseif inside then
          if line:find("-- <<< ReaTooled startup <<<", 1, true) then inside, after = false, true end
        elseif after and line == "" then
          after = false   -- the blank line the installer put after the block
        else
          after = false
          out[#out + 1] = line
        end
      end
      if found then
        local rest = table.concat(out, "\n")
        local had = exists(BACKUP_ROOT .. "/" .. records[1].name .. "/" .. rel)
        if rest:match("^%s*$") and not had then plan_remove(rel) else plan_copy(rel, rest .. "\n") end
        reverted = reverted + 1
      end
    end
  end

  startup_eel()

  -- ReaTooled's own setup markers
  for _, k in ipairs({ "SetupVersion", "LoadScreensetOnce", "SyncOnce" }) do
    plan.ext[#plan.ext + 1] = { "ReaTooled", k, nil }
  end

  return reverted, kept, kept_names
end

------------------------------------------------------------
-- Choose how, then confirm
------------------------------------------------------------

local keep_mode = false
if records[1] and records[1] == chosen then
  local how = msg("How should \"" .. chosen.name .. "\" be restored?\n\n" ..
    "YES = Remove ReaTooled, keep my later changes (recommended)\n" ..
    "    Puts back only what ReaTooled changed. Settings, shortcuts, toolbars and " ..
    "files you changed after setup stay as they are.\n\n" ..
    "NO = Put everything back exactly as it was\n" ..
    "    Also undoes your own changes since then.\n\n" ..
    "CANCEL = Don't restore", 3)
  if how == 6 then keep_mode = true elseif how ~= 7 then return end
end

local confirm
if keep_mode then
  local reverted, kept, kept_names = plan_keep()
  if reverted == 0 then
    msg("Nothing to remove: every setting ReaTooled set has been changed since, or is already back.")
    return
  end
  confirm = "Remove ReaTooled, keeping your later changes?\n\n" ..
    reverted .. " ReaTooled change(s) will be put back to how they were before." ..
    (kept > 0 and ("\n" .. kept .. " setting(s) you changed since will be kept.") or "") ..
    (#kept_names > 0 and ("\n\nThese toolbars/menus you edited stay as you have them " ..
      "(reset them yourself if you want):\n  " .. table.concat(kept_names, "\n  ", 1, math.min(#kept_names, 12)) ..
      (#kept_names > 12 and "\n  ..." or "")) or "") ..
    "\n\nThe full list goes in Data/ReaTooled/restore_report.txt."
else
  plan_full()
  if #plan.copies == 0 then
    msg("The backup \"" .. chosen.name .. "\" doesn't have any of the files ReaTooled changes, " ..
        "so there's nothing to restore.")
    return
  end
  confirm = "Restore \"" .. chosen.name .. "\"" ..
    (chosen.date ~= "" and (" from " .. chosen.date) or "") .. "?\n\n" ..
    "This puts back your shortcuts, menus and toolbars, mouse modifiers, preferences " ..
    "and theme, screensets, script settings, SWS settings and startup script as they " ..
    "were then. Anything changed in them since that backup is undone, not only ReaTooled's changes."
end

local ok = msg(confirm .. "\n\n" ..
  "Not touched: your plugins and plugin lists, projects, ReaPack, and the installed " ..
  "scripts (the ReaTooled scripts stay installed - remove them in ReaPack if you want).\n\n" ..
  "Your current settings are backed up first, so you can undo this by restoring that backup.\n\n" ..
  "Click OK and REAPER quits (you'll be asked to save anything unsaved), puts the files " ..
  "back, and opens again.", 1)
if ok ~= 1 then return end

------------------------------------------------------------
-- Back up the current files first
------------------------------------------------------------

local safety_name = os.date("%Y-%m-%d_%H%M%S") .. " before restore"
local SAFETY = BACKUP_ROOT .. "/" .. safety_name
local failed = {}
for rel in pairs(plan.touched) do
  if exists(RES .. "/" .. rel) and not copy_file(RES .. "/" .. rel, SAFETY .. "/" .. rel) then
    failed[#failed + 1] = rel
  end
end
if #failed == 0 then
  write_file(SAFETY .. "/backup_info.txt",
    "ReaTooled backup (made before restoring \"" .. chosen.name .. "\"" ..
    (keep_mode and ", keeping later changes" or "") .. ")\nDate: " ..
    os.date("%Y-%m-%d %H:%M:%S") .. "\nREAPER: " .. reaper.GetAppVersion() .. "\n")
end
if #failed > 0 or not exists(SAFETY .. "/backup_info.txt") then
  msg("Your current settings couldn't be backed up, so nothing was changed.\n\nCould not copy:\n  " ..
      table.concat(failed, "\n  ") .. "\n\nBackup folder:\n" .. SAFETY)
  return
end

------------------------------------------------------------
-- Prepare the files; the helper writes them after REAPER quits
------------------------------------------------------------

local function unstage()
  for _, f in ipairs({ "copy.txt", "merge.txt", "remove.txt", "restore.txt", "info.txt", "screenset_window.txt" }) do
    os.remove(PENDING .. "/" .. f)
  end
end

unstage()   -- anything left over from a setup or restore that didn't finish
local copies, merges = {}, {}
for _, c in ipairs(plan.copies) do
  if c[2] and write_file(PENDING .. "/files/" .. c[1], c[2]) then
    copies[#copies + 1] = c[1]
  else
    failed[#failed + 1] = c[1]
  end
end
for rel, data in pairs(plan.merges) do
  if write_file(PENDING .. "/merge/" .. rel, data) then merges[#merges + 1] = rel else failed[#failed + 1] = rel end
end
if #failed > 0 then
  unstage()
  msg("Some files couldn't be prepared, so nothing was changed:\n  " .. table.concat(failed, "\n  "))
  return
end
write_file(PENDING .. "/copy.txt", table.concat(copies, "\n") .. "\n")
if #merges > 0 then write_file(PENDING .. "/merge.txt", table.concat(merges, "\n") .. "\n") end
if #plan.remove > 0 then write_file(PENDING .. "/remove.txt", table.concat(plan.remove, "\n") .. "\n") end
write_file(PENDING .. "/restore.txt", chosen.name .. "\n")
write_file(PENDING .. "/info.txt", "Prepared by Restore settings from a backup 1.1.3 on " ..
  os.date("%Y-%m-%d %H:%M:%S") .. ": restoring \"" .. chosen.name .. "\"" ..
  (keep_mode and " (keeping later changes)" or "") .. "\n")

local quit_cmd = find_cmd("File: Quit REAPER", 40004)
local opt = { relaunch = quit_cmd ~= nil }
_G.REATOOLED_RELAUNCH_HELPER = opt
local ran, err = pcall(dofile, SETUP)
_G.REATOOLED_RELAUNCH_HELPER = nil

if not (ran and opt.started) then
  unstage()
  msg("The restore couldn't be started" .. (ran and "" or (" (" .. tostring(err) .. ")")) ..
      ".\n\nNothing was changed. Please contact support.")
  return
end

-- Keep the ReaTooled Starter extension from starting Set up again by itself
-- (running Set up yourself turns it back on)
write_file(RES .. "/Data/ReaTooled/starter_off.txt",
  "Written by Restore settings from a backup: the ReaTooled Starter won't start Set up by itself.\n")

-- Script settings are changed now (REAPER saves them when it quits)
for _, e in ipairs(plan.ext) do
  if e[3] then reaper.SetExtState(e[1], e[2], e[3], true)
  else reaper.DeleteExtState(e[1], e[2], true) end
end

write_file(RES .. "/Data/ReaTooled/restore_report.txt",
  "ReaTooled restore, " .. os.date("%Y-%m-%d %H:%M:%S") .. ": \"" .. chosen.name .. "\"" ..
  (keep_mode and " (keeping later changes)" or " (everything)") .. "\n" ..
  "Your settings before this restore: " .. SAFETY .. "\n\n" ..
  "Put back: " .. #copies .. " file(s), " .. #merges .. " merged, " .. #plan.remove .. " removed, " ..
  #plan.ext .. " script setting(s)\n" ..
  (#plan.report > 0 and ("\n" .. table.concat(plan.report, "\n") .. "\n") or ""))

if quit_cmd then
  reaper.Main_OnCommand(quit_cmd, 0)
else
  msg("Now quit REAPER and open it again to finish the restore.")
end
