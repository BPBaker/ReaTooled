--[[
-- @description ReaTooled - Magic Zero Crossing Loop Copy Buffer Maker (Good for Room Tone)
-- @version 1.0
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
    # Turns a razor edit (or time selection) into a looping, click-free
    section and copies it, ready to paste as room tone.
    1. Sets the time selection to the razor edit areas (if there are any)
    2. Splits the item at the nearest zero crossings to the start and end
    3. Turns on "Loop source" for the section and loops that part of the source
    4. Smart-copies it
    Replaces the custom action of the same name, without needing the TJF and
    Lokasenna scripts it used.
-- CHANGELOG
-- v1.0 Initial version (from the custom action)
--]]

local TITLE = "Magic Zero Crossing Loop Copy Buffer Maker"

------------------------------------------------------------
-- Native actions, found by their exact names (so the script doesn't depend
-- on command numbers). The number is only a first guess to check quickly.
------------------------------------------------------------

local function find_cmd(name, guess)
  if guess and reaper.kbd_getTextFromCmd(guess, 0) == name then return guess end
  for id = 1, 65535 do
    if reaper.kbd_getTextFromCmd(id, 0) == name then return id end
  end
  return nil
end

local ACTIONS = {
  { key = "go_start",   name = "Go to start of time selection",                     guess = 40630 },
  { key = "zero",       name = "Move edit cursor to nearest zero crossing in items" },
  { key = "split_right",name = "Item: Split items at edit cursor (select right)",   guess = 40759 },
  { key = "go_end",     name = "Go to end of time selection",                       guess = 40631 },
  { key = "split_left", name = "Item: Split items at edit cursor (select left)",    guess = 40758 },
  { key = "loop_sect",  name = "Item properties: Loop section of audio item source" },
  { key = "smart_copy", name = "Edit: Copy items/tracks/envelope points (depending on focus) " ..
                                "within time selection, if any (smart copy)",       guess = 41383 },
}

local cmd, missing = {}, {}
for _, a in ipairs(ACTIONS) do
  cmd[a.key] = find_cmd(a.name, a.guess)
  if not cmd[a.key] then missing[#missing + 1] = a.name end
end
if #missing > 0 then
  reaper.ShowMessageBox("Could not find these REAPER actions:\n\n" ..
    table.concat(missing, "\n") .. "\n\nNothing was changed.", TITLE, 0)
  return
end

local function run(key) reaper.Main_OnCommand(cmd[key], 0) end

------------------------------------------------------------
-- Step 1: time selection = razor edit areas (replaces TJF's script)
------------------------------------------------------------

local function razor_span()
  local lo, hi
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    local _, areas = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    -- "start end envelopeGUID start end envelopeGUID ..."
    local nums = {}
    for token in areas:gmatch("%S+") do nums[#nums + 1] = token end
    for i = 1, #nums - 1, 3 do
      local s, e = tonumber(nums[i]), tonumber(nums[i + 1])
      if s and e then
        lo = (not lo or s < lo) and s or lo
        hi = (not hi or e > hi) and e or hi
      end
    end
  end
  return lo, hi
end

------------------------------------------------------------

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local rs, re = razor_span()
if rs and re and re > rs then
  reaper.GetSet_LoopTimeRange(true, false, rs, re, false)
end

local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
if te <= ts then
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(TITLE, -1)
  reaper.ShowMessageBox("Make a razor edit or a time selection first.", TITLE, 0)
  return
end

-- Step 2: split at the zero crossings nearest the start and end
run("go_start")
run("zero")
run("split_right")
run("go_end")
run("zero")
run("split_left")

-- Step 3: loop source on for the selected items (replaces Lokasenna's script),
-- then loop that section of the source
for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
end
run("loop_sect")

-- Step 4: smart copy
run("smart_copy")

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
reaper.Undo_EndBlock(TITLE, -1)
