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
    else
        local blade
        if name == 'Hacksaw' then
            for _, item in model:GetDescendants() do
                if item:IsA('BasePart') and (item.Name == 'Blade' or item.Name == 'SawBlade'
                    or item.Name == 'BladePart') then
                    blade = item
                    break
                end
            end
        end
        local bounds, size
        if blade then
            bounds, size = blade.CFrame, blade.Size
        elseif model:IsA('Model') then
            bounds, size = model:GetBoundingBox()
        else
            bounds, size = model.CFrame, model.Size
        end
        local rotation = CFrame.identity
        if size.Z > math.max(size.X, size.Y) * 1.12 then
            rotation = CFrame.Angles(0, math.rad(-90), 0)
        elseif size.Y > math.max(size.X, size.Z) * 1.12 then
            rotation = CFrame.Angles(0, 0, math.rad(90))
        end
        anchor = bounds * CFrame.new(0, -size.Y / 2, 0) * rotation
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
