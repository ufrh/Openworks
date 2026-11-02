local Toolpath = {}

local function geometryPart(folder, kind, a, b, radius, color)
    local difference = b - a
    local length = difference.Magnitude
    if length < 1e-5 then return end
    local part = Instance.new('Part')
    part.Name = kind
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Transparency = 0.18
    part.Shape = Enum.PartType.Cylinder
    part.Size = Vector3.new(length, radius * 2, radius * 2)
    part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
    part.Parent = folder
    return part
end

local function marker(folder, pos, radius, color)
    local part = Instance.new('Part')
    part.Name = 'Toolpoint'
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Shape = Enum.PartType.Ball
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Transparency = 0.05
    part.Size = Vector3.one * radius * 2
    part.Position = pos
    part.Parent = folder
end

local function point(p, frame, scale)
    return frame:PointToWorldSpace(Vector3.new(p.x, p.y, p.z) * scale)
end

local function line(folder, a, b, frame, scale, thickness, color)
    local first, last = point(a, frame, scale), point(b, frame, scale)
    geometryPart(folder, 'Toolpath', first, last, thickness * scale, color)
    marker(folder, first, thickness * scale * 2, color)
    marker(folder, last, thickness * scale * 2, color)
end

local function outlineBox(folder, center, size, frame, scale, color)
    local corners = {}
    for i = 0, 7 do
        local x = if i % 2 == 0 then -0.5 else 0.5
        local y = if math.floor(i / 2) % 2 == 0 then -0.5 else 0.5
        local z = if math.floor(i / 4) == 0 then -0.5 else 0.5
        corners[i + 1] = {x = center.x + x * size.x,
            y = center.y + y * size.y, z = center.z + z * size.z}
    end
    for i = 1, 8 do
        for _, mask in {1, 2, 4} do
            local other = bit32.bxor(i - 1, mask) + 1
            if other > i then
                line(folder, corners[i], corners[other], frame, scale, 0.8, color)
            end
        end
    end
end

function Toolpath.render(op, stock, frame, scale)
    local folder = Instance.new('Folder')
    folder.Name = 'OPENWORKS Toolpath'
    folder.Parent = workspace
    if not op then return folder end

    local color = Color3.fromRGB(246, 180, 72)
    if op.kind == 'drill' then
        local c = op.center
        local a = {x = c.x, y = c.y - op.height / 2, z = c.z}
        local b = {x = c.x, y = c.y + op.height / 2, z = c.z}
        line(folder, a, b, frame, scale, math.max(0.8, op.radius * 0.2), color)
        outlineBox(folder, c, {x = op.radius * 2, y = op.height, z = op.radius * 2},
            frame, scale, color)
    elseif op.kind == 'pocket' then
        outlineBox(folder, op.center, op.size, frame, scale, color)
    elseif op.kind == 'slot' then
        line(folder, op.from, op.to, frame, scale, math.max(0.8, op.radius * 0.25), color)
    elseif op.kind == 'profile' then
        for i = 1, #op.points - 1 do
            line(folder, op.points[i], op.points[i + 1], frame, scale,
                math.max(0.8, op.radius * 0.25), color)
        end
    elseif op.kind == 'saw' then
        local p = op.point
        local ext = math.max(stock.x, stock.y, stock.z) * 0.65
        if op.axis == 'X' then
            line(folder, {x = p.x, y = p.y - ext, z = p.z - ext},
                {x = p.x, y = p.y + ext, z = p.z - ext}, frame, scale, 1, color)
            line(folder, {x = p.x, y = p.y + ext, z = p.z + ext},
                {x = p.x, y = p.y - ext, z = p.z + ext}, frame, scale, 1, color)
        elseif op.axis == 'Y' then
            line(folder, {x = p.x - ext, y = p.y, z = p.z - ext},
                {x = p.x + ext, y = p.y, z = p.z - ext}, frame, scale, 1, color)
            line(folder, {x = p.x + ext, y = p.y, z = p.z + ext},
                {x = p.x - ext, y = p.y, z = p.z + ext}, frame, scale, 1, color)
        else
            line(folder, {x = p.x - ext, y = p.y - ext, z = p.z},
                {x = p.x + ext, y = p.y - ext, z = p.z}, frame, scale, 1, color)
            line(folder, {x = p.x + ext, y = p.y + ext, z = p.z},
                {x = p.x - ext, y = p.y + ext, z = p.z}, frame, scale, 1, color)
        end
    else
        local center = {x = (if op.signA == 1 then 0.5 else -0.5) * stock.x,
            y = 0, z = (if op.signB == 1 then 0.5 else -0.5) * stock.z}
        if op.axisA == 'X' and op.axisB == 'Z' then
            line(folder, {x = center.x, y = -stock.y / 2, z = center.z},
                {x = center.x, y = stock.y / 2, z = center.z}, frame, scale, 1.2, color)
        end
    end
    return folder
end

return Toolpath
