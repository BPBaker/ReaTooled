-- @description ReaTooled - Earlier settings (data for Set up ReaTooled)
-- @version 1.0
-- @author Brendan Baker
-- @about
--   Not an action. The values earlier ReaTooled releases (v2.1, v2.6.1) gave the reaper.ini
--   settings ReaTooled sets ("setting" in Data/ReaTooled/Config/reaper_sections_rules.txt).
--   A user who still has one of these never changed it, so "Set up ReaTooled" updates it;
--   any other value is the user's own and is kept.

return {
  ["dynamicsplit"] = {
    ["beatbase"] = { "1" },
    ["chrommidi"] = { "0" },
    ["dostretchmarkers"] = { "0" },
    ["gatehyst"] = { "-600" },
    ["gatethresh"] = { "-2400" },
    ["lastsplitslider"] = { "15" },
    ["leadpad"] = { "0" },
    ["minsilence"] = { "500000" },
    ["minslice"] = { "500000" },
    ["padfade"] = { "0" },
    ["removesilence"] = { "1" },
    ["snapoffs"] = { "0" },
    ["snapoffstime"] = { "5000" },
    ["splitcnten"] = { "0" },
    ["splitflag"] = { "6" },
    ["splitgroups"] = { "0" },
    ["trailpad"] = { "0" },
  },
  ["bigclock"] = {
    ["fgcolor"] = { "-1" },
    ["time_mode"] = { "0" },
  },
}
