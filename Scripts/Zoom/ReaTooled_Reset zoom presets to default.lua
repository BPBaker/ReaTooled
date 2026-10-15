-- @description ReaTooled: Pro Tools-style horizontal zoom presets
-- @author ReaTooled
-- @version 1.0
-- @about
--   Five recallable horizontal zoom presets that behave like Pro Tools'
--   zoom presets 1-5, with scripts to save the current zoom to each slot
--   and to reset slots to their defaults. Settings live in the lib file.
-- @provides
--   [nomain] ReaTooled_Zoom presets lib.lua
--   [main] ReaTooled_Recall zoom preset 1.lua
--   [main] ReaTooled_Recall zoom preset 2.lua
--   [main] ReaTooled_Recall zoom preset 3.lua
--   [main] ReaTooled_Recall zoom preset 4.lua
--   [main] ReaTooled_Recall zoom preset 5.lua
--   [main] ReaTooled_Save zoom preset 1.lua
--   [main] ReaTooled_Save zoom preset 2.lua
--   [main] ReaTooled_Save zoom preset 3.lua
--   [main] ReaTooled_Save zoom preset 4.lua
--   [main] ReaTooled_Save zoom preset 5.lua

-- ReaTooled: Reset horizontal zoom presets to default
local dir = debug.getinfo(1, "S").source:match([[^@?(.*[\/])]])
local Z = dofile(dir .. "ReaTooled_Zoom presets lib.lua")

local ok, answer = reaper.GetUserInputs("Reset zoom presets", 1,
  "Preset to reset (1-5 or all):", "all")
if not ok then reaper.defer(function() end) return end

answer = answer:lower():gsub("%s", "")
if answer == "all" or answer == "" then
  for n = 1, 5 do Z.reset(n) end
  Z.notify("All zoom presets reset to default")
else
  local n = tonumber(answer)
  if n and n >= 1 and n <= 5 and n % 1 == 0 then
    Z.reset(n)
    Z.notify("Zoom preset " .. n .. " reset to default")
  else
    reaper.ShowMessageBox("Enter a number from 1 to 5, or 'all'.", "Reset zoom presets", 0)
  end
end
