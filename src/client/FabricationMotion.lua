local FabricationVisual = require(script.Parent.FabricationVisual)
local Stock = require(game:GetService('ReplicatedStorage'):WaitForChild('Openworks'):WaitForChild('Stock'))

local Motion = {}

local function boundsProjection(rings, center, direction)
    local low, high = math.huge, -math.huge
    for _, ring in rings do
        for _, position in ring do
            local distance = (position - center):Dot(direction)
            low = math.min(low, distance)
            high = math.max(high, distance)
        end
    end
    return low, high
end

local function frame(position, forward, outward)
    return FabricationVisual.contactFrame(position, forward, outward)
end

function Motion.sawPlan(guide, worldHit, surfaceNormal)
    local rings = guide.rings or {guide.ring}
    local center = Vector3.zero
    local count = 0
    for _, vertex in rings[1] do
        center += vertex
        count += 1
    end
    if count < 3 then return nil, 'Cutting section is too small' end
    center /= count

    local normal = guide.normal.Unit
    local outward = surfaceNormal - normal * surfaceNormal:Dot(normal)
    if outward.Magnitude < 0.15 then
        local radial = worldHit - center
        outward = radial - normal * radial:Dot(normal)
    end
    if outward.Magnitude < 0.001 then
        outward = normal:Cross(Vector3.yAxis)
        if outward.Magnitude < 0.001 then outward = normal:Cross(Vector3.xAxis) end
    end
    outward = outward.Unit
    local forward = outward:Cross(normal).Unit

    local low, high = boundsProjection(rings, center, outward)
    local acrossLow, acrossHigh = boundsProjection(rings, center, forward)
    local depth = high - low
    if depth < 0.04 then return nil, 'Workpiece is too thin for a saw stroke' end

    return {
        center = center,
        normal = normal,
        outward = outward,
        forward = forward,
        span = depth,
        start = high,
        across = acrossHigh - acrossLow,
        clearance = math.min(0.15, math.max(0.05, depth * 0.06)),
        stroke = math.clamp((acrossHigh - acrossLow) * 0.20, 0.06, 0.45),
    }
end

function Motion.sawPose(plan, advance, phase)
    local distance = math.clamp(advance, 0, 1) * (plan.span + plan.clearance)
    local position = plan.center + plan.outward * (plan.start + plan.clearance - distance)
        + plan.forward * (math.sin(phase) * plan.stroke)
    return frame(position, plan.forward, plan.outward)
end

function Motion.filePlan(item, spec)
    local low, high = spec.boundsLow, spec.boundsHigh
    local along = if spec.edgeAxis == 'X' then Vector3.xAxis
        elseif spec.edgeAxis == 'Y' then Vector3.yAxis else Vector3.zAxis
    local axisA = if spec.axisA == 'X' then Vector3.xAxis
        elseif spec.axisA == 'Y' then Vector3.yAxis else Vector3.zAxis
    local axisB = if spec.axisB == 'X' then Vector3.xAxis
        elseif spec.axisB == 'Y' then Vector3.yAxis else Vector3.zAxis

    local outwardLocal = (axisA * spec.signA + axisB * spec.signB).Unit
    local cornerLocal = axisA * (if spec.signA == 1 then high:Dot(axisA) else low:Dot(axisA))
        + axisB * (if spec.signB == 1 then high:Dot(axisB) else low:Dot(axisB))
        + along * ((high:Dot(along) + low:Dot(along)) / 2)

    local start = item.frame:PointToWorldSpace(cornerLocal * Stock.SCALE)
    local midpoint = math.ceil(#spec.strips[1] / 2)
    local finish = (spec.strips[1][midpoint] + spec.strips[2][midpoint]) / 2
    local forward = item.frame:VectorToWorldSpace(along).Unit
    local outward = item.frame:VectorToWorldSpace(outwardLocal).Unit
    local span = (spec.strips[1][1] - spec.strips[2][1]).Magnitude

    return {
        start = start + outward * 0.04,
        finish = finish,
        forward = forward,
        outward = outward,
        stroke = math.clamp(span * 0.24, 0.08, 0.48),
    }
end

function Motion.filePose(plan, progress, phase)
    local contact = plan.start:Lerp(plan.finish, math.clamp(progress, 0, 1))
        + plan.forward * (math.sin(phase) * plan.stroke)
    return frame(contact, plan.forward, plan.outward)
end

function Motion.surfaceNormal(part, ray)
    if not part or not part.Parent then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {part}
    local hit = workspace:Raycast(ray.Origin, ray.Direction * 500, params)
    return if hit then hit.Normal else nil
end

return Motion
