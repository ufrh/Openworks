--!strict
-- Support for passive bearing housings in the ACTIVE physical/rack engines.
--
-- IMPORTANT: ComponentId is just an EDITOR selection group. It does NOT
-- create any physical weld. Only actual Weld/Fixed/Bolt relationships
-- (represented by transmission.ById rigid groups) can make a hole block
-- part of a moving chassis. This avoids the old bug where grouped but
-- mechanically loose motor housings spun with the shaft.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local construction=ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction")
local Alignment=require(construction:WaitForChild("AlignmentMath"))
local GearMath=require(construction:WaitForChild("GearMath"))

local Support={}

local function id(model)
    return model and model:GetAttribute("InstanceId")
end

-- A single housing, or a bracket rigidly built solely from several bored
-- supports, is a stationary support. A welded chassis also contains
-- structural members and MUST stay dynamically free to travel/steer.
-- Model count and geometry are from actual rigid groups, never ComponentId.
local function isStandaloneSupportGroup(group)
    if not group or #group.Models==0 then return false end
    for _,member in ipairs(group.Models) do
        if Alignment.IsShaft(member)
            or not Alignment.TargetAxis(member)
            or GearMath.Kind(member)~="None" then
            return false
        end
        if #group.Models>1 then
            -- Structural chassis are frequently built from hollow TUBES.
            -- Never anchor a mobile vehicle just because all its chassis
            -- beams happen to have a bore axis. A rigid group of ONLY
            -- drilled mounting blocks is a legitimate fixed bracket.
            local kind=string.lower(tostring(
                member:GetAttribute("TemplateId") or member.Name)
                ..tostring(member:GetAttribute("PrimitiveFamily") or ""))
                :gsub("[%s_%-]","")
            if not string.find(kind,"drilledblock",1,true)
                and not string.find(kind,"holeblock",1,true) then
                return false
            end
        end
    end
    return true
end

-- groundKeys are simulation-local. The authored construction and its saved
-- Grounded / ComponentId attributes are never changed.
-- Returns count of newly anchored support groups, plus candidate/skip
-- diagnostics for Studio Output to make misclassified housings obvious.
function Support.Resolve(graph,transmission,groundKeys)
    local motorRotorGroups={}
    local gearRotorGroups={}
    for _,edge in ipairs(graph.edges) do
        if edge.kind=="Bearing" and Alignment.IsShaft(edge.source) then
            local rotor=transmission.ById[id(edge.source)]
            local housing=transmission.ById[id(edge.target)]
            if rotor and housing and rotor==housing then
                error("Motor/bearing shaft is rigidly welded to its hole "
                    .."housing. Remove the welded connection; a bearing "
                    .."must allow relative shaft rotation")
            end
            if edge.relation
                and edge.relation:GetAttribute("MotorEnabled")==true
                and rotor then
                motorRotorGroups[rotor]=true
            end
        end
    end
    for _,entry in ipairs(transmission.Gears or {}) do
        gearRotorGroups[entry.Group]=true
    end

    local fixedGroups={}
    local seen={}
    local anchored=0
    local candidates=0
    local structural=0
    for _,edge in ipairs(graph.edges) do
        if edge.kind~="Bearing"
            or not Alignment.IsShaft(edge.source)
            or not Alignment.TargetAxis(edge.target)
            or GearMath.Kind(edge.target)~="None" then continue end

        local rotor=transmission.ById[id(edge.source)]
        local housing=transmission.ById[id(edge.target)]
        if not rotor or not housing then continue end

        -- Consider a housing whenever the shaft is powered or geared.
        -- A motor on ONE hole applies to EVERY bearing on that shaft.
        if not (motorRotorGroups[rotor] or gearRotorGroups[rotor]) then
            continue
        end
        if seen[housing] then continue end
        seen[housing]=true
        candidates+=1

        -- A hole that is welded into a real chassis stays mobile WITH the
        -- chassis, but is never driven by the shaft's angular actuator.
        -- We cannot infer mechanical rigidity from editor grouping.
        if not isStandaloneSupportGroup(housing)
            or motorRotorGroups[housing] or gearRotorGroups[housing] then
            structural+=1
            continue
        end

        -- Anchor the entire true rigid housing group: anchoring one
        -- member of a welded support bracket is sufficient for physics.
        -- Pick the encountered drilled housing's actual primitive key;
        -- never the shaft/gear group or a ComponentId key.
        if not fixedGroups[housing] then
            fixedGroups[housing]=true
            local key=edge.b
            if not groundKeys[key] then
                groundKeys[key]=true
                anchored+=1
            end
        end
    end

    return anchored,candidates,structural
end

return table.freeze(Support)
