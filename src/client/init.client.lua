local ReplicatedStorage = game:GetService('ReplicatedStorage')

local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Boolean = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Boolean'))
local Renderer = require(script:WaitForChild('FORMRenderer'))
local Union = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Union'))

local stock = FORM.box(Vector3.new(100, 50, 20))
local tool = FORM.cylinder(7, 70, 12)
local pieces, removed = Boolean.subtract(stock, tool)
assert(pieces, '[FORM] Subtraction preview failed: ' .. tostring(removed))

local complete, unified, reason, stats = pcall(Union.reconstruct, pieces)
if not complete then
    warn('[FORM] Unified surface error: ' .. tostring(unified))
elseif not unified then
    warn('[FORM] Unified surface rejected: ' .. tostring(reason))
else
    print(string.format('[FORM] Unified solid: %d triangles, %d components, Euler=%d',
        stats.weld.trianglesAfter, stats.weld.connectedComponents, stats.weld.eulerCharacteristic))
end

local verified = complete and unified ~= nil and stats.weld.connectedComponents == 1
    and stats.weld.eulerCharacteristic == 0

local success, result = pcall(function()
    local part = if verified then Renderer.create(unified, 0.04, 30)
        else Renderer.createMany(pieces, 0.04, 30)
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
print(if verified then '[FORM] Rendering validated unified topology'
    else '[FORM] Rendering complete convex-piece fallback; unified topology not validated')
