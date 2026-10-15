--[[
  ReaTooled_Clipboard Manager - Capture selection.lua

  Stores the current item selection as a Clipboard Manager entry WITHOUT
  touching the clipboard. Useful for bookmarking a set you want later without
  disturbing what you have copied right now.

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

local entry, err = CM.capture_items()
if entry then
  CM.save(entry)
else
  reaper.MB(err or 'Nothing to capture.', 'Clipboard Manager', 0)
end

reaper.defer(function() end)
