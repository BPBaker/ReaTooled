--[[
-- @description ReaTooled - Recall ReaTooled Button States
-- @version 1.6
-- @date 2026.10.29
-- @author Brendan Baker
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
    # Recalls various ReaTooled Button States
-- CHANGELOG
-- v1.6 Recalls Shuffle mode (if REAPER still has per-track ripple)
-- v1.5 Recalls the "Toggle swap left and right drag" button
-- v1.4 Scripts are found by file path instead of hard-coded command IDs, so
--      renames show up here as readable lines. Corrected section comments
--      (no behavior changes).
-- v1.3 Updated layered edit for more robust recall and removed Ripple All Marker button (now native preference)
-- v1.2 updated to new script IDS
-- v1.1 Add "Link Loop Point and Razor Areas," delete "PlayCursorLinkState"
--]]

------------------------------------------------------------
-- Find a ReaTooled script's command ID from its path
-- (relative to Scripts/ReaTooled/). Returns 0 if the file is missing.
------------------------------------------------------------
local BASE = reaper.GetResourcePath():gsub("\\", "/") .. "/Scripts/ReaTooled/"

local function cmd(rel_path)
  local path = BASE .. rel_path
  if not reaper.file_exists(path) then return 0 end
  return reaper.AddRemoveReaScript(true, 0, path, true) or 0
end

local function run(id)
  if id ~= 0 then reaper.Main_OnCommand(id, 0) end
end

local function set_button(id, on)
  if id ~= 0 then
    reaper.SetToggleCommandState(0, id, on and 1 or 0)
    reaper.RefreshToolbar2(0, id)
  end
end

------------------------------------------------------------
-- Scripts this recall depends on
------------------------------------------------------------
local TAB_TO_TRANSIENT     = cmd("Toggles/ReaTooled_Toggle Tab to Transient.lua")
local LINK_PLAY_EDIT_BTN   = cmd("Toggles/ReaTooled_Toggle Link Play Cursor to Edit Cursor.lua")
local LINK_PLAY_EDIT_BG    = cmd("Startup/ReaTooled_Enable Link Edit Cursor and Play Cursor.lua")
local LINK_TRACK_ITEM_BTN  = cmd("Toggles/ReaTooled_Toggle Link Track and Item and Razor Selection.lua")
local LINK_TRACK_ITEM_BG   = cmd("Toggles/ReaTooled_Link Track and Item and Razor Selection.lua")
local EDIT_FOLLOWS_PLAY    = cmd("Toggles/ReaTooled_Toggle Edit Cursor follows Playback on Stop.lua")
local RECALL_HOVER_MODE    = cmd("Startup/ReaTooled_Recall Hover Mode State.lua")
local REATOOLED_SHORTCUTS  = cmd("Toggles/ReaTooled_Toggle ReaTooled Shortcuts.lua")
local LAYERED_EDITING      = cmd("Toggles/ReaTooled_Toggle Layered Editing.lua")
local SLIP_INDICATOR       = cmd("Toggles/ReaTooled - Ripple Off (Slip).lua")
local DRAG_SWAP            = cmd("Tools/ReaTooled_Toggle swap left and right drag.lua")
local SHUFFLE_MODE         = cmd("Tools/ReaTooled_Toggle Shuffle mode.lua")


-- TAB TO TRANSIENT
if tonumber(reaper.GetExtState("ReaTooled", "TabToTransientState")) == 1 then
  run(TAB_TO_TRANSIENT)
end

-- LINK PLAY CURSOR TO EDIT CURSOR
-- (The ExtState key is still called "LinkLoopRazor" for historical reasons;
--  the toggle script reads and writes that key, so don't rename it here alone.)
if reaper.GetExtState("ReaTooled", "LinkLoopRazor") == "1" then
  -- Only visually turn ON the toggle button
  set_button(LINK_PLAY_EDIT_BTN, true)
  -- Then also silently start the background script, without flipping ExtState
  run(LINK_PLAY_EDIT_BG)
else
  -- Only visually turn OFF the toggle button
  set_button(LINK_PLAY_EDIT_BTN, false)
  -- No need to kill background script if extstate is off
end

-- LINK TRACK AND ITEM AND RAZOR SELECTION
if tonumber(reaper.GetExtState("ReaTooled", "LinkTrackItemState")) == 1 then
  reaper.SetExtState("ReaTooled", "LinkTrackItemState", "1", true)
  set_button(LINK_TRACK_ITEM_BTN, true)   -- toolbar button on
  run(LINK_TRACK_ITEM_BG)                 -- start the background script
end

-- EDIT CURSOR FOLLOWS PLAYBACK ON STOP (ensure desired state)
do
  local want_on = (tonumber(reaper.GetExtState("ReaTooled", "EditFollowsPlaybackState")) == 1)
  if EDIT_FOLLOWS_PLAY ~= 0 then
    local is_on = (reaper.GetToggleCommandStateEx(0, EDIT_FOLLOWS_PLAY) == 1)
    if is_on ~= want_on then
      run(EDIT_FOLLOWS_PLAY)  -- flip once to reach desired state
    end
    set_button(EDIT_FOLLOWS_PLAY, want_on)
  end
end

-- HOVER MODE
if tonumber(reaper.GetExtState("ReaTooled", "HoverModeState")) == 1 then
  run(RECALL_HOVER_MODE)
end

-- REATOOLED SHORTCUTS (keymap on/off)
if tonumber(reaper.GetExtState("ReaTooled", "ReaTooledKeymapOn")) == 1 then
  run(REATOOLED_SHORTCUTS)
end

-- LAYERED EDITING (robust recall)
do
  local want_on = (reaper.GetExtState("ReaTooled", "LayeredEditingOn") == "1")

  -- Read actual REAPER option states
  local TRIM_TOGGLE   = 41119   -- Options: Trim content behind media items (toggle) [for reading]
  local OFFSET_TOGGLE = 40507   -- Options: Offset overlapping media items vertically (toggle)
  local trim_is_on = reaper.GetToggleCommandState(TRIM_TOGGLE) == 1
  local offs_is_on = reaper.GetToggleCommandState(OFFSET_TOGGLE) == 1
  local layered_is_on = (not trim_is_on) and offs_is_on

  -- Only call the toggle script if we need to change the real setting
  if LAYERED_EDITING ~= 0 and (want_on ~= layered_is_on) then
    run(LAYERED_EDITING)  -- the toggle script enforces deterministically
  end

  -- Ensure toolbar button matches the desired recall state
  set_button(LAYERED_EDITING, want_on)
end

-- SWAP LEFT AND RIGHT DRAG (button only: the mouse settings are kept by REAPER)
set_button(DRAG_SWAP, reaper.GetExtState("ReaTooled", "DragSwap") == "1")

-- SLIP INDICATOR (Ripple Off)
run(SLIP_INDICATOR)

-- SHUFFLE MODE (recalled without toggling; stays off unless per-track ripple is on)
if reaper.GetExtState("ReaTooled", "ShuffleMode") == "1" then
  reaper.SetExtState("ReaTooled", "ShuffleRecall", "1", false)
  run(SHUFFLE_MODE)
else
  set_button(SHUFFLE_MODE, false)
end

-- === Force ripple option states on startup ===
local function ensure(command, want_on)
  local is_on = (reaper.GetToggleCommandStateEx(0, command) == 1)
  if is_on ~= want_on then reaper.Main_OnCommand(command, 0) end
end

reaper.defer(function()
  ensure(43475, true)   -- Ripple edit when editing media item edges
  ensure(43467, true)   -- Ripple per-track affects each track lane separately
end)
