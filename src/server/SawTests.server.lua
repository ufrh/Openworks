local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Stock = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('Stock'))
local SawCut = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('SawCut'))

local function run()
    local stock = Stock.create(1001, 'Block', 'Steel', {x = 60, y = 20, z = 40},
        CFrame.new(5, 7, 9) * CFrame.Angles(0, math.rad(35), 0))
    local normal = stock.frame:VectorToWorldSpace(Vector3.xAxis)
    local guide, reason = SawCut.preview(stock, stock.frame.Position, normal)
    assert(guide and #guide.ring >= 4, 'Expected intersecting saw guide: ' .. tostring(reason))

    local parts, stats = SawCut.split(stock, stock.frame.Position, normal)
    assert(parts and #parts == 2, 'Expected two cut solids: ' .. tostring(stats))
    local total = stats.removed
    for _, solid in parts do
        assert(FORM.validate(solid).ok, 'Cut fragment failed topology validation')
        total += FORM.signedVolume(solid)
    end
    assert(FORM.volumeClose(total, stock.volume), 'Saw cut lost or created material')
    local expectedKerf = 20 * 40 * SawCut.KERF_MM
    assert(math.abs(stats.removed - expectedKerf) < 0.02, 'Saw kerf volume incorrect')
    assert(math.abs(FORM.signedVolume(parts[1]) - FORM.signedVolume(parts[2])) < 0.02,
        'Centered cut did not leave two equal pieces')

    local clipped, badReason = SawCut.preview(stock,
        stock.frame:PointToWorldSpace(Vector3.new(30, 0, 0) * Stock.SCALE), normal)
    assert(not clipped and badReason, 'Cut preview should reject boundary tangent')

    local angledLocal = Vector3.new(1, 0.28, 0.22).Unit
    local angledPoint = stock.frame.Position
    local angledNormal = stock.frame:VectorToWorldSpace(angledLocal)
    local sloped, slopedStats = SawCut.split(stock, angledPoint, angledNormal)
    assert(sloped and slopedStats, '3D sloped cut must produce two pieces: ' .. tostring(slopedStats))
    assert(FORM.validate(sloped[1]).ok and FORM.validate(sloped[2]).ok,
        '3D angled cut produced nonmanifold geometry')
    assert(FORM.volumeClose(FORM.signedVolume(sloped[1])
        + FORM.signedVolume(sloped[2]) + slopedStats.removed, stock.volume),
        '3D angled cut did not conserve metal')

    local capturedLocalPoint = stock.frame:PointToObjectSpace(angledPoint)
    local movedFrame = CFrame.new(-8, 10, 3)
        * CFrame.Angles(math.rad(17), math.rad(61), math.rad(-13))
    Stock.move(stock, movedFrame)
    local movedPoint = stock.frame:PointToWorldSpace(capturedLocalPoint)
    local movedNormal = stock.frame:VectorToWorldSpace(angledLocal)
    local movingCut, movingStats = SawCut.split(stock, movedPoint, movedNormal)
    assert(movingCut and movingStats, 'Loose rotating stock must retain its local cut plane')
    assert(FORM.volumeClose(FORM.signedVolume(movingCut[1])
        + FORM.signedVolume(movingCut[2]) + movingStats.removed, stock.volume),
        'Loose stock moving through space changed cut volume')

    local sheet = Stock.create(1002, 'Sheet', 'Aluminum', {x = 90, y = 4, z = 60})
    local sheetParts, sheetStats = SawCut.split(sheet, Vector3.zero, Vector3.zAxis)
    assert(sheetParts and sheetStats, 'Saw cut failed on thin sheet: ' .. tostring(sheetStats))
    assert(FORM.volumeClose(FORM.signedVolume(sheetParts[1])
        + FORM.signedVolume(sheetParts[2]) + sheetStats.removed, sheet.volume),
        'Sheet cut violated volume conservation')

    print(string.format('[SAW] Tests passed: sealed steel, 3D angled cuts, moving local-plane tracking, kerf %.2f mm; thin-sheet split',
        SawCut.KERF_MM, stats.removed))
end

run()
