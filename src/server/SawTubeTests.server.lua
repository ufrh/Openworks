local ReplicatedStorage = game:GetService('ReplicatedStorage')
local root = ReplicatedStorage:WaitForChild('Openworks')
local FORM = require(root.FORM)
local Stock = require(root.Stock)
local SawCut = require(root.SawCut)
local SawTube = require(root.SawTube)

local tube = Stock.create(900, 'Tube', 'Steel',
    {radius = 8, innerRadius = 5, length = 80, segments = 16},
    CFrame.new(7, 12, -4) * CFrame.Angles(0, math.rad(31), math.rad(8)))

local function closedTube(solid)
    local validation = FORM.validate(solid)
    assert(validation.ok, 'Tube fragment surface invalid')
    local edgeCount = 0
    for _ in validation.edges do edgeCount += 1 end
    assert(#solid.vertices - edgeCount + #solid.triangles == 0,
        'Tube bore disappeared or topology changed')
end

local function verify(item, point, normal)
    local guide, reason = SawCut.preview(item, point, normal)
    assert(guide, 'Tube preview failed: ' .. tostring(reason))
    assert(guide.rings and #guide.rings == 2
        and #guide.rings[1] == 16 and #guide.rings[2] == 16,
        'Expected two independent annular guide outlines')
    local solids, stats = SawCut.split(item, point, normal)
    assert(solids and #solids == 2, 'Tube split failed: ' .. tostring(stats))
    assert(stats.tubeProfiles and #stats.tubeProfiles == 2,
        'Tube profile metadata not returned')
    for _, solid in solids do closedTube(solid) end
    local total = stats.removed + FORM.signedVolume(solids[1]) + FORM.signedVolume(solids[2])
    assert(FORM.volumeClose(total, item.volume), 'Tube split violated volume conservation')
    assert(stats.removed > 0, 'Tube saw kerf must remove nonzero metal')
    return solids, stats
end

local normal = tube.frame:VectorToWorldSpace(Vector3.yAxis)
local solids, stats = verify(tube, tube.frame.Position, normal)
local area = 16 * math.sin(math.pi / 8) * (8 * 8 - 5 * 5) / 2
assert(math.abs(stats.removed - area * SawCut.KERF_MM) < 0.05,
    'Tube kerf removed the wrong amount of material')

local tiltedNormal = tube.frame:VectorToWorldSpace(Vector3.new(0.28, 1, 0.18).Unit)
local oblique, obliqueStats = verify(tube, tube.frame.Position, tiltedNormal)
assert(math.abs(obliqueStats.removed - area * SawCut.KERF_MM
    / Vector3.new(0.28, 1, 0.18).Unit.Y) < 0.1,
    'Angled kerf volume is incorrect')

local upper = solids[1]
local lower, higher = FORM.bounds(upper)
local offset = (lower + higher) / 2
local centered = {vertices = {}, triangles = upper.triangles}
for i, vertex in upper.vertices do centered.vertices[i] = vertex - offset end
local resawn = {
    shape = 'Fabricated', material = 'Steel',
    solid = centered, volume = FORM.signedVolume(centered),
    frame = tube.frame * CFrame.new(offset * Stock.SCALE),
    tubeProfile = SawTube.offsetProfile(stats.tubeProfiles[1], offset),
}
local again = verify(resawn, tube.frame:PointToWorldSpace(Vector3.new(0, 20, 0) * Stock.SCALE), normal)
assert(again, 'Re-cutting a fabricated tube should work')

local bad, message = SawCut.preview(tube, tube.frame.Position,
    tube.frame:VectorToWorldSpace(Vector3.xAxis))
assert(not bad and message, 'Axial lengthwise slicing should be rejected safely')

print(string.format('[SAW TUBE] Passed: two bore-preserving solids, %.2f mm^3 kerf, angled cut, second cut, rejection', stats.removed))
