--[[
-- @description ReaTooled - Renamed scripts (data for Set up ReaTooled, not an action)
-- @version 1.0
-- @author Brendan Baker
-- @noindex
-- @about
    Scripts renamed, moved or removed since earlier ReaTooled releases, so an update
    keeps users' shortcuts, toolbar and menu buttons and mouse modifiers pointing at
    the right script. Paths are within Scripts/ReaTooled/.
      renamed or moved: ["Folder/Old name.lua"] = "Folder/New name.lua",
      removed:          ["Folder/Old name.lua"] = false,
    Never take an entry out: someone may update from an old release.
    ReaTooled_Build_release.lua warns about any script that left the release
    without an entry here.
--]]
return {
  -- 2026-11-07: replaced by Toggles/ReaTooled_Toggle Ripple edit when editing media item left edges.lua
  ["Edit/ReaTooled_Ripple left edge.lua"] = false,
}
