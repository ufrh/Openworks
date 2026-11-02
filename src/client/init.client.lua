local ReplicatedStorage = game:GetService('ReplicatedStorage')

local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Boolean = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Boolean'))
local Renderer = require(script:WaitForChild('FORMRenderer'))
local Surface = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Surface'))

local stock = FORM.box(Vector3.new(100, 50, 20))
local tool = FORM.cylinder(10, 70, 12)
local pieces, removed = Boolean.subtract(stock, tool)
assert(pieces, '[FORM] Subtraction preview failed: ' .. tostring(removed))

local boundary, stats = Surface.extract(pieces)
print(string.format('[FORM] Surface pass: %d internal triangles hidden; %d partial-overlap candidates', stats.discarded, stats.uncertain))

local success, result = pcall(function()
    local part = Renderer.create(boundary, 0.04, 30)
    part.Name = 'FORM Drilled Workpiece'
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Metal
    part.Color = Color3.fromRGB(78, 156, 120)
    part.CFrame = CFrame.new(0, 7, -12)
    part.Parent = workspace
end)

if not success then
    warn('[FORM] Combined drilled preview failed: ' .. tostring(result))
end

print(string.format('[FORM] Drilled hole removed %.4f mm^3 across %d internal solids', removed, #pieces))
print('[FORM] Single-mesh surface preview; not yet watertight or unified canonical topology')
