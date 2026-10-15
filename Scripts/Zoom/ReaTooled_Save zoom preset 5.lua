-- @noindex
-- ReaTooled: Save current horizontal zoom to preset 5 (Pro Tools style)
local dir = debug.getinfo(1, "S").source:match([[^@?(.*[\/])]])
local Z = dofile(dir .. "ReaTooled_Zoom presets lib.lua")
Z.save(5)
