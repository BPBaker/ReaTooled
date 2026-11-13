--[[
-- @description ReaTooled - Dependencies library
-- @version 1.1
-- @author Brendan Baker
-- @noindex
-- @about
--   Installs the other developers' extensions and scripts ReaTooled uses (SWS, js_ReaScriptAPI,
--   ReaImGui, reAAF and a few scripts), through ReaPack, so ReaPack records them and keeps them
--   up to date like anything else installed with it. Used by "ReaTooled_Install.lua" (the
--   ReaTooled package) and "Set up ReaTooled" (a ReaPack install).
--
--   ReaPack can't be asked to install one package; it installs everything new in a repository
--   when "install new packages" is on for it. So, for each repository that has something
--   missing, this:
--     1. writes a trimmed copy of the repository's real index: the missing packages, plus
--        everything already installed from that repository (so ReaPack doesn't call them
--        obsolete and offer to uninstall them)
--     2. points the repository at that copy with "install new packages" on (ReaPack then
--        synchronizes just that repository)
--     3. waits until ReaPack has recorded the new files
--     4. once ReaPack has finished, points the repository back at its real address with its own
--        settings (a repository it added: installs nothing new by itself), and puts the real
--        index in ReaPack's cache in place of the trimmed one (never deleted: ReaPack crashes
--        REAPER if its package browser refreshes from a cached index that isn't there)
--   Files already on disk that ReaPack doesn't record (the js_ReaScriptAPI the ReaTooled package
--   brings, or SWS from its own installer) are installed over by ReaPack, so it records and
--   updates them too; a file another ReaPack package owns is left alone.
--   If REAPER quits or crashes in between, step 4 is done the next time this library runs.
--   ReaPack_ProcessQueue is called once, to start the install, and never right after one: ReaPack
--   crashes REAPER if it's called again while an install is winding down.
--   Needs ReaPack, and curl (part of macOS, Windows 10/11 and nearly every Linux).
--]]

local M = {}

-- What ReaTooled uses from other developers (the same as reaboot-recipe.json; the release build
-- stops if the two differ). quick: an API function the extension adds, to see it's loaded;
-- quick_file: the start of its file name in UserPlugins (an extension without an API);
-- quick_script: one of its script files, when none is named like the package.
M.LIST = {
  { url = "https://github.com/ReaTeam/Extensions/raw/master/index.xml#p=Extensions/reaper-oss_SWS.ext", quick = "CF_GetSWSVersion", quick_file = "reaper_sws" },
  { url = "https://github.com/ReaTeam/Extensions/raw/master/index.xml#p=API/js_ReaScriptAPI.ext", quick = "JS_ReaScriptAPI_Version", quick_file = "reaper_js_ReaScriptAPI" },
  { url = "https://github.com/ReaTeam/Extensions/raw/master/index.xml#p=API/reaper_imgui.ext", quick = "ImGui_GetBuiltinPath", quick_file = "reaper_imgui" },
  { url = "https://raw.githubusercontent.com/smandrap/reAAF/refs/heads/main/index.xml#p=Extensions/reAAF.ext", quick_file = "reaper_reAAF" },
  { url = "https://github.com/ReaTeam/ReaScripts/raw/master/index.xml#p=Cursor/Place%20play%20cursor%20into%20view%20(when%20playing)%20or%20Center%20edit%20cursor%20(when%20stopped).eel" },
  { url = "https://github.com/ReaTeam/ReaScripts/raw/master/index.xml#p=Items%20Editing/az_Fade%20tool%20(work%20on%20context%20of%20mouse,%20razor%20or%20time%20selection).lua" },
  { url = "https://github.com/ReaTeam/ReaScripts/raw/master/index.xml#p=Items%20Editing/az_Open%20item%20copy%20in%20primary%20external%20editor%20with%20handles.lua" },
  { url = "https://github.com/ReaTeam/ReaScripts/raw/master/index.xml#p=Items%20Editing/rodilab_Duplicate%20items%20or%20tracks%20(depending%20on%20focus%20and%20time%20selection).lua" },
  { url = "https://github.com/ReaTeam/ReaScripts/raw/master/index.xml#p=Items%20Properties/rodilab_Loop%20section%20of%20audiomidi%20item%20source%20within%20time%20selection,%20if%20any.lua" },
  { url = "https://github.com/ReaTeam/ReaScripts/raw/master/index.xml#p=Various/rodilab_Color%20palette.lua" },
  { url = "https://github.com/ReaTeam/ReaScripts/raw/master/index.xml#p=Items%20Editing/80icio_Perfect%20Timing!%20-%20Audio%20Quantizer.lua" },
  { url = "https://github.com/X-Raym/REAPER-ReaScripts/raw/master/index.xml#p=Envelopes/On%20Tracks/X-Raym_Add%20envelope%20points%20at%20time%20selection%20edges%20from%20center%20to%20center%20preserving%20edges.lua" },
  { url = "https://github.com/X-Raym/REAPER-ReaScripts/raw/master/index.xml#p=FX/X-Raym_Set%20selected%20tracks%20FX%20parameter%20value%20from%20last%20focused%20FX%20last%20touch%20parameter.lua" },
  { url = "https://github.com/X-Raym/REAPER-ReaScripts/raw/master/index.xml#p=Items%20Editing/X-Raym_Move%20selected%20items%20to%20end%20of%20previous%20items%20on%20all%20visible%20tracks.lua" },
  { url = "https://github.com/X-Raym/REAPER-ReaScripts/raw/master/index.xml#p=Items%20Editing/X-Raym_Move%20selected%20items%20to%20next%20item%20on%20all%20visible%20tracks.lua" },
  { url = "https://github.com/X-Raym/REAPER-ReaScripts/raw/master/index.xml#p=Razor%20Edit/X-Raym_Set%20selected%20tracks%20razor%20edit%20area%20to%20time%20selection.lua" },
  { url = "https://github.com/MichaelPilyavskiy/ReaScripts/raw/master/index.xml#p=FX/mpl_Adjust%20normalized%20last%20touched%20parameter.lua",
    quick_script = "mpl_Add 0.01 to normalized last touched parameter.lua" },   -- (its scripts have other names)
  { url = "https://github.com/MichaelPilyavskiy/ReaScripts/raw/master/index.xml#p=Various/mpl_ImportSessionData.lua" },
  { url = "https://github.com/Odedd/ReaScripts/raw/main/index.xml#p=Various/Project%20Archiver/Odedd_Project%20Archiver.lua" },
  { url = "https://github.com/smandrap/ReaScripts/raw/master/index.xml#p=Tracks/smandrap_Duplicate%20Tracks.lua" },
  { url = "https://github.com/sonictim/TJF-Scripts/raw/master/index.xml#p=Editing/Reverse/TJF%20Non%20Destructive%20Reverse%20Time%20selection.lua" },
  { url = "https://github.com/sonictim/TJF-Scripts/raw/master/index.xml#p=Editing/Takes/TJF%20Toggle%20Mute%20(Match%20First%20Selected).lua" },
  { url = "https://github.com/sonictim/TJF-Scripts/raw/master/index.xml#p=Editing/TJF%20Toggle%20Item%20Lock%20(matches%20first%20item).lua" },
  { url = "https://github.com/sonictim/TJF-Scripts/raw/master/index.xml#p=Envelopes%20or%20Automation/TJF%20Write%20Punch%20ALL%20envelopes%20to%20Time,%20RazorEdit,%20or%20Item%20Selection.lua" },
  { url = "https://github.com/sonictim/TJF-Scripts/raw/master/index.xml#p=Session%20Navigation/TJF%20Decrease%20Selected%20Track%20Heights.lua" },
  { url = "https://github.com/sonictim/TJF-Scripts/raw/master/index.xml#p=Session%20Navigation/TJF%20Increase%20Selected%20Track%20Heights.lua" },
}

local SEC = "ReaTooled"
local PENDING = "DepsPending"         -- ExtState (kept on disk): repositories still pointing at a trimmed copy
local WAIT = 240                      -- seconds to wait for ReaPack to install (opts.timeout)
local SETTLE = 2                      -- then seconds for ReaPack to finish (its windows, its cache)
local RES = reaper.GetResourcePath():gsub("\\", "/")
local WORK = RES .. "/Data/ReaTooled/Install"
local IS_WIN = reaper.GetOS():match("Win") ~= nil

M.log = function() end   -- (set by the caller: M.log = function(s) ... end)

------------------------------------------------------------
-- Small helpers
------------------------------------------------------------
local function unurl(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
local function unxml(s)
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&#(%d+);", function(n) return utf8.char(tonumber(n)) end):gsub("&amp;", "&"))
end
local function attr(tag, name)
  local v = tag:match("%s" .. name .. '="([^"]*)"')
  return v and unxml(v) or nil
end
local function read(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end
local function write(path, data)
  local f = io.open(path, "wb"); if not f then return false end
  f:write(data); f:close(); return true
end
-- A file: link ReaPack accepts (only the characters it allows: spaces and others as %xx)
local function file_url(path)
  local p = path:gsub("\\", "/")
  if not p:match("^/") then p = "/" .. p end   -- (Windows: /C:/...)
  return "file://" .. p:gsub("[^%w%-%._~/:]", function(c) return string.format("%%%02x", c:byte()) end)   -- (lowercase: ReaPack only accepts that)
end
-- The two ways GitHub links can be written for the same index count as the same repository
local function same_url(a, b)
  local function norm(u)
    u = u:lower():gsub("^https?://", ""):gsub("/+$", "")
    local o, r, br, rest = u:match("^github%.com/([^/]+)/([^/]+)/raw/([^/]+)/(.+)$")
    if o then return o .. "/" .. r .. "/" .. br .. "/" .. rest end
    o, r, rest = u:match("^raw%.githubusercontent%.com/([^/]+)/([^/]+)/(.+)$")
    if o then return o .. "/" .. r .. "/" .. rest:gsub("^refs/heads/", "") end
    return u
  end
  return norm(a) == norm(b)
end

------------------------------------------------------------
-- Platforms (as ReaPack names them)
------------------------------------------------------------
local function this_platform()
  local v = reaper.GetAppVersion():lower()
  local os_ = reaper.GetOS()
  if os_:match("^OSX") or os_:match("^macOS") then
    if v:match("arm64") or os_:match("arm64") then return "darwin-arm64", "darwin" end
    return (os_ == "OSX32") and "darwin32" or "darwin64", "darwin"
  elseif os_:match("^Win") then
    if v:match("arm64ec") then return "windows-arm64ec", "windows" end
    return (os_ == "Win32") and "win32" or "win64", "windows"
  else
    if v:match("aarch64") then return "linux-aarch64", "linux" end
    if v:match("armv7") then return "linux-armv7l", "linux" end
    if v:match("i686") then return "linux32", "linux" end
    return "linux64", "linux"
  end
end
M.PLATFORM, M.FAMILY = this_platform()
local function platform_ok(p)
  return p == nil or p == "" or p == "all" or p == M.PLATFORM or p == M.FAMILY
end

------------------------------------------------------------
-- Versions (as ReaPack compares them: numbers and letters in turn; letters = a pre-release)
------------------------------------------------------------
local function vparts(v)
  local t = {}
  for num, word in v:gmatch("(%d*)([^%d]*)") do
    if num ~= "" then t[#t + 1] = tonumber(num) end
    local w = word:gsub("[%.%-_%s]", "")
    if w ~= "" then t[#t + 1] = w:lower() end
  end
  return t
end
local function prerelease(v) return v:match("%a") ~= nil end
local function vcmp(a, b)
  if reaper.ReaPack_CompareVersions then
    local r = reaper.ReaPack_CompareVersions(a, b, "")
    if type(r) == "number" then return r end
  end
  local pa, pb = vparts(a), vparts(b)
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i], pb[i]
    if x == nil then return (type(y) == "string") and 1 or -1 end
    if y == nil then return (type(x) == "string") and -1 or 1 end
    if type(x) ~= type(y) then return (type(x) == "number") and 1 or -1 end
    if x ~= y then return (x < y) and -1 or 1 end
  end
  return 0
end

------------------------------------------------------------
-- Index files
------------------------------------------------------------
-- { name, categories = { { name, open = '<category ...>', pkgs = { { name, type, xml, versions = {...} } } } } }
function M.parse_index(text)
  local idx = { name = attr(text:match("<index[^>]*>") or "", "name"), categories = {} }
  for ctag, cbody in text:gmatch("(<category[^>]*>)(.-)</category>") do
    local cat = { name = attr(ctag, "name") or "", open = ctag, pkgs = {} }
    for ptag, pbody in cbody:gmatch("(<reapack[^>]*>)(.-)</reapack>") do
      local pkg = { name = attr(ptag, "name") or "", type = attr(ptag, "type") or "", xml = ptag .. pbody .. "</reapack>", versions = {} }
      for vtag, vbody in pbody:gmatch("(<version[^>]*>)(.-)</version>") do
        local ver = { name = attr(vtag, "name") or "0", sources = {} }
        for stag in vbody:gmatch("<source[^>]*>") do
          ver.sources[#ver.sources + 1] = { platform = attr(stag, "platform"), type = attr(stag, "type"),
                                            file = attr(stag, "file"), main = attr(stag, "main") }
        end
        pkg.versions[#pkg.versions + 1] = ver
      end
      cat.pkgs[#cat.pkgs + 1] = pkg
    end
    idx.categories[#idx.categories + 1] = cat
  end
  return idx
end

-- The version ReaPack would install (newest, not a pre-release unless there are only those)
function M.latest(pkg)
  local best, best_pre
  for _, v in ipairs(pkg.versions) do
    if prerelease(v.name) then
      if not best_pre or vcmp(v.name, best_pre.name) > 0 then best_pre = v end
    elseif not best or vcmp(v.name, best.name) > 0 then best = v end
  end
  return best or best_pre
end

local DIRS = { script = "Scripts", effect = "Effects", data = "Data", extension = "UserPlugins", theme = "ColorThemes",
               langpack = "LangPack", webinterface = "reaper_www_root", projecttpl = "ProjectTemplates",
               tracktpl = "TrackTemplates", midinotenames = "MIDINoteNames", autoitem = "AutomationItems", keymap = "KeyMaps" }
local NESTED = { script = true, effect = true, autoitem = true, keymap = true }

-- Where ReaPack puts a source's file (relative to REAPER's resource folder), as ReaPack does it
function M.target(remote, category, pkg, src)
  local t = (src.type and src.type ~= "") and src.type or pkg.type
  local dir = DIRS[t]
  if not dir then return nil end
  local file = (src.file and src.file ~= "") and src.file or pkg.name
  if not NESTED[t] then return dir .. "/" .. file end
  -- (kept as ReaPack records it, ".." and all: "Scripts/ReaTeam Extensions/Extensions/../API/sws.py")
  return dir .. "/" .. remote .. "/" .. category .. "/" .. file
end

-- The files a package's version puts on this platform
function M.files(remote, category, pkg, ver)
  local out = {}
  for _, s in ipairs(ver and ver.sources or {}) do
    if platform_ok(s.platform) then
      local p = M.target(remote, category, pkg, s)
      if p then out[#out + 1] = p end
    end
  end
  return out
end

local function exists(rel) return reaper.file_exists(RES .. "/" .. rel) end

-- Does ReaPack record this file as belonging to this repository's package?
local function owned_by(rel, remote, package)
  local e = reaper.ReaPack_GetOwner(RES .. "/" .. rel, "")
  if not e then return false end
  local ok, repo, _, pkg = reaper.ReaPack_GetEntryInfo(e)
  reaper.ReaPack_FreeEntry(e)
  return ok and repo == remote and pkg == package
end

-- Is this package installed from this repository? (any version's files, so an older install
-- counts too; a file that's there but belongs to something else doesn't)
local function installed(remote, category, pkg)
  for _, v in ipairs(pkg.versions) do
    for _, p in ipairs(M.files(remote, category, pkg, v)) do
      if exists(p) and owned_by(p, remote, pkg.name) then return true end
    end
  end
  return false
end
-- A file of this package that another ReaPack package owns (installing it would be a conflict)
local function owned_elsewhere(remote, category, pkg)
  for _, p in ipairs(M.files(remote, category, pkg, M.latest(pkg))) do
    if exists(p) then
      local e = reaper.ReaPack_GetOwner(RES .. "/" .. p, "")
      if e then
        local ok, repo, _, name = reaper.ReaPack_GetEntryInfo(e)
        reaper.ReaPack_FreeEntry(e)
        if ok and not (repo == remote and name == pkg.name) then return repo .. " / " .. tostring(name) end
      end
    end
  end
end

------------------------------------------------------------
-- Repositories (ReaPack's settings)
------------------------------------------------------------
-- The name the user's ReaPack already uses for this index (nil: not added)
local function remote_named_for(url)
  local ini = read(RES .. "/reapack.ini") or ""
  local list = ini:match("%[remotes%](.-)\n%[") or ini:match("%[remotes%](.*)$") or ""
  for line in list:gmatch("[^\r\n]+") do
    local name, u = line:match("^remote%d+=([^|]+)|([^|]+)|")
    if name and same_url(u, url) and reaper.ReaPack_GetRepositoryInfo(name) then return name end
  end
end

local function repo_info(name)
  local ok, url, enabled, auto = reaper.ReaPack_GetRepositoryInfo(name)
  if not ok then return nil end
  return { url = url, enabled = enabled, auto = auto }
end

local download   -- (below)

-- Repositories still pointing at a trimmed copy: put them back. real: { [name] = the real index's
-- text } when it's at hand (otherwise it's downloaded; if that fails, ReaPack's cache keeps the
-- trimmed copy until ReaPack next downloads the index: it still works, the browser just shows
-- fewer of that repository's packages until then)
function M.repair(real)
  local rec = reaper.GetExtState(SEC, PENDING)
  if rec == "" or not reaper.ReaPack_AddSetRepository then return end
  for line in rec:gmatch("[^\n]+") do
    local name, url, enabled, auto = line:match("^(.-)\t(.-)\t(%d)\t(%d)$")
    if name then
      local text = real and real[name] or download(url, WORK .. "/real (repair).xml")
      if text then write(RES .. "/ReaPack/Cache/" .. name .. ".xml", text) end
      -- (two steps, so ReaPack never starts synchronizing here, even with "install new
      -- packages" on everywhere: the address with install-new off, then its own setting)
      reaper.ReaPack_AddSetRepository(name, url, enabled == "1", 0, "")
      reaper.ReaPack_AddSetRepository(name, url, enabled == "1", tonumber(auto), "")
      M.log("put back " .. name .. " (" .. url .. ")")
    end
  end
  reaper.DeleteExtState(SEC, PENDING, true)
  -- (no ReaPack_ProcessQueue here: calling it while ReaPack is still winding down an install
  -- crashes REAPER. The change is in effect at once; ReaPack saves its settings when REAPER quits)
end

------------------------------------------------------------
-- Downloading the real indexes (curl)
------------------------------------------------------------
local CURL = IS_WIN and "curl.exe" or (reaper.file_exists("/usr/bin/curl") and "/usr/bin/curl" or "curl")
local function q(s) return IS_WIN and ('"' .. s .. '"') or ("'" .. s:gsub("'", "'\\''") .. "'") end
function download(url, path)
  os.remove(path)
  reaper.ExecProcess(CURL .. " -sfL -m 90 -o " .. q(path) .. " " .. (IS_WIN and ('"' .. url .. '"') or url), 100000)
  local d = read(path)
  return d and d:find("<index", 1, true) and d or nil
end

------------------------------------------------------------
-- What's missing
------------------------------------------------------------
-- An extension's file in UserPlugins (by the start of its name), e.g. one installed by its own installer
function M.quick_has_file(prefix)
  if not prefix then return false end
  local i = 0
  while true do
    local f = reaper.EnumerateFiles(RES .. "/UserPlugins", i)
    if not f then return false end
    if f:sub(1, #prefix) == prefix then return true end
    i = i + 1
  end
end
-- Groups the list by index; quick = true: only the quick test (no internet), for "is anything missing?"
local function groups(list)
  local by, order = {}, {}
  for _, d in ipairs(list) do
    local index_url, path = d.url:match("^(.-)#p=(.+)$")
    local category, package = unurl(path):match("^(.*)/([^/]+)$")
    if not by[index_url] then by[index_url] = { url = index_url, deps = {} }; order[#order + 1] = by[index_url] end
    table.insert(by[index_url].deps, { category = category, package = package, quick = d.quick, quick_file = d.quick_file })
  end
  return order
end

-- Without the internet: extensions by their API, scripts by their file where ReaPack would put
-- them (under the repository's usual name). Returns the list of entries that look missing.
function M.quick_missing(list)
  list = list or M.LIST
  local out = {}
  for _, d in ipairs(list) do
    local index_url, path = d.url:match("^(.-)#p=(.+)$")
    local category, package = unurl(path):match("^(.*)/([^/]+)$")
    local present
    -- (an extension: loaded, or its file is there and loads at the next start)
    if d.quick and reaper.APIExists(d.quick) then present = true
    elseif d.quick_file then present = M.quick_has_file(d.quick_file)
    else
      local remote = remote_named_for(index_url)
      present = remote and exists("Scripts/" .. remote .. "/" .. category .. "/" .. (d.quick_script or package)) or false
    end
    if not present then out[#out + 1] = d end
  end
  return out
end

-- A list entry's package name, for people ("TJF Toggle Item Lock (matches first item)")
function M.name_of(d)
  local name = unurl(d.url:match("#p=.*/([^/]+)$") or d.url)
  return (name:gsub("%.ext$", ""):gsub("%.lua$", ""):gsub("%.eel$", ""):gsub("^reaper%-oss_", ""))
end

-- Is ReaPack still busy (its progress or report window open)? Needs js_ReaScriptAPI: nil
-- without it. ReaPack must have completely finished before anything calls it again.
function M.reapack_busy()
  if not reaper.JS_Window_ListFind then return nil end
  for _, word in ipairs({ "ReaPack", "report", "Report", "Transaction", "transaction" }) do
    local _, l = reaper.JS_Window_ListFind(word, false)
    for addr in ((l or "") .. ","):gmatch("(.-),") do
      local h = addr ~= "" and reaper.JS_Window_HandleFromAddress(addr)
      local title = h and reaper.JS_Window_GetTitle(h) or ""
      if h and reaper.JS_Window_IsVisible(h) and not title:find("Manage repositories") and
          (title:find("ReaPack") or title:lower():find("report") or title:lower():find("transaction")) then
        return true
      end
    end
  end
  return false
end

------------------------------------------------------------
-- Installing
------------------------------------------------------------
-- opts.on_done(report): report.installed, report.failed, report.already (lists of package names),
-- report.error (a sentence, or nil)
-- opts.extra: { { name =, url = }, ... } repositories added (or kept) with "install new packages"
--   on, synchronized in the same ReaPack run (the ReaTooled repository, from the package)
-- opts.wait: files (relative to REAPER's folder) to wait for until ReaPack records them, with
--   opts.wait_ok(rel) -> true when it's the one wanted (default: owned by any package)
-- opts.timeout: seconds to wait (default WAIT)
-- opts.list: what to install (default M.LIST)
function M.install(opts)
  opts = opts or {}
  local report = { installed = {}, failed = {}, already = {} }
  local function done(err)
    report.error = err
    if opts.on_done then opts.on_done(report) end
  end
  if not (reaper.ReaPack_AddSetRepository and reaper.ReaPack_GetOwner and reaper.ReaPack_GetRepositoryInfo) then
    return done("ReaPack isn't installed.")
  end
  M.repair()
  reaper.RecursiveCreateDirectory(WORK, 0)

  local plan, pending = {}, {}
  for gi, g in ipairs(groups(opts.list or M.LIST)) do
    local text = download(g.url, WORK .. "/real " .. gi .. ".xml")
    if not text then
      M.log("couldn't download " .. g.url)
      for _, d in ipairs(g.deps) do report.failed[#report.failed + 1] = d.package end
    else
      local idx = M.parse_index(text)
      g.text = text
      local remote = remote_named_for(g.url) or idx.name or ("ReaTooled dependency " .. gi)
      local want, missing = {}, {}
      for _, d in ipairs(g.deps) do want[d.category .. "\0" .. d.package] = d end
      local keep = {}   -- category name -> list of package xml
      for _, cat in ipairs(idx.categories) do
        for _, pkg in ipairs(cat.pkgs) do
          local d = want[cat.name .. "\0" .. pkg.name]
          local here = installed(remote, cat.name, pkg)
          if d then
            d.found = true
            local files = M.files(remote, cat.name, pkg, M.latest(pkg))
            if #files == 0 then
              M.log(pkg.name .. ": nothing for this platform (" .. M.PLATFORM .. ")")
            elseif here then
              report.already[#report.already + 1] = pkg.name
            elseif owned_elsewhere(remote, cat.name, pkg) then
              M.log(pkg.name .. ": installed from another repository (" .. owned_elsewhere(remote, cat.name, pkg) .. "), left as it is")
              report.already[#report.already + 1] = pkg.name
            else
              missing[#missing + 1] = { package = pkg.name, file = files[1] }
            end
          end
          -- (wanted, or installed already: in the trimmed copy, so nothing installed looks obsolete)
          if d or here then
            keep[cat.name] = keep[cat.name] or { open = cat.open, list = {} }
            table.insert(keep[cat.name].list, pkg.xml)
          end
        end
      end
      for _, d in ipairs(g.deps) do
        if not d.found then M.log("not in its index any more: " .. d.category .. "/" .. d.package); report.failed[#report.failed + 1] = d.package end
      end
      if #missing > 0 then
        local out = { '<?xml version="1.0" encoding="utf-8"?>', '<index version="1" name="' .. (idx.name or remote):gsub("&", "&amp;"):gsub('"', "&quot;") .. '">' }
        for _, k in pairs(keep) do
          out[#out + 1] = "  " .. k.open
          for _, x in ipairs(k.list) do out[#out + 1] = "    " .. x end
          out[#out + 1] = "  </category>"
        end
        out[#out + 1] = "</index>"
        local path = WORK .. "/" .. remote:gsub('[\\/:*?"<>|]', "_") .. ".xml"
        write(path, table.concat(out, "\n"))
        local before = repo_info(remote)
        plan[#plan + 1] = { remote = remote, url = g.url, before = before, local_url = file_url(path), missing = missing, real = text }
        -- (put back: its own address and settings; a repository added here installs nothing new by itself)
        pending[#pending + 1] = table.concat({ remote, before and before.url or g.url,
          (before == nil or before.enabled) and "1" or "0", tostring(before and before.auto or 0) }, "\t")
        M.log(remote .. ": " .. #missing .. " to install")
      end
    end
  end
  if #plan == 0 and not (opts.extra and #opts.extra > 0) then
    return done(#report.failed > 0 and "Some couldn't be checked (no internet?)." or nil)
  end

  -- Point each repository at its trimmed copy, install-new on: ReaPack synchronizes just those
  reaper.SetExtState(SEC, PENDING, table.concat(pending, "\n"), true)
  for _, x in ipairs(opts.extra or {}) do
    local ok, err = reaper.ReaPack_AddSetRepository(x.name, x.url, true, 1, "")
    M.log((ok and "added " or "ReaPack refused ") .. x.name .. (ok and "" or (": " .. tostring(err))))
  end
  for _, p in ipairs(plan) do
    local ok, err = reaper.ReaPack_AddSetRepository(p.remote, p.local_url, true, 1, "")
    if not ok then M.log("ReaPack refused " .. p.remote .. ": " .. tostring(err)) end
  end
  reaper.ReaPack_ProcessQueue(true)

  -- Wait until ReaPack has recorded every new file (or gives up), then a moment for it to finish
  local t0, settled = reaper.time_precise(), nil
  local function owned(rel)
    local e = reaper.ReaPack_GetOwner(RES .. "/" .. rel, "")
    if e then reaper.ReaPack_FreeEntry(e); return true end
    return false
  end
  local limit = opts.timeout or WAIT
  local waits = {}
  for _, rel in ipairs(opts.wait or {}) do waits[#waits + 1] = { rel = rel } end
  local function wait()
    local all = true
    for _, w in ipairs(waits) do
      if not w.done then
        w.done = (opts.wait_ok and opts.wait_ok(w.rel)) or (not opts.wait_ok and owned(w.rel))
        if not w.done then all = false end
      end
    end
    for _, p in ipairs(plan) do
      for _, m in ipairs(p.missing) do
        if not m.done then
          m.done = owned(m.file)
          if not m.done then all = false end
        end
      end
    end
    if not all and reaper.time_precise() - t0 < limit then reaper.defer(wait); return end
    settled = settled or reaper.time_precise()
    if reaper.time_precise() - settled < SETTLE then reaper.defer(wait); return end
    for _, p in ipairs(plan) do
      for _, m in ipairs(p.missing) do
        if m.done then report.installed[#report.installed + 1] = m.package else report.failed[#report.failed + 1] = m.package end
      end
    end
    for _, w in ipairs(waits) do
      if not w.done then report.failed[#report.failed + 1] = w.rel; M.log("never arrived: " .. w.rel) end
    end
    local real = {}
    for _, p in ipairs(plan) do real[p.remote] = p.real end
    M.repair(real)   -- (every repository back to its real address and settings)
    done(#report.failed > 0 and "Some couldn't be installed." or nil)
  end
  reaper.defer(wait)
end

return M
