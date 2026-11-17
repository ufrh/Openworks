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

-- A Shift face-center fit aligns the moving shape's TRUE combined
-- footprint, not necessarily its Model pivot (which authors can relocate).
-- Only genuine flat faces are centered. Cylindrical/curved sides continue
-- using their normal mouse-based behavior rather than inventing a center.
local function flatFaceAxis(part:BasePart,normal:Vector3):Vector3?
    local candidate=nil
    local best=0
    for _,axis in ipairs({part.CFrame.RightVector,part.CFrame.UpVector,
        part.CFrame.LookVector}) do
        local dot=normal:Dot(axis)
        if math.abs(dot)>best then
            best=math.abs(dot)
            candidate=axis
        end
    end
    if best<0.995 then return nil end
    if part:IsA("Part") and part.Shape==Enum.PartType.Ball then
        return nil
    end
    -- Cylinder's round side is not a rectangular face.
    if part:IsA("Part") and part.Shape==Enum.PartType.Cylinder
        and math.abs(normal:Dot(part.CFrame.RightVector))<0.995 then
        return nil
    end
    return candidate
end

local function footprintCenterAlong(ghost:Model,axis:Vector3):number?
    local lower,upper=math.huge,-math.huge
    for _,part in ipairs(ghost:GetDescendants()) do
        if part:IsA("BasePart")
            and part:GetAttribute("GearPivotOnly")~=true then
            local center=part.Position:Dot(axis)
            local radius=axisRadius(part,axis)
            lower=math.min(lower,center-radius)
            upper=math.max(upper,center+radius)
        end
    end
    if lower==math.huge then return nil end
    return (lower+upper)*0.5
end

function SurfacePlacement.SnapToNearbyFace(ghost:Model,desired:CFrame,
    hitPosition:Vector3,hitNormal:Vector3,hitPart:BasePart?,
    centerOnFace:boolean?):CFrame
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
    if centerOnFace and flatFaceAxis(hitPart,n) then
        -- Surface contact is already exact along the normal. The two
        -- tangential axes are centered around the target's geometric
        -- face center, irrespective of cursor position, size, or rotation.
        -- This intentionally takes priority over edge/lattice snapping.
        for _,axis in ipairs(axisVectors) do
            if math.abs(n:Dot(axis))<0.6 then
                local movingCenter=footprintCenterAlong(ghost,axis)
                if movingCenter then
                    delta+=axis*(hitPart.Position:Dot(axis)-movingCenter)
                end
            end
        end
        local centered=cf+delta
        ghost:PivotTo(centered)
        return centered
    end
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
