-- @description Spectrogram on Selected Track Only (Defer; batch-consistent, no undo points)
-- @version 1.4
-- @author The Reaper Script Wizard
-- @about
--   Enforces spectrogram on the currently selected track only by toggling
--   ALL of that track's items together via action 42303, and reverting exactly
--   the batch it previously toggled on the previous track.
--   All operations are wrapped to avoid creating undo points.

----------------------------------------
-- CONFIG
----------------------------------------
local CMD_TOGGLE_ALWAYS = 42303 -- Spectrogram: Toggle always show spectrogram for selected items
local RUN_INTERVAL_SEC  = 0.20  -- throttle to keep UI responsive

----------------------------------------
-- INTERNALS
----------------------------------------
local proj = 0
local last_run = 0
local prev_sel_guid = nil
local prev_batch_items = {}  -- array of MediaItem* that this script toggled on last track
local prev_batch_valid = false

-- ========== helpers ==========
local function itemGUID(it)
  local ok, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
  return ok and guid or nil
end

local function trackGUID(tr)
  local ok, guid = reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
  return ok and guid or nil
end

local function saveSelItems()
  local t = {}
  local n = reaper.CountSelectedMediaItems(proj)
  for i = 0, n-1 do t[#t+1] = reaper.GetSelectedMediaItem(proj, i) end
  return t
end

local function restoreSelItems(t)
  reaper.Main_OnCommand(40289, 0) -- Item: Unselect all items
  for i = 1, #t do
    local it = t[i]
    if it and reaper.ValidatePtr2(proj, it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end
end

local function selectItems(items)
  reaper.Main_OnCommand(40289, 0) -- Item: Unselect all items
  for i = 1, #items do
    local it = items[i]
    if it and reaper.ValidatePtr2(proj, it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end
end

local function allItemsOnTrack(tr)
  local list = {}
  local n = reaper.CountTrackMediaItems(tr)
  for i = 0, n-1 do list[#list+1] = reaper.GetTrackMediaItem(tr, i) end
  return list
end

local function sameItems(a, b)
  if #a ~= #b then return false end
  local set = {}
  for i = 1, #a do
    local g = itemGUID(a[i]); if g then set[g] = true end
  end
  for i = 1, #b do
    local g = itemGUID(b[i]); if (not g) or (not set[g]) then return false end
  end
  return true
end

-- Run a function without creating an undo point
local function withoutUndo(fn)
  reaper.Undo_BeginBlock2(proj)
  fn()
  -- flag -1 prevents creating an undo point
  reaper.Undo_EndBlock2(proj, "", -1)
end

-- Apply action 42303 to a set of items as a single atomic batch (no undo)
local function apply42303_to_items(items)
  if #items == 0 then return end
  withoutUndo(function()
    local saved = saveSelItems()
    reaper.PreventUIRefresh(1)
    selectItems(items)
    reaper.Main_OnCommand(CMD_TOGGLE_ALWAYS, 0)
    reaper.PreventUIRefresh(-1)
    restoreSelItems(saved)
  end)
end

-- ========== main loop ==========
local function update()
  local now = reaper.time_precise()
  if now - last_run < RUN_INTERVAL_SEC then
    reaper.defer(update); return
  end
  last_run = now

  local sel_tr = reaper.GetSelectedTrack(proj, 0)
  local sel_guid = sel_tr and trackGUID(sel_tr) or nil

  if sel_guid ~= prev_sel_guid then
    -- Switched tracks: revert previous batch, then toggle all items on new track
    if prev_batch_valid and #prev_batch_items > 0 then
      apply42303_to_items(prev_batch_items)  -- revert
    end
    prev_batch_items = {}
    prev_batch_valid = false

    if sel_tr then
      local items = allItemsOnTrack(sel_tr)
      if #items > 0 then
        apply42303_to_items(items)           -- toggle ALL together
        prev_batch_items = items             -- remember exactly what we toggled
        prev_batch_valid = true
      end
    end

    prev_sel_guid = sel_guid
  else
    -- Same track: if items changed (added/removed), keep the whole track consistent
    if sel_tr then
      local items_now = allItemsOnTrack(sel_tr)
      if not sameItems(items_now, prev_batch_items) then
        -- revert prior batch for this track, then toggle current list as one batch
        if prev_batch_valid and #prev_batch_items > 0 then
          apply42303_to_items(prev_batch_items)
        end
        if #items_now > 0 then
          apply42303_to_items(items_now)
          prev_batch_items = items_now
          prev_batch_valid = true
        else
          prev_batch_items = {}
          prev_batch_valid = false
        end
      end
    end
  end

  reaper.UpdateArrange()
  reaper.defer(update)
end

-- start
update()
