-- @description ReaTooled - Paste Special = Repeat to fill LOOP selection
-- @version 1.1
-- @date 2025.04.15
-- @author Brendan Baker
-- @link https://brendanpatrickbaker.com/reatooled/
-- @about Fills LOOP selection with loops of the item in the clipboard, similar to PT OPT+CMD+V
-- CHANGELOG

function main()
    reaper.Undo_BeginBlock()

    -- Get current LOOP selection (not time selection)
    local loop_start, loop_end = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
    if not loop_start or not loop_end or loop_end <= loop_start then
        --reaper.ShowMessageBox("Set a LOOP selection first.", "Paste Special = Repeat to fill LOOP selection", 0)
        reaper.Undo_EndBlock("Paste Special - Repeat to Fill LOOP Selection (no loop selection)", -1)
        return
    end

    -- (Optional but helpful) place cursor at loop start before paste
    reaper.SetEditCurPos(loop_start, false, false)

    -- Paste items/tracks
    reaper.Main_OnCommand(40058, 0) -- Item: Paste items/tracks (stock action; safer than 42398)

    -- Loop section of selected item(s) using SWS (same as your script intent)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_LOOPITEMSECTION"), 0)

    -- Mirror LOOP selection into TIME selection so 41386 can use it
    reaper.GetSet_LoopTimeRange(true, false, loop_start, loop_end, false)

    -- Fit items to TIME selection (which now equals the LOOP selection), looping if needed
    reaper.Main_OnCommand(41386, 0) -- Item: Fit items to time selection, looping if needed

    -- Remove content (trim) behind items (kept from your script)
    reaper.Main_OnCommand(40930, 0) -- Item: Remove content (trim) behind items

    -- Move cursor to start of LOOP selection
    reaper.SetEditCurPos(loop_start, false, false)

    -- Clear all Razor Edit areas (as in your script)
    reaper.Main_OnCommand(42406, 0) -- Razor edit: Clear all areas

    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Paste Special - Repeat to Fill LOOP Selection", -1)
end

main()
