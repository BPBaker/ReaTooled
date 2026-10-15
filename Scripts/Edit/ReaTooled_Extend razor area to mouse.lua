-- @description ReaTooled - Razor From Cursor To Mouse
-- @version 2.1
-- @date 2026.04.13
-- @author Brendan Baker
-- @about
--   # Creates or extends a razor edit area across multiple tracks.
--   # Behavior:
--   #   - No razor exists anywhere: creates razor from pre-click cursor to mouse on selected tracks.
--   #   - Razor exists, mouse is on a track with a razor, mouse is outside union bounds:
--   #       extends union bounds toward mouse, writes to all tracks with a razor.
--   #   - Razor exists, mouse is on a track with a razor, mouse is inside union bounds:
--   #       trims nearest edge of union bounds to mouse position, writes to all tracks with a razor.
--   #   - Razor exists, mouse is on a track without a razor:
--   #       adds that track to the razor group using existing union bounds unchanged.
--   # Requires ReaTooled - Link Razor Area to Item Selection (Context-Aware) v4.6+ to be running.
--   # Assign to a left-click mouse modifier in Arrange view.
-- @changelog
--   v2.1 - Multi-track support: razor bounds now use union across all tracks with a razor;
--          clicking a track without a razor adds it to the group using existing bounds;
--          creating a new razor now applies to all selected tracks

local reaper = reaper
local DEBUG = false

local function Msg(str)
  if DEBUG then reaper.ShowConsoleMsg(str .. "\n") end
end

local EPSILON = 0.0001

-- Get track under mouse
local mouse_x, mouse_y = reaper.GetMousePosition()
local track = reaper.GetTrackFromPoint(mouse_x, mouse_y)
if not track then Msg("[ERROR] No track under mouse.") return end

-- pos_B: where the mouse clicked (and where the cursor now is)
local pos_B = reaper.BR_PositionAtMouseCursor(false)
if not pos_B then Msg("[ERROR] Could not get mouse time.") return end
Msg("[DEBUG] pos_B (click position): " .. pos_B)

-- pos_A: where the cursor was before this click, tracked by background script
local last_cursor_str = reaper.GetExtState("ReaTooled", "lastcursor")
local pos_A = tonumber(last_cursor_str)
if not pos_A then Msg("[ERROR] No lastcursor ExtState found — is the item selection script running?") return end
Msg("[DEBUG] pos_A (pre-click cursor): " .. pos_A)

-- Collect all tracks that have a razor area and compute union bounds
local tracks_with_razor = {}
local union_start = math.huge
local union_end = -math.huge

for i = 0, reaper.CountTracks(0) - 1 do
  local t = reaper.GetTrack(0, i)
  local _, area_string = reaper.GetSetMediaTrackInfo_String(t, "P_RAZOREDITS", "", false)
  local start_s, end_s = area_string:match("(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)%s+\".-\"")
  local r_start = tonumber(start_s)
  local r_end = tonumber(end_s)
  if r_start and r_end and math.abs(r_end - r_start) > EPSILON then
    table.insert(tracks_with_razor, t)
    if r_start < union_start then union_start = r_start end
    if r_end > union_end then union_end = r_end end
  end
end

local has_any_razor = #tracks_with_razor > 0
local mouse_track_has_razor = false
for _, t in ipairs(tracks_with_razor) do
  if t == track then
    mouse_track_has_razor = true
    break
  end
end

Msg("[DEBUG] has_any_razor: " .. tostring(has_any_razor))
Msg("[DEBUG] mouse_track_has_razor: " .. tostring(mouse_track_has_razor))
if has_any_razor then
  Msg("[DEBUG] Union bounds: " .. union_start .. " - " .. union_end)
end

reaper.Undo_BeginBlock()

if not has_any_razor then
  -- Case 1: No razor exists anywhere — create on selected tracks from pos_A to pos_B
  if math.abs(pos_B - pos_A) <= EPSILON then
    Msg("[INFO] pos_A == pos_B, nothing to do.")
    reaper.Undo_EndBlock("Set razor area", -1)
    return
  end

  local new_start = math.min(pos_A, pos_B)
  local new_end = math.max(pos_A, pos_B)
  local new_area = string.format("%f %f \"reatooled\"", new_start, new_end)
  Msg("[DEBUG] Creating razor on selected tracks: " .. new_area)

  for i = 0, reaper.CountTracks(0) - 1 do
    local t = reaper.GetTrack(0, i)
    if reaper.IsTrackSelected(t) then
      reaper.GetSetMediaTrackInfo_String(t, "P_RAZOREDITS", new_area, true)
    end
  end

elseif not mouse_track_has_razor then
  -- Case 4: Razor exists but mouse is on a track without one
  -- Add that track using existing union bounds unchanged
  local new_area = string.format("%f %f \"reatooled\"", union_start, union_end)
  Msg("[DEBUG] Adding mouse track to razor group with union bounds: " .. new_area)
  reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", new_area, true)

else
  -- Cases 2 & 3: Razor exists and mouse is on a track that has one
  local new_start = union_start
  local new_end = union_end

  if pos_B < union_start then
    -- Case 2a: Mouse is left of union — extend start
    Msg("[DEBUG] Extending union start to: " .. pos_B)
    new_start = pos_B

  elseif pos_B > union_end then
    -- Case 2b: Mouse is right of union — extend end
    Msg("[DEBUG] Extending union end to: " .. pos_B)
    new_end = pos_B

  else
    -- Case 3: Mouse is inside union — trim nearest edge (left bias at midpoint)
    local mid = union_start + (union_end - union_start) / 2
    if pos_B <= mid then
      Msg("[DEBUG] Trimming union start to: " .. pos_B)
      new_start = pos_B
    else
      Msg("[DEBUG] Trimming union end to: " .. pos_B)
      new_end = pos_B
    end
  end

  local new_area = string.format("%f %f \"reatooled\"", new_start, new_end)
  Msg("[DEBUG] Writing updated razor to all razor tracks: " .. new_area)
  for _, t in ipairs(tracks_with_razor) do
    reaper.GetSetMediaTrackInfo_String(t, "P_RAZOREDITS", new_area, true)
  end
end

reaper.Undo_EndBlock("Extend razor area", -1)
reaper.UpdateArrange()
