local Layout = require(script.Parent.MaterialLayout)
local ScorePath = require(script.Parent.ScorePath)

local Regression = {}

function Regression.run()
    local work = Instance.new('Part')
    work.Name = 'LayoutRegressionStock'
    work.Size = Vector3.new(4, 0.24, 4)
    work.Anchored = true
    work.CFrame = CFrame.new(0, 150, 0)
    work.Parent = workspace

    local ruler = Instance.new('Part')
    ruler.Name = 'LayoutRegressionRuler'
    ruler.Size = Vector3.new(3, 0.13, 0.36)
    ruler.Anchored = true
    ruler:SetAttribute('DraftingKind', 'Ruler')
    ruler:SetAttribute('isTool', true)
    ruler.CFrame = work.CFrame * CFrame.new(
        0, work.Size.Y * 0.5 + ruler.Size.Y * 0.5 + 0.025, 0)
    ruler.Parent = workspace

    local edge = ruler.Size.Z * 0.5
    local contact = Vector3.new(-0.7, work.Size.Y * 0.5, edge + 0.035)
    local guide = Layout.rulerGuide(work, ruler, contact)
    assert(guide, 'A straight physical ruler should constrain a nearby steel score')

    local a = Layout.snap(work, guide,
        Vector3.new(-1.1, work.Size.Y * 0.5, edge + 0.05))
    local b = Layout.snap(work, guide,
        Vector3.new(1.1, work.Size.Y * 0.5, edge - 0.07))
    assert(a and b and math.abs(a.Z - b.Z) < 0.0001,
        'Ruler-guided metal marks should be exactly collinear')
    assert(ScorePath.valid(work, a, 'Y', 1)
        and ScorePath.valid(work, b, 'Y', 1),
        'Ruler marks must lie on the exposed material face')
    assert((b - a).Magnitude > 1.5,
        'Snapped stroke did not preserve ruler length')

    local rot = math.rad(35)
    local frame = Layout.rulerFrame(work, ruler,
        Vector3.new(0, work.Size.Y * 0.5, 0), rot)
    assert(frame, 'Could not physically place ruler onto metal')
    ruler.CFrame = frame
    local rotatedPoint = ruler.CFrame:PointToWorldSpace(
        Vector3.new(0, -ruler.Size.Y * 0.5, edge + 0.03))
    local rotatedContact = ScorePath.project(work, rotatedPoint)
    local rotatedGuide = rotatedContact
        and Layout.rulerGuide(work, ruler, rotatedContact)
    assert(rotatedGuide, 'Rotating the ruler lost its marking constraint')
    local rotated = Layout.snap(work, rotatedGuide, rotatedContact)
    assert(rotated and ScorePath.valid(work, rotated, 'Y', 1),
        'Rotated ruler generated a mark outside material stock')

    ruler.CFrame += Vector3.new(0, 4, 0)
    assert(not Layout.rulerGuide(work, ruler, contact),
        'Ruler should not guide scoring when lifted far from metal')

    ruler:Destroy()
    work:Destroy()
    return true, 'ruler-guided metal layout, rotated placement and off-surface rejection passed'
end

return Regression
