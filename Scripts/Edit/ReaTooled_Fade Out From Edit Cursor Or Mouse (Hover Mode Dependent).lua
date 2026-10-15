--[[
-- @description ReaTooled - Fade Out From Edit Cursor or Mouse (Hover Mode Dependant)
-- @version 1.2
-- @date 2024.11.20
-- @author Brendan Baker copied from TJF/Tim Farrell (http://github.com/sonictim/TJF-Scripts/)
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
  # Adjusted to work with the modified ReaTooled Hover Edit Mode script ("_RS7cb08a92f7a211ce66734644b4fbe99a91bd42f5") 
  # TJF Fade Out from Edit Cursor or Mouse (Hover Mode Dependant)
    Depending on Status of Hover mode will either fade out from edit cursor or mouse cursor
    Recommend Assigning to "G" key
#changelog
    v1.0 initial release
    v1.1 bug fixes
    v1.2 change SetEditCurPos to not move view when fading
  
  
--]]

reaper.Undo_BeginBlock()

local cmd_id = reaper.NamedCommandLookup("_RS7cb08a92f7a211ce66734644b4fbe99a91bd42f5")  --get ID of Hover Mode
local state = reaper.GetToggleCommandStateEx(0,cmd_id)  -- get command state
      
    if state==1 then
    
          local current_pos =  reaper.GetCursorPosition()
            
          local x,y = reaper.GetMousePosition()
          local item = reaper.GetItemFromPoint(x,y,false) -- boolean is "allow locked items"
             
            if item then
            
                if not reaper.IsMediaItemSelected( item ) then 
                    reaper.Main_OnCommand(40528, 0)  -- select item under mouse cursor
                end
            end 
            
            
            if reaper.GetSelectedMediaItem(0,0) then --check if something is selected
            
                reaper.Main_OnCommand(40514, 0)  -- View: Move edit cursor to mouse cursor (no snapping)
                reaper.Main_OnCommand(40510, 0)  -- Item: Fade items out from cursor
                reaper.SetEditCurPos(current_pos, 0, 0)
            
            
            end
               
    
    else
    
        reaper.Main_OnCommand(40510, 0) -- Item: Fade items out from cursor
    
    end--if
    
reaper.Undo_EndBlock("Fade out", 0)
