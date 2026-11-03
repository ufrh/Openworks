local FORM = require(script.Parent.FORM)
local Stock = require(script.Parent.Stock)
local PathCut = require(script.Parent.PathCut)
local PrismProfile = require(script.Parent.PrismProfile)
local ContourFile = require(script.Parent.ContourFile)
local ScorePath = require(script.Parent.ScorePath)
local Shading = require(script.Parent.FORM.Shading)

local GeometryRegression = {}

local function requireSolids(parts)
    assert(type(parts) == 'table' and #parts == 2,
        'Expected exactly two physical solid fragments')
    for i, part in parts do
        local check = FORM.validate(part)
        assert(check.ok, 'Fragment ' .. tostring(i) .. ' has invalid topology: '
            .. tostring(check.issues[1] and check.issues[1].code))
    end
end

local function center(solid)
    local low, high = FORM.bounds(solid)
    local midpoint = (low + high) * 0.5
    local vertices = {}
    for i, point in solid.vertices do vertices[i] = point - midpoint end
    return {vertices = vertices, triangles = solid.triangles},
        (high - low) * Stock.SCALE, midpoint * Stock.SCALE
end

function GeometryRegression.run()
    local work = Instance.new('Part')
    work.Size = Vector3.new(4, 0.24, 4)
    work.CFrame = CFrame.identity
    work:SetAttribute('FORMNativeStock', true)

    local original = FORM.box(work.Size / Stock.SCALE)
    local outline = PrismProfile.extract(original)
    assert(outline and #outline == 4, 'Cannot extract initial rectangular outline')

    local firstPath = {
        Vector3.new(-2, 0.12, 0),
        Vector3.new(-0.7, 0.12, 0.2),
        Vector3.new(0.7, 0.12, 0.2),
        Vector3.new(2, 0.12, 0),
    }
    local first, firstError = PathCut.split(work, firstPath)
    assert(first, 'Initial curved cut: ' .. tostring(firstError))
    requireSolids(first)

    local one, size, translation = center(first[1])
    work.Size = size
    work.CFrame = CFrame.new(translation)

    local half = work.Size * 0.5
    local secondPath = {
        Vector3.new(0, half.Y, -half.Z),
        Vector3.new(0, half.Y, half.Z),
    }
    local second, secondError = PathCut.split(work, secondPath, nil, one)
    assert(second, 'Second cut into previously shaped metal: ' .. tostring(secondError))
    requireSolids(second)

    local two, newSize, placement = center(second[1])
    work.Size = newSize
    work.CFrame = CFrame.new(translation + placement)
    local contour = PrismProfile.extract(two)
    assert(contour and #contour >= 3, 'Re-cut fragment lost its real perimeter')

    local chosen
    for i, corner in contour do
        local before = contour[(i - 2) % #contour + 1]
        local after = contour[i % #contour + 1]
        local incoming, outgoing = corner - before, after - corner
        local delta = incoming.X * outgoing.Y - incoming.Y * outgoing.X
        if delta > 0.0001 then chosen = corner break end
    end
    assert(chosen, 'No fileable convex contour edge')
    local filed, fileError = ContourFile.apply(work, {solid = two},
        Vector3.new(chosen.X * Stock.SCALE, 0, chosen.Y * Stock.SCALE),
        2, 'Round')
    assert(filed, 'Filing a shaped edge: ' .. tostring(fileError))
    assert(FORM.validate(filed).ok, 'Filed result has invalid geometry')
    assert(FORM.signedVolume(filed) < FORM.signedVolume(two),
        'Filing must remove, not add, material')

    local smooth = ScorePath.smooth(work, {
        Vector3.new(-0.2, work.Size.Y * 0.5, -0.2),
        Vector3.new(-0.1, work.Size.Y * 0.5, 0.08),
        Vector3.new(0, work.Size.Y * 0.5, 0.2),
        Vector3.new(0.1, work.Size.Y * 0.5, 0.08),
        Vector3.new(0.2, work.Size.Y * 0.5, -0.2),
    })
    assert(#smooth > 5 and #smooth <= ScorePath.MAX_POINTS,
        'Score was not smoothly resampled')
    local normals = Shading.normals(filed, 65)
    assert(#normals == #filed.triangles, 'Shading normals do not match mesh faces')

    work:Destroy()
    return true, 'FORM: curved cut, repeated cut, contour file, score smoothing and shading passed'
end

return GeometryRegression
