--!strict
-- Shared runtime support policy for shaft-in-hole bearings.
-- A HingeConstraint never powers the housing. Isolated hole blocks
-- supporting a drive shaft become stationary pivots. A hole welded
-- into a chassis/body MUST remain free to move with that body.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local construction=ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction")
local Alignment=require(construction:WaitForChild("AlignmentMath"))
local GearMath=require(construction:WaitForChild("GearMath"))

local Support={}

local function id(model)
    return model and model:GetAttribute("InstanceId")
end

-- Works with GearTransmission (native physics) and GearKinematics (racks).
-- Returns how many previously ungrounded standalone housings were fixed.
function Support.Resolve(graph,transmission,groundKeys)
    local componentCounts={}
    for _,model in ipairs(graph.models) do
        local cid=model:GetAttribute("ComponentId")
        if type(cid)=="string" and cid~="" then
            componentCounts[cid]=(componentCounts[cid] or 0)+1
        end
    end

    local rotorGroups={}
    local gearedGroups={}
    for _,edge in ipairs(graph.edges) do
        if edge.kind=="Bearing" and Alignment.IsShaft(edge.source) then
            local rotor=transmission.ById[id(edge.source)]
            local housing=transmission.ById[id(edge.target)]
            if rotor and housing and rotor==housing then
                error("Bearing shaft is rigidly welded to its hole housing. "
                    .."Remove the weld so the shaft can rotate independently")
            end
            if edge.relation and edge.relation:GetAttribute("MotorEnabled")==true
                and rotor then
                rotorGroups[rotor]=true
            end
        end
    end
    for _,entry in ipairs(transmission.Gears or {}) do
        gearedGroups[entry.Group]=true
    end

    -- A housing can be used by multiple bearings; the shaft can be
    -- motor-driven OR receive movement from meshed output gears.
    local seen={}
    local anchored=0
    for _,edge in ipairs(graph.edges) do
        if edge.kind~="Bearing" or not Alignment.IsShaft(edge.source)
            or not Alignment.TargetAxis(edge.target)
            or GearMath.Kind(edge.target)~="None" then continue end
        local rotor=transmission.ById[id(edge.source)]
        local housing=transmission.ById[id(edge.target)]
        local cid=edge.target:GetAttribute("ComponentId")
        local grouped=type(cid)=="string" and cid~=""
            and (componentCounts[cid] or 0)>1
        local standalone=housing and #housing.Models==1
            and not grouped
        if standalone and rotor and (rotorGroups[rotor]
            or gearedGroups[rotor]) then
            -- Never fix a structure that also acts as a shaft/gear rotor.
            -- No constraint reaction from the shaft is transferred to a
            -- free-standing drilled support.
            if not rotorGroups[housing] and not gearedGroups[housing]
                and not groundKeys[edge.b] and not seen[edge.b] then
                groundKeys[edge.b]=true
                seen[edge.b]=true
                anchored+=1
            end
        end
    end
    return anchored
end

return table.freeze(Support)
