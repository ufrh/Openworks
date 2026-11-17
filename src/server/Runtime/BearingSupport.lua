--!strict
-- Bearing topology validation for the ACTIVE PhysicalSimulationService and
-- RackSimulationService engines. This module does NOT ground, anchor,
-- stabilize, counter-rotate, or otherwise drive any housing.
--
-- A bearing is a passive revolute connection between independent rigid
-- groups. An authored Grounded flag is the ONLY reason to anchor a housing.
-- The motor's world-relative shaft actuator must never power the housing.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local construction=ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction")
local Alignment=require(construction:WaitForChild("AlignmentMath"))
local GearMath=require(construction:WaitForChild("GearMath"))

local Support={}

local function id(model)
    return model and model:GetAttribute("InstanceId")
end

-- groundKeys is read-only here: this method verifies that bearing rotors
-- and housings really are separate rigid bodies. Explicit grounded status
-- is reported, never inferred from components, shafts, or gear contact.
function Support.Resolve(graph,transmission,groundKeys)
    local visited={}
    local bearings=0
    local mobile=0
    local authoredGrounded=0
    for _,edge in ipairs(graph.edges) do
        if edge.kind~="Bearing" or not Alignment.IsShaft(edge.source)
            or not Alignment.TargetAxis(edge.target)
            or GearMath.Kind(edge.target)~="None" then continue end
        local shaftGroup=transmission.ById[id(edge.source)]
        local housingGroup=transmission.ById[id(edge.target)]
        if shaftGroup and housingGroup and shaftGroup==housingGroup then
            error("Motor/bearing shaft is rigidly welded to its hole "
                .."housing. Remove the weld: bearings require two "
                .."independent, freely rotating rigid bodies")
        end
        if not housingGroup or visited[housingGroup] then continue end
        visited[housingGroup]=true
        bearings+=1
        local grounded=false
        for _,original in ipairs(graph.models) do
            local memberId=id(original)
            if transmission.ById[memberId]==housingGroup
                and groundKeys["p:"..tostring(memberId)] then
                grounded=true
                break
            end
        end
        if grounded then authoredGrounded+=1 else mobile+=1 end
    end
    return mobile,bearings,authoredGrounded
end

return table.freeze(Support)
