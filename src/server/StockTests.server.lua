local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Stock = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('Stock'))

local function check(id, shape, material, dimensions, expected)
    local piece = Stock.create(id, shape, material, dimensions)
    assert(FORM.validate(piece.solid).ok, shape .. ' is not a closed oriented solid')
    assert(FORM.volumeClose(piece.volume, FORM.signedVolume(piece.solid)),
        shape .. ' volume does not match canonical mesh')
    assert(math.abs(piece.volume - expected) <= math.max(0.03, expected * 0.00005),
        shape .. ' volume outside dimensional tolerance: ' .. tostring(piece.volume))
    assert(piece.massKg > 0, shape .. ' missing mass')
    assert(piece.material == material and piece.id == id, 'Workpiece lost identity/material')
    return piece
end

local block = check(1, 'Block', 'Steel', {x = 60, y = 20, z = 40}, 48000)
local sheet = check(2, 'Sheet', 'Aluminum', {x = 90, y = 4, z = 60}, 21600)
local rod = Stock.create(3, 'Rod', 'Steel', {radius = 6, length = 80})
local tube = Stock.create(4, 'Tube', 'Aluminum', {radius = 8, innerRadius = 5, length = 80})
for _, item in {rod, tube} do
    assert(FORM.validate(item.solid).ok, item.shape .. ' topology invalid')
end
assert(tube.volume < rod.volume * 2 and tube.volume > 0, 'Tube volume incorrect')
assert(math.abs(rod.volume - 12 * 12 * math.sin(math.pi / 8) * 80 / 2 * 16) < 1,
    'Rod polygonal volume incorrect')
local expectedTube = 16 * math.sin(math.pi / 8) * (8 * 8 - 5 * 5) * 80 / 2
assert(math.abs(tube.volume - expectedTube) < 1, 'Tube cross-sectional area incorrect')

local oldVolume = block.volume
local oldFrame = block.frame
Stock.move(block, CFrame.new(4, 5, -8) * CFrame.Angles(0, math.rad(45), 0))
assert(block.frame ~= oldFrame, 'Placement did not change')
assert(FORM.volumeClose(oldVolume, FORM.signedVolume(block.solid)),
    'World placement changed canonical local-space volume')
assert(sheet.massKg < block.massKg, 'Material density calculation incorrect')

for _, sample in {
    {'Sheet', 'Steel', {x = 40, y = 50, z = 50}},
    {'Tube', 'Steel', {radius = 8, innerRadius = 9, length = 80}},
    {'Block', 'Wood', {x = 20, y = 20, z = 20}},
} do
    local ok = pcall(Stock.create, 9, sample[1], sample[2], sample[3])
    assert(not ok, 'Invalid raw stock was accepted: ' .. sample[1])
end

print(string.format('[STOCK] M1 tests passed: block %.0f, sheet %.0f, rod %.2f, tube %.2f mm^3; placements and metal mass valid',
    block.volume, sheet.volume, rod.volume, tube.volume))
