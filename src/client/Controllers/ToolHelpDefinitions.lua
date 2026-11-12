--!strict
-- One concise keybind dictionary for the always-visible UI v2 left sidebar.
-- Subtool bindings come from shared SubtoolDefinitions, never copied here.
-- This module only lists existing actions in the active controllers.
local Help={}

local function entry(key,action)
    return {key=key,action=action}
end
local function put(items,key,action)
    table.insert(items,entry(key,action))
end

function Help.Context(tools,build,mechanics,assemblyTool,player)
    local primary=tools.PrimaryId
    local sub=tools.SubtoolId
    local rows={}
    local stage=""
    if not primary then return {title="CONTROLS",rows={}} end

    if primary=="Build" then
        local pending=build.Pending
        local layered=build.Layered and build.Layered.Alignment
        local smart=build.SmartMatch
        if layered then
            stage=if layered.Stage=="Fit" then "SHAFT FIT"
                elseif layered.Stage=="PickTarget" then "CHOOSE OPENING"
                else "ALIGNMENT"
            put(rows,"Click",if layered.Stage=="PickTarget" then "Select opening"
                elseif layered.Stage=="Fit" then "Finish fitting"
                else "Confirm fit")
            if layered.Stage~="PickTarget" then
                put(rows,"[ / ]","Adjust insertion")
                put(rows,"Q / E","Roll shaft")
                put(rows,"Wheel","Adjust depth / fit")
            end
            put(rows,"Esc","Cancel alignment")
        elseif build.PendingMateChoice or build.LockedAlignment then
            stage="SMART FIT"
            put(rows,"Wheel","Insertion depth")
            put(rows,"Q / E","Shaft roll")
            put(rows,"Click","Choose connection")
            put(rows,"Esc","Cancel fit")
        elseif sub=="Place" then
            stage="PLACE"
            put(rows,"Click","Place primitive")
            put(rows,"B","Primitive catalog")
            put(rows,"R / T / Y","Rotate axes")
            put(rows,"N","Exact dimensions")
            if smart then
                put(rows,"Tab","Cycle fit target")
                put(rows,"Shift+Tab","Previous target")
            else
                put(rows,"Alt","Free placement")
            end
            put(rows,"Esc","Cancel placement")
        elseif sub=="Edit" then
            stage=if pending then "TRANSFORM" else "EDIT"
            if pending then
                put(rows,"Click","Confirm move")
                put(rows,"R / T / Y","Rotate axes")
                put(rows,"Alt+Arrows","Nudge")
                put(rows,"Esc","Cancel move")
            else
                put(rows,"Click","Select primitive")
                put(rows,"Double click","Select inside component")
                put(rows,"Drag / G","Move")
                put(rows,"F / Ctrl+D","Duplicate")
                put(rows,"R / T / Y","Rotate axes")
                put(rows,"N","Exact dimensions")
                put(rows,"Alt+Arrows","Nudge position")
                put(rows,"Shift+Alt","Fine arrow nudge")
                put(rows,"C / U","Group / ungroup")
                put(rows,"L","Align shaft")
                put(rows,"X / I","X-ray / isolate")
                put(rows,"Tab","Select behind")
                put(rows,"Delete","Delete selected")
            end
        elseif sub=="Resize" then
            stage="RESIZE"
            put(rows,"Drag","Resize face handles")
            put(rows,"N","Exact dimensions")
            put(rows,"Esc","Exit resize")
        elseif sub=="Paint" then
            stage="APPEARANCE"
            put(rows,"Click","Select object")
            put(rows,"M","Open Properties")
            put(rows,"F2","Unlock cursor")
        end
        if sub~="Paint" then
            put(rows,"Ctrl+Z / Y","Undo / redo")
        end
    elseif primary=="Mechanics" then
        if sub=="Connect" then
            local state=mechanics.Stage
            if state=="Preview" or state=="Fit" then
                stage=if state=="Fit" then "FINE FIT" else "INSERTION"
                put(rows,"Click","Confirm fit")
                put(rows,"[ / ]","Adjust fit")
                put(rows,"Wheel","Adjust insertion")
                put(rows,"Q / E","Roll shaft")
                put(rows,"Esc","Cancel connection")
            elseif state=="Choice" or state=="ChoiceRejected" then
                stage="CONNECTION CHOICE"
                put(rows,"Click","Choose relationship")
                put(rows,"Esc","Cancel choice")
            else
                stage="CONNECT"
                put(rows,"Click",if state=="ChooseSecond" then
                    "Select second part" else "Select first part")
                put(rows,"Esc","Reset selection")
            end
        else
            stage="CONFIGURE"
            put(rows,"Click","Inspect connection")
            put(rows,"Tab","Unlock Properties")
            put(rows,"Right click","Context actions")
        end
        put(rows,"Ctrl+Z / Y","Undo / redo")
    elseif primary=="AssemblySimulation" then
        if sub=="AssemblyEditor" then
            local draft=assemblyTool.Stage=="Selecting"
            stage=if draft then "ASSEMBLY DRAFT" else "ASSEMBLY EDITOR"
            if draft then
                put(rows,"Click","Toggle members")
                put(rows,"Alt+Click","Single primitive")
                put(rows,"Enter","Save draft")
                put(rows,"Esc","Discard draft")
                if assemblyTool.EditingId then
                    put(rows,"R","Rename assembly")
                end
            else
                put(rows,"N","Create assembly")
                put(rows,"Click","Select assembly")
            end
            put(rows,"Alt+Arrows","Move assembly")
            put(rows,"Ctrl+Z / Y","Undo / redo")
        else
            local running=player:GetAttribute("OPENWORKS_Simulating")==true
            local paused=player:GetAttribute("OPENWORKS_SimulationPaused")==true
            stage=if running then (if paused then "PAUSED" else "RUNNING")
                else "SIMULATION"
            put(rows,"P",if running then "Stop simulation" else "Run assembly")
            if running then
                put(rows,"O",if paused then "Resume physics" else "Pause physics")
                put(rows,"U","Reset simulation")
                put(rows,"I","Inspect mechanism")
                put(rows,"Hold LMB","Drive hand crank")
                put(rows,"Q / E","Drive rack")
                put(rows,"Motor key","Power bearing motor")
            else
                put(rows,"G","Ground / release")
                put(rows,"Click","Select assembly")
            end
        end
    end
    local fitActive=(primary=="Build" and
        (stage=="SHAFT FIT" or stage=="ALIGNMENT" or stage=="SMART FIT"
            or stage=="CHOOSE OPENING"))
        or (primary=="Mechanics" and
            (stage=="CONNECTION CHOICE" or stage=="INSERTION"
                or stage=="FINE FIT"))
    if not fitActive and sub~="Paint" then
        put(rows,"F2","Unlock cursor")
    end
    if not fitActive then put(rows,"F6","Save / load plot") end
    -- Shared freecam controls remain concise and only occur once below
    -- the current operation's list; no separate permanent instruction HUD.
    put(rows,"WASD","Fly camera")
    put(rows,"Space / Ctrl","Up / down")
    put(rows,"Shift","Fly faster")
    put(rows,"Z / Shift+Z","FOV zoom")
    return {title=stage~="" and stage or "CONTROLS",rows=rows}
end

return table.freeze(Help)
