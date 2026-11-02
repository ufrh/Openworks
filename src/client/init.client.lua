local ReplicatedStorage = game:GetService('ReplicatedStorage')

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

for index, solid in pieces do
    local success, result = pcall(function()
        local part = Renderer.create(solid, 0.04, 30)
        part.Name = 'FORM Sequential Cut ' .. index
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Metal
        part.Color = colors[index]
        part.CFrame = CFrame.new((index - 2) * 5, 7, -12)
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
