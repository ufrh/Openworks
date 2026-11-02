local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FabricationVisual = require(script.Parent.FabricationVisual)

local FabricationTool = {}
local appearances = setmetatable({}, {__mode = 'k'})

function FabricationTool.find(player, name)
    local character = player.Character
    local tool = character and character:FindFirstChild(name)
    if tool and tool:IsA('Tool') then return tool end

    local backpack = player:FindFirstChildOfClass('Backpack')
    tool = backpack and backpack:FindFirstChild(name)
    if tool and tool:IsA('Tool') then return tool end

    if not backpack then return nil, 'Backpack unavailable' end
    for _, asset in ReplicatedStorage:GetDescendants() do
        if asset:IsA('Tool') and asset.Name == name then
            tool = asset:Clone()
            if tool.RequiresHandle and not tool:FindFirstChild('Handle') then
                tool.RequiresHandle = false
            end
            tool.Parent = backpack
            return tool
        end
    end

    if FabricationVisual.available(name) then
        tool = Instance.new('Tool')
        tool.Name = name
        tool.RequiresHandle = false
        tool.CanBeDropped = false
        tool.ToolTip = 'OPENWORKS fabrication: ' .. name
        tool.Parent = backpack
        return tool
    end
    return nil, 'Missing ' .. name .. ' Tool or ReplicatedStorage model'
end

function FabricationTool.hideEquipped(tool)
    if appearances[tool] then return end
    local originals = {}
    for _, child in tool:GetDescendants() do
        if child:IsA('BasePart') then
            originals[child] = child.LocalTransparencyModifier
            child.LocalTransparencyModifier = 1
        end
    end
    appearances[tool] = originals
end

function FabricationTool.restore(tool)
    local originals = appearances[tool]
    if not originals then return end
    for part, opacity in originals do
        if part.Parent then part.LocalTransparencyModifier = opacity end
    end
    appearances[tool] = nil
end

return FabricationTool
