--!strict
-- Compact, state-aware controls. Show only actions useful RIGHT NOW.
-- No permanent camera manual or exhaustive keybind wall.
local Help={}
local function put(rows,key,description)
    table.insert(rows,{key=key,action=description})
end

function Help.Context(tools,build,mechanics,assemblyTool,player)
    local primary=tools.PrimaryId
    local sub=tools.SubtoolId
    local rows={}
    local title="CONTROLS"
    if not primary then return {title=title,rows=rows} end

    if primary=="Build" or primary=="Edit" then
        local alignment=build.Layered and build.Layered.Alignment
        local pending=build.Pending
        if alignment then
            title="SHAFT FIT"
            put(rows,"Click",if alignment.Stage=="PickTarget" then "Choose target"
                else "Confirm fit")
            if alignment.Stage~="PickTarget" then
                put(rows,"Wheel","Insertion depth")
                put(rows,"Q / E","Rotate fit")
            end
            put(rows,"Esc","Cancel")
        elseif build.PendingMateChoice or build.LockedAlignment then
            title="SMART FIT"
            put(rows,"Click","Choose connection")
            put(rows,"Wheel","Insertion depth")
            put(rows,"Q / E","Rotate shaft")
            put(rows,"Esc","Cancel")
        elseif build.CatalogOpen then
            title="PARTS"
            put(rows,"Click","Select a part")
            put(rows,"B / Esc","Close library")
        elseif build.ScaleMode then
            title="RESIZE"
            put(rows,"Drag","Resize")
            put(rows,"N","Enter size")
            put(rows,"V / Esc","Done")
        elseif primary=="Build" then
            title="BUILD • KEYBINDS"
            put(rows,"Click","Place part")
            put(rows,"B","Parts library")
            put(rows,"R / T / Y","Rotate axes")
            put(rows,"V","Resize grips")
            put(rows,"N","Exact dimensions")
            put(rows,"Shift / Alt","Disable snap")
            put(rows,"J / Shift+J","Avatar reference / move")
            put(rows,"Right click","Part options")
            put(rows,"Enter","Finish placement")
            put(rows,"Ctrl+Z / Y","Undo / redo")
        elseif pending then
            title="EDIT / MOVE"
            put(rows,"Click","Place")
            put(rows,"R / T / Y","Rotate")
            put(rows,"Esc","Cancel")
        else
            local count=#(build.SelectedParts or {})
            title=if count>1 then "EDIT • "..tostring(count).." SELECTED"
                else "EDIT • KEYBINDS"
            -- Show the complete Edit workflow instead of hiding the
            -- shortcuts required to build a real chassis.
            put(rows,"Click","Select part or component")
            put(rows,"Shift+Click","Add / remove selection")
            put(rows,"Alt+Click","Pick behind geometry")
            put(rows,"Tab / Shift+Tab","Cycle depth")
            put(rows,"G / Drag","Move selection")
            put(rows,"F / Ctrl+D","Duplicate selection")
            put(rows,"C","Group loose parts")
            put(rows,"E","Enter / exit component")
            put(rows,"U","Ungroup component")
            put(rows,"Shift+K","Weld selected parts")
            put(rows,"R / T / Y","Rotate axes")
            put(rows,"V","Resize grips")
            put(rows,"N","Exact dimensions")
            put(rows,"Alt+Arrows","Move in small steps")
            put(rows,"Shift+Alt+Arrows","Fine move")
            put(rows,"O / Shift+O","Set / reset fit pivot")
            put(rows,"L","Fit shaft to opening")
            put(rows,"M","Appearance")
            put(rows,"X / I","X-ray / isolate")
            put(rows,"J / Shift+J","Avatar reference / move")
            put(rows,"Right click","Mechanical settings")
            put(rows,"Backspace","Delete selection")
            put(rows,"Ctrl+Z / Y","Undo / redo")
        end
    elseif primary=="Mechanics" then
        local state=mechanics.Stage
        title="MECHANICS"
        if state=="Preview" or state=="Fit" then
            put(rows,"Click","Confirm fit")
            put(rows,"Wheel","Insertion")
            put(rows,"Q / E","Rotate")
            put(rows,"Esc","Cancel")
        elseif state=="Choice" or state=="ChoiceRejected" then
            put(rows,"Click","Choose joint")
            put(rows,"Esc","Cancel")
        else
            put(rows,"Click",if state=="ChooseSecond" then "Second part"
                else "First part")
            put(rows,"Esc","Reset")
        end
        put(rows,"Right click","Connections")
        put(rows,"Ctrl+Z / Y","Undo / redo")
    elseif primary=="AssemblySimulation" then
        if sub=="AssemblyEditor" then
            local drafting=assemblyTool.Stage=="Selecting"
            title=if drafting then "ASSEMBLY / SELECT" else "ASSEMBLY"
            if drafting then
                put(rows,"Click","Select connected mechanism")
                put(rows,"Alt+Click","Toggle one primitive")
                put(rows,"R","Choose assembled parts")
                put(rows,"Enter","Save assembly")
                put(rows,"Esc","Cancel")
            else
                put(rows,"Click","Detect connected assembly")
                put(rows,"N","New / rename assembly")
            end
            put(rows,"G","Ground / unground")
            put(rows,"Alt+Arrows","Nudge assembly")
            put(rows,"Shift+Alt+Arrows","Fine nudge")
            put(rows,"Right click","Connections")
            put(rows,"Ctrl+Z / Y","Undo / redo")
        else
            local running=player:GetAttribute("OPENWORKS_Simulating")==true
            title=if running then "SIMULATING" else "SIMULATION"
            put(rows,"P",if running then "Stop" else "Run assembly")
            if running then
                put(rows,"O","Pause / resume")
                put(rows,"U","Reset")
                put(rows,"I","Inspect mechanism")
                put(rows,"Motor key","Drive motor")
                put(rows,"Hold LMB","Hand crank")
            else
                put(rows,"G","Ground part")
            end
            put(rows,"Right click","Inspect connections")
        end
    end
    -- Every important action is discoverable in each tool, with a
    -- scrollable sidebar rather than a truncated handful of shortcuts.
    return {title=title,rows=rows}
end

return table.freeze(Help)
