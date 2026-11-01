local ReplicatedStorage = game:GetService('ReplicatedStorage')

local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Renderer = require(script:WaitForChild('FORMRenderer'))

local workpiece = FORM.box(Vector3.new(100, 50, 20))
local validation = FORM.validate(workpiece)
assert(validation.ok, '[FORM] Preview solid failed validation')

local success, result = pcall(function()
    local part = Renderer.create(workpiece, 0.04)
    part.Name = 'FORM Preview - 100x50x20 mm'
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Metal
    part.Color = Color3.fromRGB(78, 156, 120)
    part.CFrame = CFrame.new(0, 7, -12)
    part.Parent = workspace
    return part
end)

if success then
    print('[FORM] Mesh rendered | Volume:', FORM.signedVolume(workpiece), 'mm^3')
else
    warn('[FORM] Mesh preview unavailable: ' .. tostring(result))
    warn('[FORM] Check EditableMesh permissions in Creator Dashboard and Studio output.')
end
