local ScorePath = require(script.Parent:WaitForChild('ScorePath'))

local Layout = {}
Layout.SNAP_DISTANCE = 0.27

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < 100000
end

local function exposedFace(work)
    local axis, sign = ScorePath.face(work)
    local localNormal = ScorePath.normal(axis, sign)
    local normal = work.CFrame:VectorToWorldSpace(localNormal)
    local center = work.CFrame:PointToWorldSpace(
        localNormal * (if axis == 'X' then work.Size.X * 0.5
            elseif axis == 'Y' then work.Size.Y * 0.5
            else work.Size.Z * 0.5))
    local x = work.CFrame.RightVector
    if math.abs(x:Dot(normal)) > 0.95 then x = work.CFrame.LookVector end
    x = (x - normal * x:Dot(normal)).Unit
    return CFrame.fromMatrix(center, x, normal, x:Cross(normal)), normal
end

function Layout.rulerAngle(work, ruler)
    local frame = exposedFace(work)
    local direction = frame:VectorToObjectSpace(ruler.CFrame.RightVector)
    return math.atan2(-direction.Z, direction.X)
end

function Layout.rulerFrame(work, ruler, point, rotation)
    if not work or not ruler or typeof(point) ~= 'Vector3'
        or not finite(rotation) or math.abs(rotation) > math.pi * 2
        or not ScorePath.valid(work, point, ScorePath.face(work)) then
        return nil
    end
    local frame, normal = exposedFace(work)
    local worldPoint = work.CFrame:PointToWorldSpace(point)
    local planar = frame:PointToObjectSpace(worldPoint)
    return frame * CFrame.new(planar.X, ruler.Size.Y * 0.5 + 0.025,
        planar.Z) * CFrame.Angles(0, rotation, 0)
end

function Layout.rulerGuide(work, ruler, localPoint)
    if not work or not ruler or not ruler:IsA('BasePart')
        or ruler:GetAttribute('DraftingKind') ~= 'Ruler'
        or typeof(localPoint) ~= 'Vector3' or not work.Parent or not ruler.Parent then
        return nil
    end
    local frame, normal = exposedFace(work)
    if ruler.CFrame.UpVector:Dot(normal) < 0.82 then return nil end
    local height = (ruler.Position - frame.Position):Dot(normal)
    if height < -0.08 or height > 0.65 then return nil end

    local alongWorld = if ruler.Size.X >= ruler.Size.Z
        then ruler.CFrame.RightVector else ruler.CFrame.LookVector
    local directionWorld = alongWorld - normal * alongWorld:Dot(normal)
    if directionWorld.Magnitude < 0.8 then return nil end
    directionWorld = directionWorld.Unit
    local perpendicularWorld = normal:Cross(directionWorld).Unit

    local span = math.max(ruler.Size.X, ruler.Size.Z) * 0.5
    local width = math.min(ruler.Size.X, ruler.Size.Z) * 0.5
    local worldPoint = work.CFrame:PointToWorldSpace(localPoint)
    local origin = ruler.Position - normal * height
    local best, nearest

    for _, side in {-1, 1} do
        local edge = origin + perpendicularWorld * width * side
        local distance = math.abs((worldPoint - edge):Dot(perpendicularWorld))
        local along = (worldPoint - edge):Dot(directionWorld)
        if distance <= Layout.SNAP_DISTANCE and math.abs(along) <= span + 0.08
            and (not nearest or distance < nearest) then
            best = {
                origin = work.CFrame:PointToObjectSpace(edge),
                direction = work.CFrame:VectorToObjectSpace(directionWorld),
                span = span,
                ruler = ruler,
            }
            nearest = distance
        end
    end
    return best, nearest
end

function Layout.snap(work, guide, localPoint)
    if not guide or typeof(localPoint) ~= 'Vector3' then return nil end
    local travel = (localPoint - guide.origin):Dot(guide.direction)
    local along = math.clamp(travel, -guide.span, guide.span)
    local projected = guide.origin + guide.direction * along
    local point, axis, sign = ScorePath.project(work,
        work.CFrame:PointToWorldSpace(projected))
    if point and ScorePath.valid(work, point, axis, sign) then
        return point
    end
end

return Layout
