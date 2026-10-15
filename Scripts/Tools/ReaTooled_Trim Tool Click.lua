-- @description Item Body Drag to Trim Edge (Group-Safe, Ripple-Correct, Track-Group Aware) — Mouse Modifier (CLICK-launched)
-- @version 4.0.3
-- @date 2025.10.23
-- @author Brendan Baker
-- @about
--   HOW TO USE (Mouse Modifiers):
--     • Preferences > Mouse Modifiers:
--         - Context: "Media item: left click"  → assign THIS SCRIPT
--         - Context: "Media item: left drag"   → set to "No action"
--       The script launches on click (often mouse-up), ARMS, then starts live defer on the next left-button press.
--
--   Intent (inherits v2.7.8 rules; adapted for click-launched gesture):
--     • One undo point per gesture (mouse-down → mouse-up).
--     • Ripple OFF: no reposition/ripple pass on mouse-up (only the live trim).
--     • Ripple ON : left-edge → translate edited set by -Δ, ripple downstream by -Δ; right-edge → ripple downstream by +Δ.
--     • Item Groups: only boundary-corresponding items (start for left-edge, end for right-edge), across tracks, with tolerance.
--     • Track Groups: only when 1156 ON + 40771 ON + MEDIA_EDIT on member tracks; options 43638/42788/43639 respected.
--     • Honors 1156, 40771, 43638, 42788, 43639, 40041 (Auto-crossfade), 41117 (Trim-behind with edited item “winning”).
--     • Fixed lanes aware; locked items skipped; muted items included; pooled MIDI normal.
--     • Mouse-up ripple/translation via ApplyNudge so envelopes follow when 40070 is ON.
--     • Edge vs Body classification with asymmetric hysteresis (bias to edge); no jitter between modes.

----------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------
local DEBUG = true            -- true to log console + optional tooltips
local DEBUG_TOOLTIPS = true
local function log(...) if not DEBUG then return end for i=1,select("#", ...) do reaper.ShowConsoleMsg(tostring(select(i,...))) end reaper.ShowConsoleMsg("\n") end
local function dbg(fmt, ...) if not DEBUG then return end reaper.ShowConsoleMsg(string.format(fmt.."\n", ...)) end
local function tip(fmt, ...)
  if not (DEBUG and DEBUG_TOOLTIPS) then return end
  local s = string.format(fmt, ...)
  local x, y = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(s, x+16, y+24, true)
end
if DEBUG then reaper.ShowConsoleMsg("") end

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local LOCK_GROUP_STARTS   = false
local BOUNDARY_TOL        = 1e-4
local REQUIRE_SAME_LANE   = true

-- Edge/body hysteresis (asymmetric: end edge allows body closer)
local EDGE_GRAB_PX_START  = 8
local BODY_SAFE_PX_START  = 14
local EDGE_GRAB_PX_END    = 8
local BODY_SAFE_PX_END    = 10

-- Live throttles
local DELTA_EPS           = 0
local UI_THROTTLE_S       = 0

-- CLICK launch arming
local ARM_TIMEOUT_S       = 0.8   -- time window to catch the next left-button press

----------------------------------------------------------------
-- Dependencies
----------------------------------------------------------------
if not reaper.BR_GetMouseCursorContext or not reaper.JS_Mouse_GetState then
  reaper.ShowMessageBox("Requires SWS + JS_ReaScript API.", "Missing Dependency", 0)
  return
end

----------------------------------------------------------------
-- Toggles / options
----------------------------------------------------------------
local function isRipplePerTrackEnabled() return reaper.GetToggleCommandState(40310) == 1 end
local function isRippleAllTracksEnabled() return reaper.GetToggleCommandState(40311) == 1 end
local function isRippleOff()              return reaper.GetToggleCommandState(40309) == 1 end
local function anyRippleOn() return (isRipplePerTrackEnabled() or isRippleAllTracksEnabled()) and (not isRippleOff()) end

local function grouping_master_enabled() return reaper.GetToggleCommandState(1156) == 1 end
local function opt_StartOrEnd()   return reaper.GetToggleCommandState(43638) == 1 end
local function opt_StartAndEnd()  return reaper.GetToggleCommandState(42788) == 1 end
local function opt_Enclosed()     return reaper.GetToggleCommandState(43639) == 1 end

local function opt_AutoCrossfade()  return reaper.GetToggleCommandState(40041) == 1 end
local function opt_TrimBehind()     return reaper.GetToggleCommandState(41117) == 1 end
local function snap_enabled()       return reaper.GetToggleCommandState(1157)  == 1 end -- Options: Toggle snapping

----------------------------------------------------------------
-- Validation / item helpers
----------------------------------------------------------------
local function valid_item(it)  return it ~= nil and reaper.ValidatePtr2(0, it, "MediaItem*") end
local function valid_track(tr) return tr ~= nil and reaper.ValidatePtr2(0, tr, "MediaTrack*") end
local function safe_GetActiveTake(it) if not valid_item(it) then return nil end; return reaper.GetActiveTake(it) end

local function item_start(item) return reaper.GetMediaItemInfo_Value(item, "D_POSITION") end
local function item_len(item)   return reaper.GetMediaItemInfo_Value(item, "D_LENGTH") end
local function item_end(item)   return item_start(item) + item_len(item) end
local function approx_eq(a,b,tol) return math.abs((a or 0)-(b or 0)) <= (tol or BOUNDARY_TOL) end

local function is_item_locked(item)
  local v = reaper.GetMediaItemInfo_Value(item, "C_LOCK")
  return (type(v) == "number" and v ~= 0)
end

local function get_fixed_lane_index(item)
  local idx = reaper.GetMediaItemInfo_Value(item, "I_FIXEDLANE")
  if type(idx) ~= "number" then return -1 end
  return math.floor(idx + 0.5)
end
local function track_has_fixed_lanes(track)
  local fl = reaper.GetMediaTrackInfo_Value(track, "I_FIXEDLANES")
  return (type(fl) == "number") and (fl > 0)
end
local function same_lane(itemA, itemB)
  if not REQUIRE_SAME_LANE then return true end
  local trA = reaper.GetMediaItem_Track(itemA)
  local trB = reaper.GetMediaItem_Track(itemB)
  if not valid_track(trA) or not valid_track(trB) then return true end
  local aHas = track_has_fixed_lanes(trA)
  local bHas = track_has_fixed_lanes(trB)
  if not aHas or not bHas then return true end
  return get_fixed_lane_index(itemA) == get_fixed_lane_index(itemB)
end

----------------------------------------------------------------
-- Mouse/time helpers (grid-aware)
----------------------------------------------------------------
local function get_hovered_item()
  local x, y = reaper.GetMousePosition()
  local it = reaper.GetItemFromPoint(x, y, false)
  return valid_item(it) and it or nil
end
local function get_project_time_from_mouse()
  reaper.BR_GetMouseCursorContext()
  return reaper.BR_GetMouseCursorContext_Position() or reaper.GetCursorPosition()
end
local function get_snapped_mouse_time()
  local t = get_project_time_from_mouse()
  return reaper.SnapToGrid(0, t) or t
end
local function mouse_time_for_drag()
  if snap_enabled() then return get_snapped_mouse_time() end
  return get_project_time_from_mouse()
end

-- px distance from mouse to item edges (for classification)
local function mouse_time_and_pps()
  local t = get_project_time_from_mouse()
  local pps = reaper.GetHZoomLevel()
  if not pps or pps <= 0 then pps = 1e-6 end
  return t, pps
end
local function edge_dist_px(item)
  if not valid_item(item) then return math.huge, math.huge end
  local t, pps = mouse_time_and_pps()
  local s = item_start(item)
  local e = item_end(item)
  return math.abs((t - s) * pps), math.abs((t - e) * pps)
end

-- Edge vs Body classifier (asymmetric thresholds, bias to edge)
local function classify_press_mode(item)
  local ds, de = edge_dist_px(item)
  local nearStart = (ds <= de)
  if ds <= EDGE_GRAB_PX_START or de <= EDGE_GRAB_PX_END then
    return "edge", (nearStart and "start" or "end")
  end
  if ds >= BODY_SAFE_PX_START and de >= BODY_SAFE_PX_END then
    return "body", nil
  end
  return "edge", (nearStart and "start" or "end")
end

-- Body only if comfortably away from BOTH edges
local function is_mouse_in_trim_body(item)
  if not valid_item(item) then return false end
  local ds, de = edge_dist_px(item)
  if ds < BODY_SAFE_PX_START or de < BODY_SAFE_PX_END then return false end
  -- avoid fade zones
  local mouseTime = get_project_time_from_mouse()
  local s = item_start(item)
  local e = item_end(item)
  local fin = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
  local fout = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
  if mouseTime <= (s + fin) then return false end
  if mouseTime >= (e - fout) then return false end
  return true
end

local function get_target_edge(item, time)
  if not valid_item(item) then return "end" end
  local pos = item_start(item)
  local len = item_len(item)
  return (time < pos + len / 2) and "start" or "end"
end

----------------------------------------------------------------
-- Save/restore selection
----------------------------------------------------------------
local function get_item_guid(item) if not valid_item(item) then return nil end; return reaper.BR_GetMediaItemGUID(item) end
local function save_item_selection()
  local selected = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if valid_item(it) then selected[get_item_guid(it)] = true end
  end
  return selected
end
local function restore_item_selection(saved)
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  if not saved then return end
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    if valid_item(it) then
      local g = get_item_guid(it)
      if g and saved[g] then reaper.SetMediaItemSelected(it, true) end
    end
  end
end

----------------------------------------------------------------
-- State capture / clamping
----------------------------------------------------------------
local function capture_item_state(item, edge)
  if not valid_item(item) then return nil end
  local take = safe_GetActiveTake(item)
  local pos  = item_start(item)
  local len  = item_len(item)
  local offs = (take and reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")) or 0
  local fade = {}
  if edge == "start" then
    fade.len = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
  else
    fade.len = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
  end
  return { pos = pos, len = len, offs = offs, fade = fade }
end

local function clamp_delta_to_source(item, st, edge, delta)
  if not valid_item(item) or not st then return 0 end
  if is_item_locked(item) then return 0 end
  local take = safe_GetActiveTake(item)
  if not take then
    return math.max(math.min(delta, st.len - 0.0001), -st.len + 0.0001)
  end
  local src    = reaper.GetMediaItemTake_Source(take)
  local srcLen, isQN = reaper.GetMediaSourceLength(src)
  if isQN then srcLen = reaper.TimeMap2_QNToTime(0, srcLen) end
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
  if rate == 0 then rate = 1 end
  local maxEndTime = srcLen / math.abs(rate)
  if edge == "start" then
    local newStart = st.offs + (delta / rate)
    if newStart < 0 then
      return (0 - st.offs) * rate
    elseif st.len - delta <= 0 then
      return st.len - 0.0001
    end
  else
    local endPos = st.pos + st.len + delta
    if (endPos - st.pos) > maxEndTime then
      return (maxEndTime - st.len)
    elseif st.len + delta <= 0 then
      return -st.len + 0.0001
    end
  end
  return delta
end

local function compute_group_clamped_delta(driver, edge, rawDelta, states, groupItems)
  local set = { driver }
  for _, it in ipairs(groupItems) do set[#set+1] = it end
  local sign, want = (rawDelta >= 0) and 1 or -1, math.abs(rawDelta)
  local allowed = want
  for _, it in ipairs(set) do
    local st = states[it]
    if st then allowed = math.min(allowed, math.abs(clamp_delta_to_source(it, st, edge, sign * want) or 0)) end
  end
  return sign * allowed
end

----------------------------------------------------------------
-- Apply trim (live)
----------------------------------------------------------------
local function apply_trim(item, st, edge, delta, anchor_left_edge)
  if delta == 0 or not valid_item(item) or not st then return end
  if is_item_locked(item) then return end

  local take = safe_GetActiveTake(item)
  local rate = (take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")) or 1
  if rate == 0 then rate = 1 end

  if edge == "start" then
    local newLen = st.len - delta
    if newLen < 0.0001 then newLen = 0.0001 end

    if anchor_left_edge then
      -- Ripple ON (live visual): keep position; adjust offs/length
      reaper.SetMediaItemInfo_Value(item, "D_LENGTH", newLen)
      if take then
        local newOffs = st.offs + (delta / rate); if newOffs < 0 then newOffs = 0 end
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", newOffs)
      end
    else
      -- Ripple OFF: normal left trim moves D_POSITION
      local newPos = st.pos + delta
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", newPos)
      reaper.SetMediaItemInfo_Value(item, "D_LENGTH",  newLen)
      if take then
        local newOffs = st.offs + (delta / rate); if newOffs < 0 then newOffs = 0 end
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", newOffs)
      end
    end

    -- Clamp fade-in to new length
    if st.fade and st.fade.len then
      local fin = math.min(st.fade.len, newLen - 0.0001)
      reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", fin)
    end
  else
    -- Right edge trim: position stays, only length changes
    local newLen = st.len + delta
    if newLen < 0.0001 then newLen = 0.0001 end
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", newLen)
    if st.fade and st.fade.len then
      local fout = math.min(st.fade.len, newLen - 0.0001)
      reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fout)
    end
  end
end

----------------------------------------------------------------
-- Group/track-group correspondence (v2.7.8 rules)
----------------------------------------------------------------
local function track_groups_globally_enabled()
  return grouping_master_enabled() and (reaper.GetToggleCommandState(40771) == 1)
end
local function track_group_has_media_edit(track)
  if not track_groups_globally_enabled() then return false end
  if not reaper.GetSetTrackGroupMembershipEx then return false end
  for grp = 0, 31 do
    local lead   = reaper.GetSetTrackGroupMembershipEx(track, "MEDIA_EDIT_LEAD",   grp, 0, 0)
    if lead ~= 0 then return true end
    local follow = reaper.GetSetTrackGroupMembershipEx(track, "MEDIA_EDIT_FOLLOW", grp, 0, 0)
    if follow ~= 0 then return true end
  end
  return false
end

local function boundary_match_for_edge(driver, other, edge, refStart, refEnd)
  if not valid_item(driver) or not valid_item(other) then return false end
  if not same_lane(driver, other) then return false end
  local oS, oE = item_start(other), item_end(other)
  if edge == "start" then
    return approx_eq(oS, refStart, BOUNDARY_TOL)
  else
    return approx_eq(oE, refEnd, BOUNDARY_TOL)
  end
end
local function enclosed_by_reference(other, refStart, refEnd)
  local oS, oE = item_start(other), item_end(other)
  return (oS >= refStart - BOUNDARY_TOL) and (oE <= refEnd + BOUNDARY_TOL)
end
local function start_or_end_match_reference(other, refStart, refEnd)
  local oS, oE = item_start(other), item_end(other)
  return approx_eq(oS, refStart, BOUNDARY_TOL) or approx_eq(oE, refEnd, BOUNDARY_TOL)
end
local function start_and_end_match_reference(other, refStart, refEnd)
  local oS, oE = item_start(other), item_end(other)
  return approx_eq(oS, refStart, BOUNDARY_TOL) and approx_eq(oE, refEnd, BOUNDARY_TOL)
end

local function collect_item_group_correspondents(driver, edge, refStart, refEnd)
  local out = {}
  if not grouping_master_enabled() then return out end
  if not valid_item(driver) then return out end
  local gid = reaper.GetMediaItemInfo_Value(driver, "I_GROUPID")
  if gid <= 0 then return out end
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    if valid_item(it) and it ~= driver and reaper.GetMediaItemInfo_Value(it, "I_GROUPID") == gid then
      if not is_item_locked(it) and boundary_match_for_edge(driver, it, edge, refStart, refEnd) then
        out[#out+1] = it
      end
    end
  end
  return out
end

local function collect_track_group_correspondents(driver, edge, refStart, refEnd)
  local out = {}
  if not track_groups_globally_enabled() then return out end
  local driverTrack = reaper.GetMediaItem_Track(driver)
  if not valid_track(driverTrack) then return out end

  local members = {}
  local function consider(tr) if valid_track(tr) and track_group_has_media_edit(tr) then members[#members+1] = tr end end
  consider(driverTrack)
  for t = 0, reaper.CountTracks(0) - 1 do local tr = reaper.GetTrack(0, t); if tr ~= driverTrack then consider(tr) end end
  if #members == 0 then return out end

  local useSE, useSAE, useENC = opt_StartOrEnd(), opt_StartAndEnd(), opt_Enclosed()
  local function include_by_options(it)
    if is_item_locked(it) then return false end
    if REQUIRE_SAME_LANE and not same_lane(driver, it) then return false end
    local anyOptOn = useSE or useSAE or useENC
    if anyOptOn then
      if useSAE and start_and_end_match_reference(it, refStart, refEnd) then return true end
      if useSE  and start_or_end_match_reference(it, refStart, refEnd)  then return true end
      if useENC and enclosed_by_reference(it, refStart, refEnd) then return true end
      return false
    else
      return boundary_match_for_edge(driver, it, edge, refStart, refEnd)
    end
  end

  for _, tr in ipairs(members) do
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      if valid_item(it) and it ~= driver and include_by_options(it) then out[#out+1] = it end
    end
  end
  return out
end

local function collect_group_context(driverItem, edge, refStart, refEnd)
  local items = {}
  if not grouping_master_enabled() then return items end
  local ig = collect_item_group_correspondents(driverItem, edge, refStart, refEnd)
  for _, it in ipairs(ig) do items[#items+1] = it end
  local tg = collect_track_group_correspondents(driverItem, edge, refStart, refEnd)
  for _, it in ipairs(tg) do items[#items+1] = it end
  return items
end

----------------------------------------------------------------
-- Edited / Downstream sets
----------------------------------------------------------------
local function build_edited_set(driver, syncedItems)
  local edited = {}
  if valid_item(driver) then edited[driver] = true end
  for _, it in ipairs(syncedItems or {}) do if valid_item(it) then edited[it] = true end end
  return edited
end

local function build_downstream_set(driver, originalEnd)
  local set = {}
  if not anyRippleOn() then return set end
  local rippleTrack = isRipplePerTrackEnabled()
  local rippleAll   = isRippleAllTracksEnabled()
  local driverTrack = reaper.GetMediaItem_Track(driver)
  local function track_in_scope(tr) return rippleAll or (rippleTrack and tr == driverTrack) end
  for t = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, t)
    if valid_track(tr) and track_in_scope(tr) then
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        if valid_item(it) and not is_item_locked(it) then
          local pos = item_start(it)
          if pos + BOUNDARY_TOL >= originalEnd then set[it] = true end
        end
      end
    end
  end
  return set
end

----------------------------------------------------------------
-- ApplyNudge move (envelopes follow when 40070 ON)
----------------------------------------------------------------
local function native_move_items_by_delta(itemSet, delta)
  if not itemSet or delta == 0 then return end
  local clean, count = {}, 0
  for it in pairs(itemSet) do
    if valid_item(it) and not is_item_locked(it) then clean[it]=true; count=count+1 end
  end
  if count == 0 then return end
  local savedSel = save_item_selection()
  reaper.PreventUIRefresh(1)
  reaper.Main_OnCommand(40289, 0) -- unselect all
  for it in pairs(clean) do reaper.SetMediaItemSelected(it, true) end
  reaper.ApplyNudge(0, 0, 0, 1, math.abs(delta), (delta < 0), 0)
  reaper.Main_OnCommand(40289, 0)
  restore_item_selection(savedSel)
  reaper.PreventUIRefresh(-1)
end

----------------------------------------------------------------
-- Ripple finalize (mouse-up)
----------------------------------------------------------------
local function ripple_resolve_on_mouseup(driver, edge, delta, originalEnd, syncedItems)
  if delta == 0 or not anyRippleOn() then return end
  dbg("[ripple] edge=%s Δ=%.9f originalEnd=%.9f", edge, delta, originalEnd)
  local editedSet = build_edited_set(driver, syncedItems)
  local downstream = build_downstream_set(driver, originalEnd)
  if edge == "start" then
    native_move_items_by_delta(editedSet, -delta)
    native_move_items_by_delta(downstream, -delta)
  else
    native_move_items_by_delta(downstream, delta)
  end
end

----------------------------------------------------------------
-- Overlap handling helpers (mouse-up tidy)
----------------------------------------------------------------
local function trim_right_edge_to(item, newEnd)
  if not valid_item(item) or is_item_locked(item) then return end
  local s = item_start(item)
  local newLen = math.max(0.0001, newEnd - s)
  local fout = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
  if fout > newLen - 0.0001 then reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", math.max(0, newLen - 0.0001)) end
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", newLen)
end
local function trim_left_edge_to(item, newStart)
  if not valid_item(item) or is_item_locked(item) then return end
  local s, e = item_start(item), item_end(item)
  if newStart < s then newStart = s end
  if newStart > e - 0.0001 then newStart = e - 0.0001 end
  local take = safe_GetActiveTake(item)
  local rate = (take and reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")) or 1
  if rate == 0 then rate = 1 end
  local delta = newStart - s
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", newStart)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH",  math.max(0.0001, e - newStart))
  if take then
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    local newOffs = offs + (delta / rate); if newOffs < 0 then newOffs = 0 end
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", newOffs)
  end
  local fin = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
  local newLen = e - newStart
  if fin > newLen - 0.0001 then reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", math.max(0, newLen - 0.0001)) end
end

local function manual_handle_overlap_pair(leftItem, rightItem, editedSet)
  local ls, le = item_start(leftItem),  item_end(leftItem)
  local rs, re_ = item_start(rightItem), item_end(rightItem)
  local overlap = math.max(0.0, le - rs)
  if overlap <= 0 then
    if opt_AutoCrossfade() then
      reaper.SetMediaItemInfo_Value(leftItem,  "D_FADEOUTLEN", 0)
      reaper.SetMediaItemInfo_Value(rightItem, "D_FADEINLEN",  0)
    end
    return
  end
  if opt_AutoCrossfade() then
    reaper.SetMediaItemInfo_Value(leftItem,  "D_FADEOUTLEN", overlap)
    reaper.SetMediaItemInfo_Value(rightItem, "D_FADEINLEN",  overlap)
    return
  end
  if opt_TrimBehind() then
    local leftEdited  = editedSet and editedSet[leftItem]  or false
    local rightEdited = editedSet and editedSet[rightItem] or false
    if leftEdited and not rightEdited then trim_left_edge_to(rightItem, le); return end
    if rightEdited and not leftEdited then trim_right_edge_to(leftItem, rs); return end
    trim_right_edge_to(leftItem, rs); return
  end
end

local function same_lane_if_required(a, b) if not REQUIRE_SAME_LANE then return true end; return same_lane(a, b) end

local function resolve_overlaps_grouped(dragItem, syncedItems)
  local working = {}
  if valid_item(dragItem) then working[#working+1] = dragItem end
  for _, it in ipairs(syncedItems or {}) do if valid_item(it) then working[#working+1] = it end end
  if #working == 0 then return end

  local editedSet = build_edited_set(dragItem, syncedItems)
  local spanPerTrack = {}
  for _, it in ipairs(working) do
    local tr = reaper.GetMediaItem_Track(it)
    if valid_track(tr) then
      local s, e = item_start(it), item_end(it)
      local rec = spanPerTrack[tr] or { s = math.huge, e = -math.huge }
      if s < rec.s then rec.s = s end
      if e > rec.e then rec.e = e end
      spanPerTrack[tr] = rec
    end
  end

  reaper.PreventUIRefresh(1)
  for tr, span in pairs(spanPerTrack) do
    local items = {}
    for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      if valid_item(it) then
        local s, e = item_start(it), item_end(it)
        if e > span.s - BOUNDARY_TOL and s < span.e + BOUNDARY_TOL then items[#items+1] = it end
      end
    end
    table.sort(items, function(a,b) return item_start(a) < item_start(b) end)
    for i = 1, (#items - 1) do
      local a, b = items[i], items[i+1]
      if same_lane_if_required(a, b) then
        local overlap = item_end(a) - item_start(b)
        if overlap > BOUNDARY_TOL or opt_AutoCrossfade() then
          manual_handle_overlap_pair(a, b, editedSet)
        end
      end
    end
  end
  reaper.PreventUIRefresh(-1)
end

----------------------------------------------------------------
-- Main gesture (runs only while mouse is down)
----------------------------------------------------------------
local function run_gesture(driver)
  local savedSel = save_item_selection()

  if not valid_item(driver) then
    dbg("[error] No driver item at gesture start.")
    return
  end
  if is_item_locked(driver) then
    dbg("[abort] Driver is locked.")
    return
  end

  local mode, whichEdge = classify_press_mode(driver)
  local edge = whichEdge or get_target_edge(driver, mouse_time_for_drag())
  dbg("[classify] mode=%s edge=%s", mode, edge or "?")

  reaper.Undo_BeginBlock2(0)

  local pos, len = item_start(driver), item_len(driver)
  local originalEnd = pos + len
  local dragState = { item = driver, edge = edge, originalPos = pos, originalEnd = originalEnd, mouseStart = get_project_time_from_mouse() }

  local initialStates = {}
  local st = capture_item_state(driver, edge)
  if not st then
    dbg("[error] Failed to capture initial state.")
    reaper.Undo_EndBlock2(0, "Trim (cancel)", -1)
    return
  end
  initialStates[driver] = st

  local syncedItems = collect_group_context(driver, edge, dragState.originalPos, dragState.originalEnd)
  dbg("[group] syncedItems=%d", #syncedItems)
  for _, it in ipairs(syncedItems) do local s = capture_item_state(it, edge); if s then initialStates[it] = s end end

  local initialMouseX = (edge == "start") and st.pos or (st.pos + st.len)
  local rippleWasOnAtStart = anyRippleOn()
  dbg("[state] rippleOn=%s initialMouseX=%.9f pos=%.9f len=%.9f", tostring(rippleWasOnAtStart), initialMouseX, pos, len)

  local lastUpdateT, lastDelta = -1, 0

  -- Live loop while left button is down
  while reaper.JS_Mouse_GetState(1) == 1 do
    local now = reaper.time_precise()
    if UI_THROTTLE_S == 0 or lastUpdateT < 0 or (now - lastUpdateT) >= UI_THROTTLE_S then
      lastUpdateT = now
      local mouseTime = mouse_time_for_drag()
      local rawDelta  = mouseTime - initialMouseX
      local groupDelta = compute_group_clamped_delta(driver, edge, rawDelta, initialStates, syncedItems)
      if DELTA_EPS <= 0 or math.abs(groupDelta - lastDelta) > DELTA_EPS then
        lastDelta = groupDelta
        tip("Δ=%.6f  [%s%s]", groupDelta, edge, rippleWasOnAtStart and ", ripple" or "")
        dbg("[live] rawΔ=%.9f groupΔ=%.9f mouseTime=%.9f", rawDelta, groupDelta, mouseTime)

        local anchor_left = (edge == "start") and rippleWasOnAtStart
        apply_trim(driver, initialStates[driver], edge, groupDelta, anchor_left)
        for _, it in ipairs(syncedItems) do
          local s2 = initialStates[it]; if s2 then apply_trim(it, s2, edge, groupDelta, anchor_left) end
        end

        -- Live auto-crossfade preview
        if opt_AutoCrossfade() then
          local working = {}; working[#working+1] = driver; for _, it in ipairs(syncedItems) do working[#working+1] = it end
          local spanPerTrack = {}
          for _, it in ipairs(working) do
            local tr = reaper.GetMediaItem_Track(it)
            if valid_track(tr) then
              local sA, eA = item_start(it), item_end(it)
              local rec = spanPerTrack[tr] or { s = math.huge, e = -math.huge }
              if sA < rec.s then rec.s = sA end
              if eA > rec.e then rec.e = eA end
              spanPerTrack[tr] = rec
            end
          end
          for tr, span in pairs(spanPerTrack) do
            local items = {}
            for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
              local it = reaper.GetTrackMediaItem(tr, i)
              if valid_item(it) then
                local sA, eA = item_start(it), item_end(it)
                if eA > span.s - BOUNDARY_TOL and sA < span.e + BOUNDARY_TOL then items[#items+1] = it end
              end
            end
            table.sort(items, function(a,b) return item_start(a) < item_start(b) end)
            for i = 1, (#items - 1) do
              local a, b = items[i], items[i+1]
              if not REQUIRE_SAME_LANE or same_lane(a, b) then
                local overlap = item_end(a) - item_start(b)
                if overlap > 0 then
                  reaper.SetMediaItemInfo_Value(a, "D_FADEOUTLEN", overlap)
                  reaper.SetMediaItemInfo_Value(b, "D_FADEINLEN",  overlap)
                else
                  reaper.SetMediaItemInfo_Value(a, "D_FADEOUTLEN", 0)
                  reaper.SetMediaItemInfo_Value(b, "D_FADEINLEN",  0)
                end
              end
            end
          end
        end

        reaper.UpdateArrange()
      end
    end
    reaper.defer(function() end)
  end

  local finalDelta = lastDelta
  dbg("[final] Δ=%.9f", finalDelta)

  if finalDelta ~= 0 then
    if anyRippleOn() then
      ripple_resolve_on_mouseup(driver, edge, finalDelta, dragState.originalEnd, syncedItems)
    else
      if edge == "start" and LOCK_GROUP_STARTS then
        local curPos = item_start(driver)
        local deltaBack = dragState.originalPos - curPos
        if math.abs(deltaBack) > 1e-9 then
          dbg("[snapback] moving edited set by %.9f", deltaBack)
          local editedSet = build_edited_set(driver, syncedItems)
          native_move_items_by_delta(editedSet, deltaBack)
        end
      end
    end
  end

  resolve_overlaps_grouped(driver, syncedItems)
  restore_item_selection(savedSel)
  reaper.Undo_EndBlock2(0, "Trim items (ReaTooled – click-launched)", -1)
end

----------------------------------------------------------------
-- Arming logic for click-launched context
----------------------------------------------------------------
local function arm_and_wait()
  local launchItem = get_hovered_item()
  if not valid_item(launchItem) then
    dbg("[arm] No item under mouse at launch; arming anyway.")
  else
    dbg("[arm] Launch item GUID=%s", tostring(reaper.BR_GetMediaItemGUID(launchItem)))
  end

  local t0 = reaper.time_precise()
  tip("ReaTooled Trim: armed — press LMB within %.1fs", ARM_TIMEOUT_S)

  local function loop()
    -- Abort on timeout
    if (reaper.time_precise() - t0) > ARM_TIMEOUT_S then
      tip("ReaTooled Trim: arm timeout")
      dbg("[arm] Timeout; abort.")
      return
    end

    -- If left button pressed, pick current item (prefer current hover)
    if reaper.JS_Mouse_GetState(1) == 1 then
      local cur = get_hovered_item()
      local driver = valid_item(cur) and cur or launchItem
      if not valid_item(driver) then
        dbg("[arm] LMB down but no valid item; abort.")
        return
      end
      dbg("[arm] Captured item; starting gesture.")
      run_gesture(driver)
      return
    end

    reaper.defer(loop)
  end

  loop()
end

----------------------------------------------------------------
-- Entry (bound to Media item: left click)
----------------------------------------------------------------
do
  local mouseState = reaper.JS_Mouse_GetState(1)
  dbg("[launch] JS_Mouse_GetState(1)=%d", mouseState)
  if mouseState == 1 then
    -- Rare case: click context fires with button still down → start now
    local driver = get_hovered_item()
    if valid_item(driver) then
      dbg("[launch] Button down; starting gesture immediately.")
      run_gesture(driver)
    else
      dbg("[launch] Button down but no item; arming fallback.")
      arm_and_wait()
    end
  else
    -- Typical case: fired on mouse-up → arm and wait for the next press
    arm_and_wait()
  end
end
