local ReplicatedStorage = game:GetService('ReplicatedStorage')

local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Cut = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Cut'))
local Renderer = require(script:WaitForChild('FORMRenderer'))

local stock = FORM.box(Vector3.new(100, 50, 20))
local positive, negative = Cut.split(stock, Vector3.zero, Vector3.new(1, 0.4, 0.7))
assert(positive and negative, '[FORM] Preview cut failed: ' .. tostring(negative))

for index, solid in {positive, negative} do
    local success, result = pcall(function()
        local part = Renderer.create(solid, 0.04)
        part.Name = 'FORM Cut ' .. index
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Metal
        part.Color = if index == 1 then Color3.fromRGB(78, 156, 120) else Color3.fromRGB(183, 155, 95)
        part.CFrame = CFrame.new(0, 7, -12) * CFrame.new((if index == 1 then 1 else -1) * 1.5, 0, 0)
        part.Parent = workspace
    end)

    if not success then
        warn('[FORM] Cut preview failed: ' .. tostring(result))
    end
end

print('[FORM] Split volumes:', FORM.signedVolume(positive), FORM.signedVolume(negative), 'mm^3')
