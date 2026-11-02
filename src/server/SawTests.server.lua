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

    local sheet = Stock.create(1002, 'Sheet', 'Aluminum', {x = 90, y = 4, z = 60})
    local sheetParts, sheetStats = SawCut.split(sheet, Vector3.zero, Vector3.zAxis)
    assert(sheetParts and sheetStats, 'Saw cut failed on thin sheet: ' .. tostring(sheetStats))
    assert(FORM.volumeClose(FORM.signedVolume(sheetParts[1])
        + FORM.signedVolume(sheetParts[2]) + sheetStats.removed, sheet.volume),
        'Sheet cut violated volume conservation')

    print(string.format('[SAW] Tests passed: 2 sealed steel fragments, kerf %.2f mm, %.2f mm³ removed; thin-sheet split valid',
        SawCut.KERF_MM, stats.removed))
end

run()
