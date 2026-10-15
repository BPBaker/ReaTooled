--[[
-- @description ReaTooled - Add Stretch Marker (Hover Mode Dependant)
-- @version 1.1
-- @date 2024.08.22
-- @author Brendan Baker copied from TJF/Tim Farrell (http://github.com/sonictim/TJF-Scripts/)
-- @link http://brendanpatrickbaker.com/reatooled/
-- @about
  # Adjusted to work with the modified ReaTooled Hover Edit Mode script ("_RS7cb08a92f7a211ce66734644b4fbe99a91bd42f5")   
  # TJF Add Strech Marker (Hover Mode Dependant)
  Will add Stretch Markers at Mouse Cursor or Edit Curser depending on Hover Mode Status
  Recommend Assign to "W" key
@changelog
  v1.0 initial release
  v1.1 bug fixes - add SWS arrange view save and recall
  
--]]
reaper.Undo_BeginBlock()

reaper.Main_OnCommand(40570, 0) --disable locking


local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false) -- Get start and end time selection value in seconds

  if start_time ~= end_time then -- if there is a time selection
          reaper.Main_OnCommand(41843, 0) -- Item: Add stretch markers at time selection

  else



          local cmd_id = reaper.NamedCommandLookup("_RS7cb08a92f7a211ce66734644b4fbe99a91bd42f5")  --get ID of Hover Mode
          local state = reaper.GetToggleCommandStateEx(0,cmd_id)  -- get command state
                
              if state==1 then
              
                      local current_pos =  reaper.GetCursorPosition()
                      
                      local x,y = reaper.GetMousePosition()
                      local item = reaper.GetItemFromPoint(x,y,false) -- boolean is "allow locked items"
                      reaper.Main_OnCommand(reaper.NamedCommandLookup("_WOL_SAVEVIEWS5"), 0) -- Save SWS arrange view spot 5
                      if item then
                      
                          if not reaper.IsMediaItemSelected( item ) then 
                              reaper.Main_OnCommand(40528, 0)  -- select item under mouse cursor
                          end
                      end 
                      
                      
                      if reaper.GetSelectedMediaItem(0,0) then --check if something is selected
                      
                          reaper.Main_OnCommand(40514, 0)  -- View: Move edit cursor to mouse cursor (no snapping)
                          reaper.Main_OnCommand(41842, 0)  -- Item: Add stretch marker at cursor
                          reaper.SetEditCurPos(current_pos, 1, 0)
                          reaper.Main_OnCommand(reaper.NamedCommandLookup("_WOL_RESTOREVIEWS5"), 0) -- Restore SWS arrange view spot 5
                      
                      
                      end
                         
              
              else
              
                  reaper.Main_OnCommand(41842, 0) -- Item: Add stretch marker at cursor
              
              end--if
    end--if
    

    
reaper.Undo_EndBlock("Add Stretch Marker", 0)
