local ReplicatedStorage = game:GetService('ReplicatedStorage')

local ToolVisual = {}

local function sourceModel(name)
    for _, asset in ReplicatedStorage:GetDescendants() do
        if asset.Name == name and (asset:IsA('Model') or asset:IsA('BasePart')) then
            return asset
        end
    end
    return nil
end

function ToolVisual.attach(tool)
    if tool:GetAttribute('OpenworksVisualAttached') then return true end

    local source = sourceModel(tool.Name)
    local handle = tool:FindFirstChild('Handle')
    if not source then
        return handle ~= nil or not tool.RequiresHandle
    end

    local root = source:Clone()
    root.Name = 'OpenworksVisual'
    local visualParts = {}
    if root:IsA('BasePart') then
        visualParts[1] = root
    else
        for _, instance in root:GetDescendants() do
            if instance:IsA('BasePart') then visualParts[#visualParts + 1] = instance end
        end
    end
    if #visualParts == 0 then root:Destroy() return false end

    local origin = if root:IsA('BasePart') then root
        else root:FindFirstChild('Handle', true) or root.PrimaryPart or visualParts[1]
    if not origin:IsA('BasePart') then origin = visualParts[1] end

    if handle and handle:IsA('BasePart') then
        local transform = handle.CFrame * origin.CFrame:Inverse()
        for _, part in visualParts do
            part.CFrame = transform * part.CFrame
        end
    else
        handle = origin
        handle.Name = 'Handle'
    end

    root.Parent = tool
    if handle == origin then
        handle.Parent = tool
    end

    for _, part in visualParts do
        part.Anchored = false
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.Massless = true
        if part ~= handle then
            local weld = Instance.new('WeldConstraint')
            weld.Part0 = handle
            weld.Part1 = part
            weld.Parent = part
        end
    end

    handle.Anchored = false
    handle.CanCollide = false
    tool:SetAttribute('OpenworksVisualAttached', true)
    return true
end

return ToolVisual
