--[[
-- @description ReaTooled - Trim right side of items (Hover Mode Dependant)
-- @version 1.0
-- @date 2024.01.18
-- @author Brendan Baker adapted from TJF/Tim Farrell (http://github.com/sonictim/TJF-Scripts/)
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
  # Trim right Side of Item to Mouse Cursor
  Modified from TJF's scripts to work better when in Ripple mode, and to move cursor to the trim/edit edge 
  Depending on Hover mode will Trim Right Edge of items to mouse cursor or edit cursor
  Recommend Assigning to "S" key

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
                --reaper.Main_OnCommand(41311, 0)  -- Trim Right Edge to Mouse Cursor
                reaper.Main_OnCommand(40512, 0)  -- Trim Items Right of Cursor
                --reaper.SetEditCurPos(current_pos, 1, 0)
                reaper.Main_OnCommand(40319, 0)  --Calls command "Item navigation: Move cursor right to edge of item"
            
            end
    else
                  
              if reaper.GetSelectedMediaItem(0,0) then  --if there is an item selection
              
                reaper.Main_OnCommand(40631, 0) --  go to end of time selection
                reaper.Main_OnCommand(40512, 0) --  Trim Items Right of Cursor
              --  reaper.Main_OnCommand(40630, 0) --  Trim Items Left of Cursor
              
              end
    
    
    
    end--if

reaper.Undo_EndBlock("Trim right edge", 0)
