-- @description Item Body Drag to Trim Edge v7.8.2 (Group/Track-Group Safe, Native Fades, Native Edge-Safe Ripple)
-- @version 7.8.2
-- @date 2026-10-29
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
--   • v7.8.2 – Snap offset stays on the same spot in the audio when the start edge moves
--       (as REAPER's own trim does; it stays at the start if the item has none).
--       SELECT_EDGE_MATCHED: whether items trimmed only because their edge is at the
--       same time (ripple modes) are selected afterwards (true, like Pro Tools) or not.
--   • v7.8.1 – Butt joints in ripple modes: the two-edge cursor slides the cut point in
--       every mode (both edges move, both items' audio stays put, nothing after moves:
--       the total length doesn't change). Only what the neighbor can't follow (it ran
--       out of audio) ripples, so no gap opens. The single-edge cursor in ripple modes
--       is a Shuffle trim of that one item, as before.
--   • v7.8.0 – Edit cursor, loop points, and the cursor you saw:
--       - After a trim (or a click), the trimmed items are selected (the selection is
--         kept if the clicked item was already selected), the edit cursor goes to the
--         start of the selected items, and with "Link Timeline and Edit Selection" on,
--         the loop points are set to them, like the Move Tool's click.
--       - The click is decided by the cursor REAPER showed just before the press (REAPER
--         can change its cursor as the button goes down): two-edge, single-edge, handles.
--       - Nothing is changed while REAPER itself is dragging (its own handles).
--       - DIAG_PRESS = true reports each press in the console (testing).
--   • v7.7.2 – Butt joints follow REAPER's cursor: with REAPER's two-edge cursor (right
--       at the joint) both items' edges move; with the single-edge cursor only that
--       item's edge moves. Where REAPER's cursor can't be read: two edges within
--       JOINT_PX of the joint.
--   • v7.7.1 – Butt joints: dragging an edge where two items meet (Ripple OFF) moves
--       both items' edges together, as REAPER's own edge drag did (it made an overlap
--       or crossfade). The neighbor follows as far as its audio allows; past that the
--       grabbed edge goes on alone. Body clicks still trim only the clicked item.
--   • v7.7.0 – Edges are the Trim Tool's too; REAPER's own handles decided by REAPER:
--       - Which clicks go to REAPER is decided by the cursor REAPER shows at that spot:
--         fade handles and curves, the volume handle and other handles go to REAPER;
--         the body and REAPER's edge zone are the Trim Tool's. This matches REAPER's own
--         zones at any zoom or item height (the fixed 7 px zone left a strip where both
--         REAPER and the Trim Tool acted, and couldn't see the handles at the top of an
--         item). The 7 px zone is still used where REAPER's cursor can't be read.
--       - A plain click or drag on an edge grabs that edge (no jump), with the same
--         group, selected-item, snap and ripple handling as body trims (REAPER's own
--         plain edge drag is turned off by the Trim Tool controller 2.4). Edge drags with
--         modifier keys are still REAPER's.
--       - The cursor is no longer forced to the arrow off items every frame.
--       - A click that changes nothing makes no undo point.
--   • v7.6.0 – Selected items, groups, stretch markers, loops, autoscroll:
--       - Clicking a selected item trims every selected item's same edge by the same
--         amount (in ripple modes, one item per track: the clicked track's clicked item,
--         elsewhere the item whose edge is nearest).
--       - Item groups: every item in the group gets the same edit (was: only items
--         whose edge lined up within 1 ms).
--       - Track groups (no "start/end at the same time" option on): on each following
--         track, the matching item gets the same edit: of the items overlapping the
--         clicked item, the one whose same edge is nearest (was: only items whose edge
--         lined up within 1 ms).
--       - Stretch markers stay with the audio when the start edge moves.
--       - Looped items (MIDI items loop by default) can be extended to the left.
--       - Dragging past the left or right of the arrange scrolls it; the edge follows
--         the mouse instead of jumping when the mouse is over the track panel.
--       - Take envelopes are updated every ENV_UPDATE_FRAMES frames while dragging
--         (and exactly at the click and on release), for items with long clip gain.
--       - Removed a check for REAPER's fade/edge zones that never ran (it read the wrong
--         value); the script's own fade and edge zones are what hand clicks to REAPER.
--       - Undo is named "Trim items".
--   • v7.5.1 – Snap and double-clicks:
--       - With snap on, dragging puts the edge on the grid line nearest the mouse (it
--         was offset by the distance between the click and the grid line it snapped
--         to, so the edge could land a grid line too far, making items longer or
--         shorter than expected, and rippling the items after them by that much more).
--       - A double-click trims once (in ripple mode its second click trimmed again).
--   • v7.5.0 – Ripple (per track and all tracks) kept in sync:
--       - Each track ripples from the end of its own trimmed item, not the clicked
--         item's end (grouped items with different lengths left items unmoved
--         between the two ends).
--       - The items after the edit are the ones found at the click, used as they are
--         at release (was: found again at release from a cutoff that could miss the
--         item crossfaded on the right of the trimmed item).
--       - Every trimmed item's crossfaded neighbor on the right moves with the ripple
--         (was: only the clicked item's, and not even that one when the item was the
--         first on its track).
--       - Per track: only tracks with a trimmed item ripple. Selected tracks without
--         one no longer move (their items slid over the items before them). Set
--         RIPPLE_SELECTED_TRACKS = true for the old behavior.
--       - Track automation (with "Move envelope points with media items" on) stays
--         with the audio: on the trimmed tracks, start-edge ripples also move the
--         points under the trimmed item, and the points in the time that was removed
--         are deleted instead of piling up on the moved ones. Other tracks (all
--         tracks mode) move from the clicked item's end, the same as their items.
--   • v7.4.1 – Crossfades in grouped trims (Ripple OFF):
--       - Every trimmed item (grouped items, track-group followers), not only the
--         clicked one, slides its own crossfade with the neighbor on the trimmed side,
--         and all of them make the same move at the click (they were left behind
--         when the clicked item had a crossfade).
--       - Overlap cleanup on release leaves the untouched side of every trimmed item
--         alone (was: only the clicked item's).
--   • v7.4.0 – Clicks, takes, clip gain, groups:
--       - Clicks are read from the arrange view's own mouse messages, so a quick click
--         between two checks is no longer missed, and the trim lands where you clicked.
--         Clicks on windows floating over the arrange (FX, other apps) are ignored.
--         Falls back to polling the mouse if the messages can't be read.
--       - Every take of the item is trimmed, not only the active one.
--       - Take envelopes (clip gain, pan, pitch, take FX) stay with the audio when the
--         start edge moves.
--       - Track groups: only tracks that follow a group the clicked track leads take part
--         (was: any track in any group with media editing). The clicked track's other
--         items are no longer included.
--       - After a trim, only the trimmed items are removed if they end up shorter than
--         about 1 ms (was: any item that short on those tracks).
--       - All trimmed items move by the same amount and stop together when one of them
--         reaches a limit (start or end of its file, its fades).
--   • v7.3.1 – Start-edge trims keep the audio in place on items with a playrate other
--       than 1.0 (the start in source moved by the distance divided by the rate, not
--       multiplied by it). Also fixed for neighbours trimmed by an overlap.
--   • v7.3.0 – Undo and redraw:
--       - The undo point is made at mouse-up instead of being held open from mouse-down
--         for the whole drag (an open undo block across background cycles could take in
--         unrelated actions). The drag itself creates no undo points, so the result is
--         the same single "Trim items" step. If the tool is stopped mid-drag, or the
--         dragged item disappears, the change so far still gets an undo point.
--       - The arrange is redrawn only while a trim is in progress (and once after it),
--         not 30 times a second while the Trim tool is just selected.
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
-- Ripple per track: also ripple selected tracks that have no trimmed item (old behavior)
local RIPPLE_SELECTED_TRACKS   = false
-- While dragging, take envelopes (clip gain etc.) are moved every this many frames
-- (always exactly at the click and on release). 1 = every frame.
local ENV_UPDATE_FRAMES        = 3
-- Dragging past the left/right of the arrange scrolls it
local AUTOSCROLL               = true
local AUTOSCROLL_RATE          = 0.5   -- pixels scrolled per frame, per pixel past the edge

-- UI tolerances (px → converted per-zoom)
local EDGE_GRAB_PX             = 7          -- tolerance around the native edge
local JOINT_PX                 = 3          -- butt joint (both edges), where REAPER's cursor can't be read
-- After a trim, also select the items on other tracks that were trimmed only because
-- their edge is at the same time (ripple modes). true = like Pro Tools (all trimmed
-- items selected); false = only the clicked item, its groups and the selection.
local SELECT_EDGE_MATCHED      = true
local DIAG_PRESS               = false      -- true: report each press in the console (testing)
local LINK_CMD_GUID            = "_RSed328eb507619b18c1154efa1b048d816cfc2d0c"   -- Link Timeline and Edit Selection
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
    grabOffset        = nil,      -- edge position relative to the (snapped) mouse time
    grabEdge          = false,    -- the edge itself was grabbed (no jump at the click)
    grabJoint         = false,    -- grabbed at a butt joint: the neighbor's edge moves too
    driverWasSelected = false,    -- the clicked item was selected at the press
    edgeMatched       = nil,      -- items trimmed only because their edge is at the same time
    pressMouseTime    = nil,      -- timeline time clicked
    pressBoundary     = nil,      -- driver edge position after press-time snap
    initialPressDelta = 0,        -- how far press-time snap moved the edge

    -- Scope (frozen at press)
    selectedTrackSet  = nil,      -- map of tracks selected at press time
    editedSet         = {},       -- all items that will be trimmed
    initStates        = {},       -- cap_state() snapshots keyed by item

    -- Ripple
    originalEnd       = nil,      -- driver item_end() at press (pre-snap)
    rippleTrackScope  = nil,      -- map of tracks in ripple scope
    pressEdges        = nil,      -- track -> {s, e}: its trimmed items' start/end at press
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
    slides              = {},     -- trimmed item -> {nei, state, edge}: crossfade neighbor
                                  -- on the trimmed side, trimmed with it (Ripple OFF)

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
-- A track's membership in groups 1-32 and 33-64 for one group setting
-- ("MEDIA_EDIT_LEAD" or "MEDIA_EDIT_FOLLOW"), as two bit masks
local function group_masks(tr, name)
  local lo, hi = 0, 0
  if reaper.GetSetTrackGroupMembershipEx then
    lo = reaper.GetSetTrackGroupMembershipEx(tr, name, 0, 0, 0) or 0
    hi = reaper.GetSetTrackGroupMembershipEx(tr, name, 32, 0, 0) or 0
  elseif reaper.GetSetTrackGroupMembership then
    lo = reaper.GetSetTrackGroupMembership(tr, name, 0, 0) or 0
    if reaper.GetSetTrackGroupMembershipHigh then
      hi = reaper.GetSetTrackGroupMembershipHigh(tr, name, 0, 0) or 0
    end
  end
  return math.floor(lo) & 0xFFFFFFFF, math.floor(hi) & 0xFFFFFFFF
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

-- Item groups: every other item in the group gets the same edit
local function collect_item_group_followers(driver, edge, refStart, refEnd)
  local out = {}
  if not GroupMasterOn() then return out end
  local gid = reaper.GetMediaItemInfo_Value(driver,"I_GROUPID") or 0
  if gid <= 0 then return out end
  for i=0, reaper.CountMediaItems(0)-1 do
    local it = reaper.GetMediaItem(0,i)
    if valid_item(it) and it ~= driver and not is_locked(it)
       and reaper.GetMediaItemInfo_Value(it,"I_GROUPID") == gid then
      out[#out+1]=it
    end
  end
  return out
end

local function collect_trackgroup_followers(driver, edge, refStart, refEnd)
  local out = {}
  if not TrackGroupsOn() then return out end
  local driverTr = reaper.GetMediaItem_Track(driver)
  if not valid_track(driverTr) then return out end
  -- Groups the clicked track leads for media editing
  local leadLo, leadHi = group_masks(driverTr, "MEDIA_EDIT_LEAD")
  if leadLo == 0 and leadHi == 0 then return out end
  -- Other tracks that follow one of those groups
  local members = {}
  for t=0, reaper.CountTracks(0)-1 do
    local tr = reaper.GetTrack(0,t)
    if tr ~= driverTr then
      local folLo, folHi = group_masks(tr, "MEDIA_EDIT_FOLLOW")
      if (folLo & leadLo) ~= 0 or (folHi & leadHi) ~= 0 then members[#members+1]=tr end
    end
  end
  if #members==0 then return out end

  local useSE, useSAE, useENC = OptSE(), OptSAE(), OptENC()

  -- REAPER's "only items that start/end at the same time / are enclosed" options:
  -- every item they match follows
  if useSE or useSAE or useENC then
    local function include(it)
      if is_locked(it) or (REQUIRE_SAME_LANE and not same_lane(driver,it)) then return false end
      if useSAE and start_and_end_match(it,refStart,refEnd) then return true end
      if useSE  and start_or_end_match(it,refStart,refEnd)  then return true end
      if useENC and enclosed_by(it,refStart,refEnd)         then return true end
      return false
    end
    for _,tr in ipairs(members) do
      for i=0, reaper.CountTrackMediaItems(tr)-1 do
        local it = reaper.GetTrackMediaItem(tr,i)
        if valid_item(it) and it~=driver and include(it) then out[#out+1]=it end
      end
    end
    return out
  end

  -- Otherwise the edit is mirrored, like Pro Tools: on each following track, the
  -- item that matches the clicked one gets the same edit: of the items overlapping
  -- the clicked item, the one whose same edge is nearest the clicked item's edge.
  local ref = (edge == "start") and refStart or refEnd
  for _,tr in ipairs(members) do
    local best, bestDist = nil, math.huge
    for i=0, reaper.CountTrackMediaItems(tr)-1 do
      local it = reaper.GetTrackMediaItem(tr,i)
      if valid_item(it) and it ~= driver and not is_locked(it)
         and (not REQUIRE_SAME_LANE or same_lane(driver,it)) then
        local s, e = item_start(it), item_end(it)
        local edgeT = (edge == "start") and s or e
        local overlap = math.min(e, refEnd) - math.max(s, refStart)
        local dist = math.abs(edgeT - ref)
        if (overlap > BOUNDARY_TOL or dist <= BOUNDARY_TOL) and dist < bestDist then
          best, bestDist = it, dist
        end
      end
    end
    if best then out[#out+1] = best end
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
    if RIPPLE_SELECTED_TRACKS then
      for tr,_ in pairs(selectedTracks or {}) do
        scope[tr] = true
      end
    end
  end
  for it,_ in pairs(editedSet or {}) do
    local tr = valid_item(it) and reaper.GetMediaItem_Track(it) or nil
    if valid_track(tr) then scope[tr] = true end
  end
  return scope
end

-- Items after the edit: on a track with trimmed items, those starting at or after
-- the end of its trimmed item(s); on other tracks, after the clicked item's end
local function snapshot_downstream_items(originalEnd, trackScope, excludeSet)
  local snap = {}
  for tr,_ in pairs(trackScope or {}) do
    local pe  = G.pressEdges and G.pressEdges[tr]
    local cut = (pe and pe.e) or originalEnd
    for i=0, reaper.CountTrackMediaItems(tr)-1 do
      local it = reaper.GetTrackMediaItem(tr,i)
      if valid_item(it) and not (excludeSet and excludeSet[it]) and not is_locked(it) then
        if item_start(it) >= cut - BOUNDARY_TOL then
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
local function take_rate(tk)
  local r = reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1
  if r == 0 then r = 1 end
  return r
end

local function valid_take(tk) return tk and reaper.ValidatePtr2(0, tk, "MediaItem_Take*") end

-- Shift every point of a take's envelopes (clip gain, pan, pitch, take FX) by dt,
-- in take time, so they stay with the audio when the start in source changes.
-- Every point moves by the same amount, so their order doesn't change.
local function shift_take_envelopes(tk, dt)
  if dt == 0 then return end
  for e = 0, reaper.CountTakeEnvelopes(tk) - 1 do
    local env = reaper.GetTakeEnvelope(tk, e)
    if env then
      for i = 0, reaper.CountEnvelopePoints(env) - 1 do
        local ok, t, v, sh, te, sel = reaper.GetEnvelopePoint(env, i)
        if ok then reaper.SetEnvelopePoint(env, i, t + dt, v, sh, te, sel, true) end
      end
    end
  end
end

-- Stretch markers: same shift, in take time (their source positions stay)
local function shift_stretch_markers(tk, dt)
  if dt == 0 or not reaper.GetTakeNumStretchMarkers then return end
  for i = 0, reaper.GetTakeNumStretchMarkers(tk) - 1 do
    local idx, pos, srcpos = reaper.GetTakeStretchMarker(tk, i)
    if idx and idx >= 0 then reaper.SetTakeStretchMarker(tk, i, pos + dt, srcpos) end
  end
end

-- Set a take's start in source right away, with its envelopes and stretch markers
-- (used for neighbors trimmed by an overlap)
local function set_take_offset(tk, newOffs)
  local cur = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
  if math.abs(newOffs - cur) < 1e-12 then return end
  reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", newOffs)
  shift_take_envelopes(tk, -(newOffs - cur))
  shift_stretch_markers(tk, -(newOffs - cur))
end

-- Length of a take's source in seconds (for looped takes)
local function take_source_len(tk)
  local src = reaper.GetMediaItemTake_Source(tk)
  if not src then return 0 end
  local len, isQN = reaper.GetMediaSourceLength(src)
  if isQN then len = reaper.TimeMap2_QNToTime(0, len) end
  return math.max(0, len or 0)
end

-- Every take of the item, at press time: start in source, playrate, looping.
-- raw = the start in source as if never wrapped round a loop; envDone = how far
-- its envelopes have been moved so far (they may lag a few frames while dragging)
local function cap_takes(it)
  local list = {}
  for t = 0, reaper.CountTakes(it) - 1 do
    local tk = reaper.GetTake(it, t)
    if tk then
      local offs = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
      local loop = reaper.GetMediaItemTakeInfo_Value(tk, "B_LOOPSRC") == 1
      list[#list + 1] = {
        tk = tk, offs = offs, rate = take_rate(tk),
        loop = loop, srclen = loop and take_source_len(tk) or 0,
        raw = offs, envWant = 0, envDone = 0,
      }
    end
  end
  return list
end

-- Move a captured take's start in source to offs + delta (raw, unwrapped): the
-- offset and stretch markers now, the envelopes now or at the next update
local ENV_NOW = true   -- false on drag frames between envelope updates
local function move_take(t, newRaw)
  if not valid_take(t.tk) then return end
  if not t.loop and newRaw < 0 then newRaw = 0 end
  local set = newRaw
  if t.loop and t.srclen > 0 then set = newRaw % t.srclen end
  reaper.SetMediaItemTakeInfo_Value(t.tk, "D_STARTOFFS", set)
  shift_stretch_markers(t.tk, -(newRaw - t.raw))
  t.raw = newRaw
  t.envWant = -(newRaw - t.offs)
  if ENV_NOW and t.envWant ~= t.envDone then
    shift_take_envelopes(t.tk, t.envWant - t.envDone)
    t.envDone = t.envWant
  end
end

-- Bring every lagging take envelope up to date
local function flush_take_envelopes(states, slides)
  local function f(st)
    for _, t in ipairs((st and st.takes) or {}) do
      if t.envWant ~= t.envDone and valid_take(t.tk) then
        shift_take_envelopes(t.tk, t.envWant - t.envDone)
        t.envDone = t.envWant
      end
    end
  end
  for _, st in pairs(states or {}) do f(st) end
  for _, sl in pairs(slides or {}) do f(sl.state) end
end

local function cap_state(it, edge)
  if not valid_item(it) then return nil end
  local tk   = get_take(it)
  local pos  = item_start(it)
  local len  = item_len(it)
  local offs = (tk and reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")) or 0
  return {pos=pos, len=len, offs=offs, takes=cap_takes(it),
          snap=reaper.GetMediaItemInfo_Value(it, "D_SNAPOFFSET") or 0}
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

  local takes = st.takes or {}

  if edge == "start" then
    -- Don't go before the start of any take's source
    for _, t in ipairs(takes) do
      if not t.loop then                          -- looped takes repeat to the left
        local newOffs = t.offs + (delta * t.rate)   -- timeline seconds x rate = source seconds
        if newOffs < 0 then
          delta = (0 - t.offs) / t.rate
        end
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

    -- Don't go past the end of any take's source (unless it loops)
    for _, t in ipairs(takes) do
      local tk = t.tk
      if valid_take(tk) and reaper.GetMediaItemTakeInfo_Value(tk, "B_LOOPSRC") ~= 1 then
        local src = reaper.GetMediaItemTake_Source(tk)
        if src then
          local srcLen, isQN = reaper.GetMediaSourceLength(src)
          if isQN then srcLen = reaper.TimeMap2_QNToTime(0, srcLen) end
          srcLen = math.max(0, srcLen or 0)

          local maxLenNoLoop = (srcLen - t.offs) / math.abs(t.rate)
          newLen = st.len + delta
          if maxLenNoLoop <= EPS then
            delta = -st.len + EPS
          elseif newLen > maxLenNoLoop then
            delta = maxLenNoLoop - st.len
          end
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
  if not valid_item(it) or not st or is_locked(it) then return end
  if delta == 0 and not st.moved then return end
  st.moved = (delta ~= 0)

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

    -- Snap offset is measured from the item's start: keep it on the same spot in the
    -- audio (an item without one keeps it at its start)
    if (st.snap or 0) > EPS then
      local snap = math.max(0, math.min(newLen, st.snap - (newPos - st.pos)))
      reaper.SetMediaItemInfo_Value(it, "D_SNAPOFFSET", snap)
    end

    -- Every take: start in source moves with the edge, so the audio stays put
    for _, t in ipairs(st.takes or {}) do
      move_take(t, t.offs + (delta * t.rate))   -- timeline seconds x rate = source seconds
    end
  else
    local newLen = math.max(EPS, st.len + delta)
    reaper.SetMediaItemInfo_Value(it,"D_LENGTH", newLen)
  end
end

-- The largest move every item can make: each item's limits (source bounds, fades)
-- can only shorten the move, so all trimmed items, and the crossfade neighbors
-- sliding with them, move by the same amount and stop together.
local function common_delta(states, edge, delta)
  for it, st in pairs(states or {}) do
    if st and valid_item(it) and not is_locked(it) then
      local d = clamp_to_source(it, st, edge, delta)
      if math.abs(d) < math.abs(delta) then delta = d end
    end
  end
  -- crossfaded neighbors limit the move (the crossfade must stay intact); butted
  -- neighbors don't: they follow as far as they can (see trim_all)
  for _, sl in pairs(G.slides or {}) do
    if not sl.butt and sl.state and valid_item(sl.nei) and not is_locked(sl.nei) then
      local d = clamp_to_source(sl.nei, sl.state, sl.edge, delta)
      if math.abs(d) < math.abs(delta) then delta = d end
    end
  end
  return delta
end

-- Trim every item (and its sliding crossfade neighbor) by one common move.
-- Returns the move made.
local function trim_all(edge, delta)
  delta = common_delta(G.initStates, edge, delta)
  for it, st in pairs(G.initStates or {}) do
    if st and valid_item(it) and not is_locked(it) then apply_trim(it, st, edge, delta) end
  end
  for _, sl in pairs(G.slides or {}) do
    if sl.state and valid_item(sl.nei) and not is_locked(sl.nei) then
      local d = sl.butt and clamp_to_source(sl.nei, sl.state, sl.edge, delta) or delta
      apply_trim(sl.nei, sl.state, sl.edge, d)
    end
  end
  return delta
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

  for _, t in ipairs(cap_takes(nei)) do
    local offs1 = t.offs + (delta * t.rate)
    if offs1 < 0 then offs1 = 0 end
    set_take_offset(t.tk, offs1)
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
  for it, sl in pairs(G.slides or {}) do
    if (leftItem == it and rightItem == sl.nei) or (leftItem == sl.nei and rightItem == it) then
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
    local ed = G.editedSet or {}
    if G.edge == "start" and (leftItem == G.driver or ed[leftItem]) then
      return
    end
    if G.edge == "end" and (rightItem == G.driver or ed[rightItem]) then
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

-- zone: what REAPER's cursor says is under the mouse ("body", "edge", "native" for
-- one of REAPER's own handles, or nil if unknown). mods: modifier keys held.
-- Returns nil when the click is REAPER's.
local function classify_press(it, tRaw, zone, mods)
  if zone == "native" then return nil end   -- fade handle, volume handle ...: REAPER's

  local s = item_start(it)
  local e = item_end(it)
  local fin  = reaper.GetMediaItemInfo_Value(it,"D_FADEINLEN")  or 0
  local fout = reaper.GetMediaItemInfo_Value(it,"D_FADEOUTLEN") or 0

  -- 1) On an edge (REAPER's edge zone, or within EDGE_GRAB_PX): grab that edge.
  --    With modifier keys, REAPER's own edge drags (stretch etc.) take it.
  local edgeTolT = px_to_time(EDGE_GRAB_PX)
  local nearEdge = math.abs(tRaw - s) <= edgeTolT or math.abs(tRaw - e) <= edgeTolT
  if zone == "edge" or zone == "joint" or (zone ~= "body" and nearEdge) then
    if (mods or 0) ~= 0 then return nil end
    local edge = (math.abs(tRaw - s) <= math.abs(e - tRaw)) and "start" or "end"
    -- both edges of a butt joint: REAPER's two-edge cursor (or, unknown, right at it)
    local joint = (zone == "joint")
    if zone == nil then
      local d = (edge == "start") and math.abs(tRaw - s) or math.abs(e - tRaw)
      joint = d <= px_to_time(JOINT_PX)
    end
    return {modeKind="body", grab="edge", edge=edge, joint=joint}
  end

  -- 2) Fade zone + halo (where REAPER's cursor can't be read): REAPER's
  if zone == nil and in_fade_halo(it, tRaw) then
    return nil
  end

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

  local drivers, isDriver = { primary }, { [primary] = true }
  local function add_driver(it)
    if valid_item(it) and not is_locked(it) and not isDriver[it] then
      isDriver[it] = true
      drivers[#drivers+1] = it
    end
  end
  -- Clicking a selected item trims every selected item
  if reaper.IsMediaItemSelected(primary) then
    for i = 0, reaper.CountSelectedMediaItems(0)-1 do
      add_driver(reaper.GetSelectedMediaItem(0, i))
    end
  end
  local ownDrivers = #drivers   -- the clicked item and the selection; the rest are edge matches
  for _, it in ipairs(collect_codrivers(primary, edge, refBoundary, G.selectedTrackSet)) do
    add_driver(it)
  end

  local followers, seen = {}, {}
  local function add_unique(it)
    if valid_item(it) and not seen[it] then
      seen[it] = true
      followers[#followers+1] = it
    end
  end

  -- Items that follow the clicked item or the selection (groups) are "own"; items that
  -- only come from an edge match (and their groups) are noted in G.edgeMatched
  local own = {}
  for n, d in ipairs(drivers) do
    local isOwn = n <= ownDrivers
    if isOwn then own[d] = true end
    local ds, de = item_start(d), item_end(d)
    for _, it in ipairs(collect_item_group_followers(d, edge, ds, de)) do
      add_unique(it)
      if isOwn then own[it] = true end
    end
    for _, it in ipairs(collect_trackgroup_followers(d, edge, ds, de)) do
      add_unique(it)
      if isOwn then own[it] = true end
    end
  end
  G.edgeMatched = {}
  for _, it in ipairs(drivers)   do if not own[it] then G.edgeMatched[it] = true end end
  for _, it in ipairs(followers) do if not own[it] then G.edgeMatched[it] = true end end

  G.editedSet = {}
  for _, it in ipairs(drivers)   do G.editedSet[it] = true end
  for _, it in ipairs(followers) do G.editedSet[it] = true end

  -- Ripple: one trimmed item per track (more would need a ripple between them).
  -- The clicked item on its track; elsewhere the item whose edge is nearest.
  if AnyRippleOn() then
    local keep = {}
    for it,_ in pairs(G.editedSet) do
      local tr = item_track_safe(it)
      if tr then
        local edgeT = (edge == "start") and item_start(it) or item_end(it)
        local d = (it == primary) and -1 or math.abs(edgeT - refBoundary)
        if not keep[tr] or d < keep[tr].d then keep[tr] = { it = it, d = d } end
      end
    end
    G.editedSet = {}
    for _, k in pairs(keep) do G.editedSet[k.it] = true end
  end

  G.initStates = {}
  for it,_ in pairs(G.editedSet) do
    G.initStates[it] = cap_state(it, edge)
  end
end

local function freeze_ripple_scope(primary)
  G.originalEnd      = item_end(primary)
  G.rippleTrackScope = build_ripple_track_scope(primary, G.selectedTrackSet, G.editedSet)

  -- Where each track's edit is: its trimmed items' earliest start and latest end
  G.pressEdges = {}
  for it,_ in pairs(G.editedSet) do
    local tr = item_track_safe(it)
    if tr then
      local s0, e0 = item_start(it), item_end(it)
      local pe = G.pressEdges[tr]
      if not pe then
        G.pressEdges[tr] = { s = s0, e = e0 }
      else
        if s0 < pe.s then pe.s = s0 end
        if e0 > pe.e then pe.e = e0 end
      end
    end
  end

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

-- Ripple on: the item each trimmed item crossfades with on its right (it starts
-- before the trimmed item ends, so it isn't "after the edit") moves with the ripple.
-- Then computes guardPairs. Must follow freeze_crossfade_pair_detection() and
-- freeze_ripple_scope().
local function freeze_right_xfade_neighbor(primary)
  G.rightXfadeNeighbor = nil

  if AnyRippleOn() then
    for it,_ in pairs(G.editedSet or {}) do
      local tr = valid_item(it) and item_track_safe(it)
      if tr then
        local list = {}
        for i = 0, reaper.CountTrackMediaItems(tr)-1 do
          local o = reaper.GetTrackMediaItem(tr, i)
          if valid_item(o) and same_lane(it, o) then list[#list+1] = o end
        end
        table.sort(list, function(a, b) return item_start(a) < item_start(b) end)
        for idx, o in ipairs(list) do
          if o == it then
            local right = list[idx + 1]
            if right and valid_item(right) and not is_locked(right) and not G.editedSet[right]
               and item_start(right) < item_end(it) - BOUNDARY_TOL then
              G.downstreamSnap[right] = true
              if it == primary then G.rightXfadeNeighbor = right end
            end
            break
          end
        end
      end
    end
  end

  -- guardPairs depends on the complete downstreamSnap (including rightXfadeNeighbor)
  G.guardPairs = pertrack_first_downstream_and_anchor(
                    G.originalEnd, G.rippleTrackScope, G.downstreamSnap
                 )
end

-- Ripple OFF: for every trimmed item, the neighbor it crossfades with on the
-- trimmed side (both items have fades and overlap). It's trimmed with the item,
-- so the crossfade slides instead of being cut or stretched.
local function freeze_slide_neighbors(primary, edge)
  G.slideLeftNeighbor  = nil
  G.slideLeftState     = nil
  G.slideRightNeighbor = nil
  G.slideRightState    = nil
  G.slides             = {}

  -- Crossfades slide with Ripple OFF; butt joints grabbed with the two-edge cursor
  -- slide in every mode
  local rippleOff = RippleOff()
  if not rippleOff and not G.grabJoint then return end

  local used = {}
  for it,_ in pairs(G.editedSet or {}) do
    local tr = valid_item(it) and item_track_safe(it)
    if tr then
      local list = {}
      for i = 0, reaper.CountTrackMediaItems(tr)-1 do
        local o = reaper.GetTrackMediaItem(tr, i)
        if valid_item(o) and same_lane(it, o) then list[#list+1] = o end
      end
      table.sort(list, function(a,b) return item_start(a) < item_start(b) end)
      local idx
      for n, o in ipairs(list) do if o == it then idx = n break end end

      local nei, ov, ok
      if idx and edge == "start" then
        nei = list[idx - 1]
        if nei then
          ov = item_end(nei) - item_start(it)
          ok = rippleOff and ov > BOUNDARY_TOL
               and (reaper.GetMediaItemInfo_Value(nei, "D_FADEOUTLEN") or 0) > BOUNDARY_TOL
               and (reaper.GetMediaItemInfo_Value(it,  "D_FADEINLEN")  or 0) > BOUNDARY_TOL
          -- grabbed at a butt joint (two-edge cursor): both edges move
          ok = ok or (G.grabJoint and math.abs(ov) <= BOUNDARY_TOL)
        end
      elseif idx then
        nei = list[idx + 1]
        if nei then
          ov = item_end(it) - item_start(nei)
          ok = rippleOff and ov > BOUNDARY_TOL
               and (reaper.GetMediaItemInfo_Value(it,  "D_FADEOUTLEN") or 0) > BOUNDARY_TOL
               and (reaper.GetMediaItemInfo_Value(nei, "D_FADEINLEN")  or 0) > BOUNDARY_TOL
          ok = ok or (G.grabJoint and math.abs(ov) <= BOUNDARY_TOL)
        end
      end

      if ok and valid_item(nei) and not is_locked(nei) and not G.editedSet[nei] and not used[nei] then
        used[nei] = true
        local nedge = (edge == "start") and "end" or "start"
        G.slides[it] = { nei = nei, state = cap_state(nei, nedge), edge = nedge,
                         butt = math.abs(ov) <= BOUNDARY_TOL,
                         edge0 = (nedge == "start") and item_start(nei) or item_end(nei) }
        if it == primary then
          if edge == "start" then
            G.slideLeftNeighbor, G.slideLeftState = nei, G.slides[it].state
          else
            G.slideRightNeighbor, G.slideRightState = nei, G.slides[it].state
          end
        end
      end
    end
  end
end

-- After the press move: the trim during the drag starts from where items are now
local function recapture_states(edge)
  flush_take_envelopes(G.initStates, G.slides)
  G.initStates = {}
  for it,_ in pairs(G.editedSet or {}) do
    G.initStates[it] = cap_state(it, edge)
  end
  for _, sl in pairs(G.slides or {}) do
    sl.state = cap_state(sl.nei, sl.edge)
  end
  if G.slideLeftNeighbor and G.driver and G.slides[G.driver] then G.slideLeftState = G.slides[G.driver].state end
  if G.slideRightNeighbor and G.driver and G.slides[G.driver] then G.slideRightState = G.slides[G.driver].state end
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
-- Track automation follows the ripple. On a track with trimmed items:
--   start edge: the audio after the new start moves by the ripple, so points from
--     there on move; points in the time cut from the start are deleted
--   end edge: points from the old end on move; points in the time cut are deleted
-- Other tracks (all tracks mode): points from the clicked item's old end on move,
-- like their items; points in the time removed there are deleted.
local function ripple_track_envelopes(edge, total, R)
  if not MoveEnvWithItems() or R == 0 then return end
  for tr,_ in pairs(G.rippleTrackScope or {}) do
    if valid_track(tr) then
      local pe = G.pressEdges and G.pressEdges[tr]
      local from, delA, delB
      if pe and edge == "start" then
        from = pe.s + math.max(0, total)
        if total > 0 then delA, delB = pe.s, pe.s + total end
      elseif pe then
        from = pe.e
        if total < 0 then delA, delB = pe.e + total, pe.e end
      else
        from = G.originalEnd
        if R < 0 then delA, delB = G.originalEnd + R, G.originalEnd end
      end
      for e = 0, reaper.CountTrackEnvelopes(tr)-1 do
        local env = reaper.GetTrackEnvelope(tr, e)
        if env then
          if delA and (delB - delA) > 2 * BOUNDARY_TOL then
            reaper.DeleteEnvelopePointRange(env, delA + BOUNDARY_TOL, delB - BOUNDARY_TOL)
          end
          offset_envelope_after(env, from, R)
        end
      end
    end
  end
end

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

  -- Butt joint slid with the two-edge cursor: the cut point moved, the total length
  -- didn't. Only the part the neighbor couldn't follow ripples.
  if G.grabJoint and G.slides and G.slides[primary] then
    local sl = G.slides[primary]
    if valid_item(sl.nei) and sl.edge0 then
      local now = (sl.edge == "start") and item_start(sl.nei) or item_end(sl.nei)
      total = total - (now - sl.edge0)
    end
  end

  if math.abs(total or 0) <= (BOUNDARY_TOL or 0.001) then return end

  local edited = {}
  for it,_ in pairs(G.editedSet or {}) do edited[it] = true end

  -- Start edge: the trimmed items go back to where they started (the audio after
  -- the new start moves with the ripple)
  if RIPPLE_INCLUDE_DRIVER_ON_MOUSEUP and edge == "start" then
    batch_translate_items(edited, -total, nil, nil, false, false)
  end

  -- Items after the edit (found at the click) move by the same amount
  local R = (edge == "start") and (-total) or (total)
  local downstream = {}
  for it,_ in pairs(G.downstreamSnap or {}) do
    if valid_item(it) and not is_locked(it) and not edited[it] then downstream[it] = true end
  end
  batch_translate_items(downstream, R, nil, nil, false, false)

  ripple_track_envelopes(edge, total, R)
  if RippleAllTracks() and MarkersRegionsRippleAll() then
    move_markers_regions_after(G.originalEnd, R)
  end
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

  -- Remove trimmed items that ended up as slivers (only items this trim changed)
  local trimmed = {}
  for it,_ in pairs(G.editedSet or {}) do trimmed[it] = true end
  for _, sl in pairs(G.slides or {}) do trimmed[sl.nei] = true end
  for it,_ in pairs(trimmed) do
    if valid_item(it) and item_len(it) <= SLICE_CLEAN_TOL then
      local tr = item_track_safe(it)
      if tr then reaper.DeleteTrackMediaItem(tr, it) end
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

-- REAPER's own cursor: the cursor on screen whenever it isn't one this script set.
-- REAPER shows a different cursor for each thing it would do at that spot, so this
-- tells us where its own handles are (fade handles and curves, volume handle ...).
local function ckey(h) return h and tostring(h) or nil end
local ourCursor    = nil   -- key of the cursor this script last set (nil: none showing)
local reaperCursor = nil   -- key of REAPER's cursor, last seen
local function set_cursor(h, notOurs)
  if not h then return end
  reaper.JS_Mouse_SetCursor(h)
  ourCursor = (not notOurs) and ckey(h) or nil
end
local function read_reaper_cursor()
  if not reaper.JS_Mouse_GetCursor then return end
  local k = ckey(reaper.JS_Mouse_GetCursor())
  if k and k ~= ourCursor then reaperCursor = k end
end
-- REAPER's cursors over an item, measured in REAPER 7 (Move Tool):
--   32512 arrow = body; 417 / 418 = edge zone, single edge (trim left/right);
--   450 = right at the edge, two edges (a butt joint)
local REAPER_BODY, REAPER_EDGE, REAPER_JOINT = {}, {}, {}
REAPER_BODY[ckey(cursor_default) or "-"] = true
for _, id in ipairs({ 417, 418 }) do
  local h = reaper.JS_Mouse_LoadCursor(id)
  if h then REAPER_EDGE[ckey(h)] = true end
end
do
  local h = reaper.JS_Mouse_LoadCursor(450)
  if h then REAPER_JOINT[ckey(h)] = true end
end
local CURSOR_NAME = {}
for _, id in ipairs({ 32512, 32644, 417, 418, 450, 183, 184, 105, 488, 463, 525, 526 }) do
  local h = reaper.JS_Mouse_LoadCursor(id)
  if h then CURSOR_NAME[ckey(h)] = tostring(id) end
end
-- "body", "edge", "joint", "native" (one of REAPER's handles) or nil (unknown)
local function reaper_zone()
  if not reaperCursor then return nil end
  if REAPER_JOINT[reaperCursor] then return "joint" end
  if REAPER_EDGE[reaperCursor] then return "edge" end
  if REAPER_BODY[reaperCursor] then return "body" end
  return "native"
end

local function cursor_for_mode(edge)
  return (edge == "start") and cursor_trim_left or cursor_trim_right
end

local function pick_cursor_for_hover(hov, tRaw)
  if not valid_item(hov) or is_locked(hov) then return nil end
  local zone = reaper_zone()
  if zone == "native" or zone == "edge" or zone == "joint" then return nil end   -- REAPER's own cursor shows

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
    reaper.Undo_EndBlock(msg or "Trim items", -1)
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

----------------------------------------------------------------
-- CLICKS FROM THE ARRANGE VIEW'S MOUSE MESSAGES
-- Reading the arrange view's own mouse-down messages (passed on to REAPER as
-- usual) catches every click, even one pressed and released between two checks,
-- with the exact point clicked, and never a click on a window floating over the
-- arrange. If they can't be read, presses are found by polling the mouse.
----------------------------------------------------------------
local ARRANGE = reaper.JS_Window_FindChildByID and reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
-- Double-clicks (WM_LBUTTONDBLCLK) aren't read: their second click would trim again
local CLICK_MSGS = { "WM_LBUTTONDOWN" }
local clickMsgOn = {}
local MSG_OK = false
local lastClickTime = 0

if ARRANGE and reaper.JS_WindowMessage_Intercept and reaper.JS_WindowMessage_Peek then
  for _, m in ipairs(CLICK_MSGS) do
    if reaper.JS_WindowMessage_Intercept(ARRANGE, m, true) == 1 then
      clickMsgOn[m] = true
      local ok, _, t = reaper.JS_WindowMessage_Peek(ARRANGE, m)
      if ok and t and t > lastClickTime then lastClickTime = t end
    end
  end
  MSG_OK = clickMsgOn["WM_LBUTTONDOWN"] == true
end

local function release_click_msgs()
  if not (ARRANGE and reaper.JS_WindowMessage_Release) then return end
  for m in pairs(clickMsgOn) do pcall(reaper.JS_WindowMessage_Release, ARRANGE, m) end
  clickMsgOn = {}
end

-- A click in the arrange since the last check: {x, y} in arrange coordinates
local function new_click()
  local found = nil
  for m in pairs(clickMsgOn) do
    local ok, _, t, _, _, x, y = reaper.JS_WindowMessage_Peek(ARRANGE, m)
    if ok and t and t > lastClickTime then
      if (not found) or t > found.t then found = { t = t, x = x, y = y } end
    end
  end
  if found then lastClickTime = found.t end
  return found
end

-- Where that click was: screen point, timeline time (nil = use the mouse now),
-- and whether REAPER's mouse context (native fade/edge zones) applies to it
local function click_point(c, mouseDown)
  local mx, my = reaper.GetMousePosition()
  local sx, sy = reaper.JS_Window_ClientToScreen(ARRANGE, c.x, c.y)
  if not sx then return mx, my, nil, true end
  -- Mouse still down far from the converted point: trust the mouse
  if mouseDown and (math.abs(sx - mx) > 40 or math.abs(sy - my) > 40) then return mx, my, nil, true end
  -- Mouse still where it was clicked: REAPER's own context is exact
  if math.abs(sx - mx) <= 2 and math.abs(sy - my) <= 2 then return mx, my, nil, true end
  local viewStart = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  local pps = reaper.GetHZoomLevel() or 1
  if pps <= 0 then pps = 1e-6 end
  return sx, sy, viewStart + c.x / pps, false
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
  if cursor_default and lastSetByUs then reaper.JS_Mouse_SetCursor(cursor_default) end
  release_click_msgs()
  if G and G.undoOpen then end_undo() end
  if G and G.mode == "body" then reaper.Undo_OnStateChange("Trim items") end   -- stopped mid-drag

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
  local drv = G.driver
  local dst = G.initStates and drv and G.initStates[drv]
  if not (dst and valid_item(drv)) then return end
  G.inPressAlign = true
  -- The move is worked out on the clicked item, then made by every trimmed item
  local fin  = reaper.GetMediaItemInfo_Value(drv, "D_FADEINLEN")  or 0
  local fout = reaper.GetMediaItemInfo_Value(drv, "D_FADEOUTLEN") or 0
  local delta
  if edge == "start" then
    delta = ((targetTime or dst.pos) - math.max(0, fin)) - dst.pos
  else
    delta = ((targetTime or (dst.pos + dst.len)) + math.max(0, fout)) - (dst.pos + dst.len)
  end
  trim_all(edge, delta)
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
  local sl     = G.slides and G.slides[driver]
  if not (sl and valid_item(sl.nei)) then return end

  -- The clicked item's crossfade seam goes to the (snapped) cursor
  local seamTime  = (edge == "end") and item_start(sl.nei) or item_end(sl.nei)
  G.grabOffset    = current_edge_pos(driver, edge) - seamTime   -- edge relative to the seam
  local snapDelta = snapped_delta_from_raw(cursorTime - seamTime, seamTime, 0)

  -- Every trimmed item, and each one's crossfade neighbor, makes the same move
  reaper.PreventUIRefresh(1)
  trim_all(edge, snapDelta)
  reaper.PreventUIRefresh(-1)

  G.pressBoundary     = current_edge_pos(driver, edge)
  G.initialPressDelta = 0
  recapture_states(edge)
  G.initialMouseRaw = cursorTime
end

----------------------------------------------------------------
-- MAIN LOOP – sub-handlers dispatched by mode
----------------------------------------------------------------
local locked_cursor  = nil
local prevMouseDown  = false
local hoverZone      = nil    -- REAPER's cursor zone, last seen with the button up

local function hovered_item()
  local x,y = reaper.GetMousePosition()
  local it = reaper.GetItemFromPoint(x,y,false)
  return valid_item(it) and it or nil
end

-- Over an item's body: the trim cursor. Anywhere else REAPER's own cursor is left
-- alone (REAPER sets it as the mouse moves); outside REAPER, back to the arrow.
local function handle_hover(hov, mTimeRaw)
  local allowed = __rt_allow_custom_cursor_now()
  if allowed and valid_item(hov) and not is_locked(hov) then
    local c = pick_cursor_for_hover(hov, mTimeRaw)
    if c then
      set_cursor(c)
      lastSetByUs = true
      return
    end
  elseif lastSetByUs and not allowed then
    set_cursor(cursor_default, true)
  end
  lastSetByUs = false
  ourCursor = nil   -- what's on screen now is REAPER's
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

  -- The edge sits this far from the (snapped) mouse: the fade's length, so the end
  -- of the fade-in (or start of the fade-out) follows the mouse
  if G.edge == "start" then
    G.grabOffset = -math.max(0, reaper.GetMediaItemInfo_Value(G.driver, "D_FADEINLEN") or 0)
  else
    G.grabOffset =  math.max(0, reaper.GetMediaItemInfo_Value(G.driver, "D_FADEOUTLEN") or 0)
  end

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

  recapture_states(G.edge)

  local leftEnd2,  leftNei2    = find_left_crossfade_end(G.driver)
  local rightStart2, rightNei2 = find_right_crossfade_start(G.driver)

  G.pressLeftXfadeEndAtPress = leftEnd2
  G.pressLeftXfadeNeighbor   = leftNei2
  G.pressXfadeStartAtPress   = rightStart2
  G.pressXfadeNeighbor       = rightNei2

  G.pressBoundary   = (G.edge == "start") and item_start(G.driver) or item_end(G.driver)
  G.initialMouseRaw = mTimeRaw
end

local function handle_press(hov, mTimeRaw, zone, mods)
  local cls = classify_press(hov, mTimeRaw, zone, mods)
  if DIAG_PRESS then
    local pps = reaper.GetHZoomLevel() or 1
    local s, e = item_start(hov), item_end(hov)
    reaper.ShowConsoleMsg(string.format(
      "press: REAPER cursor %s (zone %s), %.1f px from start, %.1f px from end, mods %d -> %s\n",
      CURSOR_NAME[reaperCursor or ""] or tostring(reaperCursor), tostring(zone),
      (mTimeRaw - s) * pps, (e - mTimeRaw) * pps, mods or 0,
      not cls and "REAPER's" or ((cls.grab == "edge" and (cls.joint and "joint (both edges)" or "single edge") or "body") .. " " .. cls.edge)))
  end

  if not cls or cls.modeKind == "edge" then
    locked_cursor = nil
    return
  end

  G.mode    = "body"
  G.driverWasSelected = reaper.IsMediaItemSelected(hov)
  G.grabEdge = (cls.grab == "edge")
  G.grabJoint = G.grabEdge and cls.joint == true
  G.pressMouseTime = mTimeRaw
  G.driver  = hov
  G.edge    = cls.edge
  G.modeKind = cls.modeKind
  G.initialMouseRaw = mTimeRaw
  -- rippleApplied and initialPressDelta are already 0 from new_G()

  freeze_scope(hov, G.edge)

  locked_cursor = cursor_for_mode(G.edge)
  if __rt_allow_custom_cursor_now() and locked_cursor then
    set_cursor(locked_cursor)
  else
    set_cursor(cursor_default, true)
  end

  local pressBoundary = (G.edge == "start") and item_start(G.driver) or item_end(G.driver)

  if cls.grab == "edge" then
    -- The edge itself was grabbed: it doesn't jump, it follows the mouse from here
    G.grabEdge        = true
    G.pressBoundary   = pressBoundary
    G.initialMouseRaw = mTimeRaw
    G.grabOffset      = pressBoundary - mTimeRaw
  elseif BODY_SET_EDGE_ON_PRESS then
    local slidingCrossfade = RippleOff() and G.slides and G.slides[G.driver]

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
    G.grabOffset      = pressBoundary - mTimeRaw
  end
end

-- While dragging: if the mouse is left or right of the arrange (over the track
-- panel, or past the right side), scroll toward it and use the time at the arrange's
-- edge (REAPER's mouse context has no timeline time there)
local function drag_mouse_time(mTimeRaw)
  if not (ARRANGE and reaper.JS_Window_ScreenToClient and reaper.JS_Window_GetClientSize) then return mTimeRaw end
  local mx, my = reaper.GetMousePosition()
  local cx = reaper.JS_Window_ScreenToClient(ARRANGE, mx, my)
  local okW, w = reaper.JS_Window_GetClientSize(ARRANGE)
  if type(okW) == "number" and w == nil then w = okW end   -- returns (w, h) or (ok, w, h)
  if not cx or not w or w <= 0 then return mTimeRaw end
  if cx >= 0 and cx <= w then return mTimeRaw end
  local pps = reaper.GetHZoomLevel() or 1
  if pps <= 0 then pps = 1e-6 end
  local vs, ve = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  if AUTOSCROLL then
    local over  = (cx < 0) and cx or (cx - w)
    local shift = (over * AUTOSCROLL_RATE) / pps
    local ns = math.max(0, vs + shift)
    if ns ~= vs then
      reaper.GetSet_ArrangeView2(0, true, 0, 0, ns, ns + (ve - vs))
      vs = ns
    end
  end
  return vs + ((cx < 0) and 0 or w) / pps
end

local dragFrame = 0
local function handle_drag(mTimeRaw)
  mTimeRaw = drag_mouse_time(mTimeRaw)
  dragFrame = dragFrame + 1
  ENV_NOW = (ENV_UPDATE_FRAMES <= 1) or (dragFrame % ENV_UPDATE_FRAMES == 0)
  local pressBoundary = (G.edge=="start")
    and (G.pressBoundary or item_start(G.driver))
     or (G.pressBoundary or item_end(G.driver))

  -- Where the edge goes: the (snapped) mouse time, plus the edge's offset from it.
  -- Nothing moves until the mouse leaves the deadband around the press.
  local rawDelta = (mTimeRaw - G.initialMouseRaw)
  local delta
  if G.grabOffset == nil then
    delta = snapped_delta_from_raw(rawDelta, pressBoundary, px_to_time(DRAG_DEADBAND_PX))
  elseif math.abs(rawDelta) < px_to_time(DRAG_DEADBAND_PX) then
    delta = 0
  elseif G.grabEdge then
    -- grabbed edge: the edge (not the mouse) snaps to the grid
    local raw    = mTimeRaw + G.grabOffset
    local target = SnapEnabled() and reaper.SnapToGrid(0, raw) or raw
    delta = target - pressBoundary
  else
    local target = SnapEnabled() and reaper.SnapToGrid(0, mTimeRaw) or mTimeRaw
    delta = (target + G.grabOffset) - pressBoundary
  end

  do
    local stD = G.initStates and G.initStates[G.driver]
    if stD and valid_item(G.driver) and (not is_locked(G.driver)) then
      delta = clamp_to_source(G.driver, stD, G.edge, delta)
    end
  end

  if __rt_allow_custom_cursor_now() and locked_cursor then
    set_cursor(locked_cursor)
  else
    set_cursor(cursor_default, true)
  end

  -- One move for every trimmed item and the crossfade neighbors sliding with
  -- them, so they all stay together and stop together
  delta = trim_all(G.edge, delta)

  ENV_NOW = true

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

-- Like the Move Tool's click: the trimmed items are selected (if the clicked item
-- was already selected, the selection is kept and they're added to it), the edit
-- cursor goes to the start of the selection, and with Link Timeline and Edit
-- Selection on, the loop points span the selection. The view doesn't scroll and
-- playback doesn't jump.
local function link_timeline_on()
  local cmd = reaper.NamedCommandLookup(LINK_CMD_GUID)
  return cmd ~= 0 and reaper.GetToggleCommandStateEx(0, cmd) == 1
end
local function select_and_place_cursor()
  if not G.driverWasSelected then reaper.SelectAllMediaItems(0, false) end
  for it,_ in pairs(G.editedSet or {}) do
    if valid_item(it) and (SELECT_EDGE_MATCHED or not (G.edgeMatched and G.edgeMatched[it])) then
      reaper.SetMediaItemSelected(it, true)
    end
  end
  local s, e = math.huge, -math.huge
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local p = item_start(it)
      if p < s then s = p end
      if p + item_len(it) > e then e = p + item_len(it) end
    end
  end
  if s == math.huge then return end
  reaper.SetEditCurPos(s, false, false)
  if e > s and link_timeline_on() then reaper.GetSet_LoopTimeRange(true, true, s, e, false) end
end

local function handle_release()
  -- An edge grabbed and let go without moving changes nothing: no undo point
  if G.grabEdge and valid_item(G.driver)
     and math.abs(current_edge_pos(G.driver, G.edge) - (G.pressBoundary or 0)) < 1e-9 then
    select_and_place_cursor()
    G = new_G()
    locked_cursor = nil
    return
  end
  -- One undo point for the whole gesture: the live drag made no undo points,
  -- so this block (opened here, closed below) captures press-to-release.
  begin_undo()
  flush_take_envelopes(G.initStates, G.slides)
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
  select_and_place_cursor()
  end_undo("Trim items")

  G = new_G()
  locked_cursor = nil
end

local mode_handlers = {
  body = function(mouseDown, hov, mTimeRaw)
    if not valid_item(G.driver) then
      reaper.Undo_OnStateChange("Trim items")   -- keep what the drag already changed undoable
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

  if not __rt_is_reaper_foreground() and lastSetByUs then
    set_cursor(cursor_default, true)
    lastSetByUs = false
  end

  -- Refresh cursor context exactly once per frame.
  refresh_cursor_context()
  read_reaper_cursor()

  local mouseDown = reaper.JS_Mouse_GetState(1) == 1
  local mods      = reaper.JS_Mouse_GetState(4 | 8 | 16 | 32)   -- Ctrl/Cmd, Shift, Alt/Opt, Win/Ctrl
  local hov       = hovered_item()
  local mTimeRaw  = get_mouse_time_raw()
  -- What REAPER showed before the button went down (it can change its cursor on the press)
  local pressZone = hoverZone
  if not mouseDown then hoverZone = reaper_zone() end

  -- Cursor over items, only with the button up (not during REAPER's own drags)
  if G.mode == "none" and not mouseDown then
    handle_hover(hov, mTimeRaw)
  end

  local pressed = false
  if G.mode == "none" then
    local c = MSG_OK and new_click() or nil
    if c then
      local px, py, tClick, useCtx = click_point(c, mouseDown)
      local it = reaper.GetItemFromPoint(px, py, false)
      if valid_item(it) and not is_locked(it) then
        handle_press(it, tClick or mTimeRaw, pressZone, mods)
        pressed = true
        -- Pressed and released between two checks: finish the click now
        if G.mode == "body" and not mouseDown then handle_release() end
      end
    elseif (not MSG_OK) and mouseDown and not prevMouseDown
       and valid_item(hov) and not is_locked(hov) then
      handle_press(hov, mTimeRaw, pressZone, mods)
    end
  end

  local was_trimming = (G.mode ~= "none")
  local handler = mode_handlers[G.mode]
  if handler then
    handler(mouseDown, hov, mTimeRaw)
  end

  prevMouseDown = mouseDown
  -- Redraw only while a trim is in progress, and once more as it ends
  if pressed or was_trimming or G.mode ~= "none" then reaper.UpdateArrange() end
  reaper.defer(main)
end

main()
