-- @description Item Body Drag to Trim Edge v7.2.0 (Group/Track-Group Safe, Native Fades, Native Edge-Safe Ripple)
-- @version 7.2.0
-- @date 2026-03-18
-- @author Brendan Baker (with assistant)
-- @about
--   ReaScript: REAPER 7.48+ | Requires SWS + JS_ReaScript API
--   • Body-drag to trim either edge (edge determined by press in left/right body half, using fade seams).
--   • Native fades only: pressing inside fades is ignored so native fade edits work as-is.
--   • Native edge grabs are allowed. If 43475 ("Ripple edit when editing media item edges") is ON, we do not
--     apply our own ripple on mouse-up for native-edge gestures (prevents double ripple).
--   • Ripple OFF: only edge/offset/fades change + optional crossfade sliding between neighbors.
--   • Ripple Per-Track: scope = driver's track + selected tracks (snapshot at press).
--     Grouped / track-grouped followers still follow even on unselected tracks.
--   • Ripple All-Tracks: whole project timeline; markers/regions only if 43690 is ON.
--   • Native-like Live Ripple (BODY_NATIVE_RIPPLE=true): downstream translates continuously.
--   • Crossfades preserved (length + shapes) wherever allowed; locked items never edited.
--   • Fixed lanes aware (same-lane only when REQUIRE_SAME_LANE=true).
--   • One undo point per gesture.
--   • Honors: 1156 (group master), 40771 (track grouping enabled), 43638/42788/43639 (track group edit modes),
--             40041 (auto-xfade), 41117 (trim content behind), 40070 (move env with items),
--             43690 (Ripple edit all affects regions/markers), 43475 (ripple when edge-editing).
--   • PATCH 6.0.2:
--       - Left-edge body press in a C+A crossfade now snaps using the *seam* (end of C) as reference.
--       - Right-edge body press in an A+B crossfade uses the start of the crossfade as the snap reference.
--       - With BODY_NATIVE_RIPPLE=true, start-edge snap ripples downstream immediately at press (driver feels "locked").
--   • PATCH 6.0.3:
--       - Clamp logic unified: items cannot be trimmed past their fades (single or crossfades).
--         Minimum effective length is fade-in + fade-out (plus EPS), so you can shrink until
--         you have "just a fade-in and fade-out", but never eat into fades.
--       - Crossfade sliding when Ripple is OFF:
--           * Left drag on A with a left crossfade C–A: C's end moves with A's start, crossfade length/shape preserved.
--           * Right drag on A with a right crossfade A–B: B's start moves with A's end, crossfade preserved.
--         This works regardless of BODY_NATIVE_RIPPLE, as long as ripple editing is OFF.
--   • v7.0.0 – Refactor (no behavior changes):
--       - All G fields now declared in new_G() — no more ad-hoc field creation mid-gesture.
--         Eliminates stale-state risk between gestures.
--       - freeze_scope() decomposed into five focused sub-functions:
--         freeze_drivers_and_followers, freeze_ripple_scope, freeze_fade_snapshots,
--         freeze_crossfade_pairs, freeze_slide_neighbors.
--       - resolve_pair() guard asymmetry documented explicitly; editedSet-aware guard added.
--       - clamp_to_source() split: fade-floor constraint extracted to clamp_min_length_for_fades(),
--         source-boundary constraint kept in clamp_to_source_bounds(). Both composed by clamp_to_source().
--       - batch_translate_items() now takes an explicit moveEnvelopes boolean instead of
--         inferring intent from a nil cutoff; callers updated accordingly.
--       - DOWNSTREAM_SNAPSHOT_TOL alias removed; BOUNDARY_TOL used directly.
--       - SLICE_CLEAN_TOL and LIVE_RIPPLE_MIN_DT annotated with rationale.
--       - RIPPLE_INCLUDE_DRIVER_ON_MOUSEUP behavior documented with invariant comment.
--       - main() loop refactored into handle_hover / handle_press / handle_drag / handle_release
--         sub-functions dispatched by a mode table.
--       - Debug assertions added for nil initStates entries in drag loop.
--   • v7.1.0 – Cleanup and correctness:
--       - Removed dead functions: build_ripple_sets, compute_item_zones_min,
--         fade_seam_for_start, fade_seam_for_end (none were called anywhere).
--       - Removed unused cursor_fade_in / cursor_fade_out cursor handles.
--       - Removed G.initialMouse field (was set but never read; G.initialMouseRaw is used).
--       - clamp_min_length_for_fades() now reads press-time fade lengths from G.pressXf
--         instead of querying live item values, which could be polluted by the AutoXfade
--         live preview mid-drag. Fixes fade-floor clamp inconsistency during preview.
--       - BR_GetMouseCursorContext() is now called exactly once per frame in main() and
--         the results cached as frame-local upvalues; px_to_time() uses GetHZoomLevel()
--         directly without re-priming the cursor context.
--       - handle_press() press-time snap logic extracted into do_press_snap_default()
--         and do_press_snap_sliding(), reducing handle_press() to a clean dispatcher.
--       - resolve_pair() TrimBehind else-branch clarified: "both edited OR neither edited"
--         is now explicitly documented and the duplicate code path collapsed.
--       - snapped_delta_from_raw() deadband/snap interaction documented: deadband takes
--         priority over snap — delta returns 0 inside the deadband even at a grid point.
--       - pertrack_first_downstream_and_anchor() rewritten with a single O(N) index pass
--         instead of O(N²) nested loops.
--   • v7.2.0 – Further cleanup and performance:
--       - Removed dead functions: temp_move_items_only, clamp (neither was called anywhere).
--       - Removed duplicate EdgeRippleOn() — RippleEdgeOptionOn() (tg(43475)) is the single
--         source; startup block updated to use it.
--       - Removed _ctx_window from frame cache — it was assigned but never read.
--       - do_press_snap_sliding() trivial wrapper removed; handle_press() calls
--         press_time_align_sliding_crossfade() directly with an explanatory comment.
--       - freeze_crossfade_pairs() split into two focused functions:
--           freeze_crossfade_pair_detection() — populates G.pressCF only.
--           freeze_right_xfade_neighbor()     — mutates G.downstreamSnap and sets
--                                               G.rightXfadeNeighbor, then computes guardPairs.
--         freeze_scope() calls them in sequence; the hidden ordering dependency is now explicit.
--       - freeze_fade_snapshots() scoped to rippleTrackScope + driver's track instead of
--         walking the entire project. pressXf is only read for items within gesture reach.
--       - restore_press_crossfades() scoped to rippleTrackScope + driver's track instead
--         of walking the entire project at mouse-up.
--       - handle_drag() sliding-neighbor exclusion set pre-computed once before the trim
--         loop, eliminating per-item per-frame calls to is_current_sliding_neighbor().
--       - Redundant zero-assignments removed from handle_press() (rippleApplied,
--         initialPressDelta already zeroed by new_G()).
--       - live_preview_autoxf() preview threshold comments clarified: PREVIEW_MIN_FADE_PX
--         is the minimum overlap to draw a preview fade; PREVIEW_HYST_PX adds hysteresis
--         to prevent jitter near the threshold. They are summed into a single cutoff T.

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local BODY_NATIVE_RIPPLE       = false      -- native-like live translation while dragging
local BODY_SET_EDGE_ON_PRESS   = true       -- snap edge at press to cursor time
local REQUIRE_SAME_LANE        = true
-- When true: for start-edge moves, edited set rides the initial press jump so it "feels native"
local RIPPLE_INCLUDE_DRIVER_ON_MOUSEUP = true

-- UI tolerances (px → converted per-zoom)
local EDGE_GRAB_PX             = 7          -- tolerance around the native edge
local BODY_SAFE_PX             = 9          -- keep-away from fades for body classification
local DRAG_DEADBAND_PX         = 1.5        -- ignore first ~1-2 px of motion after press
-- NOTE: deadband takes priority over snap. If the cursor is within the deadband but
-- sitting exactly on a grid point, delta is still returned as 0. This prevents
-- accidental snapping on the very first frame of movement.

-- Numerics
local EPS                      = 0.0001
local BOUNDARY_TOL             = 0.001

-- Minimum delta before live ripple is applied each frame.
-- 1e-5 s ≈ 0.01 ms — below any perceptible audio boundary.
local LIVE_RIPPLE_MIN_DT       = 1e-5

-- Items shorter than this after a trim are deleted as "slices".
-- 3× EPS gives a small safety margin over the absolute minimum (EPS),
-- so rounding from multiple clamp passes never leaves a ghost item.
local SLICE_CLEAN_TOL          = math.max(BOUNDARY_TOL, EPS * 3)

-- Live AutoXfade preview thresholds.
-- PREVIEW_MIN_FADE_PX: minimum overlap in pixels before a preview crossfade is drawn
--   (avoids sub-pixel fades that would be invisible and just add noise).
-- PREVIEW_HYST_PX: extra hysteresis added to the threshold to prevent flicker when
--   overlap hovers right at the minimum. Both are summed into a single cutoff T.
local PREVIEW_MIN_FADE_PX      = 2.0
local PREVIEW_HYST_PX          = 1.5

local DEBUG                    = false
local function dbg(...) if DEBUG then reaper.ShowConsoleMsg(table.concat({...}," ").."\n") end end

-- Extra pixel padding around fades where body-drag is disabled
local FADE_HALO_PX = 6    -- try 6–12; lower = tighter, higher = safer

----------------------------------------------------------------
-- DEPENDENCIES CHECK
----------------------------------------------------------------
if not reaper.BR_GetMouseCursorContext or not reaper.JS_Mouse_GetState then
  reaper.ShowMessageBox("Requires SWS + JS_ReaScript API.", "Missing Dependency", 0)
  return
end

----------------------------------------------------------------
-- TOGGLES (helpers to read REAPER state)
----------------------------------------------------------------
local function tg(id) return reaper.GetToggleCommandState(id) == 1 end
local function GroupMasterOn()           return tg(1156) end
local function TrackGroupsOn()           return GroupMasterOn() and tg(40771) end
local function OptSE()                   return tg(43638) end
local function OptSAE()                  return tg(42788) end
local function OptENC()                  return tg(43639) end
local function AutoXfadeOn()             return tg(40041) end
local function TrimBehindOn()            return tg(41117) end
local function MoveEnvWithItems()        return tg(40070) end
local function RipplePerTrack()          return tg(40310) end
local function RippleAllTracks()         return tg(40311) end
local function RippleOff()               return tg(40309) end
local function AnyRippleOn()             return (RipplePerTrack() or RippleAllTracks()) and (not RippleOff()) end
local function MarkersRegionsRippleAll() return tg(43690) end
local function RippleEdgeOptionOn()      return tg(43475) end  -- "Ripple edit when editing media item edges"
local function SnapEnabled()             return tg(1157) end

----------------------------------------------------------------
-- Edge-ripple option management
-- EDGE_RIPPLE_CMD is the same command as RippleEdgeOptionOn() above;
-- kept as a named constant so set_toggle() and the startup block are readable.
----------------------------------------------------------------
local EDGE_RIPPLE_CMD = 43475

local function set_toggle(cmd, wantOn)
  local isOn = reaper.GetToggleCommandState(cmd) == 1
  if wantOn and not isOn then
    reaper.Main_OnCommand(cmd, 0)
  elseif (not wantOn) and isOn then
    reaper.Main_OnCommand(cmd, 0)
  end
end

----------------------------------------------------------------
-- SMALL UTILS
----------------------------------------------------------------
local function valid_item(it)  return it and reaper.ValidatePtr2(0, it, "MediaItem*") end
local function valid_track(tr) return tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") end
local function is_locked(it)   return (reaper.GetMediaItemInfo_Value(it,"C_LOCK") or 0) ~= 0 end

local function item_track_safe(it)
  if not it then return nil end
  if not reaper.ValidatePtr2(0, it, "MediaItem*") then return nil end
  local tr = reaper.GetMediaItem_Track(it)
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then return nil end
  return tr
end

local function item_start(it)  return reaper.GetMediaItemInfo_Value(it, "D_POSITION") end
local function item_len(it)    return reaper.GetMediaItemInfo_Value(it, "D_LENGTH") end
local function item_end(it)    return item_start(it) + item_len(it) end
local function approx(a,b,t)   return math.abs((a or 0) - (b or 0)) <= (t or BOUNDARY_TOL) end

local function get_take(it)    if not valid_item(it) then return nil end return reaper.GetActiveTake(it) end

-- Frame-local cursor context cache.
-- Populated once per frame at the top of main(); all per-frame calls that need
-- the context read from these upvalues instead of re-calling BR_GetMouseCursorContext.
-- _ctx_window is intentionally discarded (_) — only segment, details, and pos are used.
local _ctx_segment, _ctx_details, _ctx_pos = "", "", 0

local function refresh_cursor_context()
  local _, seg, det = reaper.BR_GetMouseCursorContext()
  _ctx_segment = seg
  _ctx_details = det
  _ctx_pos = reaper.BR_GetMouseCursorContext_Position() or reaper.GetCursorPosition()
end

local function get_mouse_time_raw()
  return _ctx_pos
end

-- px_to_time uses only GetHZoomLevel — no cursor context side effect.
local function px_to_time(px)
  local pps = reaper.GetHZoomLevel() or 1e-6
  if pps <= 0 then pps = 1e-6 end
  if (px or 0) == 0 then return 0 end
  return px / pps
end

local function current_edge_pos(it, edge)
  return (edge == "start") and item_start(it) or item_end(it)
end

----------------------------------------------------------------
-- FOREGROUND / WINDOW HELPERS (strict cursor policy)
----------------------------------------------------------------
local function __rt_root_of(hwnd)
  if not hwnd or not reaper.JS_Window_GetParent then return hwnd end
  local r = hwnd
  while true do
    local p = reaper.JS_Window_GetParent(r)
    if not p then break end
    r = p
  end
  return r
end

local function __rt_is_mouse_in_reaper()
  if not reaper.JS_Window_FromPoint then return true end
  local x, y = reaper.GetMousePosition()
  local w = reaper.JS_Window_FromPoint(x, y)
  if not w then return false end
  local root = __rt_root_of(w)
  return root == reaper.GetMainHwnd()
end

local function __rt_is_reaper_foreground()
  if reaper.JS_Window_GetForeground then
    return __rt_root_of(reaper.JS_Window_GetForeground()) == reaper.GetMainHwnd()
  end
  if reaper.JS_Window_GetFocus then
    return __rt_root_of(reaper.JS_Window_GetFocus()) == reaper.GetMainHwnd()
  end
  return true
end

local function __rt_allow_custom_cursor_now()
  return __rt_is_reaper_foreground() and __rt_is_mouse_in_reaper()
end

local function snapped_delta_from_raw(rawDelta, pressBoundary, deadbandT)
  -- Deadband check runs first: if motion is below the threshold, return 0
  -- regardless of snap grid. This is intentional — see CONFIG note above.
  if math.abs(rawDelta) < (deadbandT or 0) then return 0 end
  if not SnapEnabled() then return rawDelta end
  local targetAbs     = pressBoundary + rawDelta
  local snappedTarget = reaper.SnapToGrid(0, targetAbs)
  return snappedTarget - pressBoundary
end

local function DefaultXfadeShape()
  if reaper.SNM_GetIntConfigVar then
    local v = reaper.SNM_GetIntConfigVar("defxfadeshape", -1)
    if type(v)=="number" and v >= 0 then return v end
  end
  return 0
end
local DEFAULT_XFADE_SHAPE = DefaultXfadeShape()

----------------------------------------------------------------
-- NATIVE ZONE DETECTION (fade / crossfade / edge)
-- Uses the frame-cached cursor context — no extra API call.
----------------------------------------------------------------
local function in_native_fade_or_edge_zone()
  if _ctx_segment ~= "arrange" or not _ctx_details then return false end
  if not _ctx_details:find("item") then return false end
  if _ctx_details:find("fade") or _ctx_details:find("edge") then
    return true
  end
  return false
end

----------------------------------------------------------------
-- STATE
-- ALL fields that may exist on G must be declared here.
-- Fields created ad-hoc mid-gesture are a source of stale-state
-- bugs across gesture boundaries; new_G() is the single source of truth.
----------------------------------------------------------------
local function new_G()
  return {
    -- Gesture lifecycle
    mode              = "none",   -- "none" | "body"
    modeKind          = nil,      -- "body" | "edge" (from classification)
    driver            = nil,      -- primary item under cursor at press
    edge              = nil,      -- "start" | "end"
    undoOpen          = false,
    inPressAlign      = false,    -- true only during press-time snap alignment

    -- Mouse / drag tracking
    initialMouseRaw   = nil,      -- mouse time at start of drag (post press-snap)
    pressBoundary     = nil,      -- driver edge position after press-time snap
    initialPressDelta = 0,        -- how far press-time snap moved the edge

    -- Scope (frozen at press)
    selectedTrackSet  = nil,      -- map of tracks selected at press time
    editedSet         = {},       -- all items that will be trimmed
    initStates        = {},       -- cap_state() snapshots keyed by item

    -- Ripple
    originalEnd       = nil,      -- driver item_end() at press (pre-snap)
    rippleTrackScope  = nil,      -- map of tracks in ripple scope
    downstreamSnap    = nil,      -- snapshot of downstream items at press
    guardPairs        = nil,      -- per-track first-downstream + prevEnd
    rippleApplied     = 0,        -- cumulative live-ripple delta applied so far

    -- Crossfade state (press-time snapshots)
    pressXf           = nil,      -- per-item {fin={len,shape}, fout={len,shape}} at press
    pressCF           = nil,      -- set of true crossfade pairs present at press

    -- Crossfade geometry (press-time seam references)
    pressLeftXfadeEndAtPress  = nil,  -- abs time of left CF seam (end of C)
    pressLeftXfadeNeighbor    = nil,  -- the C item
    pressXfadeStartAtPress    = nil,  -- abs time of right CF seam (start of B)
    pressXfadeNeighbor        = nil,  -- the B item

    -- Right-edge crossfade neighbor (for ripple downstream inclusion)
    rightXfadeNeighbor = nil,

    -- Crossfade sliding neighbors (Ripple OFF only)
    slideLeftNeighbor   = nil,
    slideLeftState      = nil,    -- cap_state(leftNeighbor, "end")
    slideRightNeighbor  = nil,
    slideRightState     = nil,    -- cap_state(rightNeighbor, "start")

    -- Live preview
    previewOrig       = nil,      -- per-item original fade values for live AutoXfade preview
  }
end

local G = new_G()

----------------------------------------------------------------
-- FIXED LANES
----------------------------------------------------------------
local function track_has_fixed_lanes(tr)
  return (reaper.GetMediaTrackInfo_Value(tr,"I_FIXEDLANES") or 0) > 0
end

local function same_lane(a,b)
  if not REQUIRE_SAME_LANE then return true end
  if not a or not b then return false end
  if not reaper.ValidatePtr2(0, a, "MediaItem*") then return false end
  if not reaper.ValidatePtr2(0, b, "MediaItem*") then return false end

  local ta = item_track_safe(a)
  local tb = item_track_safe(b)
  if not ta or not tb then return false end

  if (not track_has_fixed_lanes(ta)) or (not track_has_fixed_lanes(tb)) then
    return true
  end

  local ia = reaper.GetMediaItemInfo_Value(a,"I_FIXEDLANE")
  local ib = reaper.GetMediaItemInfo_Value(b,"I_FIXEDLANE")
  if type(ia) ~= "number" or type(ib) ~= "number" then return true end

  return math.floor(ia+0.5) == math.floor(ib+0.5)
end

----------------------------------------------------------------
-- GROUP / TRACK-GROUP HELPERS
----------------------------------------------------------------
local function track_group_has_media_edit(tr)
  if not TrackGroupsOn() then return false end
  if not reaper.GetSetTrackGroupMembershipEx then return false end
  for g=0,31 do
    local lead   = reaper.GetSetTrackGroupMembershipEx(tr,"MEDIA_EDIT_LEAD",g,0,0)
    local follow = reaper.GetSetTrackGroupMembershipEx(tr,"MEDIA_EDIT_FOLLOW",g,0,0)
    if (lead ~= 0) or (follow ~= 0) then return true end
  end
  return false
end

local function boundary_match_for_edge(driver, other, edge, refStart, refEnd)
  if not same_lane(driver, other) then return false end
  local os, oe = item_start(other), item_end(other)
  if edge == "start" then
    return approx(os, refStart, BOUNDARY_TOL)
  else
    return approx(oe, refEnd, BOUNDARY_TOL)
  end
end

local function start_or_end_match(other, refStart, refEnd)
  local os, oe = item_start(other), item_end(other)
  return approx(os, refStart, BOUNDARY_TOL) or approx(oe, refEnd, BOUNDARY_TOL)
end

local function start_and_end_match(other, refStart, refEnd)
  local os, oe = item_start(other), item_end(other)
  return approx(os, refStart, BOUNDARY_TOL) and approx(oe, refEnd, BOUNDARY_TOL)
end

local function enclosed_by(other, refStart, refEnd)
  local os, oe = item_start(other), item_end(other)
  return os >= refStart - BOUNDARY_TOL and oe <= refEnd + BOUNDARY_TOL
end

local function collect_item_group_followers(driver, edge, refStart, refEnd)
  local out = {}
  if not GroupMasterOn() then return out end
  local gid = reaper.GetMediaItemInfo_Value(driver,"I_GROUPID") or 0
  if gid <= 0 then return out end
  local function include(it)
    if it == driver or is_locked(it) then return false end
    return boundary_match_for_edge(driver,it,edge,refStart,refEnd)
  end
  for i=0, reaper.CountMediaItems(0)-1 do
    local it = reaper.GetMediaItem(0,i)
    if valid_item(it) and reaper.GetMediaItemInfo_Value(it,"I_GROUPID")==gid and include(it) then
      out[#out+1]=it
    end
  end
  return out
end

local function collect_trackgroup_followers(driver, edge, refStart, refEnd)
  local out = {}
  if not TrackGroupsOn() then return out end
  local driverTr = reaper.GetMediaItem_Track(driver)
  local members = {}
  local function consider(tr)
    if valid_track(tr) and track_group_has_media_edit(tr) then members[#members+1]=tr end
  end
  consider(driverTr)
  for t=0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0,t)
    if tr ~= driverTr then consider(tr) end
  end
  if #members==0 then return out end

  local useSE, useSAE, useENC = OptSE(), OptSAE(), OptENC()
  local function include(it)
    if is_locked(it) or (REQUIRE_SAME_LANE and not same_lane(driver,it)) then return false end
    if useSAE and start_and_end_match(it,refStart,refEnd) then return true end
    if useSE  and start_or_end_match(it,refStart,refEnd)  then return true end
    if useENC and enclosed_by(it,refStart,refEnd)         then return true end
    if (not useSAE and not useSE and not useENC) then
      return boundary_match_for_edge(driver,it,edge,refStart,refEnd)
    end
    return false
  end

  for _,tr in ipairs(members) do
    for i=0, reaper.CountTrackMediaItems(tr)-1 do
      local it = reaper.GetTrackMediaItem(tr,i)
      if valid_item(it) and it~=driver and include(it) then
        out[#out+1]=it
      end
    end
  end
  return out
end

----------------------------------------------------------------
-- SELECTED TRACKS (Per-Track ripple scope expansion)
----------------------------------------------------------------
local function snapshot_selected_tracks()
  local map = {}
  for i=0, reaper.CountSelectedTracks(0)-1 do
    map[reaper.GetSelectedTrack(0,i)] = true
  end
  return map
end

----------------------------------------------------------------
-- CO-DRIVERS (selected tracks boundary-aligned with primary)
----------------------------------------------------------------
local function collect_codrivers(primary, edge, refBoundary, selectedTracks)
  local out = {}
  local function is_in_scope(tr)
    if RippleAllTracks() then return true end
    if RipplePerTrack() then
      local pTr = reaper.GetMediaItem_Track(primary)
      if tr==pTr then return true end
      return selectedTracks and selectedTracks[tr]
    end
    return false
  end

  for t=0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0,t)
    if is_in_scope(tr) then
      for i=0, reaper.CountTrackMediaItems(tr)-1 do
        local it = reaper.GetTrackMediaItem(tr,i)
        if valid_item(it) and not is_locked(it) and it~=primary and same_lane(primary,it) then
          if edge=="start" and approx(item_start(it), refBoundary, BOUNDARY_TOL) then
            out[#out+1]=it
          elseif edge=="end" and approx(item_end(it), refBoundary, BOUNDARY_TOL) then
            out[#out+1]=it
          end
        end
      end
    end
  end
  return out
end

----------------------------------------------------------------
-- SNAPSHOT DOWNSTREAM / SCOPE
----------------------------------------------------------------
local function build_ripple_track_scope(primary, selectedTracks, editedSet)
  local scope = {}
  if RippleAllTracks() then
    for t=0, reaper.CountTracks(0)-1 do
      scope[reaper.GetTrack(0,t)] = true
    end
  elseif RipplePerTrack() then
    local pTr = reaper.GetMediaItem_Track(primary)
    if valid_track(pTr) then scope[pTr] = true end
    for tr,_ in pairs(selectedTracks or {}) do
      scope[tr] = true
    end
  end
  for it,_ in pairs(editedSet or {}) do
    local tr = valid_item(it) and reaper.GetMediaItem_Track(it) or nil
    if valid_track(tr) then scope[tr] = true end
  end
  return scope
end

local function snapshot_downstream_items(originalEnd, trackScope, excludeSet)
  local snap = {}
  for tr,_ in pairs(trackScope or {}) do
    for i=0, reaper.CountTrackMediaItems(tr)-1 do
      local it = reaper.GetTrackMediaItem(tr,i)
      if valid_item(it) and not (excludeSet and excludeSet[it]) and not is_locked(it) then
        if item_start(it) >= originalEnd - BOUNDARY_TOL then
          snap[it] = true
        end
      end
    end
  end
  return snap
end

-- Build per-track guard table: for each track in scope, record the first
-- downstream item and the latest end-time of any item that sits before it.
-- Single O(N) index pass to group downstream items by track, then one scan
-- per track to find prevEnd.
local function pertrack_first_downstream_and_anchor(originalEnd, trackScope, downstreamSnap)
  -- 1) Build per-track index of downstream items in one pass (O(N))
  local byTrack = {}
  for it,_ in pairs(downstreamSnap or {}) do
    if valid_item(it) then
      local tr = reaper.GetMediaItem_Track(it)
      if valid_track(tr) then
        if not byTrack[tr] then byTrack[tr] = {} end
        byTrack[tr][#byTrack[tr]+1] = it
      end
    end
  end

  -- 2) For each track in scope, find first downstream item and prevEnd (O(N) per track)
  local guard = {}
  for tr,_ in pairs(trackScope or {}) do
    local items = byTrack[tr]
    if items and #items > 0 then
      local first, firstS = nil, math.huge
      for _,it in ipairs(items) do
        local s = item_start(it)
        if s < firstS then firstS, first = s, it end
      end

      if first then
        local prevE = nil
        for i=0, reaper.CountTrackMediaItems(tr)-1 do
          local it2 = reaper.GetTrackMediaItem(tr,i)
          if valid_item(it2) then
            local e2 = item_end(it2)
            if e2 <= firstS + BOUNDARY_TOL then
              if (not prevE) or (e2 > prevE) then prevE = e2 end
            end
          end
        end
        if prevE then guard[tr] = {first=first, prevEnd=prevE} end
      end
    end
  end
  return guard
end

local function build_downstream_with_cutoffs(primary, edge)
  local edited = {}
  for it,_ in pairs(G.editedSet or {}) do edited[it] = true end
  local downstream, enclosed = {}, {}

  if not AnyRippleOn() then return edited, downstream, enclosed end

  local cutoffMap = {}
  for tr,_ in pairs(G.rippleTrackScope or {}) do
    local gp = G.guardPairs and G.guardPairs[tr] or nil
    cutoffMap[tr] = (gp and gp.prevEnd) or G.originalEnd
  end

  local finalBoundary = item_end(primary)
  local function in_scope(tr) return G.rippleTrackScope and G.rippleTrackScope[tr] end

  for t=0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0,t)
    if valid_track(tr) and in_scope(tr) then
      local cutoff = cutoffMap[tr] or G.originalEnd
      for i=0, reaper.CountTrackMediaItems(tr)-1 do
        local it = reaper.GetTrackMediaItem(tr,i)
        if valid_item(it) and not edited[it] and not is_locked(it) then
          local s = item_start(it)
          local e = item_end(it)
          if s >= cutoff - BOUNDARY_TOL then
            downstream[it] = true
            if edge == "end" and (finalBoundary > cutoff + BOUNDARY_TOL) then
              if s >= cutoff - BOUNDARY_TOL and e <= finalBoundary + BOUNDARY_TOL then
                enclosed[it] = true
              end
            end
          end
        end
      end
    end
  end

  return edited, downstream, enclosed
end

local function mark_press_crossfade_pair(left, right)
  if not G.pressCF then G.pressCF = {} end
  local row = G.pressCF[left]
  if not row then
    row = {}
    G.pressCF[left] = row
  end
  row[right] = true
end

local function was_press_crossfade_pair(left, right)
  return G.pressCF and G.pressCF[left] and G.pressCF[left][right] or false
end

local function build_downstream_from_snapshot()
  local edited = {}
  for it,_ in pairs(G.editedSet or {}) do
    edited[it] = true
  end

  local downstream = {}
  local enclosed   = {}

  if not AnyRippleOn() then
    return edited, downstream, enclosed
  end

  for it,_ in pairs(G.downstreamSnap or {}) do
    if valid_item(it) and not is_locked(it) then
      downstream[it] = true
    end
  end

  return edited, downstream, enclosed
end

----------------------------------------------------------------
-- STATE CAPTURE / APPLY TRIM
----------------------------------------------------------------
local function cap_state(it, edge)
  if not valid_item(it) then return nil end
  local tk   = get_take(it)
  local pos  = item_start(it)
  local len  = item_len(it)
  local offs = (tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")) or 0
  return {pos=pos, len=len, offs=offs}
end

-- Returns the delta clamped so the item's length never falls below
-- fade-in + fade-out + EPS. This prevents trimming into existing fades.
--
-- IMPORTANT: reads fade lengths from G.pressXf (press-time snapshot) rather than
-- querying the live item values. During a drag, live_preview_autoxf() may have
-- already rewritten item fades as part of the AutoXfade preview, which would cause
-- the clamp floor to shift mid-gesture. Press-time values are stable.
local function clamp_min_length_for_fades(it, st, edge, delta)
  if not st then return delta end

  -- Prefer press-time fade snapshot; fall back to live query only if pressXf
  -- is not yet populated (e.g. called during press-time alignment itself).
  local xf   = G.pressXf and G.pressXf[it]
  local fin  = (xf and xf.fin  and xf.fin.len)  or reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN")  or 0
  local fout = (xf and xf.fout and xf.fout.len) or reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0

  -- Minimum length = fade-in + fade-out + EPS (body can vanish but fades must survive)
  local minLen = math.max(EPS, fin + fout + EPS)

  -- Corner case: fades already consume most/all of item length — don't force expansion
  if minLen > st.len - EPS then
    minLen = math.max(EPS, st.len - EPS)
  end

  if edge == "start" then
    local newLen = st.len - delta
    if newLen < minLen then
      return st.len - minLen
    end
  else
    local newLen = st.len + delta
    if newLen < minLen then
      return minLen - st.len
    end
  end

  return delta
end

-- Returns the delta clamped to source file / take boundaries only
-- (no fade-length awareness here — see clamp_min_length_for_fades).
local function clamp_to_source_bounds(it, st, edge, delta)
  if not st then return delta end

  local tk = get_take(it)

  if edge == "start" then
    -- Don't go before source start
    if tk then
      local rate = reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1
      if rate == 0 then rate = 1 end
      local newOffs = st.offs + (delta / rate)
      if newOffs < 0 then
        delta = (0 - st.offs) * rate
      end
    end
    if st.len - delta <= EPS then
      delta = st.len - EPS
    end

  else
    -- end edge
    local newLen = st.len + delta
    if newLen <= EPS then
      delta = -st.len + EPS
      newLen = st.len + delta
    end

    if tk then
      local rate = reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1
      if rate == 0 then rate = 1 end
      local arate = math.abs(rate)

      local loopOn = (reaper.GetMediaItemTakeInfo_Value(tk, "B_LOOPSRC") == 1)
      if not loopOn then
        local src    = reaper.GetMediaItemTake_Source(tk)
        local srcLen, isQN = reaper.GetMediaSourceLength(src)
        if isQN then srcLen = reaper.TimeMap2_QNToTime(0, srcLen) end
        srcLen = math.max(0, srcLen or 0)

        local maxLenNoLoop = (srcLen - st.offs) / arate
        if maxLenNoLoop <= EPS then
          delta = -st.len + EPS
        elseif newLen > maxLenNoLoop then
          delta = maxLenNoLoop - st.len
        end
      end
    end
  end

  return delta
end

-- Compose both clamps: source bounds first, then fade-floor.
-- Order matters: fade-floor is applied to the already source-clamped delta
-- so both constraints are satisfied simultaneously.
local function clamp_to_source(it, st, edge, delta)
  if not st or is_locked(it) then return 0 end
  delta = clamp_to_source_bounds(it, st, edge, delta)
  delta = clamp_min_length_for_fades(it, st, edge, delta)
  return delta
end

local function apply_trim(it, st, edge, delta)
  if not valid_item(it) or not st or delta==0 or is_locked(it) then return end
  local tk = get_take(it)
  local rate = (tk and reaper.GetMediaItemTakeInfo_Value(tk,"D_PLAYRATE")) or 1
  if rate==0 then rate=1 end

  if edge=="start" then
    local newPos = st.pos + delta
    local newLen = math.max(EPS, st.len - delta)

    -- BODY_NATIVE_RIPPLE + start edge during drag: keep item left edge fixed on timeline.
    -- During press-time alignment (inPressAlign=true) we DO let the edge move so we can
    -- measure initialPressDelta correctly.
    if BODY_NATIVE_RIPPLE and AnyRippleOn() and not G.inPressAlign then
      newPos = st.pos
    end

    reaper.SetMediaItemInfo_Value(it,"D_POSITION", newPos)
    reaper.SetMediaItemInfo_Value(it,"D_LENGTH",  newLen)

    if tk then
      local newOffs = st.offs + (delta / rate)
      if newOffs < 0 then newOffs = 0 end
      reaper.SetMediaItemTakeInfo_Value(tk,"D_STARTOFFS", newOffs)
    end
  else
    local newLen = math.max(EPS, st.len + delta)
    reaper.SetMediaItemInfo_Value(it,"D_LENGTH", newLen)
  end
end

----------------------------------------------------------------
-- ENVELOPES & MARKERS (for ripple)
----------------------------------------------------------------
local function offset_envelope_after(env, cutoff, delta)
  if not env or delta==0 then return end
  local ai = reaper.CountAutomationItems(env)
  for i=0, ai-1 do
    local p = reaper.GetSetAutomationItemInfo(env,i,"D_POSITION",0,false)
    if p >= cutoff - BOUNDARY_TOL then
      reaper.GetSetAutomationItemInfo(env,i,"D_POSITION", p+delta, true)
    end
  end
  local n = reaper.CountEnvelopePoints(env)
  for i=n-1,0,-1 do
    local ok,t,val,sh,te,se = reaper.GetEnvelopePoint(env,i)
    if ok and t >= cutoff - BOUNDARY_TOL then
      reaper.SetEnvelopePoint(env,i,t+delta,val,sh,te,se,true)
    end
  end
  reaper.Envelope_SortPoints(env)
end

local function offset_track_envs_after(trackSet, cutoff, delta)
  if not MoveEnvWithItems() or delta==0 then return end
  for tr,_ in pairs(trackSet or {}) do
    if valid_track(tr) then
      for e=0, reaper.CountTrackEnvelopes(tr)-1 do
        offset_envelope_after(reaper.GetTrackEnvelope(tr,e), cutoff, delta)
      end
    end
  end
end

local function move_markers_regions_after(cutoff, delta)
  if delta == 0 then return end
  local _, numR, numM = reaper.CountProjectMarkers(0)
  local total = numR + numM
  for i = 0, total - 1 do
    local ok, isrgn, pos, rgnend, name, idx, color = reaper.EnumProjectMarkers3(0, i)
    if ok then
      if pos >= cutoff - BOUNDARY_TOL then
        if isrgn then
          reaper.SetProjectMarker3(0, idx, true, pos + delta, rgnend + delta, name, color)
        else
          reaper.SetProjectMarker3(0, idx, false, pos + delta, 0, name, color)
        end
      elseif isrgn and rgnend >= cutoff - BOUNDARY_TOL then
        reaper.SetProjectMarker3(0, idx, true, pos, rgnend + delta, name, color)
      end
    end
  end
end

-- Translate a set of items, and optionally envelopes and markers.
-- moveEnvelopes: pass true to shift track envelopes (respects MoveEnvWithItems toggle).
-- moveMarkersRegions: pass true to shift markers/regions (only meaningful for RippleAll).
-- cutoff: only items/envelopes/markers at or after this time are moved.
local function batch_translate_items(itemSet, delta, cutoff, trackScope, moveEnvelopes, moveMarkersRegions)
  if delta==0 then return end
  reaper.PreventUIRefresh(1)
  for it,_ in pairs(itemSet or {}) do
    if valid_item(it) and not is_locked(it) then
      local p = item_start(it)
      reaper.SetMediaItemInfo_Value(it,"D_POSITION", p+delta)
    end
  end
  if moveEnvelopes and trackScope and cutoff then
    offset_track_envs_after(trackScope, cutoff, delta)
  end
  if moveMarkersRegions and cutoff then
    move_markers_regions_after(cutoff, delta)
  end
  reaper.PreventUIRefresh(-1)
end

----------------------------------------------------------------
-- CROSSFADES (preserve) + OVERLAP RESOLUTION
----------------------------------------------------------------
local function set_fade_in(it, len, shape)
  reaper.SetMediaItemInfo_Value(it,"D_FADEINLEN", math.max(0,len or 0))
  if shape then reaper.SetMediaItemInfo_Value(it,"C_FADEINSHAPE", shape) end
end

local function set_fade_out(it,len, shape)
  reaper.SetMediaItemInfo_Value(it,"D_FADEOUTLEN", math.max(0,len or 0))
  if shape then reaper.SetMediaItemInfo_Value(it,"C_FADEOUTSHAPE", shape) end
end

local function preserve_crossfade_pair(A, B, wantLen, shapeAout, shapeBin)
  if not valid_item(A) or not valid_item(B) then return end
  local ov = math.max(0, item_end(A) - item_start(B))
  if ov <= BOUNDARY_TOL then return end
  local use = math.min(ov, math.max(0, wantLen or 0))
  local shapeOut = (type(shapeAout) == "number") and shapeAout or DEFAULT_XFADE_SHAPE
  local shapeIn  = (type(shapeBin)  == "number") and shapeBin  or DEFAULT_XFADE_SHAPE
  set_fade_out(A, use, shapeOut)
  set_fade_in (B, use, shapeIn)
end

local function delete_if_tiny(tr, it)
  if not valid_item(it) or is_locked(it) then return end
  if item_len(it) <= SLICE_CLEAN_TOL then
    reaper.DeleteTrackMediaItem(tr, it)
  end
end

local function trim_neighbor_left_and_shorten_fade_in(nei, newStart)
  if not valid_item(nei) or is_locked(nei) then return end
  local oldStart = item_start(nei)
  local oldEnd   = item_end(nei)
  newStart = math.min(newStart or oldStart, oldEnd - EPS)

  local delta = newStart - oldStart
  if math.abs(delta) <= BOUNDARY_TOL then return end

  local tk   = get_take(nei)
  local rate = (tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")) or 1
  if rate == 0 then rate = 1 end
  if tk then
    local offs0 = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
    local offs1 = offs0 + (delta / rate)
    if offs1 < 0 then offs1 = 0 end
    reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", offs1)
  end

  local newLen = math.max(EPS, oldEnd - newStart)
  reaper.SetMediaItemInfo_Value(nei, "D_POSITION", newStart)
  reaper.SetMediaItemInfo_Value(nei, "D_LENGTH",   newLen)

  local fin = reaper.GetMediaItemInfo_Value(nei, "D_FADEINLEN") or 0
  if fin > 0 then
    local fadeEnd_abs = oldStart + fin
    local newFin      = math.max(0, fadeEnd_abs - newStart)
    reaper.SetMediaItemInfo_Value(nei, "D_FADEINLEN", math.min(newFin, newLen - EPS))
  end
end

local function trim_neighbor_right_and_shorten_fade_out(nei, newEnd)
  if not valid_item(nei) or is_locked(nei) then return end

  local oldStart = item_start(nei)
  local oldEnd   = item_end(nei)

  newEnd = math.max(math.min(newEnd or oldEnd, oldEnd), oldStart + EPS)

  if math.abs(newEnd - oldEnd) <= BOUNDARY_TOL then
    return
  end

  local newLen = newEnd - oldStart
  reaper.SetMediaItemInfo_Value(nei, "D_LENGTH", newLen)

  local fout = reaper.GetMediaItemInfo_Value(nei, "D_FADEOUTLEN") or 0
  if fout > 0 then
    local fadeStart_abs = oldEnd - fout

    if newEnd <= fadeStart_abs + BOUNDARY_TOL then
      reaper.SetMediaItemInfo_Value(nei, "D_FADEOUTLEN", 0)
    else
      local newFout = newEnd - fadeStart_abs
      if newFout < 0 then newFout = 0 end
      if newFout > newLen - EPS then newFout = newLen - EPS end
      reaper.SetMediaItemInfo_Value(nei, "D_FADEOUTLEN", newFout)
    end
  end
end

----------------------------------------------------------------
-- Sliding crossfade pair identification (Ripple OFF)
----------------------------------------------------------------
local function is_sliding_crossfade_pair(leftItem, rightItem)
  if not G then return false end
  if not RippleOff() then return false end
  if G.mode ~= "body" then return false end

  if G.edge == "start" and G.slideLeftNeighbor and G.driver then
    local a = G.slideLeftNeighbor
    local b = G.driver
    if (leftItem == a and rightItem == b) or (leftItem == b and rightItem == a) then
      return true
    end
  end

  if G.edge == "end" and G.slideRightNeighbor and G.driver then
    local a = G.driver
    local b = G.slideRightNeighbor
    if (leftItem == a and rightItem == b) or (leftItem == b and rightItem == a) then
      return true
    end
  end

  return false
end

local function resolve_pair(leftItem, rightItem, editedSet)
  local ls, le = item_start(leftItem),  item_end(leftItem)
  local rs      = item_start(rightItem)
  local ov = le - rs
  if ov <= BOUNDARY_TOL then return end

  ----------------------------------------------------------------
  -- Special case 1: crossfade-sliding pair (Ripple OFF).
  -- Leave the overlap and fades exactly as the drag left them.
  ----------------------------------------------------------------
  if is_sliding_crossfade_pair(leftItem, rightItem) then
    return
  end

  ----------------------------------------------------------------
  -- Guard: protect crossfades on the NON-edited edge of the driver
  -- when Ripple is OFF.
  --
  -- Editing A's START edge (C–A–B): skip the A–B pair on the right.
  -- Editing A's END edge  (C–A–B): skip the C–A pair on the left.
  --
  -- NOTE: This guard checks only G.driver (the primary item), not the
  -- full editedSet. Followers at the same boundary will still have their
  -- overlaps resolved here. This is intentional: followers participate
  -- in overlap resolution on both sides so that group/track-group edits
  -- remain consistent. If future requirements change this, extend the
  -- guard to: editedSet and editedSet[leftItem] / editedSet[rightItem].
  ----------------------------------------------------------------
  if RippleOff() and G and G.driver then
    if G.edge == "start" and leftItem == G.driver then
      return
    end
    if G.edge == "end" and rightItem == G.driver then
      return
    end
  end

  ----------------------------------------------------------------
  -- Special case 2: true crossfade present at press time, AutoXfade OFF.
  -- Only when BOTH items had fades at press. Simple overlaps or
  -- single-fade overlaps still obey TrimBehind.
  ----------------------------------------------------------------
  local pressOut = G.pressXf and G.pressXf[leftItem]  and G.pressXf[leftItem].fout or nil
  local pressIn  = G.pressXf and G.pressXf[rightItem] and G.pressXf[rightItem].fin  or nil
  local pressOutLen = pressOut and (pressOut.len or 0) or 0
  local pressInLen  = pressIn  and (pressIn.len  or 0) or 0

  if pressOut and pressIn
     and pressOutLen > BOUNDARY_TOL
     and pressInLen  > BOUNDARY_TOL
     and not AutoXfadeOn()
     and was_press_crossfade_pair(leftItem, rightItem)
  then
    local wantLen  = math.min(pressOut.len or 0, pressIn.len or 0, ov)
    preserve_crossfade_pair(leftItem, rightItem, wantLen, pressOut.shape, pressIn.shape)
    return
  end

  ----------------------------------------------------------------
  -- Normal handling: AutoXfade / TrimBehind / leave overlap.
  ----------------------------------------------------------------
  if AutoXfadeOn() then
    set_fade_out(leftItem,  ov, DEFAULT_XFADE_SHAPE)
    set_fade_in (rightItem, ov, DEFAULT_XFADE_SHAPE)
    return
  end

  if TrimBehindOn() then
    local leftEdited  = editedSet and editedSet[leftItem]  or false
    local rightEdited = editedSet and editedSet[rightItem] or false

    if leftEdited and not rightEdited then
      -- Edited item expanded right into an unedited neighbor: push neighbor back.
      trim_neighbor_left_and_shorten_fade_in(rightItem, le)
      delete_if_tiny(item_track_safe(rightItem), rightItem)
    else
      -- rightEdited and not leftEdited:   edited item expanded left, trim the left neighbor.
      -- both edited:                      trim the left item (arbitrary but consistent choice).
      -- neither edited (shouldn't occur): same fallback, trim left.
      trim_neighbor_right_and_shorten_fade_out(leftItem, rs)
      delete_if_tiny(item_track_safe(leftItem), leftItem)
    end
    return
  end

  -- TrimBehind OFF and AutoXfade OFF: leave overlap as-is
end

local function build_span_per_track_from_edited(editedSet)
  local span={}
  for it,_ in pairs(editedSet or {}) do
    if valid_item(it) then
      local tr = reaper.GetMediaItem_Track(it)
      if valid_track(tr) then
        local rec = span[tr] or {s=math.huge, e=-math.huge}
        local s=item_start(it)
        local e=item_end(it)
        if s < rec.s then rec.s = s end
        if e > rec.e then rec.e = e end
        span[tr]=rec
      end
    end
  end
  return span
end

local function delete_fully_enclosed_neighbors(editedSet)
  if not TrimBehindOn() then return end
  local toDelete = {}
  local editedByTrack = {}
  for it,_ in pairs(editedSet or {}) do
    if valid_item(it) then
      local tr = reaper.GetMediaItem_Track(it)
      if valid_track(tr) then
        local list = editedByTrack[tr]
        if not list then list = {}; editedByTrack[tr] = list end
        list[#list+1] = it
      end
    end
  end
  for tr, editedList in pairs(editedByTrack) do
    local E = {}
    for _,e in ipairs(editedList) do
      if valid_item(e) and not is_locked(e) then
        E[#E+1] = {it=e, s=item_start(e), e=item_end(e)}
      end
    end
    for i=0, reaper.CountTrackMediaItems(tr)-1 do
      local x = reaper.GetTrackMediaItem(tr, i)
      if valid_item(x) and (not editedSet[x]) and (not is_locked(x)) then
        local xs, xe = item_start(x), item_end(x)
        for _,r in ipairs(E) do
          local owner = r.it
          if same_lane(owner, x) then
            if xs >= r.s - BOUNDARY_TOL and xe <= r.e + BOUNDARY_TOL then
              toDelete[x] = true
              break
            end
          end
        end
      end
    end
  end
  for x,_ in pairs(toDelete) do
    local tr = valid_item(x) and reaper.GetMediaItem_Track(x) or nil
    if valid_track(tr) then reaper.DeleteTrackMediaItem(tr, x) end
  end
end

local function resolve_overlaps_within_span(spanPerTrack, editedSet)
  reaper.PreventUIRefresh(1)
  for tr, span in pairs(spanPerTrack or {}) do
    local items = {}
    for i=0, reaper.CountTrackMediaItems(tr)-1 do
      local it = reaper.GetTrackMediaItem(tr,i)
      if valid_item(it) then
        local s=item_start(it)
        local e=item_end(it)
        if e > span.s - BOUNDARY_TOL and s < span.e + BOUNDARY_TOL then
          items[#items+1]=it
        end
      end
    end
    table.sort(items, function(a,b) return item_start(a) < item_start(b) end)
    for i=1, (#items-1) do
      local a=items[i]
      local b=items[i+1]
      if valid_item(a) and valid_item(b) and same_lane(a,b) then
        resolve_pair(a,b, editedSet)
      end
    end
  end
  reaper.PreventUIRefresh(-1)
end

----------------------------------------------------------------
-- LIVE CROSSFADES PREVIEW (AutoXfade-style, Ripple OFF)
----------------------------------------------------------------
local function __ensure_preview_orig(it)
  if not G then return end
  if not G.previewOrig then G.previewOrig = {} end
  if G.previewOrig[it] then return end
  G.previewOrig[it] = {
    fin   = reaper.GetMediaItemInfo_Value(it,"D_FADEINLEN")  or 0,
    fout  = reaper.GetMediaItemInfo_Value(it,"D_FADEOUTLEN") or 0,
    finSh = reaper.GetMediaItemInfo_Value(it,"C_FADEINSHAPE"),
    foutSh= reaper.GetMediaItemInfo_Value(it,"C_FADEOUTSHAPE"),
  }
end

local function preview_clear_all()
  if not G or not G.previewOrig then return end
  reaper.PreventUIRefresh(1)
  for it, rec in pairs(G.previewOrig) do
    if valid_item(it) then
      reaper.SetMediaItemInfo_Value(it,"D_FADEINLEN",  math.max(0, rec.fin  or 0))
      reaper.SetMediaItemInfo_Value(it,"D_FADEOUTLEN", math.max(0, rec.fout or 0))
      if rec.finSh  then reaper.SetMediaItemInfo_Value(it,"C_FADEINSHAPE",  rec.finSh)  end
      if rec.foutSh then reaper.SetMediaItemInfo_Value(it,"C_FADEOUTSHAPE", rec.foutSh) end
    end
  end
  reaper.PreventUIRefresh(-1)
  G.previewOrig = {}
end

local function live_preview_autoxf()
  if not G then return end
  if AnyRippleOn() then return end
  if not AutoXfadeOn() then return end
  if G.mode ~= "body" then return end

  -- T = minimum overlap (px) + hysteresis (px), converted to seconds.
  -- Overlaps smaller than T won't get a preview fade drawn.
  local T = px_to_time(PREVIEW_MIN_FADE_PX) + px_to_time(PREVIEW_HYST_PX)
  if T < 0 then T = 0 end

  preview_clear_all()

  local tracks = {}
  for it,_ in pairs(G.editedSet or {}) do
    local tr = valid_item(it) and item_track_safe(it) or nil
    if valid_track(tr) then tracks[tr] = true end
  end
  if next(tracks) == nil then return end

  reaper.PreventUIRefresh(1)
  for tr,_ in pairs(tracks) do
    local list = {}
    for i=0, reaper.CountTrackMediaItems(tr)-1 do
      local it = reaper.GetTrackMediaItem(tr,i)
      if valid_item(it) then list[#list+1] = it end
    end
    table.sort(list, function(a,b) return item_start(a) < item_start(b) end)

    for i=1, (#list-1) do
      local A, B = list[i], list[i+1]
      if valid_item(A) and valid_item(B) and same_lane(A,B) then
        local ov = math.max(0, item_end(A) - item_start(B))
        if ov > T then
          __ensure_preview_orig(A)
          __ensure_preview_orig(B)
          set_fade_out(A, ov, DEFAULT_XFADE_SHAPE)
          set_fade_in (B, ov, DEFAULT_XFADE_SHAPE)
        end
      end
    end
  end
  reaper.PreventUIRefresh(-1)
end

----------------------------------------------------------------
-- Restore press-time crossfade intent
-- Scoped to rippleTrackScope + driver's track: pressXf is only populated
-- for items within gesture reach, so iterating the full project is unnecessary.
----------------------------------------------------------------
local function restore_press_crossfades(editedSet, pressXf)
  if not pressXf then return end
  reaper.PreventUIRefresh(1)

  local function try_restore_pair(left, right, wantOut, wantIn)
    if not (valid_item(left) and valid_item(right)) then return end
    if not same_lane(left, right) then return end
    local ov = math.max(0, item_end(left) - item_start(right))
    if ov <= BOUNDARY_TOL then return end

    local useOut = wantOut and math.max(0, wantOut.len or 0) or nil
    local useIn  = wantIn  and math.max(0, wantIn.len  or 0) or nil

    local wantLen
    if useOut and useIn then
      wantLen = math.min(useOut, useIn, ov)
    elseif useOut then
      wantLen = math.min(useOut, ov)
    elseif useIn then
      wantLen = math.min(useIn, ov)
    else
      wantLen = ov
    end

    local shapeOut = wantOut and wantOut.shape
    local shapeIn  = wantIn  and wantIn.shape
    preserve_crossfade_pair(left, right, wantLen, shapeOut, shapeIn)
  end

  -- Build the scoped track set: ripple scope + driver's own track
  local scopedTracks = {}
  for tr,_ in pairs(G.rippleTrackScope or {}) do
    scopedTracks[tr] = true
  end
  if G.driver then
    local dTr = item_track_safe(G.driver)
    if valid_track(dTr) then scopedTracks[dTr] = true end
  end

  for tr,_ in pairs(scopedTracks) do
    if valid_track(tr) then
      local L = {}
      for i=0, reaper.CountTrackMediaItems(tr)-1 do
        local it = reaper.GetTrackMediaItem(tr,i)
        if valid_item(it) then L[#L+1] = it end
      end
      table.sort(L, function(a,b) return item_start(a) < item_start(b) end)

      for i=1, (#L-1) do
        local A, B = L[i], L[i+1]
        if same_lane(A,B) and was_press_crossfade_pair(A,B) then
          local xfA = pressXf[A]
          local xfB = pressXf[B]
          local wantOut = xfA and xfA.fout or nil
          local wantIn  = xfB and xfB.fin  or nil
          if wantOut or wantIn then
            try_restore_pair(A, B, wantOut, wantIn)
          end
        end
      end
    end
  end

  reaper.PreventUIRefresh(-1)
end

----------------------------------------------------------------
-- PRESS CLASSIFICATION / CROSSFADE SEAMS
----------------------------------------------------------------
local function find_left_crossfade_end(driver)
  if not valid_item(driver) then return nil end
  local tr = item_track_safe(driver)
  if not valid_track(tr) then return nil end

  local aStart = item_start(driver)
  local bestEnd, bestItem = nil, nil

  for i = 0, reaper.CountTrackMediaItems(tr)-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if valid_item(it) and it ~= driver and same_lane(driver, it) then
      local s = item_start(it)
      local e = item_end(it)
      if e > aStart + BOUNDARY_TOL and s < aStart - BOUNDARY_TOL then
        if (not bestEnd) or (e < bestEnd) then
          bestEnd, bestItem = e, it
        end
      end
    end
  end

  return bestEnd, bestItem
end

local function find_right_crossfade_start(driver)
  if not valid_item(driver) then return nil end
  local tr = item_track_safe(driver)
  if not valid_track(tr) then return nil end

  local aStart = item_start(driver)
  local aEnd   = item_end(driver)
  local bestSeam, bestItem = nil, nil

  for i = 0, reaper.CountTrackMediaItems(tr)-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if valid_item(it) and it ~= driver and same_lane(driver, it) then
      local s = item_start(it)
      local e = item_end(it)
      if s >= aStart - BOUNDARY_TOL and s < aEnd - BOUNDARY_TOL and e > s + BOUNDARY_TOL then
        if (not bestSeam) or (s < bestSeam) then
          bestSeam, bestItem = s, it
        end
      end
    end
  end

  return bestSeam, bestItem
end

local function in_fade_halo(it, tRaw)
  if not valid_item(it) then return false end

  local s    = item_start(it)
  local e    = item_end(it)
  local fin  = reaper.GetMediaItemInfo_Value(it,"D_FADEINLEN")  or 0
  local fout = reaper.GetMediaItemInfo_Value(it,"D_FADEOUTLEN") or 0
  local haloT = px_to_time(FADE_HALO_PX)

  if fin > 0 then
    local fadeInStart = s
    local fadeInEnd   = s + fin
    if tRaw >= (fadeInStart - haloT) and tRaw <= (fadeInEnd + haloT) then
      return true
    end
  end

  if fout > 0 then
    local fadeOutStart = e - fout
    local fadeOutEnd   = e
    if tRaw >= (fadeOutStart - haloT) and tRaw <= (fadeOutEnd + haloT) then
      return true
    end
  end

  return false
end

local function classify_press_no_fade(it, tRaw)
  local s = item_start(it)
  local e = item_end(it)
  local fin  = reaper.GetMediaItemInfo_Value(it,"D_FADEINLEN")  or 0
  local fout = reaper.GetMediaItemInfo_Value(it,"D_FADEOUTLEN") or 0

  -- 1) Native fade zone + halo → let REAPER handle completely
  if in_fade_halo(it, tRaw) then
    return nil
  end

  -- 2) Native edge tolerance → treat as native edge
  local edgeTolT = px_to_time(EDGE_GRAB_PX)
  if math.abs(tRaw - s) <= edgeTolT then return {modeKind="edge", edge="start"} end
  if math.abs(tRaw - e) <= edgeTolT then return {modeKind="edge", edge="end"}   end

  -- 3) Body span between fade seams
  local bodyL = s + math.max(0, fin)
  local bodyR = e - math.max(0, fout)
  local minBody = px_to_time(BODY_SAFE_PX) + BOUNDARY_TOL
  if (bodyR - bodyL) >= minBody and tRaw >= bodyL and tRaw <= bodyR then
    local mid = bodyL + (bodyR - bodyL) * 0.5
    return {modeKind="body", edge=(tRaw <= mid) and "start" or "end"}
  end

  -- 4) Fallback: geometric midpoint (no/very small body span)
  local mid = s + (e - s) * 0.5
  return {modeKind="body", edge=(tRaw <= mid) and "start" or "end"}
end

----------------------------------------------------------------
-- FREEZE SCOPE SUB-FUNCTIONS
-- Each handles exactly one responsibility; called in sequence by freeze_scope().
-- Ordering constraint: ripple scope depends on editedSet; right-xfade-neighbor
-- depends on downstreamSnap; guardPairs depends on rightXfadeNeighbor being in snap.
----------------------------------------------------------------

local function freeze_drivers_and_followers(primary, edge)
  G.selectedTrackSet = snapshot_selected_tracks()

  local s = item_start(primary)
  local e = item_end(primary)
  local refBoundary = (edge == "start") and s or e
  G.pressBoundary = refBoundary

  local drivers = { primary }
  local codr = collect_codrivers(primary, edge, refBoundary, G.selectedTrackSet)
  for _, it in ipairs(codr) do
    drivers[#drivers+1] = it
  end

  local followers, seen = {}, {}
  local function add_unique(it)
    if valid_item(it) and not seen[it] then
      seen[it] = true
      followers[#followers+1] = it
    end
  end

  for _, d in ipairs(drivers) do
    local ds, de = item_start(d), item_end(d)
    for _, it in ipairs(collect_item_group_followers(d, edge, ds, de)) do
      add_unique(it)
    end
    for _, it in ipairs(collect_trackgroup_followers(d, edge, ds, de)) do
      add_unique(it)
    end
  end

  G.editedSet = {}
  for _, it in ipairs(drivers)   do G.editedSet[it] = true end
  for _, it in ipairs(followers) do G.editedSet[it] = true end

  G.initStates = {}
  for it,_ in pairs(G.editedSet) do
    G.initStates[it] = cap_state(it, edge)
  end
end

local function freeze_ripple_scope(primary)
  G.originalEnd      = item_end(primary)
  G.rippleTrackScope = build_ripple_track_scope(primary, G.selectedTrackSet, G.editedSet)

  local exclude = {}
  for it,_ in pairs(G.editedSet) do
    exclude[it] = true
  end

  G.downstreamSnap = snapshot_downstream_items(G.originalEnd, G.rippleTrackScope, exclude)
end

-- Snapshots press-time fade lengths for all items within gesture reach.
-- Scoped to rippleTrackScope + driver's track; the full project walk is unnecessary
-- because pressXf is only ever read for items adjacent to or within the gesture.
local function freeze_fade_snapshots(primary)
  G.pressXf = {}

  local scopedTracks = {}
  for tr,_ in pairs(G.rippleTrackScope or {}) do
    scopedTracks[tr] = true
  end
  local dTr = item_track_safe(primary)
  if valid_track(dTr) then scopedTracks[dTr] = true end

  for tr,_ in pairs(scopedTracks) do
    if valid_track(tr) then
      for i = 0, reaper.CountTrackMediaItems(tr)-1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        if valid_item(it) then
          local fin   = reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN")  or 0
          local fout  = reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0
          local finSh = reaper.GetMediaItemInfo_Value(it, "C_FADEINSHAPE")
          local foutSh= reaper.GetMediaItemInfo_Value(it, "C_FADEOUTSHAPE")
          G.pressXf[it] = {
            fin  = { len = fin,  shape = finSh  },
            fout = { len = fout, shape = foutSh },
          }
        end
      end
    end
  end
end

-- Identifies all true crossfade pairs (both neighbors have fades) present at press time.
-- Populates G.pressCF only — no side effects on other G fields.
local function freeze_crossfade_pair_detection()
  G.pressCF = {}

  for t = 0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0, t)
    if valid_track(tr) then
      local list = {}
      for i = 0, reaper.CountTrackMediaItems(tr)-1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        if valid_item(it) then list[#list+1] = it end
      end
      table.sort(list, function(a,b) return item_start(a) < item_start(b) end)

      for i = 1, (#list-1) do
        local A, B = list[i], list[i+1]
        if same_lane(A,B) then
          local ov_press = math.max(0, item_end(A) - item_start(B))
          if ov_press > BOUNDARY_TOL then
            local foutA = reaper.GetMediaItemInfo_Value(A,"D_FADEOUTLEN") or 0
            local finB  = reaper.GetMediaItemInfo_Value(B,"D_FADEINLEN")  or 0
            if foutA > BOUNDARY_TOL and finB > BOUNDARY_TOL then
              mark_press_crossfade_pair(A, B)
            end
          end
        end
      end
    end
  end
end

-- Finds the immediate right-side crossfade neighbor of the driver (if any),
-- adds it to G.downstreamSnap so it participates in ripple, and then computes
-- guardPairs. Must be called AFTER freeze_crossfade_pair_detection() and
-- AFTER G.downstreamSnap is populated by freeze_ripple_scope().
local function freeze_right_xfade_neighbor(primary)
  G.rightXfadeNeighbor = nil

  if AnyRippleOn() then
    local tr = item_track_safe(primary)
    if valid_track(tr) then
      local list = {}
      for i = 0, reaper.CountTrackMediaItems(tr)-1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        if valid_item(it) and same_lane(primary, it) then
          list[#list+1] = it
        end
      end
      table.sort(list, function(a, b) return item_start(a) < item_start(b) end)

      for idx, it in ipairs(list) do
        if it == primary then
          local right = list[idx + 1]
          if right and valid_item(right) and not is_locked(right) then
            local eA = item_end(primary)
            local sB = item_start(right)
            if sB < eA - BOUNDARY_TOL then
              G.rightXfadeNeighbor = right
              G.downstreamSnap[right] = true
            end
          end
          break
        end
      end
    end
  end

  -- guardPairs depends on the complete downstreamSnap (including rightXfadeNeighbor)
  G.guardPairs = pertrack_first_downstream_and_anchor(
                    G.originalEnd, G.rippleTrackScope, G.downstreamSnap
                 )
end

local function freeze_slide_neighbors(primary, edge)
  G.slideLeftNeighbor  = nil
  G.slideLeftState     = nil
  G.slideRightNeighbor = nil
  G.slideRightState    = nil

  if not RippleOff() then return end

  local tr = item_track_safe(primary)
  if not valid_track(tr) then return end

  local list = {}
  for i = 0, reaper.CountTrackMediaItems(tr)-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if valid_item(it) and same_lane(primary, it) then
      list[#list+1] = it
    end
  end
  table.sort(list, function(a,b) return item_start(a) < item_start(b) end)

  local idxPrimary = nil
  for idx, it in ipairs(list) do
    if it == primary then idxPrimary = idx break end
  end
  if not idxPrimary then return end

  local left  = list[idxPrimary - 1]
  local right = list[idxPrimary + 1]

  local finPrimary  = reaper.GetMediaItemInfo_Value(primary, "D_FADEINLEN")  or 0
  local foutPrimary = reaper.GetMediaItemInfo_Value(primary, "D_FADEOUTLEN") or 0

  -- Left neighbor: true C–A crossfade (both items must have fades)
  if left and valid_item(left) and not is_locked(left) then
    local ov       = item_end(left) - item_start(primary)
    local foutLeft = reaper.GetMediaItemInfo_Value(left, "D_FADEOUTLEN") or 0
    if ov > BOUNDARY_TOL and foutLeft > BOUNDARY_TOL and finPrimary > BOUNDARY_TOL then
      G.slideLeftNeighbor = left
      G.slideLeftState    = cap_state(left, "end")
    end
  end

  -- Right neighbor: true A–B crossfade (both items must have fades)
  if right and valid_item(right) and not is_locked(right) then
    local ov       = item_end(primary) - item_start(right)
    local finRight = reaper.GetMediaItemInfo_Value(right, "D_FADEINLEN") or 0
    if ov > BOUNDARY_TOL and foutPrimary > BOUNDARY_TOL and finRight > BOUNDARY_TOL then
      G.slideRightNeighbor = right
      G.slideRightState    = cap_state(right, "start")
    end
  end
end

-- Public entry point. Ordering is significant — see sub-function comments.
local function freeze_scope(primary, edge)
  freeze_drivers_and_followers(primary, edge)
  freeze_ripple_scope(primary)
  freeze_fade_snapshots(primary)
  freeze_crossfade_pair_detection()
  freeze_right_xfade_neighbor(primary)   -- mutates downstreamSnap; must follow both above
  freeze_slide_neighbors(primary, edge)
end

----------------------------------------------------------------
-- RIPPLE FINALIZATION
----------------------------------------------------------------
local function finalize_ripple(primary, edge, effSincePress, totalOverride)
  if not AnyRippleOn() then return end
  if not primary or not reaper.ValidatePtr2(0, primary, "MediaItem*") then return end
  if edge ~= "start" and edge ~= "end" then return end
  if not G then return end

  if (G.modeKind == "edge") and RippleEdgeOptionOn() then
    return
  end

  local total = (totalOverride ~= nil) and totalOverride
                or ((G.initialPressDelta or 0) + (effSincePress or 0))

  if math.abs(total or 0) <= (BOUNDARY_TOL or 0.001) then return end

  local edited, downstream, enclosed = build_downstream_with_cutoffs(primary, edge)
  local moveMarkers = RippleAllTracks() and MarkersRegionsRippleAll()

  -- For start-edge body gestures with RIPPLE_INCLUDE_DRIVER_ON_MOUSEUP:
  -- At mouse-up the edited items are at their trimmed positions.
  -- We translate them back by -total so the downstream shift is measured
  -- from the original boundary. Invariant: after this call, edited items
  -- are at pre-press positions and downstream items have been offset by
  -- ±total from originalEnd.
  if RIPPLE_INCLUDE_DRIVER_ON_MOUSEUP and edge == "start" then
    batch_translate_items(edited, -total, nil, nil, false, false)
  end

  if edge == "end" then
    for it,_ in pairs(enclosed or {}) do downstream[it] = true end
  end

  local rippleDelta = (edge == "start") and (-total) or (total)
  batch_translate_items(downstream, rippleDelta, G.originalEnd, G.rippleTrackScope, true, moveMarkers)
end

local function finalize_crossfades_and_overlaps(primary)
  if TrimBehindOn() then
    delete_fully_enclosed_neighbors(G.editedSet)
  end

  local span = build_span_per_track_from_edited(G.editedSet)
  resolve_overlaps_within_span(span, G.editedSet)

  if not AutoXfadeOn() then
    restore_press_crossfades(G.editedSet, G.pressXf)
  end

  for tr,_ in pairs(span) do
    for i = reaper.CountTrackMediaItems(tr)-1, 0, -1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      if valid_item(it) and item_len(it) <= SLICE_CLEAN_TOL then
        reaper.DeleteTrackMediaItem(tr, it)
      end
    end
  end
end

----------------------------------------------------------------
-- CURSORS
----------------------------------------------------------------
local cursor_default    = reaper.JS_Mouse_LoadCursor(32512)
local cursor_trim_left  = reaper.JS_Mouse_LoadCursor(417) or reaper.JS_Mouse_LoadCursor(32644) or cursor_default
local cursor_trim_right = reaper.JS_Mouse_LoadCursor(418) or reaper.JS_Mouse_LoadCursor(32644) or cursor_default

local lastSetByUs = false

local function cursor_for_mode(edge)
  return (edge == "start") and cursor_trim_left or cursor_trim_right
end

local function pick_cursor_for_hover(hov, tRaw)
  if not valid_item(hov) or is_locked(hov) then return nil end

  if in_native_fade_or_edge_zone() then
    return nil
  end

  if in_fade_halo(hov, tRaw) then
    return nil
  end

  local s = item_start(hov)
  local e = item_end(hov)
  local fin  = reaper.GetMediaItemInfo_Value(hov,"D_FADEINLEN")  or 0
  local fout = reaper.GetMediaItemInfo_Value(hov,"D_FADEOUTLEN") or 0

  local edgeTolT = px_to_time(EDGE_GRAB_PX)
  if math.abs(tRaw - s) <= edgeTolT then return nil end
  if math.abs(tRaw - e) <= edgeTolT then return nil end

  local bodyL = s + math.max(0, fin)
  local bodyR = e - math.max(0, fout)
  local minBody = px_to_time(BODY_SAFE_PX) + BOUNDARY_TOL
  if (bodyR - bodyL) >= minBody and tRaw >= bodyL and tRaw <= bodyR then
    local mid = bodyL + (bodyR - bodyL)*0.5
    return (tRaw <= mid) and cursor_trim_left or cursor_trim_right
  end

  local mid = s + (e - s) * 0.5
  return (tRaw <= mid) and cursor_trim_left or cursor_trim_right
end

----------------------------------------------------------------
-- UNDO + CLEANUP
----------------------------------------------------------------
local function begin_undo()
  if not G.undoOpen then
    reaper.Undo_BeginBlock()
    G.undoOpen=true
  end
end

local function end_undo(msg)
  if G.undoOpen then
    reaper.Undo_EndBlock(msg or "Trim items (Body, v7)", -1)
    G.undoOpen=false
  end
end

local NS         = "ReaTooled"
local RUN_KEY    = "TrimToolWorkerRunning"
local KILL_KEY   = "KillTrimTool"
local HEARTBEAT  = "TrimToolHeartbeat"

local __edgeRipplePrev    = nil
local __edgeRippleForced  = false

if reaper.HasExtState(NS, RUN_KEY) then return end
reaper.SetExtState(NS, RUN_KEY, "1", false)

__edgeRipplePrev = RippleEdgeOptionOn()
if not __edgeRipplePrev then
  set_toggle(EDGE_RIPPLE_CMD, true)
  __edgeRippleForced = true
end

local function beat()
  reaper.SetExtState(NS, HEARTBEAT, tostring(reaper.time_precise()), false)
end

local function rt_kill_requested()
  return reaper.HasExtState(NS, KILL_KEY)
end

local __rt_cleanup_done = false
local function rt_cleanup()
  if __rt_cleanup_done then return end
  __rt_cleanup_done = true
  if cursor_default then reaper.JS_Mouse_SetCursor(cursor_default) end
  if G and G.undoOpen then end_undo() end

  if __edgeRippleForced and (__edgeRipplePrev ~= nil) then
    set_toggle(EDGE_RIPPLE_CMD, __edgeRipplePrev)
    __edgeRippleForced = false
  end

  pcall(reaper.DeleteExtState, NS, RUN_KEY, false)
  pcall(reaper.DeleteExtState, NS, RUN_KEY, true)
  pcall(reaper.DeleteExtState, NS, KILL_KEY, false)
  pcall(reaper.DeleteExtState, NS, KILL_KEY, true)
end

if type(reaper.atexit)=="function" then
  reaper.atexit(rt_cleanup)
end

----------------------------------------------------------------
-- PRESS ALIGNMENT HELPERS
----------------------------------------------------------------

-- Align edge at press time using fade-seam snap reference.
-- start edge: sets item start so (start + fade-in) = targetTime
-- end   edge: sets item end   so (end   - fade-out) = targetTime
local function press_time_align_to_snap(edge, targetTime)
  G.inPressAlign = true
  for it, st in pairs(G.initStates or {}) do
    if valid_item(it) and (not is_locked(it)) and st then
      local fin  = reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN")  or 0
      local fout = reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0

      if edge == "start" then
        local desiredEdgeAbs = (targetTime or st.pos) - math.max(0, fin)
        local delta = clamp_to_source(it, st, edge, desiredEdgeAbs - st.pos)
        apply_trim(it, st, edge, delta)
      else
        local desiredEdgeAbs = (targetTime or (st.pos + st.len)) + math.max(0, fout)
        local delta = clamp_to_source(it, st, edge, desiredEdgeAbs - (st.pos + st.len))
        apply_trim(it, st, edge, delta)
      end
    end
  end
  G.inPressAlign = false
end

-- Sliding crossfade press-time alignment (Ripple OFF, true CF neighbor present).
-- Moves the crossfade seam (C end or B start) to the snapped cursor while
-- trimming BOTH items by the same delta, preserving crossfade length.
-- Resets pressBoundary, initialPressDelta, initStates, slide states, and
-- initialMouseRaw — no further state fixup needed after calling this.
local function press_time_align_sliding_crossfade(cursorTime)
  if not G or G.mode ~= "body" or not G.driver then return end
  if not RippleOff() then return end

  local driver = G.driver
  local edge   = G.edge

  local function apply_sliding_delta(wantDelta, nei, neiState, driverState, neiEdge, drvEdge)
    if not (valid_item(driver) and valid_item(nei)) then return end
    if not (driverState and neiState) then return end
    if is_locked(driver) or is_locked(nei) then return end

    local dDrv = clamp_to_source(driver, driverState, drvEdge, wantDelta)
    local dNei = clamp_to_source(nei,    neiState,    neiEdge, wantDelta)

    -- Use the more conservative (smallest magnitude) delta
    local applyDelta = (math.abs(dDrv) < math.abs(dNei)) and dDrv or dNei

    dDrv = clamp_to_source(driver, driverState, drvEdge, applyDelta)
    dNei = clamp_to_source(nei,    neiState,    neiEdge, applyDelta)

    reaper.PreventUIRefresh(1)
    apply_trim(driver, driverState, drvEdge, dDrv)
    apply_trim(nei,    neiState,    neiEdge, dNei)
    reaper.PreventUIRefresh(-1)
  end

  if edge == "end" and G.slideRightNeighbor and G.slideRightState then
    local nei      = G.slideRightNeighbor
    local seamTime = item_start(nei)
    local ref      = seamTime
    local snapDelta0 = snapped_delta_from_raw(cursorTime - ref, ref, 0)
    local wantDelta  = ref + snapDelta0 - seamTime

    local driverState = G.initStates and G.initStates[driver]
    apply_sliding_delta(wantDelta, nei, G.slideRightState, driverState, "start", "end")

  elseif edge == "start" and G.slideLeftNeighbor and G.slideLeftState then
    local nei      = G.slideLeftNeighbor
    local seamTime = item_end(nei)
    local ref      = seamTime
    local snapDelta0 = snapped_delta_from_raw(cursorTime - ref, ref, 0)
    local wantDelta  = ref + snapDelta0 - seamTime

    local driverState = G.initStates and G.initStates[driver]
    apply_sliding_delta(wantDelta, nei, G.slideLeftState, driverState, "end", "start")
  else
    return
  end

  G.pressBoundary     = current_edge_pos(driver, edge)
  G.initialPressDelta = 0

  G.initStates = {}
  for it,_ in pairs(G.editedSet or {}) do
    G.initStates[it] = cap_state(it, edge)
  end

  if G.slideRightNeighbor then
    G.slideRightState = cap_state(G.slideRightNeighbor, "start")
  end
  if G.slideLeftNeighbor then
    G.slideLeftState = cap_state(G.slideLeftNeighbor, "end")
  end

  G.initialMouseRaw = cursorTime
end

----------------------------------------------------------------
-- MAIN LOOP – sub-handlers dispatched by mode
----------------------------------------------------------------
local locked_cursor  = nil
local prevMouseDown  = false

local function hovered_item()
  local x,y = reaper.GetMousePosition()
  local it = reaper.GetItemFromPoint(x,y,false)
  return valid_item(it) and it or nil
end

local function handle_hover(hov, mTimeRaw)
  if __rt_allow_custom_cursor_now() and valid_item(hov) and not is_locked(hov) then
    local c = pick_cursor_for_hover(hov, mTimeRaw)
    if c then
      reaper.JS_Mouse_SetCursor(c)
      lastSetByUs = true
    else
      if lastSetByUs then
        reaper.JS_Mouse_SetCursor(cursor_default)
        lastSetByUs = false
      end
    end
  else
    reaper.JS_Mouse_SetCursor(cursor_default)
    lastSetByUs = false
  end
end

-- Default snap strategy: snap edge to nearest grid, using CF seam as reference.
local function do_press_snap_default(pressBoundary, mTimeRaw)
  local ref = pressBoundary
  local leftEnd,  leftNei    = find_left_crossfade_end(G.driver)
  local rightStart, rightNei = find_right_crossfade_start(G.driver)

  G.pressLeftXfadeEndAtPress = leftEnd
  G.pressLeftXfadeNeighbor   = leftNei
  G.pressXfadeStartAtPress   = rightStart
  G.pressXfadeNeighbor       = rightNei

  if G.edge == "start" and leftEnd then
    ref = leftEnd
  elseif G.edge == "end" and rightStart then
    ref = rightStart
  end

  local snapDelta0    = snapped_delta_from_raw((mTimeRaw - ref), ref, 0)
  local targetAtPress = ref + snapDelta0

  press_time_align_to_snap(G.edge, targetAtPress)

  G.pressBoundary     = (G.edge == "start") and item_start(G.driver) or item_end(G.driver)
  G.initialPressDelta = G.pressBoundary - pressBoundary

  if BODY_NATIVE_RIPPLE and AnyRippleOn() and G.edge == "start" then
    local edited, downstream = build_downstream_from_snapshot()
    local rippleDelta = -(G.initialPressDelta or 0)

    if math.abs(rippleDelta) >= LIVE_RIPPLE_MIN_DT then
      local moveMarkers = RippleAllTracks() and MarkersRegionsRippleAll()
      batch_translate_items(edited,     rippleDelta, nil, nil, false, false)
      batch_translate_items(downstream, rippleDelta, G.originalEnd, G.rippleTrackScope, true, moveMarkers)
    end

    G.initialPressDelta = 0
  end

  G.initStates = {}
  for it,_ in pairs(G.editedSet or {}) do
    G.initStates[it] = cap_state(it, G.edge)
  end

  local leftEnd2,  leftNei2    = find_left_crossfade_end(G.driver)
  local rightStart2, rightNei2 = find_right_crossfade_start(G.driver)

  G.pressLeftXfadeEndAtPress = leftEnd2
  G.pressLeftXfadeNeighbor   = leftNei2
  G.pressXfadeStartAtPress   = rightStart2
  G.pressXfadeNeighbor       = rightNei2

  G.pressBoundary   = (G.edge == "start") and item_start(G.driver) or item_end(G.driver)
  G.initialMouseRaw = mTimeRaw
end

local function handle_press(hov, mTimeRaw)
  if in_native_fade_or_edge_zone() then
    locked_cursor = nil
    return
  end

  local cls = classify_press_no_fade(hov, mTimeRaw)

  if not cls or cls.modeKind == "edge" then
    locked_cursor = nil
    return
  end

  G.mode    = "body"
  G.driver  = hov
  G.edge    = cls.edge
  G.modeKind = cls.modeKind
  G.initialMouseRaw = mTimeRaw
  -- rippleApplied and initialPressDelta are already 0 from new_G()

  begin_undo()
  freeze_scope(hov, G.edge)

  locked_cursor = cursor_for_mode(G.edge)
  if __rt_allow_custom_cursor_now() and locked_cursor then
    reaper.JS_Mouse_SetCursor(locked_cursor)
  else
    reaper.JS_Mouse_SetCursor(cursor_default)
  end

  local pressBoundary = (G.edge == "start") and item_start(G.driver) or item_end(G.driver)

  if BODY_SET_EDGE_ON_PRESS then
    local slidingCrossfade = RippleOff() and (
      (G.edge == "start" and G.slideLeftNeighbor) or
      (G.edge == "end"   and G.slideRightNeighbor)
    )

    if slidingCrossfade then
      -- Sliding strategy: press_time_align_sliding_crossfade moves the CF seam
      -- to the cursor and fully resets pressBoundary / initStates / slide states.
      press_time_align_sliding_crossfade(mTimeRaw)
    else
      do_press_snap_default(pressBoundary, mTimeRaw)
    end
  else
    G.pressBoundary   = pressBoundary
    G.initialMouseRaw = mTimeRaw
  end
end

local function handle_drag(mTimeRaw)
  local pressBoundary = (G.edge=="start")
    and (G.pressBoundary or item_start(G.driver))
     or (G.pressBoundary or item_end(G.driver))

  local rawDelta = (mTimeRaw - G.initialMouseRaw)
  local delta    = snapped_delta_from_raw(rawDelta, pressBoundary, px_to_time(DRAG_DEADBAND_PX))

  do
    local stD = G.initStates and G.initStates[G.driver]
    if stD and valid_item(G.driver) and (not is_locked(G.driver)) then
      delta = clamp_to_source(G.driver, stD, G.edge, delta)
    end
  end

  if __rt_allow_custom_cursor_now() and locked_cursor then
    reaper.JS_Mouse_SetCursor(locked_cursor)
  else
    reaper.JS_Mouse_SetCursor(cursor_default)
  end

  -- Pre-compute the sliding-neighbor exclusion set once, avoiding per-item
  -- per-frame function calls in the hot loop below.
  local skipItem = nil
  if RippleOff() then
    if G.edge == "start" and G.slideLeftNeighbor then
      skipItem = G.slideLeftNeighbor
    elseif G.edge == "end" and G.slideRightNeighbor then
      skipItem = G.slideRightNeighbor
    end
  end

  for it, st in pairs(G.initStates or {}) do
    if it ~= skipItem and valid_item(it) and (not is_locked(it)) then
      if DEBUG and not st then
        dbg("WARNING: nil initState for item", tostring(it), "— skipping")
      end
      if st then
        local d = clamp_to_source(it, st, G.edge, delta)
        apply_trim(it, st, G.edge, d)
      end
    end
  end

  -- Crossfade sliding (Ripple OFF only) — skipItem is the neighbor to co-trim
  if skipItem then
    if G.edge == "start" and G.slideLeftState then
      if valid_item(skipItem) and not is_locked(skipItem) then
        local dN = clamp_to_source(skipItem, G.slideLeftState, "end", delta)
        apply_trim(skipItem, G.slideLeftState, "end", dN)
      end
    elseif G.edge == "end" and G.slideRightState then
      if valid_item(skipItem) and not is_locked(skipItem) then
        local dN = clamp_to_source(skipItem, G.slideRightState, "start", delta)
        apply_trim(skipItem, G.slideRightState, "start", dN)
      end
    end
  end

  live_preview_autoxf()

  if BODY_NATIVE_RIPPLE and AnyRippleOn() and not (G.modeKind == "edge" and RippleEdgeOptionOn()) then
    local edited, downstream, enclosed = build_downstream_from_snapshot()

    local totalEdgeMove = (G.initialPressDelta or 0) + delta
    local targetRipple  = (G.edge == "start") and (-totalEdgeMove) or totalEdgeMove
    local diff          = targetRipple - (G.rippleApplied or 0)

    if math.abs(diff) >= LIVE_RIPPLE_MIN_DT then
      local moveMarkers = RippleAllTracks() and MarkersRegionsRippleAll()

      if G.edge == "start" then
        batch_translate_items(downstream, diff, G.originalEnd, G.rippleTrackScope, true, moveMarkers)
      else
        for it,_ in pairs(enclosed or {}) do
          downstream[it] = true
        end
        batch_translate_items(downstream, diff, G.originalEnd, G.rippleTrackScope, true, moveMarkers)
      end

      G.rippleApplied = (G.rippleApplied or 0) + diff
    end
  end
end

local function handle_release()
  local curEdge       = current_edge_pos(G.driver, G.edge)
  local effSincePress = (curEdge - (G.pressBoundary or curEdge))
  local totalEdgeMove = (G.initialPressDelta or 0) + (effSincePress or 0)

  if AnyRippleOn() and (not BODY_NATIVE_RIPPLE) then
    finalize_ripple(G.driver, G.edge, effSincePress, totalEdgeMove)
  end

  if AutoXfadeOn() and not AnyRippleOn() and not TrimBehindOn() then
    G.previewOrig = {}
  else
    preview_clear_all()
  end

  finalize_crossfades_and_overlaps(G.driver)
  end_undo("Trim items (Body, v7)")

  reaper.JS_Mouse_SetCursor(cursor_default)
  G = new_G()
  locked_cursor = nil
end

local mode_handlers = {
  body = function(mouseDown, hov, mTimeRaw)
    if not valid_item(G.driver) then
      end_undo("Trim items (Body, v7)")
      G = new_G()
      locked_cursor = nil
      return
    end

    if not mouseDown then
      handle_release()
    else
      handle_drag(mTimeRaw)
    end
  end,
}

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
local function main()
  if not G then G = new_G() end

  if rt_kill_requested() then
    pcall(reaper.DeleteExtState, NS, KILL_KEY, false)
    pcall(reaper.DeleteExtState, NS, KILL_KEY, true)
    rt_cleanup()
    return
  end

  beat()

  if not __rt_is_reaper_foreground() then
    reaper.JS_Mouse_SetCursor(cursor_default)
  end

  -- Refresh cursor context exactly once per frame.
  refresh_cursor_context()

  local mouseDown = reaper.JS_Mouse_GetState(1) == 1
  local hov       = hovered_item()
  local mTimeRaw  = get_mouse_time_raw()

  if G.mode == "none" then
    handle_hover(hov, mTimeRaw)
  end

  if G.mode == "none" and mouseDown and not prevMouseDown
     and valid_item(hov) and not is_locked(hov) then
    handle_press(hov, mTimeRaw)
  end

  local handler = mode_handlers[G.mode]
  if handler then
    handler(mouseDown, hov, mTimeRaw)
  end

  prevMouseDown = mouseDown
  reaper.UpdateArrange()
  reaper.defer(main)
end

main()
