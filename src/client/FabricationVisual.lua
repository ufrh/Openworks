local ReplicatedStorage = game:GetService('ReplicatedStorage')

local FabricationVisual = {}
FabricationVisual.__index = FabricationVisual

local function source(name)
    local direct = ReplicatedStorage:FindFirstChild(name)
    if direct and (direct:IsA('Model') or direct:IsA('BasePart')) then return direct end
    for _, item in ReplicatedStorage:GetDescendants() do
        if item.Name == name and (item:IsA('Model') or item:IsA('BasePart'))
            and not item:FindFirstAncestorOfClass('Tool') then
            return item
        end
    end
    return nil
end

local function modelParts(root)
    if root:IsA('BasePart') then return {root} end
    local parts = {}
    for _, item in root:GetDescendants() do
        if item:IsA('BasePart') then parts[#parts + 1] = item end
    end
    return parts
end

local function findMarker(root, name)
    local marker = root:FindFirstChild(name, true)
    return if marker and marker:IsA('Attachment') then marker else nil
end

function FabricationVisual.available(name)
    return source(name) ~= nil
end

function FabricationVisual.new(name, markerName)
    local asset = source(name)
    if not asset then return nil, 'Missing ' .. name .. ' Model in ReplicatedStorage' end
    local model = asset:Clone()
    model.Name = name .. ' - Working Model'
    local parts = modelParts(model)
    if #parts == 0 then
        model:Destroy()
        return nil, name .. ' Model has no BaseParts'
    end

    local pivot = model:GetPivot()
    local marker = findMarker(model, markerName)
    local anchor
    if marker then
        anchor = marker.WorldCFrame
    elseif model:IsA('Model') then
        local bounds, size = model:GetBoundingBox()
        anchor = bounds * CFrame.new(0, -size.Y / 2, 0)
    else
        anchor = model.CFrame * CFrame.new(0, -model.Size.Y / 2, 0)
    end

    for _, part in parts do
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
    end

    return setmetatable({
        model = model,
        name = name,
        offset = anchor:ToObjectSpace(pivot),
        visible = false,
        hasMarker = marker ~= nil,
    }, FabricationVisual)
end

function FabricationVisual:pose(contactFrame)
    if not self.model then return end
    if not self.visible then
        self.model.Parent = workspace
        self.visible = true
    end
    self.model:PivotTo(contactFrame * self.offset)
end

function FabricationVisual:hide()
    if not self.model then return end
    self.model.Parent = nil
    self.visible = false
end

function FabricationVisual:destroy()
    if self.model then self.model:Destroy() end
    self.model = nil
    self.visible = false
end

function FabricationVisual.contactFrame(position, forward, outward)
    local up = outward.Unit
    local right = (forward - up * forward:Dot(up)).Unit
    local back = right:Cross(up).Unit
    return CFrame.fromMatrix(position, right, up, back)
end

return FabricationVisual
