--!strict
-- Only show actions that are available in the current primary tool
-- and state. Every action dispatches through existing controllers and
-- server validation; no explorer-side privileged changes.
local Actions={}

function Actions.List(node,tools,simulating,assemblyStage)
    local result={}
    local function add(id,label,tip,shortcut)
        table.insert(result,{id=id,label=label,tooltip=tip,shortcut=shortcut})
    end
    if not node then return result end
    local primary=tools.PrimaryId
    local subtool=tools.SubtoolId
    if node.kind=="primitive" or node.kind=="component" then
        add("select","Select","Select this object in the editor")
        if primary=="Build" and not simulating then
            if node.kind=="primitive" then
                add("resize","Resize","Open face handles and precise sizing","V")
            end
            if not node.partialComponent then
                add("paint","Appearance","Edit physical material and surface finish","M")
            end
            if subtool=="Edit" and not node.partialComponent then
                add("duplicate","Duplicate","Copy this object while preserving existing duplication rules","Ctrl+D")
                add("delete","Delete","Delete the selected construction and its linked relationships","Del")
                if node.kind=="component" then
                    add("ungroup","Ungroup","Remove the editor grouping without silently welding or breaking geometry","U")
                end
            end
        elseif primary=="Mechanics" then
            if not simulating then
                if subtool=="Connect" and node.kind=="primitive" then
                    add("connect","Connect","Choose a second physical part and then a compatible connection")
                end
                add("connections","Connections","Inspect actual mechanical relationships for this object")
            end
        elseif primary=="AssemblySimulation" and not simulating then
            if subtool=="AssemblyEditor" and assemblyStage=="Selecting"
                and not node.partialComponent then
                add("membership","Toggle membership","Add or remove this object from the assembly draft")
            end
            if node.kind=="primitive" then
                add("ground","Ground / free","Toggle authored grounding for this primitive","G")
            end
        end
    elseif node.kind=="assembly" then
        add("select","Select assembly","Inspect only registered assembly members")
        if primary=="AssemblySimulation" then
            if subtool=="AssemblyEditor" and not simulating then
                add("edit-members","Edit members","Open the existing assembly membership workflow")
                add("rename","Rename","Edit the assembly's registered name")
            elseif subtool=="Simulation" then
                add(if simulating then "stop" else "run",
                    if simulating then "Stop" else "Simulate",
                    "Simulate exactly the saved assembly membership","P")
            end
        end
    elseif node.kind=="relation" then
        add("select","Inspect connection","Select both physical endpoints")
        if primary=="Mechanics" and subtool=="Configure" and not simulating then
            add("configure","Configure","Edit this relationship's limits or motor parameters")
            add("remove-relation","Remove connection",
                "Remove this relationship, not the physical parts")
        end
    elseif node.kind=="unassigned" then
        add("select","Select unassigned","Inspect primitives without a registered assembly")
    end
    if primary=="AssemblySimulation" and subtool=="AssemblyEditor"
        and not simulating then
        add("new-assembly","New assembly","Create a named assembly","N")
    end
    return result
end

return table.freeze(Actions)
