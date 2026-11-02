local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')

local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Cut = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Cut'))
local Renderer = require(script:WaitForChild('FORMRenderer'))

local stock = FORM.box(Vector3.new(100, 50, 20))
local first, remainder = Cut.split(stock, Vector3.zero, Vector3.xAxis)
assert(first and remainder, '[FORM] First preview cut failed: ' .. tostring(remainder))

local second, third = Cut.split(first, Vector3.new(0, 7, 0), Vector3.yAxis)
assert(second and third, '[FORM] Second preview cut failed: ' .. tostring(third))

local colors = {
    Color3.fromRGB(78, 156, 120),
    Color3.fromRGB(183, 155, 95),
    Color3.fromRGB(126, 145, 193),
}
local pieces = {remainder, second, third}

local rendered = {}
local separation = 1.5
local basePosition = Vector3.new(0, 7, -12)

local function arrange()
    for index, part in rendered do
        part.CFrame = CFrame.new(basePosition + Vector3.new((index - 2) * separation, 0, 0))
    end
end

for index, solid in pieces do
    local success, result = pcall(function()
        local part = Renderer.create(solid, 0.04, 30)
        part.Name = 'FORM Sequential Cut ' .. index
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Metal
        part.Color = colors[index]
        rendered[index] = part
        part.Parent = workspace
    end)

    if not success then
        warn('[FORM] Piece ' .. index .. ' preview failed: ' .. tostring(result))
    end
end

local total = 0
for _, solid in pieces do
    total += FORM.signedVolume(solid)
end
print('[FORM] Three-piece preview volume:', total, 'mm^3')

arrange()

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
