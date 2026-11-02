local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')

local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Boolean = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Boolean'))
local Renderer = require(script:WaitForChild('FORMRenderer'))

local stock = FORM.box(Vector3.new(100, 50, 20))
local tool = FORM.cylinder(10, 30, 12)
local pieces, removed = Boolean.subtract(stock, tool)
assert(pieces, '[FORM] Subtraction preview failed: ' .. tostring(removed))

local rendered = {}
local offsets = {}
local separation = 0
local basePosition = Vector3.new(0, 7, -12)

local function arrange()
    for index, part in rendered do
        part.CFrame = CFrame.new(basePosition + offsets[index] * separation)
    end
end

for index, solid in pieces do
    local success, result = pcall(function()
        local part = Renderer.create(solid, 0.04, 30)
        part.Name = 'FORM Drilled Piece ' .. index
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Metal
        part.Color = Color3.fromRGB(78, 156, 120)

        local low, high = FORM.bounds(solid)
        local center = (low + high) / 2
        offsets[index] = if center.Magnitude > 0 then center.Unit else Vector3.xAxis
        rendered[index] = part
        part.Parent = workspace
    end)

    if not success then
        warn('[FORM] Piece ' .. index .. ' preview failed: ' .. tostring(result))
    end
end

arrange()
print(string.format('[FORM] Drilled hole removed %.4f mm^3 across %d pieces', removed, #pieces))

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.LeftBracket then
        separation = math.max(0, separation - 0.5)
    elseif input.KeyCode == Enum.KeyCode.RightBracket then
        separation = math.min(20, separation + 0.5)
    elseif input.KeyCode == Enum.KeyCode.Zero then
        separation = 0
    else
        return
    end

    arrange()
    print(string.format('[FORM] Exploded view separation: %.1f studs', separation))
end)

print('[FORM] Preview controls: [ less separation | ] more separation | 0 fitted')
