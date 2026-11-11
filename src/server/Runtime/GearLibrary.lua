--!strict
-- Separate mechanical transmission primitives (not electrical components).
-- Non-CSG, reproducible gear tooth geometry with one shared tooth module.
-- Templates are registered once on the server so the existing Build
-- catalog, placement, history, and component grouping can use them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GearLibrary = {}
local LIBRARY = "OPENWORKS_PrimitiveLibrary_DRAFT"
local MODULE = 0.25 -- stud circular tooth pitch; same for all sizes
local THICKNESS = 0.3
local TOOTH_DEPTH = 0.11
-- Embed each tooth deeper into the body while preserving its outer tip.
local TOOTH_EMBED = 0.045
local TEETH = { 12, 20, 32 }

local function solid(name, parent, size, cf, color)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = cf
    p.Material = Enum.Material.Metal
    p.Color = color
    p.Anchored = true
    p.CanCollide = true
    p.CanQuery = true
    p.CanTouch = false
    p.CastShadow = true
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Parent = parent
    return p
end

function GearLibrary.Ensure()
    local library = ReplicatedStorage:FindFirstChild(LIBRARY)
    if not library then
        library = Instance.new("Folder")
        library.Name = LIBRARY
        library.Parent = ReplicatedStorage
    end
    local transmission = library:FindFirstChild("Transmission")
    if not transmission then
        transmission = Instance.new("Folder")
        transmission.Name = "Transmission"
        transmission.Parent = library
    end

    for _, count in ipairs(TEETH) do
        local name = "Gear_" .. count .. "T"
        -- All stock gears must accept the standard 0.375-stud minimum
        -- cylindrical shaft. The old 12-tooth bore was only 0.28 studs
        -- across, making a valid gear mount physically impossible.
        local existing=transmission:FindFirstChild(name)
        local pitchRadius = MODULE * count / (2 * math.pi)
        local bodyRadius = pitchRadius - TOOTH_DEPTH * 0.42
        local boreRadius = math.max(0.215, bodyRadius * 0.33)
        if existing then
            local oldRadius=existing:GetAttribute("BoreRadiusStuds")
            if type(oldRadius)=="number"
                and oldRadius>=boreRadius-0.0001 then
                continue
            end
            -- An outdated existing gear must be rebuilt: changing the
            -- radius attribute alone would misrepresent its solid rim.
            existing:Destroy()
        end
        local model = Instance.new("Model")
        model.Name = name
        model:SetAttribute("PrimitiveFamily", "Gear")
        model:SetAttribute("ResizeMode", "None")
        model:SetAttribute("GearTeeth", count)
        model:SetAttribute("GearModuleStuds", MODULE)
        model:SetAttribute("PitchRadiusStuds", pitchRadius)
        model:SetAttribute("BoreRadiusStuds", boreRadius)
        model:SetAttribute("AxialAxis", "X")
        local steel = Color3.fromRGB(88, 100, 111)

        -- Invisible noncolliding pivot. All ACTUAL geometry is outside
        -- the open bore; it must not prevent placing a shaft through it.
        local pivot = solid("Geometry", model,
            Vector3.new(THICKNESS, bodyRadius*2, bodyRadius*2),
            CFrame.identity, steel)
        pivot.Shape = Enum.PartType.Cylinder
        pivot.Transparency = 1
        pivot.CanCollide = false
        pivot.CanQuery = false
        pivot.CastShadow = false
        pivot:SetAttribute("GearPivotOnly",true)
        model.PrimaryPart = pivot

        -- Faceted annulus with a genuine empty central opening. Non-CSG
        -- segments remain native physical parts and weld at simulation.
        local segments = math.max(24, count * 2)
        local rimCenter = (bodyRadius + boreRadius) / 2
        local rimWidth = bodyRadius - boreRadius
        for index = 0, segments - 1 do
            local angle = (index + 0.5) * (2*math.pi/segments)
            local radial = Vector3.new(0, math.cos(angle), math.sin(angle))
            local tangent = Vector3.xAxis:Cross(radial)
            local point = radial * rimCenter
            local cf = CFrame.fromMatrix(point, Vector3.xAxis, radial, tangent)
            solid("Rim_"..tostring(index+1),model,
                Vector3.new(THICKNESS,rimWidth * 0.99,
                    2*math.pi*rimCenter/segments * 1.04), cf, steel)
        end

        for index = 0, count - 1 do
            local angle = (index + 0.5) * 2 * math.pi / count
            local radial = Vector3.new(0, math.cos(angle), math.sin(angle))
            local tangential = Vector3.xAxis:Cross(radial)
            -- Tooth roots overlap the gear body by about 0.052 studs,
            -- while the outer tips and gear pitch remain unchanged.
            local position = radial *
                (pitchRadius + TOOTH_DEPTH * 0.02 - TOOTH_EMBED * 0.5)
            local cf = CFrame.fromMatrix(position, Vector3.xAxis, radial, tangential)
            solid("Tooth_" .. tostring(index + 1), model,
                Vector3.new(THICKNESS, TOOTH_DEPTH + TOOTH_EMBED,
                    MODULE * 0.51), cf, steel)
        end

        model.Parent = transmission
    end
end

return GearLibrary
