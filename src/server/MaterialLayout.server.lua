local RunService = game:GetService('RunService')

if not RunService:IsStudio() then return end

task.defer(function()
    if workspace:GetAttribute('EnableBlueprintKit') == true then return end

    local bench = workspace:WaitForChild('Workbench', 20)
    if not bench then return end
    local surface
    for _, node in bench:GetDescendants() do
        if node:IsA('BasePart') and node.Name:lower() == 'surface'
            and (not surface or node.Size.X * node.Size.Z > surface.Size.X * surface.Size.Z) then
            surface = node
        end
    end
    if not surface then return end

    for _, node in workspace:GetDescendants() do
        if node:IsA('BasePart') and node:GetAttribute('DraftingKind') == 'Ruler' then
            return
        end
    end

    local width = math.min(4.2, surface.Size.X * 0.65)
    if width < 1.4 then return end

    local ruler = Instance.new('Part')
    ruler.Name = 'Layout Ruler'
    ruler.Size = Vector3.new(width, 0.13, 0.36)
    ruler.Color = Color3.fromRGB(246, 185, 69)
    ruler.Material = Enum.Material.Metal
    ruler.Anchored = false
    ruler.CanCollide = true
    ruler.CanTouch = true
    ruler.CanQuery = true
    ruler.TopSurface = Enum.SurfaceType.Smooth
    ruler.BottomSurface = Enum.SurfaceType.Smooth
    ruler.CFrame = surface.CFrame * CFrame.new(
        surface.Size.X * 0.23,
        surface.Size.Y * 0.5 + ruler.Size.Y * 0.5 + 0.085,
        -surface.Size.Z * 0.29)
    ruler:SetAttribute('isTool', true)
    ruler:SetAttribute('DraftingKind', 'Ruler')
    ruler.Parent = workspace

    local function mark(name, size, offset, color)
        local part = Instance.new('Part')
        part.Name = name
        part.Size = size
        part.CFrame = ruler.CFrame * CFrame.new(offset)
        part.Color = color
        part.Material = Enum.Material.SmoothPlastic
        part.Anchored = false
        part.Massless = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CastShadow = false
        part.Parent = ruler

        local joint = Instance.new('WeldConstraint')
        joint.Part0 = ruler
        joint.Part1 = part
        joint.Parent = part
    end

    local top = ruler.Size.Y * 0.5 + 0.007
    local dark = Color3.fromRGB(38, 43, 47)
    for _, side in {-1, 1} do
        mark('RulerEdge_' .. side,
            Vector3.new(width, 0.014, 0.022),
            Vector3.new(0, top, side * (ruler.Size.Z * 0.5 - 0.019)), dark)
    end
    local count = math.floor((width * 0.5 - 0.07) / 0.2)
    for n = -count, count do
        local length = if n % 5 == 0 then 0.17
            elseif n % 2 == 0 then 0.11 else 0.065
        mark('MillimeterTick_' .. n,
            Vector3.new(if n % 5 == 0 then 0.018 else 0.011, 0.012, length),
            Vector3.new(n * 0.2, top + 0.002,
                -ruler.Size.Z * 0.24 + length * 0.5), dark)
    end

    print('[OPENWORKS:Layout] Physical metal-layout ruler spawned on workbench')
end)
