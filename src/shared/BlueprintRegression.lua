local Blueprint = require(script.Parent.BlueprintGeometry)

local Regression = {}

function Regression.run()
    local sheet = Instance.new('Part')
    sheet.Size = Vector3.new(5, 0.06, 3.5)
    sheet.CFrame = CFrame.new(0, 10, 0)
    sheet:SetAttribute('isBlueprint', true)
    Blueprint.decorate(sheet)
    local grid = sheet:FindFirstChild('BlueprintPaperDetail')
    assert(grid and #grid:GetChildren() > 35,
        'Physical paper grid and title block were not created')
    local gridCount = #grid:GetChildren()

    local ruler = Instance.new('Part')
    ruler.Size = Vector3.new(3, 0.075, 0.21)
    ruler.CFrame = sheet.CFrame * CFrame.new(0, 0.12, 0)
    ruler:SetAttribute('DraftingKind', 'Ruler')
    ruler:SetAttribute('OnWorkbench', true)

    local start = Vector2.new(-15, 3.5)
    local finish = Vector2.new(20, 5)
    local guide = Blueprint.rulerGuide(sheet, ruler, start)
    assert(guide, 'Physical ruler failed to constrain a nearby pencil stroke')
    local a = Blueprint.snap(guide, start)
    local b = Blueprint.snap(guide, finish)
    assert(math.abs(a.Y - b.Y) < 0.01,
        'The ruler did not create a straight geometric line')
    assert(Blueprint.inside(sheet, a) and Blueprint.inside(sheet, b),
        'Ruler projected marks outside of the drawing sheet')

    assert(Blueprint.append(sheet, a, b), 'Ruler line was not saved')
    local saved = Blueprint.read(sheet)
    assert(#saved == 1 and saved[1].kind == 'Line',
        'Saved blueprint line could not be decoded')
    assert(sheet:FindFirstChild('BlueprintInk')
        and #sheet.BlueprintInk:GetChildren() == 1,
        'Physical ink line was not welded to the sheet')

    local miss = Vector2.new(0, 30)
    assert(not Blueprint.rulerGuide(sheet, ruler, miss),
        'Ruler incorrectly snapped a distant pencil stroke')
    assert(Blueprint.erase(sheet, (a + b) * 0.5),
        'The eraser did not remove the selected physical line')
    assert(#Blueprint.read(sheet) == 0
        and #sheet.BlueprintInk:GetChildren() == 0,
        'Erasing left phantom ink on the blueprint')
    assert(sheet:FindFirstChild('BlueprintPaperDetail') == grid
        and #grid:GetChildren() == gridCount,
        'Grid was duplicated or erased when the drawing changed')

    ruler:Destroy()
    sheet:Destroy()
    return true, 'Physical paper, ruler constraint, saved ink and eraser passed'
end

return Regression
