local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))

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

    print('[FORM] Foundation tests passed')
end

run()
