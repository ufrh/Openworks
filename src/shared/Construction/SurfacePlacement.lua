--!strict
-- Shared support-plane placement for multi-part previews.
-- Given a preview at desired rotation/pivot, shift EVERY member together so
-- its lowest world-space geometry rests on the aimed surface, not below it.
local SurfacePlacement = {}
-- Face planes must be exactly coincident: clearance creates visible seams.
local EPSILON = 0

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
local EDGE_CAPTURE=0.05

local function quantize(value,step)
    return math.floor(value/step+0.5)*step
end

function SurfacePlacement.SnapToNearbyFace(ghost:Model,desired:CFrame,
    hitPosition:Vector3,hitNormal:Vector3,hitPart:BasePart?):CFrame
    if not hitPart or not hitPart:IsA("BasePart") then
        return SurfacePlacement.SnapToSurface(ghost,desired,
            hitPosition,hitNormal)
    end
    local targetCF=hitPart.CFrame
    local n=hitNormal.Unit
    -- A raycast on a faceted/CSG surface may be microscopically inside
    -- the part's canonical planar face. For ordinary orthogonal block
    -- faces resolve the actual support plane from its oriented bounds,
    -- so adjacent solids meet EXACTLY despite raycast numerical drift.
    local faceHit=hitPosition
    local planar=false
    for _,axis in ipairs({targetCF.RightVector,targetCF.UpVector,
        targetCF.LookVector}) do
        if math.abs(n:Dot(axis))>0.999 then
            planar=true
            break
        end
    end
    if planar then
        local facePlane=n:Dot(hitPart.Position)+axisRadius(hitPart,n)
        faceHit=hitPosition+n*(facePlane-n:Dot(hitPosition))
    end
    local cf=SurfacePlacement.SnapToSurface(ghost,desired,
        faceHit,hitNormal)
    ghost:PivotTo(cf)
    local delta=Vector3.zero
    local axisVectors={targetCF.RightVector,targetCF.UpVector,
        targetCF.LookVector}
    local targetSize=hitPart.Size
    local components={targetSize.X,targetSize.Y,targetSize.Z}
    for i,axis in ipairs(axisVectors) do
        if math.abs(n:Dot(axis))<0.6 then
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
            local bestEdge=EDGE_CAPTURE
            for _,candidate in ipairs(candidates) do
                local distance=math.abs(tangent-candidate)
                if distance<bestEdge then
                    -- Real target face edges/centers outrank an arbitrary
                    -- local lattice point if the cursor is near an edge.
                    bestEdge=distance
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
