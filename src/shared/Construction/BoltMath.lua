--!strict
-- A physical bolt only fastens bodies whose actual coaxial openings it spans.
-- Used for both ghost feedback and server-authoritative placement.
local Alignment=require(script.Parent:WaitForChild("AlignmentMath"))
local Bore=require(script.Parent:WaitForChild("BoreClearance"))
local Grid=require(script.Parent:WaitForChild("GridMath"))
local Bolt={}
function Bolt.IsBolt(model)
    return model and model:IsA("Model") and model.PrimaryPart~=nil
        and type(model:GetAttribute("BoltDiameterU"))=="number"
        and type(model:GetAttribute("BoltLengthU"))=="number"
end
function Bolt.Fits(bolt,hole)
    if not Bolt.IsBolt(bolt) or not hole or not hole.PrimaryPart then
        return false,"Missing bolt or opening"
    end
    local localAxis=Alignment.TargetAxis(hole)
    local holeDiameter=Bore.OpeningDiameter(hole)
    if not localAxis or not holeDiameter then
        return false,"A real drilled bore is required"
    end
    local boltDiameter=bolt:GetAttribute("BoltDiameterU")*Grid.Unit
    local boltLength=bolt:GetAttribute("BoltLengthU")*Grid.Unit
    if boltDiameter>holeDiameter-0.002 then
        return false,"Bolt is wider than the opening"
    end
    local axis=bolt:GetPivot().RightVector
    local holeAxis=hole:GetPivot():VectorToWorldSpace(localAxis).Unit
    if math.abs(axis:Dot(holeAxis))<0.998 then
        return false,"Bolt and opening axes do not align"
    end
    local delta=hole:GetPivot().Position-bolt:GetPivot().Position
    local projection=delta:Dot(axis)
    if (delta-axis*projection).Magnitude>Grid.Unit*0.12 then
        return false,"Bolt is not centered in the opening"
    end
    local s=hole.PrimaryPart.Size
    local thickness=math.abs(localAxis.X)*s.X+
        math.abs(localAxis.Y)*s.Y+math.abs(localAxis.Z)*s.Z
    if projection-thickness*0.5 < -boltLength*0.5-0.015
        or projection+thickness*0.5 > boltLength*0.5+0.015 then
        return false,"Bolt shaft does not fully pass through the hole"
    end
    return true,projection
end
return table.freeze(Bolt)
