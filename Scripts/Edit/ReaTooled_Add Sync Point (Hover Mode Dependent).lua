--[[
-- @description ReaTooled - Add Synch Point (Hover Mode Dependant)
-- @version 1.0
-- @date 2024.01.18
-- @author Brendan Baker copied from TJF/Tim Farrell (http://github.com/sonictim/TJF-Scripts/)
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
  # Adjusted to work with the modified ReaTooled Hover Edit Mode script ("_RS7cb08a92f7a211ce66734644b4fbe99a91bd42f5") 
  # TJF TJF Add Sync Point (Hover Mode Dependent)
  Will also not split if no item is selected.
  Mimics "CMD + ," in protools
  Adds Hover Mode Support
  
--]]
reaper.Undo_BeginBlock()

local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false) -- Get start and end time selection value in seconds

  if start_time ~= end_time   -- if there is a time selection
  then
          reaper.Main_OnCommand(40061, 0) -- Item: Split items at time selection
  else
      


          local cmd_id = reaper.NamedCommandLookup("_RS7cb08a92f7a211ce66734644b4fbe99a91bd42f5")  --get ID of Hover Mode
          local state = reaper.GetToggleCommandStateEx(0,cmd_id)  -- get command state
                
              if  state==1
              then
              
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
                              reaper.Main_OnCommand(40541, 0)  -- Item: Set snap offset to cursor
                              reaper.SetEditCurPos(current_pos, 1, 0)
                          
                          
                          end
                         
              
              else
              
                  reaper.Main_OnCommand(40541, 0) -- Item: Set snap offset to cursor
              
              end--if
      
    end--if
    

    
reaper.Undo_EndBlock("Add Sync Point", 0)
