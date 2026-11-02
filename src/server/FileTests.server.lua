local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Stock = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('Stock'))
local FileShape = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FileShape'))

local function near(a, b, tolerance)
    return math.abs(a - b) <= tolerance
end

local function checkRound(stock, hit, radius)
    local preview, why = FileShape.preview(stock, hit, radius)
    assert(preview, 'Expected filing preview: ' .. tostring(why))
    assert(#preview.strips == 2 and #preview.strips[1] == FileShape.SEGMENTS + 1,
        'Curved filing preview should show both edge ends')

    local before = FORM.signedVolume(stock.solid)
    local solid, stats = FileShape.apply(stock, preview)
    assert(solid, 'Filing failed: ' .. tostring(stats))
    assert(FORM.validate(solid).ok, 'Filed workpiece is not closed')
    assert(stats.removed > 0 and stats.retained < before, 'Filing did not remove material')
    assert(FORM.volumeClose(before, stats.removed + stats.retained),
        'Filing violated volume conservation')
    assert(near(FORM.signedVolume(solid), stats.retained, 0.001),
        'Calculated volume differs from rendered result')
    return solid, stats
end

local base = Stock.create(1, 'Block', 'Steel', {x = 60, y = 20, z = 40})
local hit = Vector3.new(29.8, 9.9, 0) * Stock.SCALE
local output, result = checkRound(base, hit, 3)
local idealRemoved = (1 - math.pi / 4) * 3 * 3 * 40
assert(near(result.removed, idealRemoved, idealRemoved * 0.12),
    'Rounded-corner volume differs greatly from analytical arc')

local continued = {
    solid = output, frame = CFrame.identity,
    material = 'Steel', shape = 'Fabricated',
    volume = FORM.signedVolume(output),
}
local second, secondStats = checkRound(continued,
    Vector3.new(-29.8, 9.9, 0) * Stock.SCALE, 3)
assert(second and secondStats.removed > 0,
    'Opposite edge could not be filed after first rounding')

local sheet = Stock.create(2, 'Sheet', 'Aluminum', {x = 70, y = 4, z = 40})
local thin = checkRound(sheet, Vector3.new(34.9, 1.9, 0) * Stock.SCALE, 1)
assert(thin and FORM.validate(thin).ok, 'Small radius filing failed on thin sheet')

local snapped, explanation = FileShape.preview(sheet,
    Vector3.new(0, 2, 0) * Stock.SCALE, 1)
assert(snapped and snapped.axisA ~= snapped.axisB,
    'Face hover should snap to a nearby outer edge: ' .. tostring(explanation))

local alreadyRounded, roundedReason = FileShape.preview(continued,
    Vector3.new(29.8, 9.9, 0) * Stock.SCALE, 3)
assert(not alreadyRounded and roundedReason,
    'Already-rounded corner must reject another filing pass')

local tube = Stock.create(3, 'Tube', 'Steel', {radius = 8, innerRadius = 5, length = 80})
local refused, reason = FileShape.preview(tube, Vector3.zero, 3)
assert(not refused and reason, 'Tube should be rejected by convex-only edge rounding')

print(string.format('[FILE] Tests passed: convex rounding (%.3f mm³), repeated edges, thin sheet, face snap, previously rounded edge and tube guard',
    result.removed))
