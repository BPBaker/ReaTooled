--[[
-- @description ReaTooled - Renamed scripts (data for Set up ReaTooled, not an action)
-- @version 1.2
-- @author Brendan Baker
-- @noindex
-- @about
    Scripts renamed, moved or removed since earlier ReaTooled releases, so an update
    keeps users' shortcuts, toolbar and menu buttons and mouse modifiers pointing at
    the right script. Paths are within Scripts/ReaTooled/.
      renamed or moved: ["Folder/Old name.lua"] = "Folder/New name.lua",
      removed:          ["Folder/Old name.lua"] = false,
    Another developer's script that a ReaTooled script replaces: its path within
    Scripts/, starting with "/" (a ReaPack-installed copy is found there):
      replaced:         ["/Their folder/Their script.lua"] = "Folder/New name.lua",
    Their script stays installed; only ReaTooled's shortcuts, buttons, menus and mouse
    modifiers move to ReaTooled's script.
    Never take an entry out: someone may update from an old release.
    ReaTooled_Build_release.lua warns about any script that left the release
    without an entry here.
--]]
return {
  -- 2026-11-07: replaced by Toggles/ReaTooled_Toggle Ripple edit when editing media item left edges.lua
  ["Edit/ReaTooled_Ripple left edge.lua"] = false,

  -- 2026-11-20 (v3.01): TJF's scripts replaced by ReaTooled's own versions
  ["/TJF Scripts/Editing/TJF Toggle Item Lock (matches first item).lua"] = "Edit/ReaTooled_Toggle item lock.lua",
  ["/TJF Scripts/Editing/Takes/TJF Toggle Mute (Match First Selected).lua"] = "Edit/ReaTooled_Toggle mute.lua",
  ["/TJF Scripts/Editing/Reverse/TJF Non Destructive Reverse Time selection.lua"] = "Edit/ReaTooled_Reverse (non-destructive).lua",
  ["/TJF Scripts/Envelopes or Automation/TJF Write Punch ALL envelopes to Time, RazorEdit, or Item Selection.lua"] = "Edit/ReaTooled_Write current value to all envelopes in selection.lua",
  ["/TJF Scripts/Session Navigation/TJF Increase Selected Track Heights.lua"] = "Tracks/ReaTooled_Increase selected track heights.lua",
  ["/TJF Scripts/Session Navigation/TJF Decrease Selected Track Heights.lua"] = "Tracks/ReaTooled_Decrease selected track heights.lua",

  -- 2026-11-20 (v3.02): X-Raym's and Rodilab's scripts replaced by ReaTooled's own versions
  ["/X-Raym Scripts/Envelopes/On Tracks/X-Raym_Add envelope points at time selection edges from center to center preserving edges.lua"] = "Edit/ReaTooled_Add envelope points at selection edges (center value inside).lua",
  ["/ReaTeam Scripts/Items Properties/rodilab_Loop section of audiomidi item source within time selection, if any.lua"] = "Edit/ReaTooled_Loop item source section (razor area or time selection).lua",
}
