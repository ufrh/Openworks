--!strict
-- Shared support-plane placement for multi-part previews.
-- Given a preview at desired rotation/pivot, shift EVERY member together so
-- its lowest world-space geometry rests on the aimed surface, not below it.
local SurfacePlacement = {}
local EPSILON = 0.002

local function axisRadius(part: BasePart, normal: Vector3): number
    local cf = part.CFrame
    local half = part.Size * 0.5
    return math.abs(normal:Dot(cf.RightVector)) * half.X
        + math.abs(normal:Dot(cf.UpVector)) * half.Y
        + math.abs(normal:Dot(cf.LookVector)) * half.Z
end

function SurfacePlacement.SnapToSurface(ghost: Model, desiredPivot: CFrame,
    hitPosition: Vector3, hitNormal: Vector3): CFrame
    local n = hitNormal.Unit
    ghost:PivotTo(desiredPivot)

    local lowest = math.huge
    for _, part in ipairs(ghost:GetDescendants()) do
        if part:IsA("BasePart")
            and part:GetAttribute("GearPivotOnly")~=true then
            lowest = math.min(lowest, n:Dot(part.Position) - axisRadius(part, n))
        end
    end
    if lowest == math.huge then return desiredPivot end

    local clearance = n:Dot(hitPosition) - lowest + EPSILON
    local nextCF = desiredPivot + n * clearance
    ghost:PivotTo(nextCF)
    return nextCF
end

-- Neighbour-face placement is based on the actual target part's
-- local coordinate frame instead of the world-origin construction grid.
-- This eliminates parity drift between independently sized parts and
-- makes edges, centers and neighboring faces align exactly.
local FACE_LATTICE=0.0625 -- 0.25 U; smallest ordinary size quantum
local EDGE_CAPTURE=0.16

local function quantize(value,step)
    return math.floor(value/step+0.5)*step
end

function SurfacePlacement.SnapToNearbyFace(ghost:Model,desired:CFrame,
    hitPosition:Vector3,hitNormal:Vector3,hitPart:BasePart?):CFrame
    if not hitPart or not hitPart:IsA("BasePart") then
        return SurfacePlacement.SnapToSurface(ghost,desired,
            hitPosition,hitNormal)
    end
    -- First make face-to-face contact exact, regardless of pivot
    -- placement, fractional dimensions or orientation.
    local cf=SurfacePlacement.SnapToSurface(ghost,desired,
        hitPosition,hitNormal)
    local targetCF=hitPart.CFrame
    local n=hitNormal.Unit
    local normalLocal=targetCF:VectorToObjectSpace(n)
    ghost:PivotTo(cf)
    local delta=Vector3.zero
    local axisVectors={targetCF.RightVector,targetCF.UpVector,
        targetCF.LookVector}
    local targetSize=hitPart.Size
    local components={targetSize.X,targetSize.Y,targetSize.Z}
    for i,axis in ipairs(axisVectors) do
        if math.abs(normalLocal[i==1 and "X" or i==2 and "Y" or "Z"])
            <0.6 then
            -- Coordinates are relative to the target's own center.
            -- Snap to any existing face edge when near it; otherwise
            -- use the fine local fabrication lattice rather than world 0.
            local tangent=(cf.Position-targetCF.Position):Dot(axis)
            local halfTarget=components[i]*0.5
            local halfMoving=0
            for _,part in ipairs(ghost:GetDescendants()) do
                if part:IsA("BasePart")
                    and part:GetAttribute("GearPivotOnly")~=true then
                    local radius=axisRadius(part,axis)
                    halfMoving=math.max(halfMoving,
                        math.abs((part.Position-cf.Position):Dot(axis))+radius)
                end
            end
            local candidates={
                0,
                halfTarget-halfMoving,
                -halfTarget+halfMoving,
                halfTarget+halfMoving,
                -halfTarget-halfMoving,
            }
            local snapped=quantize(tangent,FACE_LATTICE)
            for _,candidate in ipairs(candidates) do
                if math.abs(tangent-candidate)<=EDGE_CAPTURE
                    and math.abs(tangent-candidate)
                        <math.abs(tangent-snapped) then
                    snapped=candidate
                end
            end
            delta+=axis*(snapped-tangent)
        end
    end
    local result=cf+delta
    ghost:PivotTo(result)
    return result
end

return table.freeze(SurfacePlacement)
