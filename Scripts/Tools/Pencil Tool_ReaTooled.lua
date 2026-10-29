-- @description ReaTooled - Pencil Tool
-- @version 1.1
-- @date 2026.10.28
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about
--   # Loads mouse modifiers for drawing, similar to Pro Tools' "Pencil Tool"
--     - Automation (envelope lanes, segments and points): drag draws freehand
--     - Clip gain: click an audio item to add a point to its take volume
--       envelope (the envelope is created and shown if needed); drag on the
--       envelope line to draw freehand
--     - Zoomed in to sample level: drag redraws the waveform (REAPER's sample
--       edits)
--     - Empty track space: drag draws an empty MIDI item
--     - Items never move or trim with the Pencil
--   Sample edits: when you're zoomed in to draw samples and the item under the
--   mouse has its sample edits bypassed, they're turned on for that item only
--   (by a small background script that stops when you choose another tool).
--   Other items, and the other tools, leave sample edits as they are.
-- @changelog
--   v1.1 Sample edits are turned on only for the item you're about to draw on
--        (no longer toggled for the selected items by running it again)
--   v1.0 Initial version

local _, script_path = reaper.get_action_context()
local dir = script_path:match("^(.*[/\\])") or ""

local ok, tools = pcall(dofile, dir .. "ReaTooled_Tools lib.lua")
if not ok or type(tools) ~= "table" then
  reaper.ShowMessageBox("ReaTooled_Tools lib.lua is missing from:\n" .. dir ..
    "\n\nUpdate ReaTooled in ReaPack (Extensions > ReaPack > Synchronize packages).", "ReaTooled", 0)
  return
end

----------------------------------------
-- Companion script for clicks on items
----------------------------------------
local function script_action(file)
  local path = dir .. file
  if not reaper.file_exists(path) then return "0" end
  local id = reaper.AddRemoveReaScript(true, 0, path, true)
  if not id or id == 0 then return "0" end
  return "_" .. reaper.ReverseNamedCommandLookup(id)
end
local PENCIL_CLICK = script_action("ReaTooled_Pencil click on item.lua")

----------------------------------------
-- Mouse modifiers (every key of these contexts, like the other tools)
----------------------------------------
local function all(v, first)
  local t = {}
  for i = 0, 15 do t[i] = v end
  if first then t[0] = first end
  return t
end

tools.set_mods({
  -- Items: no moving or trimming; a click adds a clip gain point
  MM_CTX_ITEM             = all("0"),
  MM_CTX_ITEMLOWER        = all("0"),
  MM_CTX_ITEM_CLK         = all("-1", PENCIL_CLICK),
  MM_CTX_ITEMLOWER_CLK    = all("-1", PENCIL_CLICK),
  MM_CTX_ITEM_DBLCLK      = all("-1", "0"),
  MM_CTX_ITEMLOWER_DBLCLK = all("-1", "0"),
  -- Empty track space: drag draws an empty MIDI item
  MM_CTX_TRACK            = all("0", "5 m"),   -- 5 m = Draw an empty MIDI item
  MM_CTX_TRACK_CLK        = all("-1"),
})
tools.enter_pencil()   -- envelopes and sample edits (put back by the other tools)

-- Background helper: turns sample edits on for the item you're about to draw on
do
  local alive = tonumber(reaper.GetExtState("ReaTooled", "PencilSampleEditsAlive")) or 0
  if reaper.time_precise() - alive > 1 then
    local path = dir .. "ReaTooled_Pencil sample edits (background).lua"
    if reaper.file_exists(path) then
      local id = reaper.AddRemoveReaScript(true, 0, path, true)
      if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end
    end
  end
end

----------------------------------------
-- Locking: off, so take envelopes (clip gain) can be drawn
----------------------------------------
reaper.Main_OnCommand(40570, 0) -- Disable locking
reaper.Main_OnCommand(42621, 0) -- Clear arrange override mode

tools.finish("pencil")
