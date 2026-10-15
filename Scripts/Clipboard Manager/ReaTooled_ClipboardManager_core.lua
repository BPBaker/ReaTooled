--[[
  ReaTooled_ClipboardManager_core.lua
  Shared library for the ReaTooled Clipboard Manager.

  Not a standalone action -- loaded by:
    ReaTooled_Clipboard Manager.lua
    ReaTooled_Clipboard Manager - Copy and capture.lua
    ReaTooled_Clipboard Manager - Capture selection.lua

  Author: ReaTooled
  Licence: MIT
]]--

local CM = {}

CM.EXT           = 'ReaTooled_ClipboardManager'
CM.FORMAT        = 1
CM.PIECE_LEN     = 4000   -- max chars per project ExtState value
CM.MAX_COLORS    = 6      -- swatches shown per entry
CM.CMD_COPY_ITEMS = 40698 -- Edit: Copy items

--=============================================================================
-- Encoding
--
-- State chunks are multiline and may contain quote characters, both of which
-- are hazardous inside an .RPP key/value line. Percent-escape the dangerous
-- set before storage; the transform is exact and reversible.
--=============================================================================

local ESCAPE_MAP = {
  ['%']  = '%25',
  ['\n'] = '%0A',
  ['\r'] = '%0D',
  ['"']  = '%22',
  ["'"]  = '%27',
  ['`']  = '%60',
  [' ']  = '%20',
}

local function encode(s)
  return (s:gsub('[%%\n\r"\'` ]', ESCAPE_MAP))
end

local function decode(s)
  return (s:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

--=============================================================================
-- Serialisation
--
-- Structural lines are prefixed '@@'. Raw state chunks are always indented or
-- angle-bracketed by REAPER, so a bare '@@ENDCHUNK' line cannot occur inside
-- one -- the sentinel is unambiguous.
--=============================================================================

local function serialize(entry)
  local out = {}
  local function put(s) out[#out + 1] = s end

  put('@@V ' .. CM.FORMAT)
  put('@@F type ' .. (entry.type or 'items'))
  put('@@F name ' .. (entry.name or ''):gsub('[\r\n]', ' '))
  put('@@F captured_at ' .. tostring(entry.captured_at or 0))
  put('@@F span ' .. string.format('%.10f', entry.display.span or 0))

  for _, n in ipairs(entry.display.track_names or {}) do
    put('@@TRACK ' .. n:gsub('[\r\n]', ' '))
  end
  for _, c in ipairs(entry.display.colors or {}) do
    put('@@COLOR ' .. tostring(c))
  end

  for _, it in ipairs(entry.items or {}) do
    put('@@ITEM')
    put('@@F track_guid ' .. (it.track_guid or ''))
    put('@@F track_index ' .. tostring(it.track_index or -1))
    put('@@F position ' .. string.format('%.10f', it.position or 0))
    put('@@F length ' .. string.format('%.10f', it.length or 0))
    put('@@CHUNK')
    put(it.chunk or '')
    put('@@ENDCHUNK')
  end

  return table.concat(out, '\n')
end

local function deserialize(blob)
  local entry = {
    type        = 'items',
    name        = '',
    captured_at = 0,
    items       = {},
    display     = { track_names = {}, colors = {}, span = 0, count = 0 },
  }

  local cur, chunk_lines, in_chunk = nil, nil, false

  for line in (blob .. '\n'):gmatch('(.-)\n') do
    if in_chunk then
      if line == '@@ENDCHUNK' then
        cur.chunk = table.concat(chunk_lines, '\n')
        in_chunk, chunk_lines = false, nil
      else
        chunk_lines[#chunk_lines + 1] = line
      end

    elseif line == '@@ITEM' then
      cur = {}
      entry.items[#entry.items + 1] = cur

    elseif line == '@@CHUNK' then
      in_chunk, chunk_lines = true, {}

    elseif line:sub(1, 8) == '@@TRACK ' then
      local t = entry.display.track_names
      t[#t + 1] = line:sub(9)

    elseif line:sub(1, 8) == '@@COLOR ' then
      local t = entry.display.colors
      t[#t + 1] = tonumber(line:sub(9)) or 0

    elseif line:sub(1, 4) == '@@F ' then
      local key, val = line:sub(5):match('^(%S+) ?(.*)$')
      if key then
        if cur and (key == 'track_guid' or key == 'track_index'
                    or key == 'position' or key == 'length') then
          cur[key] = tonumber(val) or val
        elseif key == 'type' or key == 'name' then
          entry[key] = val
        elseif key == 'captured_at' then
          entry.captured_at = tonumber(val) or 0
        elseif key == 'span' then
          entry.display.span = tonumber(val) or 0
        end
      end
    end
  end

  entry.display.count = #entry.items
  return entry
end

CM.serialize   = serialize
CM.deserialize = deserialize
CM._encode     = encode
CM._decode     = decode

--=============================================================================
-- Storage (project ExtState, chunked)
--=============================================================================

local function get(key)
  local _, val = reaper.GetProjExtState(0, CM.EXT, key)
  return val or ''
end

local function set(key, val)
  reaper.SetProjExtState(0, CM.EXT, key, val or '')
end

function CM.get_rev()
  return tonumber(get('rev')) or 0
end

local function bump_rev()
  set('rev', tostring(CM.get_rev() + 1))
end

local function read_index()
  local ids, seen = {}, {}
  for id in get('index'):gmatch('[^,]+') do
    if not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  return ids
end

local function write_index(ids)
  set('index', table.concat(ids, ','))
end

CM.read_index = read_index

local function store_blob(id, blob)
  local encoded = encode(blob)
  local n = 0
  local pos = 1
  while pos <= #encoded do
    local stop = math.min(pos + CM.PIECE_LEN - 1, #encoded)
    -- '%' only ever begins a 3-char escape, so back off if the boundary
    -- would land inside one.
    if stop < #encoded then
      if encoded:sub(stop, stop) == '%' then
        stop = stop - 1
      elseif encoded:sub(stop - 1, stop - 1) == '%' then
        stop = stop - 2
      end
    end
    n = n + 1
    set('e_' .. id .. '_' .. n, encoded:sub(pos, stop))
    pos = stop + 1
  end
  set('e_' .. id .. '_n', tostring(n))
end

local function load_blob(id)
  local n = tonumber(get('e_' .. id .. '_n')) or 0
  if n == 0 then return nil end
  local parts = {}
  for i = 1, n do
    parts[#parts + 1] = get('e_' .. id .. '_' .. i)
  end
  return decode(table.concat(parts))
end

local function clear_blob(id)
  local n = tonumber(get('e_' .. id .. '_n')) or 0
  for i = 1, n do set('e_' .. id .. '_' .. i, '') end
  set('e_' .. id .. '_n', '')
end

--- Save a new entry (prepended) or overwrite an existing one.
function CM.save(entry)
  if not entry.id then
    entry.id = string.format('%d_%d', os.time(), math.random(1000, 9999))
    local ids = read_index()
    table.insert(ids, 1, entry.id)
    write_index(ids)
  else
    clear_blob(entry.id)
  end
  store_blob(entry.id, serialize(entry))
  bump_rev()
  reaper.MarkProjectDirty(0)
  return entry.id
end

function CM.delete(id)
  clear_blob(id)
  local ids, keep = read_index(), {}
  for _, v in ipairs(ids) do
    if v ~= id then keep[#keep + 1] = v end
  end
  write_index(keep)
  bump_rev()
  reaper.MarkProjectDirty(0)
end

function CM.delete_all()
  for _, id in ipairs(read_index()) do clear_blob(id) end
  write_index({})
  bump_rev()
  reaper.MarkProjectDirty(0)
end

function CM.set_order(ids)
  write_index(ids)
  bump_rev()
  reaper.MarkProjectDirty(0)
end

function CM.load(id)
  local blob = load_blob(id)
  if not blob then return nil end
  local entry = deserialize(blob)
  entry.id = id
  return entry
end

--- All entries in stored order (newest first, unless reordered).
function CM.load_all()
  local list = {}
  for _, id in ipairs(read_index()) do
    local e = CM.load(id)
    if e then list[#list + 1] = e end
  end
  return list
end

--=============================================================================
-- Capture
--=============================================================================

local function native_to_rgb(native)
  local r, g, b = reaper.ColorFromNative(native)
  return r * 65536 + g * 256 + b
end

--- Snapshot the current item selection. Returns an entry, or nil + reason.
function CM.capture_items()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return nil, 'No items selected.' end

  local entry = {
    type        = 'items',
    captured_at = os.time(),
    items       = {},
    display     = { track_names = {}, colors = {}, span = 0, count = n },
  }

  local seen_track, seen_color = {}, {}
  local min_pos, max_end = math.huge, -math.huge
  local first_name

  for i = 0, n - 1 do
    local item  = reaper.GetSelectedMediaItem(0, i)
    local track = reaper.GetMediaItem_Track(item)
    local ok, chunk = reaper.GetItemStateChunk(item, '', false)
    if ok then
      local pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
      local len = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')

      entry.items[#entry.items + 1] = {
        chunk       = chunk,
        track_guid  = reaper.GetTrackGUID(track),
        track_index = math.floor(
          reaper.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER')) - 1,
        position    = pos,
        length      = len,
      }

      if pos < min_pos then min_pos = pos end
      if pos + len > max_end then max_end = pos + len end

      local _, tname = reaper.GetTrackName(track)
      if tname and tname ~= '' and not seen_track[tname] then
        seen_track[tname] = true
        entry.display.track_names[#entry.display.track_names + 1] = tname
      end

      local take = reaper.GetActiveTake(item)
      local native = take
        and reaper.GetDisplayedMediaItemColor2(item, take)
        or  reaper.GetDisplayedMediaItemColor(item)
      local rgb = native_to_rgb(native)
      if not seen_color[rgb] and #entry.display.colors < CM.MAX_COLORS then
        seen_color[rgb] = true
        entry.display.colors[#entry.display.colors + 1] = rgb
      end

      if not first_name then
        if take then
          local tn = reaper.GetTakeName(take)
          if tn and tn ~= '' then first_name = tn end
        end
        if not first_name and tname and tname ~= '' then first_name = tname end
      end
    end
  end

  if #entry.items == 0 then return nil, 'Could not read item state.' end

  entry.display.span = (max_end > min_pos) and (max_end - min_pos) or 0
  entry.display.count = #entry.items

  first_name = first_name or 'Items'
  entry.name = (#entry.items > 1)
    and string.format('%s +%d', first_name, #entry.items - 1)
    or  first_name

  return entry
end

--=============================================================================
-- Recall
--=============================================================================

--- Give every item/take in a chunk a fresh GUID so restored temporaries can
--- never collide with items still living in the project.
local function refresh_guids(chunk)
  chunk = '\n' .. chunk
  chunk = chunk:gsub('(\n%s*I?GUID )%{[^}\n]*%}', function(prefix)
    return prefix .. reaper.genGuid('')
  end)
  chunk = chunk:gsub('\n%s*IID %d+', '')
  return chunk:sub(2)
end

CM._refresh_guids = refresh_guids

local function track_by_guid(guid)
  if not guid or guid == '' then return nil end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(tr) == guid then return tr end
  end
  return nil
end

local function save_razor()
  local saved = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, s = reaper.GetSetMediaTrackInfo_String(tr, 'P_RAZOREDITS', '', false)
    saved[#saved + 1] = { tr, s or '' }
  end
  return saved
end

local function apply_razor(saved, clear)
  for _, pair in ipairs(saved) do
    reaper.GetSetMediaTrackInfo_String(
      pair[1], 'P_RAZOREDITS', clear and '' or pair[2], true)
  end
end

--- Rebuild a stored set as temporary items, hand them to REAPER's native copy
--- action, then remove them and put the project back exactly as it was.
--- Returns ok, message.
function CM.recall(entry)
  if not entry or #(entry.items or {}) == 0 then
    return false, 'Entry is empty.'
  end

  -- Preserve everything the operation could disturb.
  local saved_items = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    saved_items[#saved_items + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  local saved_tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    saved_tracks[#saved_tracks + 1] = reaper.GetSelectedTrack(0, i)
  end
  local saved_cursor = reaper.GetCursorPosition()
  local saved_razor  = save_razor()

  reaper.PreventUIRefresh(1)

  -- An active razor selection would hijack the copy action.
  apply_razor(saved_razor, true)
  reaper.SelectAllMediaItems(0, false)

  local temp_items, temp_tracks, degraded = {}, {}, false

  for _, it in ipairs(entry.items) do
    local track = track_by_guid(it.track_guid)

    if not track then
      local idx = tonumber(it.track_index) or -1
      if idx >= 0 and idx < reaper.CountTracks(0) then
        track = reaper.GetTrack(0, idx)
      end
      degraded = true
    end

    if not track then
      local n = reaper.CountTracks(0)
      reaper.InsertTrackAtIndex(n, false)
      track = reaper.GetTrack(0, n)
      temp_tracks[#temp_tracks + 1] = track
      degraded = true
    end

    local new_item = reaper.AddMediaItemToTrack(track)
    if new_item then
      reaper.SetItemStateChunk(new_item, refresh_guids(it.chunk), false)
      reaper.SetMediaItemSelected(new_item, true)
      temp_items[#temp_items + 1] = { new_item, track }
    end
  end

  local ok = #temp_items > 0
  if ok then
    reaper.Main_OnCommand(CM.CMD_COPY_ITEMS, 0)
  end

  for _, pair in ipairs(temp_items) do
    reaper.DeleteTrackMediaItem(pair[2], pair[1])
  end
  for i = #temp_tracks, 1, -1 do
    reaper.DeleteTrack(temp_tracks[i])
  end

  -- Restore.
  reaper.SelectAllMediaItems(0, false)
  for _, item in ipairs(saved_items) do
    reaper.SetMediaItemSelected(item, true)
  end
  for i = 0, reaper.CountTracks(0) - 1 do
    reaper.SetTrackSelected(reaper.GetTrack(0, i), false)
  end
  for _, tr in ipairs(saved_tracks) do
    reaper.SetTrackSelected(tr, true)
  end
  reaper.SetEditCurPos(saved_cursor, false, false)
  apply_razor(saved_razor, false)

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()

  if not ok then return false, 'Nothing could be restored.' end
  if degraded then
    return true, 'Copied, but some source tracks were missing.'
  end
  return true, string.format('Copied %d item%s to clipboard.',
    #temp_items, #temp_items == 1 and '' or 's')
end

--=============================================================================
-- Misc
--=============================================================================

function CM.relative_time(ts)
  local d = os.time() - (ts or 0)
  if d < 10   then return 'just now' end
  if d < 60   then return string.format('%ds ago', d) end
  if d < 3600 then return string.format('%dm ago', math.floor(d / 60)) end
  if d < 86400 then return string.format('%dh ago', math.floor(d / 3600)) end
  if d < 604800 then return string.format('%dd ago', math.floor(d / 86400)) end
  return os.date('%d %b', ts)
end

function CM.format_span(sec)
  sec = sec or 0
  if sec <= 0 then return '-' end
  if sec < 60 then return string.format('%.2fs', sec) end
  return string.format('%d:%05.2f', math.floor(sec / 60), sec % 60)
end

return CM
