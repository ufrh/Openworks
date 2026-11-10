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
        if part:IsA("BasePart") then
            lowest = math.min(lowest, n:Dot(part.Position) - axisRadius(part, n))
        end
    end
    if lowest == math.huge then return desiredPivot end

    local clearance = n:Dot(hitPosition) - lowest + EPSILON
    local nextCF = desiredPivot + n * clearance
    ghost:PivotTo(nextCF)
    return nextCF
end

return table.freeze(SurfacePlacement)
