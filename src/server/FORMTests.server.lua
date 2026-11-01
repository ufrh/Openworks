local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))

local Cut = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Cut'))

local function close(a, b)
    return math.abs(a - b) <= math.max(1e-6, math.abs(b) * 1e-9)
end

local function run()
    local box = FORM.box(Vector3.new(100, 50, 20))
    local result = FORM.validate(box)
    assert(result.ok, 'Box topology failed: ' .. tostring(result.issues[1] and result.issues[1].code))
    assert(#box.vertices == 8 and #box.triangles == 12, 'Unexpected topology')
    assert(close(FORM.signedVolume(box), 100000), 'Incorrect volume')

    local lo, hi = FORM.bounds(box)
    assert(lo == Vector3.new(-50, -25, -10) and hi == Vector3.new(50, 25, 10), 'Incorrect bounds')

    local inverted = FORM.box(Vector3.new(10, 10, 10))
    inverted.triangles[1] = {1, 2, 3}
    assert(not FORM.validate(inverted).ok, 'Inverted face undetected')

    local open = FORM.box(Vector3.new(10, 10, 10))
    table.remove(open.triangles)
    assert(not FORM.validate(open).ok, 'Open mesh undetected')

    for _, normal in {
        Vector3.xAxis,
        Vector3.yAxis,
        Vector3.zAxis,
        Vector3.new(1, 0.4, 0.7).Unit,
    } do
        local positive, negative = Cut.split(box, Vector3.zero, normal)
        assert(positive and negative, 'Planar split failed: ' .. tostring(negative))
        assert(FORM.validate(positive).ok and FORM.validate(negative).ok, 'Open cut surfaces')
        local expected = FORM.signedVolume(box)
        local actual = FORM.signedVolume(positive) + FORM.signedVolume(negative)
        local difference = actual - expected
        local tolerance = math.max(1e-5, expected * 1e-8)
        print(string.format('[FORM] Cut volume delta: %+.9f mm^3 (limit %.9f)', difference, tolerance))
        assert(math.abs(difference) <= tolerance,
            string.format('Split volume mismatch: expected %.9f, actual %.9f, delta %+.9f mm^3', expected, actual, difference))
    end

    local outside, reason = Cut.split(box, Vector3.new(200, 0, 0), Vector3.xAxis)
    assert(not outside and reason == 'PLANE_DOES_NOT_INTERSECT', 'Outside plane not rejected')

    print('[FORM] Foundation and planar split tests passed')
end

run()
