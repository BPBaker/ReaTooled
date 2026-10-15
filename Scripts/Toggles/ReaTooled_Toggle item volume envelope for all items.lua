-- @description ReaTooled ToggleToggle visibility of all take volume envelopes
-- @date 2025.03.21
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @version 1.0
-- @description Toggle visibility of all take volume envelopes (corrected with cmd 40693)
-- To be used in conjunction with "ReaTooled_Play-Stop (with memory, edit-play toggles, and no undo).lua"
-- CHANGELOG
-- v1.0 -


local reaper = reaper
reaper.ClearConsole()

local function msg(str)
  reaper.ShowConsoleMsg(tostring(str) .. "\n")
end

local function should_show()
  local item_cnt = reaper.CountMediaItems(0)
  for i = 0, item_cnt - 1 do
    local item = reaper.GetMediaItem(0, i)
    local take_cnt = reaper.CountTakes(item)
    for j = 0, take_cnt - 1 do
      local take = reaper.GetMediaItemTake(item, j)
      if take then
        local env = reaper.GetTakeEnvelopeByName(take, "Volume")
        if not env then return true end
        local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
        if ok and chunk:match("VIS%s+0") then return true end
      end
    end
  end
  return false
end

local function select_only(item, take)
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  reaper.SetMediaItemSelected(item, true)
  reaper.SetActiveTake(take)
end

local function ensure_env_exists(item, take)
  local env = reaper.GetTakeEnvelopeByName(take, "Volume")
  if env then return env end
  select_only(item, take)
  reaper.Main_OnCommand(40693, 0) -- ✅ Correct: Take: Toggle take volume envelope
  return reaper.GetTakeEnvelopeByName(take, "Volume")
end

local function set_env_visibility(env, visible)
  if not env then return end
  local ok, chunk = reaper.GetEnvelopeStateChunk(env, "", false)
  if not ok then return end
  local vis_line = visible and "VIS 1" or "VIS 0"
  chunk = chunk:gsub("VIS%s+%d+", vis_line)
  reaper.SetEnvelopeStateChunk(env, chunk, false)
end

-- === MAIN ===
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local show = should_show()
local item_cnt = reaper.CountMediaItems(0)
--msg("Toggling envelopes to " .. (show and "SHOW" or "HIDE"))

for i = 0, item_cnt - 1 do
  local item = reaper.GetMediaItem(0, i)
  local take_cnt = reaper.CountTakes(item)
  for j = 0, take_cnt - 1 do
    local take = reaper.GetMediaItemTake(item, j)
    if take then
      local env = ensure_env_exists(item, take)
      set_env_visibility(env, show)
    end
  end
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Toggle take volume envelopes (fixed)", -1)


