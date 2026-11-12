--!strict
-- Separate mechanical transmission primitives (not electrical components).
-- Precompiled bevel CSG solids, plus reproducible native spur/rack geometry.
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

-- Matched straight-bevel transmission gears. The old v2 prefabs were
-- three STACKED rings plus two rows of box teeth. Bevel v3 uses a sloped
-- radial body and teeth IN THE SAME CONICAL SURFACE, then precompiles the
-- entire solid to ONE PartOperation via CSG. The central shaft bore is
-- SUBTRACTED after the union and remains physically open.
--
-- This is a straight-tooth geometric approximation (not involute teeth).
-- Its pitch cone / shaft crossing angles still drive GearMath meshing.
local GeometryService=game:GetService("GeometryService")

local function bevelTemplate(transmission,count,shaftAngleDeg)
    local kind="Bevel"..tostring(shaftAngleDeg)
    local name=kind.."_"..count.."T"
    local old=transmission:FindFirstChild(name)
    if old and old:IsA("Model")
        and old:GetAttribute("GearKind")==kind
        and old:GetAttribute("GeometryVersion")==3
        and old:FindFirstChild("BevelSolid") then return end

    local pitchRadius=MODULE*count/(2*math.pi)
    local halfCone=math.rad(shaftAngleDeg*0.5)
    local boreRadius=0.215
    local steel=Color3.fromRGB(105,120,135)
    local model=Instance.new("Model")
    model.Name=name
    model:SetAttribute("PrimitiveFamily","Gear")
    model:SetAttribute("ResizeMode","None")
    model:SetAttribute("GearKind",kind)
    model:SetAttribute("GearTeeth",count)
    model:SetAttribute("GearModuleStuds",MODULE)
    model:SetAttribute("PitchRadiusStuds",pitchRadius)
    model:SetAttribute("BoreRadiusStuds",boreRadius)
    model:SetAttribute("BevelConeDeg",shaftAngleDeg*0.5)
    model:SetAttribute("BevelShaftAngleDeg",shaftAngleDeg)
    model:SetAttribute("AxialAxis","X")

    -- Keep the established centered axle origin for snapping, hub fitting,
    -- GearKinematics and old saves. This is NOT a visible/collidable solid.
    local pivot=solid("Geometry",model,
        Vector3.new(THICKNESS,pitchRadius*2,pitchRadius*2),
        CFrame.identity,steel)
    pivot.Shape=Enum.PartType.Cylinder
    pivot.Transparency=1
    pivot.CanCollide=false
    pivot.CanQuery=false
    pivot.CastShadow=false
    pivot:SetAttribute("GearPivotOnly",true)
    model.PrimaryPart=pivot

    -- Scratch input parts are never placed in Workspace or duplicated by
    -- Build. Only the final precompiled, one-piece geometry is registered.
    local scratch=Instance.new("Model")
    scratch.Name=name.."_CSGInputs"

    -- Every rib uses a single sloped basis (instead of several axial
    -- layers). Along local X, radial position changes by tan(cone)*X.
    -- Their overlapping tangent widths approximate the faceted conical
    -- annulus; every tooth penetrates its root, producing one CSG body.
    local tanCone=math.tan(halfCone)
    local cosCone=math.cos(halfCone)
    local rootRadius=pitchRadius-0.048
    local innerRadius=boreRadius+0.018
    local hubRadius=boreRadius+0.092
    local hub=solid("InnerHub",scratch,
        Vector3.new(THICKNESS*0.88,hubRadius*2,hubRadius*2),
        CFrame.identity,steel)
    hub.Shape=Enum.PartType.Cylinder
    local additions={}
    local function rib(name,angle,radiusInside,radiusOutside,width,axialLength)
        local radial=Vector3.new(0,math.cos(angle),math.sin(angle))
        local tangent=Vector3.xAxis:Cross(radial)
        local axis=(Vector3.xAxis+radial*tanCone).Unit
        local normal=(radial-Vector3.xAxis*tanCone).Unit
        local center=radial*((radiusInside+radiusOutside)*0.5)
        local beam=solid(name,scratch,
            Vector3.new(axialLength/cosCone,
                (radiusOutside-radiusInside)*cosCone,width),
            CFrame.fromMatrix(center,axis,normal,tangent),steel)
        table.insert(additions,beam)
    end
    -- Dense adjacent root ribs give one continuous sloped cone body,
    -- rather than three rows of flat tooth/disc shapes.
    local segments=math.max(36,count*2)
    for index=0,segments-1 do
        local angle=(index+0.5)*2*math.pi/segments
        rib("ConicalRoot_"..(index+1),angle,
            innerRadius,rootRadius,
            (2*math.pi*rootRadius/segments)*1.22,
            THICKNESS+0.012)
    end
    -- Each straight bevel tooth is a single inclined radial tooth across
    -- the entire face width, tapering radially with the pitch cone. All
    -- roots intersect the continuous sloping body for a true single union.
    for index=0,count-1 do
        local angle=(index+0.5)*2*math.pi/count
        rib("ConicalTooth_"..(index+1),angle,
            rootRadius-TOOTH_EMBED-0.012,
            pitchRadius+TOOTH_DEPTH*0.58,
            MODULE*0.52,THICKNESS-0.016)
    end

    local options={
        CollisionFidelity=Enum.CollisionFidelity.PreciseConvexDecomposition,
        SplitApart=false,
    }
    local ok,unions=pcall(function()
        return GeometryService:UnionAsync(hub,additions,options)
    end)
    if not ok or type(unions)~="table" or #unions~=1
        or not unions[1]:IsA("BasePart") then
        if ok and type(unions)=="table" then
            for _,piece in ipairs(unions) do piece:Destroy() end
        end
        warn("[OPENWORKS] Unified bevel gear CSG union failed for "
            ..name..": "..tostring(if ok then "expected one solid" else unions))
        scratch:Destroy()
        model:Destroy()
        return
    end

    -- Roblox cylinder axes are local X, matching both the gear's shaft
    -- and the invisible PrimaryPart. Use a cutter that crosses the entire
    -- widened tapered solid; no invisible disk blocks the center.
    local union=unions[1]
    local cutter=solid("ShaftBoreCutter",scratch,
        Vector3.new(THICKNESS*4,boreRadius*2,boreRadius*2),
        CFrame.identity,steel)
    cutter.Shape=Enum.PartType.Cylinder
    local drilled,solids=pcall(function()
        return GeometryService:SubtractAsync(union,{cutter},options)
    end)
    union:Destroy()
    scratch:Destroy()
    if not drilled or type(solids)~="table" or #solids~=1
        or not solids[1]:IsA("BasePart") then
        if drilled and type(solids)=="table" then
            for _,piece in ipairs(solids) do piece:Destroy() end
        end
        warn("[OPENWORKS] Could not drill bevel shaft bore for "
            ..name..": "..tostring(if drilled then "expected one solid" else solids))
        model:Destroy()
        return
    end

    local geometry=solids[1]
    geometry.Name="BevelSolid"
    geometry.Anchored=true
    geometry.CanCollide=true
    geometry.CanQuery=true
    geometry.CanTouch=false
    geometry.Material=Enum.Material.Metal
    geometry.Color=steel
    geometry.CastShadow=true
    if geometry:IsA("PartOperation") then geometry.UsePartColor=true end
    geometry.Parent=model
    model:SetAttribute("GeometryVersion",3)
    model:SetAttribute("UnifiedBevelSolid",true)
    -- Atomic replacement: never destroy an existing/older prefab until its
    -- replacement has successfully unioned and acquired a through-bore.
    if old then old:Destroy() end
    model.Parent=transmission
end

-- A rack is a toothed translating bar, not a gear with an infinite
-- radius. Its local +Y face contains teeth at a 0.25-stud linear pitch.
-- The pitch line is 0.20 studs above the bar's centered PrimaryPart.
local function rackTemplate(transmission,length)
    local name="Rack_"..length.."Stud"
    local old=transmission:FindFirstChild(name)
    if old then
        if old:GetAttribute("GearKind")=="Rack"
            and old:GetAttribute("GeometryVersion")==2 then return end
        old:Destroy()
    end
    local model=Instance.new("Model")
    model.Name=name
    model:SetAttribute("PrimitiveFamily","Rack")
    model:SetAttribute("GearKind","Rack")
    model:SetAttribute("ResizeMode","None")
    model:SetAttribute("RackPitchStuds",MODULE)
    model:SetAttribute("RackLengthStuds",length)
    model:SetAttribute("RackPitchOffsetStuds",0.20)
    model:SetAttribute("RackAxis","Z")
    model:SetAttribute("GeometryVersion",2)
    local steel=Color3.fromRGB(125,136,146)
    local body=solid("Geometry",model,
        Vector3.new(0.35,0.22,length),CFrame.identity,steel)
    model.PrimaryPart=body
    local teeth=math.floor(length/MODULE)
    for j=0,teeth-1 do
        local z=(j+0.5)*MODULE-length*0.5
        local pos=Vector3.new(0,0.175,z)
        solid("RackTooth_"..(j+1),model,
            Vector3.new(0.34,0.16,MODULE*0.53),
            CFrame.new(pos),steel)
    end
    model.Parent=transmission
end

-- A separate grounded stationary carriage supports the rack with an
-- explicit sliding lane. The rack is not secretly welded to this model.
-- Guides are sized so a rack has four studs of actual travel.
local function rackGuideTemplate(transmission,length)
    local name="RackGuide_"..length.."Stud"
    local old=transmission:FindFirstChild(name)
    if old then
        if old:GetAttribute("RackGuideLengthStuds")==length
            and old:GetAttribute("GeometryVersion")==2 then return end
        old:Destroy()
    end
    local model=Instance.new("Model")
    model.Name=name
    model:SetAttribute("PrimitiveFamily","RackGuide")
    model:SetAttribute("ResizeMode","None")
    model:SetAttribute("RackGuideLengthStuds",length)
    model:SetAttribute("GearKind","RackGuide")
    model:SetAttribute("GeometryVersion",2)
    local steel=Color3.fromRGB(76,92,105)
    -- The noncolliding primary represents the rack's centered travel
    -- reference, allowing all guide geometry to stay below/alongside it.
    local pivot=solid("Geometry",model,
        Vector3.new(0.42,0.22,length),
        CFrame.identity,steel)
    pivot.Transparency=1
    pivot.CanCollide=false
    pivot.CanQuery=false
    pivot.CastShadow=false
    pivot:SetAttribute("GearPivotOnly",true)
    model.PrimaryPart=pivot
    solid("Base",model,Vector3.new(0.53,0.09,length),
        CFrame.new(0,-0.235,0),steel)
    for _,side in ipairs({-1,1}) do
        solid("GuideSide_"..side,model,
            Vector3.new(0.085,0.31,length),
            CFrame.new(side*0.265,-0.045,0),steel)
    end
    model.Parent=transmission
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

    -- Matched, equal-tooth pairs for 45° and 90° shafts.
    -- Non-1:1 bevel ratios need intentionally different cone angles.
    for _,angle in ipairs({45,90}) do
        for _,count in ipairs({12,20}) do
            bevelTemplate(transmission,count,angle)
        end
    end
    for _,length in ipairs({4,8}) do
        rackTemplate(transmission,length)
    end
    for _,length in ipairs({8,12}) do
        rackGuideTemplate(transmission,length)
    end
end

return GearLibrary
