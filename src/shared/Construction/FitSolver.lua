--!strict
-- Shared collision-independent pose solver. Alignment is geometric only:
-- mechanical relationships require their dedicated server-authorized commit.
local Origin=require(script.Parent:WaitForChild("FitOrigin"))
local Features=require(script.Parent:WaitForChild("FitFeatureRegistry"))
local Solver={}
local CAPTURE=0.42
local function rayDistance(ray,position)
    if not ray then return math.huge end
    local direction=ray.Direction.Unit
    local delta=position-ray.Origin
    local along=delta:Dot(direction)
    if along<=0 or along>256 then return math.huge end
    return (delta-direction*along).Magnitude
end
function Solver.PivotCandidate(ghost,target,aimRay,aimed)
    local feature=Features.Describe(target)
    if not feature or not feature.HasOrigin then return nil end
    local sourceLocal,custom=Origin.PreviewLocal(ghost)
    if not custom then return nil end
    local mouseDistance=rayDistance(aimRay,feature.Origin)
    if mouseDistance>CAPTURE then return nil end
    local original=ghost:GetPivot()
    local pose=CFrame.new(feature.Origin)*original.Rotation
        *CFrame.new(-sourceLocal)
    return {
        kind="Pivot",relationKind="FitOnly",
        cf=pose,target=target,
        score=if target==aimed then -1.4+mouseDistance
            else -0.1+mouseDistance,
        approach=feature.Origin,
        offsetUnits=0,rollDegrees=0,
    }
end
-- Optional selected grab point overrides normal bounding-box face placement.
-- A custom pivot can be placed against a free surface or floor, not only
-- against another user-authored origin.
function Solver.SurfacePose(ghost,rotation,hitPosition)
    local _,has=Origin.PreviewLocal(ghost)
    if not has then return nil end
    return Origin.PlaceAt(ghost,rotation,hitPosition)
end
return table.freeze(Solver)
