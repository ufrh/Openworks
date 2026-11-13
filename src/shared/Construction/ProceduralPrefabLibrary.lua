--!strict
-- OPENWORKS | Procedural, baked mesh stock for gears and bolts.
-- One EditableMesh is used per base profile, baked into DataModel-scoped
-- static Content, then destroyed. MeshPart instances only clone the STATIC
-- Content. Rebuilt by the server on every session; no saved transient mesh IDs.
-- Can also be invoked from the Studio Edit-mode Command Bar to make a gallery.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Prefabs = {}
local LIBRARY_NAME = "OPENWORKS_PrimitiveLibrary_DRAFT"
local GALLERY_NAME = "OPENWORKS_ProceduralPrefabGallery"
local VERSION = 1
local COUNTS = {8, 12, 20, 32}
local SCALES = {0.6, 0.8, 1.0, 1.2, 1.4}
local BOLT_SCALES = {0.5, 0.75, 1.0, 1.25, 1.5}
-- Geometric involute module (pitch diameter / tooth count).
-- The rest of OPENWORKS stores CIRCULAR pitch in GearModuleStuds, so
-- GearModuleStuds = math.pi * this value. Both values are authored below.
local CAD_MODULE = 0.25
local PRESSURE_ANGLE = math.rad(20)
local FACE_WIDTH = 0.60
local BORE_RADIUS = 0.375 -- 0.75 stud base bore; minimum scaled Ø is 0.45.
local BEVEL_SLOPE = 1 -- tan(45° pitch cone); 90° equal-tooth bevel pair.
local FLANK_STEPS = 10
local TIP_STEPS = 5
local ROOT_GAP_STEPS = 4
local ROOT_SHOULDER = math.rad(0.55)
local BOLT_BASE_SHAFT_LENGTH = 2.0
local BOLT_BASE_SHAFT_DIAMETER = 0.25

local installed = false
local installedList = {}
local progress = "Not started"
local lastError = nil

local function stage(message)
    progress = message
    print("[OPENWORKS][PREFABS] " .. message)
end

local function failure(message)
    lastError = message
    warn("[OPENWORKS][PREFABS] " .. message)
end

local function assertFinite(n)
    assert(n == n and math.abs(n) < 1e8, "Non-finite generated coordinate")
end

local function createEditable()
    return assert(AssetService:CreateEditableMesh(),
        "OPENWORKS cannot create EditableMesh. Enable Mesh / Image APIs in Experience Settings > Security.")
end

-- Keep prefab baking on the verified five-gear prototype's Box pipeline.
-- High-detail precise collision decomposition during CreateMeshPartAsync can
-- fail before ANY models are registered. Gear meshing is governed by shaft-
-- centric mathematical relationships, not physical tooth contact, so gear
-- visuals remain noncollidable instead of filling the center bore with a
-- box. Gear collision proxies are a separate future physics acceptance task.
local function bakedPart(mesh, desiredFidelity)
    local bakeOK, bakeStatus, staticContent = pcall(function()
        return AssetService:CreateDataModelContentAsync(Content.fromObject(mesh))
    end)
    if not bakeOK or bakeStatus ~= Enum.CreateContentResult.Success
        or not staticContent then
        mesh:Destroy()
        error("Static mesh bake failed (Mesh / Image APIs must be enabled): "
            .. tostring(bakeStatus))
    end
    local created, part = pcall(function()
        return AssetService:CreateMeshPartAsync(staticContent, {
            CollisionFidelity = Enum.CollisionFidelity.Box,
            RenderFidelity = Enum.RenderFidelity.Precise,
        })
    end)
    mesh:Destroy()
    assert(created and part,
        "Static visual MeshPart creation failed: " .. tostring(part))

    part.Name = "Geometry"
    part.Anchored = true
    part.CanQuery = true
    part.CanTouch = false
    part.CastShadow = true
    part.RenderFidelity = Enum.RenderFidelity.Precise
    part.Material = Enum.Material.Metal
    part.MaterialVariant = ""
    part.Color = Color3.fromRGB(145, 154, 166)

    -- The MeshPart collision geometry must be configured at creation, not by
    -- assigning CollisionFidelity afterward (read-only during gameplay).
    -- Box is safe for a bolt's solid shank/head but NOT for a gear's bore.
    local isGear = desiredFidelity == Enum.CollisionFidelity.PreciseConvexDecomposition
    part.CanCollide = not isGear
    part:SetAttribute("OpenworksCollisionReady", not isGear)
    part:SetAttribute("OpenworksCollisionMode", if isGear then "VisualOnly" else "Box")
    return part
end

local function makeOutline(teeth)
    local pitch = teeth * CAD_MODULE / 2
    local base = pitch * math.cos(PRESSURE_ANGLE)
    local root = pitch - 1.25 * CAD_MODULE
    local tip = pitch + CAD_MODULE
    assert(root > BORE_RADIUS + 0.1,
        "The smallest gear needs a real rim outside its bore")
    local function involute(r)
        if r <= base then return 0 end
        local t = math.sqrt((r / base) ^ 2 - 1)
        return t - math.atan(t)
    end
    local atPitch = involute(pitch)
    local function halfTooth(r)
        return math.pi / (2 * teeth) + atPitch - involute(r)
    end
    local samples = {}
    local step = 2 * math.pi / teeth
    for tooth = 0, teeth - 1 do
        local center = tooth * step
        local rootShoulder = halfTooth(base) + ROOT_SHOULDER
        local tipHalf = halfTooth(tip)
        assert(tipHalf > 0 and rootShoulder * 2 < step,
            "Invalid involute cross-section")
        table.insert(samples, {r = root, a = center - rootShoulder})
        for j = 0, FLANK_STEPS do
            local r = base + (tip - base) * (j / FLANK_STEPS)
            table.insert(samples, {r = r, a = center - halfTooth(r)})
        end
        for j = 1, TIP_STEPS do
            local a = center - tipHalf + 2 * tipHalf * j / TIP_STEPS
            table.insert(samples, {r = tip, a = a})
        end
        for j = FLANK_STEPS - 1, 0, -1 do
            local r = base + (tip - base) * (j / FLANK_STEPS)
            table.insert(samples, {r = r, a = center + halfTooth(r)})
        end
        table.insert(samples, {r = root, a = center + rootShoulder})
        for j = 1, ROOT_GAP_STEPS - 1 do
            local a = center + rootShoulder
                + (step - 2 * rootShoulder) * j / ROOT_GAP_STEPS
            table.insert(samples, {r = root, a = a})
        end
    end
    return samples, pitch, root, tip
end

local function buildGearMesh(teeth, bevel)
    local samples, pitch, root, tip = makeOutline(teeth)
    local mesh = createEditable()
    local rings = {}
    local positions = {}
    local triangleCount = 0

    local function vertex(v)
        assertFinite(v.X); assertFinite(v.Y); assertFinite(v.Z)
        local id = mesh:AddVertex(v)
        positions[id] = v
        return id
    end
    local frontNormal = mesh:AddNormal(Vector3.new(1, 0, 0))
    local backNormal = mesh:AddNormal(Vector3.new(-1, 0, 0))
    local function tri(a, b, c, normal)
        local pa, pb, pc = positions[a], positions[b], positions[c]
        local area = (pb - pa):Cross(pc - pa)
        assert(area.Magnitude > 1e-7, "Degenerate triangle generated")
        local face = mesh:AddTriangle(a, b, c)
        if normal then
            mesh:SetFaceNormals(face, {normal, normal, normal})
        end
        triangleCount += 1
    end
    for i, v in ipairs(samples) do
        local cosine, sine = math.cos(v.a), math.sin(v.a)
        local frontScale = bevel and (1 + FACE_WIDTH * BEVEL_SLOPE / (2 * pitch)) or 1
        local backScale = bevel and (1 - FACE_WIDTH * BEVEL_SLOPE / (2 * pitch)) or 1
        assert(backScale * root > BORE_RADIUS + 0.01,
            "Bevel small-end rim intersects the shaft bore")
        rings[i] = {
            of = vertex(Vector3.new(FACE_WIDTH / 2, v.r * frontScale * cosine,
                v.r * frontScale * sine)),
            ob = vertex(Vector3.new(-FACE_WIDTH / 2, v.r * backScale * cosine,
                v.r * backScale * sine)),
            inf = vertex(Vector3.new(FACE_WIDTH / 2, BORE_RADIUS * cosine,
                BORE_RADIUS * sine)),
            inb = vertex(Vector3.new(-FACE_WIDTH / 2, BORE_RADIUS * cosine,
                BORE_RADIUS * sine)),
        }
    end
    for i = 1, #samples do
        local j = i % #samples + 1
        local a, b = rings[i], rings[j]
        -- Front annulus faces +X, back annulus faces -X.
        tri(a.of, b.of, a.inf, frontNormal)
        tri(b.of, b.inf, a.inf, frontNormal)
        tri(a.ob, a.inb, b.ob, backNormal)
        tri(b.ob, a.inb, b.inb, backNormal)
        -- Outside wall, including involute flanks and tapered bevel teeth.
        local sideVector = (positions[a.ob] - positions[a.of]):Cross(
            positions[b.of] - positions[a.of])
        local sideNormal = mesh:AddNormal(sideVector.Unit)
        tri(a.of, a.ob, b.of, sideNormal)
        tri(b.of, a.ob, b.ob, sideNormal)
        -- True cylindrical through-bore, never a filled-in spindle disc.
        local midAngle = (samples[i].a + samples[j].a) / 2
        if j == 1 then midAngle = (samples[i].a + samples[j].a + 2 * math.pi) / 2 end
        local innerNormal = mesh:AddNormal(Vector3.new(
            0, -math.cos(midAngle), -math.sin(midAngle)))
        tri(a.inf, b.inf, a.inb, innerNormal)
        tri(b.inf, b.inb, a.inb, innerNormal)
    end
    assert(triangleCount <= 20000, "Gear exceeds Roblox 20k-triangle limit")
    return bakedPart(mesh, Enum.CollisionFidelity.PreciseConvexDecomposition),
        {pitch = pitch, root = root, tip = tip, triangles = triangleCount,
            vertices = #samples * 4}
end

-- A single continuous watertight hex-head bolt, with a chamfered head,
-- smooth shoulder, tapered tip and a helical thread relief in the shaft.
-- Local +X follows the shaft, matching BoltMath and existing bolt prefabs.
local function buildBoltMesh()
    local mesh = createEditable()
    local vertices = {}
    local rings = {}
    local sides = 72 -- divisible by 6 for actual flat hex faces
    local shaftLength = BOLT_BASE_SHAFT_LENGTH
    local shaftRadius = BOLT_BASE_SHAFT_DIAMETER / 2
    local headLength = 0.17
    local headRadius = shaftRadius * 1.86
    local headStart = -shaftLength / 2 - headLength
    local shaftStart = -shaftLength / 2
    local shaftEnd = shaftLength / 2
    local threadStart = shaftStart + shaftLength * 0.25
    local threadEnd = shaftEnd - shaftLength * 0.08
    local turns = 11

    local function hexRadius(a)
        local sector = math.pi / 3
        local difference = ((a % sector) - sector / 2)
        return headRadius * math.cos(math.pi / 6) / math.cos(difference)
    end
    local function threadRadius(x, angle)
        if x < threadStart then return shaftRadius end
        local fade = math.clamp((x - threadStart) / (shaftLength * 0.07), 0, 1)
        local phase = ((x - threadStart) / (threadEnd - threadStart)
            * turns - angle / (2 * math.pi)) % 1
        local ridge = 1 - math.abs(phase * 2 - 1) -- one helical triangular ridge
        local tip = math.clamp((shaftEnd - x) / (shaftLength * 0.08), 0.3, 1)
        return shaftRadius * (1 - 0.14 * fade * (1 - ridge)) * tip
    end
    local sections = {
        {x = headStart, mode = "hex", k = 0.94},
        {x = headStart + 0.025, mode = "hex", k = 1.0},
        {x = shaftStart - 0.027, mode = "hex", k = 1.0},
        {x = shaftStart, mode = "hex", k = 0.94},
        {x = shaftStart, mode = "shaft"}, -- actual radial head shoulder
        {x = shaftStart + 0.015, mode = "shaft"},
    }
    local steps = 68
    for i = 1, steps do
        local x = shaftStart + 0.015 + (shaftEnd - shaftStart - 0.015) * i / steps
        table.insert(sections, {x = x, mode = "shaft"})
    end
    local function vertex(v)
        local id = mesh:AddVertex(v)
        vertices[id] = v
        return id
    end
    local count = 0
    local function tri(a, b, c)
        local pa, pb, pc = vertices[a], vertices[b], vertices[c]
        assert((pb-pa):Cross(pc-pa).Magnitude > 1e-9,
            "Bolt mesh contains a degenerate face")
        mesh:AddTriangle(a, b, c)
        count += 1
    end
    for si, section in ipairs(sections) do
        rings[si] = {}
        for i = 0, sides - 1 do
            local a = 2 * math.pi * i / sides
            local r = if section.mode == "hex"
                then hexRadius(a) * section.k
                else threadRadius(section.x, a)
            rings[si][i + 1] = vertex(Vector3.new(
                section.x, r * math.cos(a), r * math.sin(a)))
        end
    end
    for si = 1, #rings - 1 do
        for i = 1, sides do
            local j = i % sides + 1
            local a,b = rings[si][i],rings[si][j]
            local c,d = rings[si+1][i],rings[si+1][j]
            tri(a,b,c)
            tri(b,d,c)
        end
    end
    local headCenter = vertex(Vector3.new(headStart,0,0))
    local tipCenter = vertex(Vector3.new(shaftEnd,0,0))
    for i = 1, sides do
        local j = i % sides + 1
        tri(headCenter, rings[1][j],rings[1][i])
        tri(tipCenter, rings[#rings][i],rings[#rings][j])
    end
    assert(count <= 20000, "Bolt exceeds Roblox 20k-triangle limit")
    local part = bakedPart(mesh, Enum.CollisionFidelity.PreciseConvexDecomposition)
    return part, {triangles = count, vertices = #sections * sides + 2,
        headLength = headLength}
end

local function folder(parent, name)
    local found = parent:FindFirstChild(name)
    if not found then
        found = Instance.new("Folder")
        found.Name = name
        found.Parent = parent
    end
    assert(found:IsA("Folder"), "Prefab path occupied by non-folder: " .. name)
    return found
end

local function addGear(parent, source, kind, teeth, index, details)
    local scale = SCALES[index]
    local bevel = kind == "Bevel90"
    local name = string.format("%s_%02dT_S%02d", kind == "Spur" and "GearMesh" or "Bevel90Mesh",
        teeth, index)
    local model = Instance.new("Model")
    model.Name = name
    model:SetAttribute("ProceduralPrefabVersion", VERSION)
    model:SetAttribute("PrimitiveFamily", "Gear")
    model:SetAttribute("CatalogGroup", "Gears")
    model:SetAttribute("CatalogName", string.format("Precision %s  ·  %dT  ·  Size %d",
        bevel and "90° Bevel" or "Spur", teeth, index))
    model:SetAttribute("ResizeMode", "None")
    model:SetAttribute("GearKind", bevel and "Bevel90" or "Spur")
    model:SetAttribute("GearTeeth", teeth)
    model:SetAttribute("GearModuleStuds", math.pi * CAD_MODULE * scale)
    model:SetAttribute("PitchRadiusStuds", details.pitch * scale)
    model:SetAttribute("BoreRadiusStuds", BORE_RADIUS * scale)
    model:SetAttribute("BevelConeDeg", bevel and 45 or nil)
    model:SetAttribute("BevelShaftAngleDeg", bevel and 90 or nil)
    model:SetAttribute("AxialAxis", "X")
    model:SetAttribute("GeometryVersion", 4)
    model:SetAttribute("ToothCount", teeth)
    model:SetAttribute("PitchDiameter", 2 * details.pitch * scale)
    model:SetAttribute("RootDiameter", 2 * details.root * scale)
    model:SetAttribute("TipDiameter", 2 * details.tip * scale)
    model:SetAttribute("BoreDiameter", 2 * BORE_RADIUS * scale)
    model:SetAttribute("FaceWidth", FACE_WIDTH * scale)
    model:SetAttribute("Triangles", details.triangles)
    model:SetAttribute("StaticDataModelMesh", true)
    local mesh = source:Clone()
    mesh.Name = "Geometry"
    mesh.Size = source.Size * scale
    mesh.Parent = model
    model.PrimaryPart = mesh
    model.Parent = parent
    return model
end

local function addBolt(parent, source, index, details)
    local scale = BOLT_SCALES[index]
    local diameterU, lengthU = scale, 8 * scale
    local model = Instance.new("Model")
    model.Name = string.format("BoltMesh_%03dU", math.round(diameterU * 100))
    model:SetAttribute("ProceduralPrefabVersion", VERSION)
    model:SetAttribute("PrimitiveFamily", "Bolt")
    model:SetAttribute("CatalogGroup", "Fasteners")
    model:SetAttribute("CatalogName", string.format("Precision Hex Bolt  ·  Ø%.2f × %.1f U",
        diameterU, lengthU))
    model:SetAttribute("ResizeMode", "None")
    model:SetAttribute("BoltDiameterU", diameterU)
    model:SetAttribute("BoltLengthU", lengthU)
    model:SetAttribute("AxialAxis", "X")
    model:SetAttribute("GeometryVersion", 4)
    model:SetAttribute("Threaded", true)
    model:SetAttribute("ThreadTurns", 11)
    model:SetAttribute("StaticDataModelMesh", true)
    model:SetAttribute("Triangles", details.triangles)
    local shape = source:Clone()
    shape.Name = "BoltSolid"
    shape.Size = source.Size * scale
    shape.Parent = model
    -- BoltMath uses the primary part as the exact shank reference;
    -- the hex head is outside the shank's -X end. Keep this standard.
    local pivot = Instance.new("Part")
    pivot.Name = "Geometry"
    pivot.Shape = Enum.PartType.Cylinder
    pivot.Size = Vector3.new(BOLT_BASE_SHAFT_LENGTH * scale,
        BOLT_BASE_SHAFT_DIAMETER * scale, BOLT_BASE_SHAFT_DIAMETER * scale)
    pivot.Anchored = true
    pivot.CanCollide = false
    pivot.CanQuery = false
    pivot.CanTouch = false
    pivot.Transparency = 1
    pivot.CastShadow = false
    pivot.Parent = model
    model.PrimaryPart = pivot
    model.Parent = parent
    return model
end

function Prefabs.Ensure()
    if installed then
        local valid = #installedList == 45
        for _, model in ipairs(installedList) do
            if not model.Parent then
                valid = false
                break
            end
        end
        if valid then return installedList end
        installed = false
        installedList = {}
    end
    lastError = nil
    stage("Preparing 45 precision prefabs")
    local library = folder(ReplicatedStorage, LIBRARY_NAME)
    local transmission = folder(library, "Transmission")
    local fasteners = folder(library, "Fasteners")
    local pending = {}
    local templates = {}
    local function prepare(category, model)
        table.insert(pending, {category = category, model = model})
    end
    local ok, err = pcall(function()
        for _, teeth in ipairs(COUNTS) do
            for _, kind in ipairs({"Spur", "Bevel90"}) do
                stage(string.format("Baking %dT %s visual mesh (%d of 9)",
                    teeth, kind, #templates + 1))
                local base, details = buildGearMesh(teeth, kind == "Bevel90")
                table.insert(templates, base)
                for index = 1, #SCALES do
                    prepare(transmission, addGear(nil, base, kind, teeth, index, details))
                end
            end
        end
        stage("Baking threaded hex bolt visual mesh (9 of 9)")
        local boltBase, boltDetails = buildBoltMesh()
        table.insert(templates, boltBase)
        for index = 1, #BOLT_SCALES do
            prepare(fasteners, addBolt(nil, boltBase, index, boltDetails))
        end
        assert(#pending == 45, "Expected 45 prepared templates, got " .. #pending)
    end)
    for _, template in ipairs(templates) do template:Destroy() end
    if not ok then
        for _, item in ipairs(pending) do item.model:Destroy() end
        local message = progress .. " FAILED: " .. tostring(err)
        failure(message)
        error(message)
    end
    -- Replace only our own generated IDs, never legacy or user-authored assets.
    -- All 45 prefabs are prepared and conflict-checked before replacement.
    for _, item in ipairs(pending) do
        local existing = item.category:FindFirstChild(item.model.Name)
        if existing then
            assert(existing:GetAttribute("ProceduralPrefabVersion") == VERSION,
                "Refusing to replace non-generated prefab " .. item.model.Name)
        end
    end
    for _, item in ipairs(pending) do
        local existing = item.category:FindFirstChild(item.model.Name)
        if existing then existing:Destroy() end
        item.model.Parent = item.category
        table.insert(installedList, item.model)
    end
    installed = true
    stage("Ready: 45 baked prefabs installed in ReplicatedStorage")
    return installedList
end

function Prefabs.GetStatus()
    local library = ReplicatedStorage:FindFirstChild(LIBRARY_NAME)
    local transmission = library and library:FindFirstChild("Transmission")
    local fasteners = library and library:FindFirstChild("Fasteners")
    local n = 0
    for _, group in ipairs({transmission, fasteners}) do
        if group then
            for _, item in ipairs(group:GetChildren()) do
                if item:GetAttribute("ProceduralPrefabVersion") == VERSION then
                    n += 1
                end
            end
        end
    end
    return {
        Ready = installed and n == 45,
        Count = n,
        Progress = progress,
        LastError = lastError,
        Gallery = Workspace:FindFirstChild(GALLERY_NAME) ~= nil,
        Studio = RunService:IsStudio(),
    }
end

function Prefabs.BuildGallery(focusCamera)
    local items = Prefabs.Ensure()
    assert(#items == 45, "Cannot display an incomplete 45-piece gallery")
    stage("Building Workspace gallery (45 parts)")
    local old = Workspace:FindFirstChild(GALLERY_NAME)
    if old then old:Destroy() end
    local root = Instance.new("Model")
    root.Name = GALLERY_NAME
    root:SetAttribute("GalleryOnly", true)
    root:SetAttribute("GeneratedPrefabs", #items)
    local rowSpace = 16
    local colSpace = 16
    local origin = Vector3.new(0, 2, -205) -- outside all player plot regions
    local rows = 9
    for i, source in ipairs(items) do
        local row = math.floor((i - 1) / 5)
        local column = (i - 1) % 5
        local x = origin.X + (column - 2) * colSpace
        local z = origin.Z + (row - (rows - 1) / 2) * rowSpace
        local display = source:Clone()
        display.Name = source.Name
        display.Parent = root
        local isBolt = source:GetAttribute("PrimitiveFamily") == "Bolt"
        local orientation = isBolt and CFrame.identity or CFrame.Angles(0, 0, math.pi / 2)
        local height = 1.5 + (isBolt and 0.3 or source.PrimaryPart.Size.X / 2)
        display:PivotTo(CFrame.new(x, height, z) * orientation)
        for _, part in ipairs(display:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = true
                part.CanCollide = false
                part.CanTouch = false
                part.CanQuery = false
            end
        end
        local plate = Instance.new("Part")
        plate.Name = "DisplayBase"
        plate.Size = Vector3.new(13, 0.25, 13)
        plate.CFrame = CFrame.new(x, 0.25, z)
        plate.Color = Color3.fromRGB(38, 48, 61)
        plate.Material = Enum.Material.SmoothPlastic
        plate.Anchored = true
        plate.CanCollide = false
        plate.CanQuery = false
        plate.Parent = root
        local marker = Instance.new("Part")
        marker.Name = "DisplayLabelAnchor"
        marker.Size = Vector3.new(0.1,0.1,0.1)
        marker.CFrame = CFrame.new(x, 5.5, z + 5.5)
        marker.Anchored = true
        marker.Transparency = 1
        marker.CanCollide = false
        marker.CanQuery = false
        marker.Parent = root
        local gui = Instance.new("BillboardGui")
        gui.Name = "PrefabName"
        gui.Size = UDim2.fromOffset(240, 48)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 900
        gui.Adornee = marker
        gui.Parent = marker
        local text = Instance.new("TextLabel")
        text.Size = UDim2.fromScale(1, 1)
        text.BackgroundColor3 = Color3.fromRGB(23, 32, 44)
        text.BackgroundTransparency = 0.13
        text.TextColor3 = Color3.fromRGB(228, 235, 241)
        text.Font = Enum.Font.GothamMedium
        text.TextScaled = true
        text.Text = source:GetAttribute("CatalogName") or source.Name
        text.Parent = gui
    end
    root.Parent = Workspace
    if focusCamera and Workspace.CurrentCamera then
        local camera = Workspace.CurrentCamera
        camera.CameraType = Enum.CameraType.Scriptable
        local center = origin + Vector3.new(0,0,0)
        camera.CFrame = CFrame.lookAt(center + Vector3.new(0,100,118),center)
    end
    assert(#root:GetChildren() >= 45, "Incomplete Workspace prefab gallery")
    stage("Gallery ready at Workspace." .. GALLERY_NAME .. " (Z=-205)")
    return root
end

return Prefabs
