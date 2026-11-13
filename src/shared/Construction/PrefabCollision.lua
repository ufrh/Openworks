--!strict
-- Authoritative collision/query policy for baked transmission and fastener
-- prefabs. MeshParts are visual geometry; simple invisible collision proxies
-- carry physical contact and preserve actual shaft openings.
-- The same policy is used by construction, physical and rack simulation.
local Policy={}

function Policy.Configure(part:BasePart)
    local mode=part:GetAttribute("OpenworksCollisionMode")
    if mode=="VisualOnly" then
        part.CanCollide=false
        part.CanQuery=false
        part.CanTouch=false
    elseif mode=="Proxy" then
        part.CanCollide=true
        part.CanQuery=true
        part.CanTouch=false
        part.Transparency=1
        part.CastShadow=false
    elseif mode=="PivotOnly" or part:GetAttribute("GearPivotOnly")==true then
        part.CanCollide=false
        part.CanQuery=false
        part.CanTouch=false
        part.Transparency=1
        part.CastShadow=false
    else
        -- Legacy primitives preserve their pre-existing behavior.
        part.CanCollide=true
        part.CanQuery=true
        part.CanTouch=false
    end
end

function Policy.IsContactSolid(part:BasePart):boolean
    return part.CanCollide and part:GetAttribute("OpenworksCollisionMode")~="VisualOnly"
end

return table.freeze(Policy)
