--[[
  ReaTooled_Clipboard Manager - Copy and capture.lua

  Performs REAPER's native "Edit: Copy items" AND stores the same selection as
  a Clipboard Manager entry, in one keystroke. Bind this over Ctrl+C so every
  copy is automatically recallable.

  If nothing is selected it does nothing, leaving the existing clipboard alone.

  Author: ReaTooled
  Licence: MIT
]]--

local sep = package.config:sub(1, 1)
local script_dir = ({reaper.get_action_context()})[2]:match('^(.*' .. sep .. ')')
package.path = script_dir .. '?.lua;' .. package.path

local ok, CM = pcall(require, 'ReaTooled_ClipboardManager_core')
if not ok then
  reaper.MB('Could not load ReaTooled_ClipboardManager_core.lua.\n\n' ..
            'It must sit in the same folder as this script.',
            'Clipboard Manager', 0)
  return
end

local function main()
  if reaper.CountSelectedMediaItems(0) == 0 then return end

  -- Native copy first, so the real clipboard is authoritative.
  reaper.Main_OnCommand(CM.CMD_COPY_ITEMS, 0)

  local entry, err = CM.capture_items()
  if entry then
    CM.save(entry)
  elseif err then
    reaper.ShowConsoleMsg('Clipboard Manager: ' .. err .. '\n')
  end
end

main()
reaper.defer(function() end)
