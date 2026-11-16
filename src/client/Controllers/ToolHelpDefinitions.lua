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
            title="BUILD"
            put(rows,"Click","Place")
            put(rows,"B","Parts library")
            put(rows,"R / T / Y","Rotate")
            put(rows,"V","Resize")
            put(rows,"Shift / Alt","Disable snap")
            put(rows,"Right click","Part options")
            put(rows,"Enter","Finish")
        elseif pending then
            title="EDIT / MOVE"
            put(rows,"Click","Place")
            put(rows,"R / T / Y","Rotate")
            put(rows,"Esc","Cancel")
        else
            title="EDIT"
            put(rows,"Click","Select")
            put(rows,"Drag / G","Move")
            put(rows,"F","Duplicate")
            put(rows,"V","Resize")
            put(rows,"R / T / Y","Rotate")
            put(rows,"Right click","Connections")
            put(rows,"Delete","Delete")
            put(rows,"Ctrl+Z","Undo")
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
        put(rows,"Ctrl+Z","Undo")
    elseif primary=="AssemblySimulation" then
        if sub=="AssemblyEditor" then
            local drafting=assemblyTool.Stage=="Selecting"
            title=if drafting then "ASSEMBLY / SELECT" else "ASSEMBLY"
            if drafting then
                put(rows,"Click","Add / remove part")
                put(rows,"Enter","Save assembly")
                put(rows,"Esc","Cancel")
            else
                put(rows,"N","New assembly")
                put(rows,"Click","Select assembly")
            end
            put(rows,"G","Ground part")
            put(rows,"Right click","Connections")
        else
            local running=player:GetAttribute("OPENWORKS_Simulating")==true
            title=if running then "SIMULATING" else "SIMULATION"
            put(rows,"P",if running then "Stop" else "Run assembly")
            if running then
                put(rows,"O","Pause / resume")
                put(rows,"U","Reset")
                put(rows,"Motor key","Drive motor")
                put(rows,"Hold LMB","Hand crank")
            else
                put(rows,"G","Ground part")
            end
            put(rows,"Right click","Inspect connections")
        end
    end
    -- The complete keybinds remain in the existing controllers; this is
    -- intentionally a short, legible help strip, not a tutorial wall.
    return {title=title,rows=rows}
end

return table.freeze(Help)
