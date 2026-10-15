-- Requires: JS_ReaScript API for mouse tracking

local isDragging = false
local item, edge = nil, nil
local start_pos, end_pos, initial_mouse_pos = nil, nil, nil

function AdjustItemEdge()
    if isDragging and item then
        -- Step 6: Track mouse movement and adjust edge
        local new_mouse_pos = reaper.BR_PositionAtMouseCursor(false)

        if edge == "start" then
            local new_start = new_mouse_pos
            local new_length = end_pos - new_start
            if new_length > 0 then
                reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_start)
                reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_length)
            end
        elseif edge == "end" then
            local new_length = new_mouse_pos - start_pos
            if new_length > 0 then
                reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_length)
            end
        end

        reaper.UpdateArrange()

        -- Step 7: Check if mouse button is released, stop dragging if so
        if reaper.JS_Mouse_GetState(1) == 0 then
            -- reaper.ShowConsoleMsg("Mouse Released! Committing change.\n")
            isDragging = false
            reaper.Undo_EndBlock("Adjust Item Edge", -1)
        end

        -- Keep checking while dragging
        reaper.defer(AdjustItemEdge)
        return
    end

    -- Step 1: Get mouse screen position
    local mouse_x, mouse_y = reaper.GetMousePosition()
    item, take = reaper.GetItemFromPoint(mouse_x, mouse_y, true)

    if not item then
        reaper.defer(AdjustItemEdge) -- Keep running for continuous use
        return
    end

    -- Step 2: Get item start and end positions
    start_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    end_pos = start_pos + length

    -- Step 3: Get mouse position in project time
    initial_mouse_pos = reaper.BR_PositionAtMouseCursor(false)
    if not initial_mouse_pos then
        reaper.defer(AdjustItemEdge) -- Keep running for continuous use
        return
    end

    -- Step 4: Determine if the mouse is closer to start or end
    local dist_to_start = math.abs(initial_mouse_pos - start_pos)
    local dist_to_end = math.abs(initial_mouse_pos - end_pos)
    edge = (dist_to_start < dist_to_end) and "start" or "end"

    -- Step 5: Wait for mouse button press
    if reaper.JS_Mouse_GetState(1) == 1 then
        -- reaper.ShowConsoleMsg("Mouse Down! Adjusting " .. edge .. " edge.\n")

        reaper.Undo_BeginBlock()
        isDragging = true
    end

    -- Keep running indefinitely
    reaper.defer(AdjustItemEdge)
end

-- Start the script
-- reaper.ShowConsoleMsg("Running AdjustItemEdge Script... Ready for continuous use.\n")
reaper.defer(AdjustItemEdge)

