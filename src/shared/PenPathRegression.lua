local PenPath = require(script.Parent.PenPath)
local ScorePath = require(script.Parent.ScorePath)

local Regression = {}

local function node(point, incoming, outgoing)
    return {point = point, inHandle = incoming or point, outHandle = outgoing or point}
end

function Regression.run()
    local sheet = Instance.new('Part')
    sheet.Name = 'PenRegressionMetal'
    sheet.Size = Vector3.new(4, 0.24, 4)
    sheet.CFrame = CFrame.new(0, 150, 0)
    sheet.Anchored = true

    local y = sheet.Size.Y * 0.5
    local first = Vector3.new(-1, y, -1)
    local last = Vector3.new(1, y, 1)
    local straight, straightDetails = PenPath.sample(sheet, {
        node(first), node(last),
    })
    assert(straight and straightDetails.face == 'Y'
        and #straight >= 2
        and (straight[1] - first).Magnitude < 1e-6
        and (straight[#straight] - last).Magnitude < 1e-6,
        'Pen Tool must preserve both straight endpoints')
    for _, p in straight do
        assert(math.abs(p.X - p.Z) < 1e-5,
            'Clicking unhandled anchors must create a straight segment')
    end

    local curve, detail = PenPath.sample(sheet, {
        node(first, nil, Vector3.new(-0.3, y, -1)),
        node(last, Vector3.new(1, y, 0.3)),
    })
    assert(curve and detail.length > 2 and #curve <= ScorePath.MAX_POINTS,
        'Curved Pen Tool path must fit FORM score path budget')
    local deviation = 0
    for _, p in curve do
        assert(ScorePath.valid(sheet, p, 'Y', 1),
            'Bezier sampled point left the exposed metal face')
        deviation = math.max(deviation, math.abs(p.X - p.Z))
    end
    assert(deviation > 0.15,
        'Smooth Pen Tool handles must create genuine curvature')

    local invalid = PenPath.sample(sheet, {
        node(first, nil, Vector3.new(5, y, 0)),
        node(last),
    })
    assert(not invalid, 'An implausibly long pen handle must be rejected')

    local outside = PenPath.sample(sheet, {
        node(Vector3.new(1.8, y, -1),
            nil, Vector3.new(3.3, y, -0.5)),
        node(Vector3.new(1.8, y, 1),
            Vector3.new(3.3, y, 0.5)),
    })
    assert(not outside,
        'Bézier controls outside the material must fail when curve leaves the metal')

    sheet.CFrame = CFrame.new(0, 150, 0) * CFrame.Angles(0.2, 0.4, -0.15)
    local rotated = PenPath.sample(sheet, {
        node(first), node(last),
    })
    assert(rotated, 'Pen Tool must retain local-face geometry on rotated metal')

    sheet:Destroy()
    return true, 'straight/smooth Bézier scoring, geometry limits and rotated metal passed'
end

return Regression
