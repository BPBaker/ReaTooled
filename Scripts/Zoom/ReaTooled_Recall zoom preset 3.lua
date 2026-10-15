-- @noindex
-- ReaTooled: Recall horizontal zoom preset 3 (Pro Tools style)
local dir = debug.getinfo(1, "S").source:match([[^@?(.*[\/])]])
local Z = dofile(dir .. "ReaTooled_Zoom presets lib.lua")
Z.recall(3)
