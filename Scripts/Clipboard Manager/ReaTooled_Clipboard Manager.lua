--[[
  ReaTooled_Clipboard Manager.lua

  A panel of saved clipboard states. Capture a set of copied items, keep
  working, then click an older entry to load it back into REAPER's live
  clipboard and Ctrl+V as normal.

  Requires: ReaImGui (install via ReaPack)
  Companion scripts, same folder:
    ReaTooled_ClipboardManager_core.lua              (required library)
    ReaTooled_Clipboard Manager - Copy and capture.lua
    ReaTooled_Clipboard Manager - Capture selection.lua

  Author: ReaTooled
  Licence: MIT
]]--

--=============================================================================
-- Dependencies
--=============================================================================

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB(
    'ReaImGui is required.\n\n' ..
    'Install it with:  Extensions > ReaPack > Browse packages,\n' ..
    'then search for "ReaImGui: ReaScript binding for Dear ImGui".',
    'Clipboard Manager', 0)
  return
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

local sep = package.config:sub(1, 1)
local script_dir = ({reaper.get_action_context()})[2]:match('^(.*' .. sep .. ')')
package.path = script_dir .. '?.lua;' .. package.path

local lib_ok, CM = pcall(require, 'ReaTooled_ClipboardManager_core')
if not lib_ok then
  reaper.MB('Could not load ReaTooled_ClipboardManager_core.lua.\n\n' ..
            'It must sit in the same folder as this script.',
            'Clipboard Manager', 0)
  return
end

--=============================================================================
-- State
--=============================================================================

local ctx  = ImGui.CreateContext('ReaTooled Clipboard Manager',
                                 ImGui.ConfigFlags_DockingEnable)
local font = ImGui.CreateFont('sans-serif', 13)
ImGui.Attach(ctx, font)

local entries       = {}
local last_rev      = -1
local last_proj     = nil
local filter        = ''
local status_text   = ''
local status_time   = 0
local rename_id     = nil
local rename_buf    = ''
local rename_focus  = false
local confirm_clear = false
local sort_col      = -1   -- -1 = manual/stored order
local sort_asc      = false

local function say(msg)
  status_text = msg or ''
  status_time = reaper.time_precise()
end

local function refresh()
  entries = CM.load_all()
end

--=============================================================================
-- Helpers
--=============================================================================

local function rgba(rgb, alpha)
  return (rgb % 0x1000000) * 256 + (alpha % 256)
end

local function join(list, max_n)
  local n = #list
  if n == 0 then return '-' end
  if n <= max_n then return table.concat(list, ', ') end
  return table.concat(list, ', ', 1, max_n) .. string.format(' +%d', n - max_n)
end

local function matches(entry, needle)
  if needle == '' then return true end
  needle = needle:lower()
  if (entry.name or ''):lower():find(needle, 1, true) then return true end
  for _, t in ipairs(entry.display.track_names or {}) do
    if t:lower():find(needle, 1, true) then return true end
  end
  return false
end

local function move_entry(id, delta)
  local ids = CM.read_index()
  for i, v in ipairs(ids) do
    if v == id then
      local j = i + delta
      if j >= 1 and j <= #ids then
        ids[i], ids[j] = ids[j], ids[i]
        CM.set_order(ids)
      end
      return
    end
  end
end

--- Re-select the items a stored entry came from, where they still exist.
local function select_source_items(entry)
  local by_guid = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    by_guid[reaper.GetTrackGUID(tr)] = tr
  end

  reaper.PreventUIRefresh(1)
  reaper.SelectAllMediaItems(0, false)
  local found = 0
  for _, it in ipairs(entry.items) do
    local tr = by_guid[it.track_guid]
    if tr then
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local item = reaper.GetTrackMediaItem(tr, i)
        local pos  = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        if math.abs(pos - (it.position or 0)) < 1e-6 then
          reaper.SetMediaItemSelected(item, true)
          found = found + 1
          break
        end
      end
    end
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  say(found > 0 and string.format('Selected %d source item%s.', found,
        found == 1 and '' or 's')
      or 'No source items still exist.')
end

local function sorted_view()
  local view = {}
  for _, e in ipairs(entries) do
    if matches(e, filter) then view[#view + 1] = e end
  end
  if sort_col < 0 then return view end

  local keyfn = {
    [1] = function(e) return (e.name or ''):lower() end,
    [2] = function(e) return e.display.count or 0 end,
    [3] = function(e) return (e.display.track_names[1] or ''):lower() end,
    [4] = function(e) return e.display.span or 0 end,
    [5] = function(e) return e.captured_at or 0 end,
  }
  local key = keyfn[sort_col]
  if not key then return view end

  table.sort(view, function(a, b)
    local ka, kb = key(a), key(b)
    if ka == kb then return (a.captured_at or 0) > (b.captured_at or 0) end
    if sort_asc then return ka < kb else return ka > kb end
  end)
  return view
end

--=============================================================================
-- Row drawing
--=============================================================================

local COL_SWATCH_W = 16

local function draw_swatch(entry)
  local colors = entry.display.colors or {}
  local x, y   = ImGui.GetCursorScreenPos(ctx)
  local h      = ImGui.GetTextLineHeight(ctx)
  local dl     = ImGui.GetWindowDrawList(ctx)
  local n      = #colors

  if n == 0 then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + COL_SWATCH_W - 4, y + h,
                                 0x50505FFF, 2)
  else
    local seg = h / n
    for i, c in ipairs(colors) do
      ImGui.DrawList_AddRectFilled(dl, x, y + (i - 1) * seg,
                                   x + COL_SWATCH_W - 4, y + i * seg,
                                   rgba(c, 0xFF))
    end
  end
  ImGui.Dummy(ctx, COL_SWATCH_W - 4, h)
end

local pending = nil  -- deferred mutation, applied after the table closes

local function draw_row(entry, row_index)
  ImGui.TableNextRow(ctx)

  local tint = (entry.display.colors or {})[1]
  if tint then
    ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg0, rgba(tint, 0x30))
  end

  -- Swatch
  ImGui.TableNextColumn(ctx)
  draw_swatch(entry)

  -- Name / recall target
  ImGui.TableNextColumn(ctx)
  if rename_id == entry.id then
    ImGui.SetNextItemWidth(ctx, -1)
    if not rename_focus then
      ImGui.SetKeyboardFocusHere(ctx)
      rename_focus = true
    end
    local changed, buf = ImGui.InputText(ctx, '##rename' .. entry.id, rename_buf,
      ImGui.InputTextFlags_EnterReturnsTrue | ImGui.InputTextFlags_AutoSelectAll)
    rename_buf = buf
    if changed then
      pending = { op = 'rename', entry = entry, name = rename_buf }
      rename_id, rename_focus = nil, false
    elseif ImGui.IsItemDeactivated(ctx) then
      rename_id, rename_focus = nil, false
    end
  else
    local label = string.format('%s##row%d', entry.name or '(unnamed)', row_index)
    if ImGui.Selectable(ctx, label, false,
                        ImGui.SelectableFlags_SpanAllColumns) then
      pending = { op = 'recall', entry = entry }
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.BeginTooltip(ctx)
      ImGui.Text(ctx, entry.name or '')
      ImGui.Separator(ctx)
      ImGui.Text(ctx, string.format('%d item%s', entry.display.count,
        entry.display.count == 1 and '' or 's'))
      ImGui.Text(ctx, 'Tracks: ' ..
        table.concat(entry.display.track_names or {}, ', '))
      ImGui.Text(ctx, 'Captured: ' ..
        os.date('%Y-%m-%d %H:%M:%S', entry.captured_at))
      ImGui.Separator(ctx)
      ImGui.Text(ctx, 'Click to load into the clipboard, then Ctrl+V.')
      ImGui.EndTooltip(ctx)
    end

    if ImGui.BeginPopupContextItem(ctx, 'ctx' .. entry.id) then
      if ImGui.MenuItem(ctx, 'Load into clipboard') then
        pending = { op = 'recall', entry = entry }
      end
      if ImGui.MenuItem(ctx, 'Paste at edit cursor') then
        pending = { op = 'paste', entry = entry }
      end
      if ImGui.MenuItem(ctx, 'Select source items') then
        pending = { op = 'select', entry = entry }
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, 'Rename') then
        rename_id, rename_buf, rename_focus = entry.id, entry.name or '', false
      end
      if ImGui.MenuItem(ctx, 'Move up') then
        pending = { op = 'move', entry = entry, delta = -1 }
      end
      if ImGui.MenuItem(ctx, 'Move down') then
        pending = { op = 'move', entry = entry, delta = 1 }
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, 'Delete') then
        pending = { op = 'delete', entry = entry }
      end
      ImGui.EndPopup(ctx)
    end
  end

  -- Count
  ImGui.TableNextColumn(ctx)
  ImGui.Text(ctx, tostring(entry.display.count or 0))

  -- Source tracks
  ImGui.TableNextColumn(ctx)
  ImGui.Text(ctx, join(entry.display.track_names or {}, 2))

  -- Span
  ImGui.TableNextColumn(ctx)
  ImGui.Text(ctx, CM.format_span(entry.display.span))

  -- Captured
  ImGui.TableNextColumn(ctx)
  ImGui.Text(ctx, CM.relative_time(entry.captured_at))
end

--=============================================================================
-- Frame
--=============================================================================

local function draw_toolbar()
  if ImGui.Button(ctx, 'Capture selection') then
    local entry, err = CM.capture_items()
    if entry then
      CM.save(entry)
      say('Captured "' .. entry.name .. '".')
    else
      say(err)
    end
  end

  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 160)
  local changed, buf = ImGui.InputTextWithHint(ctx, '##filter', 'Filter', filter)
  if changed then filter = buf end

  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Clear all') then confirm_clear = true end

  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, string.format('%d entr%s',
    #entries, #entries == 1 and 'y' or 'ies'))

  if confirm_clear then
    ImGui.OpenPopup(ctx, 'Clear all entries?')
    confirm_clear = false
  end
  if ImGui.BeginPopupModal(ctx, 'Clear all entries?', nil,
                           ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, 'Delete every saved clipboard entry in this project?')
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Delete all', 110) then
      CM.delete_all()
      refresh()
      say('Cleared.')
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Cancel', 110) then ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndPopup(ctx)
  end
end

local TABLE_FLAGS =
    ImGui.TableFlags_Resizable
  | ImGui.TableFlags_Sortable
  | ImGui.TableFlags_RowBg
  | ImGui.TableFlags_BordersInnerV
  | ImGui.TableFlags_ScrollY
  | ImGui.TableFlags_SizingStretchProp

local function draw_table()
  local view = sorted_view()

  if not ImGui.BeginTable(ctx, 'entries', 6, TABLE_FLAGS) then return end

  ImGui.TableSetupColumn(ctx, '##swatch',
    ImGui.TableColumnFlags_WidthFixed | ImGui.TableColumnFlags_NoSort,
    COL_SWATCH_W)
  ImGui.TableSetupColumn(ctx, 'Name',     ImGui.TableColumnFlags_WidthStretch, 3)
  ImGui.TableSetupColumn(ctx, '#',        ImGui.TableColumnFlags_WidthFixed, 30)
  ImGui.TableSetupColumn(ctx, 'Source',   ImGui.TableColumnFlags_WidthStretch, 2)
  ImGui.TableSetupColumn(ctx, 'Span',     ImGui.TableColumnFlags_WidthFixed, 66)
  ImGui.TableSetupColumn(ctx, 'Captured', ImGui.TableColumnFlags_WidthFixed, 78)
  ImGui.TableSetupScrollFreeze(ctx, 0, 1)
  ImGui.TableHeadersRow(ctx)

  if ImGui.TableNeedSort(ctx) then
    local ok, col_idx, _, dir = ImGui.TableGetColumnSortSpecs(ctx, 0)
    if ok then
      sort_col = col_idx
      sort_asc = (dir == ImGui.SortDirection_Ascending)
    else
      sort_col = -1
    end
    view = sorted_view()
  end

  for i, entry in ipairs(view) do
    draw_row(entry, i)
  end

  ImGui.EndTable(ctx)

  if #view == 0 then
    ImGui.Spacing(ctx)
    if #entries == 0 then
      ImGui.TextDisabled(ctx,
        'Nothing captured yet. Copy some items, then hit Capture selection')
      ImGui.TextDisabled(ctx,
        '(or bind "Copy and capture" over Ctrl+C).')
    else
      ImGui.TextDisabled(ctx, 'No entries match the filter.')
    end
  end
end

local function apply_pending()
  if not pending then return end
  local p = pending
  pending = nil

  if p.op == 'recall' then
    local ok, msg = CM.recall(p.entry)
    say(msg)

  elseif p.op == 'paste' then
    local ok, msg = CM.recall(p.entry)
    if ok then
      reaper.Undo_BeginBlock()
      reaper.Main_OnCommand(40058, 0)  -- Item: Paste items/tracks
      reaper.Undo_EndBlock('Clipboard Manager: paste "' ..
        (p.entry.name or '') .. '"', -1)
      say('Pasted.')
    else
      say(msg)
    end

  elseif p.op == 'select' then
    select_source_items(p.entry)

  elseif p.op == 'rename' then
    p.entry.name = p.name
    CM.save(p.entry)
    refresh()

  elseif p.op == 'move' then
    move_entry(p.entry.id, p.delta)
    refresh()

  elseif p.op == 'delete' then
    CM.delete(p.entry.id)
    refresh()
    say('Deleted.')
  end
end

local function loop()
  -- Reload when the store changes, or when the active project changes.
  local proj = reaper.EnumProjects(-1, '')
  local rev  = CM.get_rev()
  if proj ~= last_proj or rev ~= last_rev then
    last_proj, last_rev = proj, rev
    refresh()
  end

  ImGui.PushFont(ctx, font)
  ImGui.SetNextWindowSize(ctx, 640, 380, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Clipboard Manager', true)

  if visible then
    draw_toolbar()
    ImGui.Separator(ctx)

    local footer = ImGui.GetFrameHeightWithSpacing(ctx)
    if ImGui.BeginChild(ctx, 'listing', 0, -footer) then
      draw_table()
      ImGui.EndChild(ctx)
    end

    ImGui.Separator(ctx)
    if status_text ~= '' and reaper.time_precise() - status_time < 4 then
      ImGui.Text(ctx, status_text)
    else
      ImGui.TextDisabled(ctx,
        'Click an entry to load it into the clipboard, then Ctrl+V.')
    end

    if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows)
       and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) and not rename_id then
      open = false
    end

    ImGui.End(ctx)
  end

  ImGui.PopFont(ctx)

  apply_pending()

  if open then reaper.defer(loop) end
end

reaper.defer(loop)
