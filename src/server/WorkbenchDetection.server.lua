local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local FORMMaterial = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORMMaterial'))
local workbench = workspace:WaitForChild('Workbench', 10)

if not workbench then
    warn('[OPENWORKS:Workbench] Workspace.Workbench not found')
    return
end

local folderName = 'OpenworksDetectionProxies'
local old = workbench:FindFirstChild(folderName)
if old then
    old:Destroy()
end

local proxies = Instance.new('Folder')
proxies.Name = folderName
proxies.Parent = workbench

local surfaces = {}
for _, descendant in workbench:GetDescendants() do
    if descendant:IsA('BasePart') and descendant.Name:lower() == 'surface' then
        table.insert(surfaces, descendant)
    end
end

local regionHeight = 1.2
local bottomInset = 0.08
local supportThickness = 0.45
local supportTopOffset = 0.015
local regions = {}

local function alignRegion(region)
    local surface = region.surface
    local proxy = region.proxy
    local support = region.support

    proxy.Size = Vector3.new(surface.Size.X, regionHeight, surface.Size.Z)
    proxy.CFrame = surface.CFrame
        * CFrame.new(0, surface.Size.Y * 0.5 + regionHeight * 0.5 - bottomInset, 0)

    support.Size = Vector3.new(surface.Size.X, supportThickness, surface.Size.Z)
    support.CFrame = surface.CFrame
        * CFrame.new(0, surface.Size.Y * 0.5 + supportTopOffset - supportThickness * 0.5, 0)
end

for index, surface in surfaces do
    local proxy = Instance.new('Part')
    proxy.Name = 'SurfaceProxy_' .. index
    proxy.Anchored = true
    proxy.CanCollide = false
    proxy.CanTouch = false
    proxy.CanQuery = false
    proxy.CastShadow = false
    proxy.Transparency = 1
    proxy.Parent = proxies

    local support = Instance.new('Part')
    support.Name = 'SurfaceSupport_' .. index
    support.Anchored = true
    support.CanCollide = true
    support.CanTouch = false
    support.CanQuery = false
    support.CastShadow = false
    support.Transparency = 1
    support.Parent = proxies

    local region = {surface = surface, proxy = proxy, support = support}
    alignRegion(region)
    table.insert(regions, region)
end

if #regions == 0 then
    warn('[OPENWORKS:Workbench] No BaseParts named surface found under Workbench')
end

local params = OverlapParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = {proxies}
params.MaxParts = 0

local detected = {}
local elapsed = 0

local function classify(part)
    local node = part

    while node and node ~= workspace do
        if node:IsA('Model') or node:IsA('BasePart') then
            if node:GetAttribute('isTool') == true then
                return node, 'Tool'
            end

            if FORMMaterial.isMarked(node) then
                return node, 'Material'
            end
        end

        node = node.Parent
    end
end

local function nearSurface(part, surface)
    local upward = surface.CFrame.UpVector
    local center = surface.Position + upward * (surface.Size.Y * 0.5)
    local half = part.Size * 0.5
    local orientation = part.CFrame
    local verticalExtent =
        math.abs(orientation.RightVector:Dot(upward)) * half.X
        + math.abs(orientation.UpVector:Dot(upward)) * half.Y
        + math.abs(orientation.LookVector:Dot(upward)) * half.Z
    local verticalCenter = (part.Position - center):Dot(upward)

    return verticalCenter - verticalExtent <= 0.22
        and verticalCenter + verticalExtent >= -0.08
end

local function scan()
    local current = {}

    for _, region in regions do
        local surface = region.surface
        local proxy = region.proxy

        if not surface.Parent then
            continue
        end

        alignRegion(region)

        for _, part in workspace:GetPartBoundsInBox(proxy.CFrame, proxy.Size, params) do
            local item, kind = classify(part)

            if item and not current[item]
                and part.AssemblyLinearVelocity.Magnitude < 1.5
                and part.AssemblyAngularVelocity.Magnitude < 2
                and nearSurface(part, surface) then
                current[item] = kind
            end
        end
    end

    local toolCount = 0
    local materialCount = 0

    for item, kind in current do
        if detected[item] ~= kind then
            print('[OPENWORKS:Workbench] Detected:', item.Name, kind)
        end

        if kind == 'Tool' then
            toolCount += 1
        else
            materialCount += 1
        end

        item:SetAttribute('OnWorkbench', true)
    end

    for item in detected do
        if not current[item] then
            if item.Parent then
                item:SetAttribute('OnWorkbench', false)
            end
            print('[OPENWORKS:Workbench] Removed:', item.Name)
        end
    end

    detected = current
    workbench:SetAttribute('ToolCount', toolCount)
    workbench:SetAttribute('MaterialCount', materialCount)
end

workbench:SetAttribute('ToolCount', 0)
workbench:SetAttribute('MaterialCount', 0)
print('[OPENWORKS:Workbench] Monitoring', #regions, 'surface regions')

RunService.Heartbeat:Connect(function(dt)
    elapsed += dt
    if elapsed < 0.2 then
        return
    end

    elapsed = 0
    scan()
end)
