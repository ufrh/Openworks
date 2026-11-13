-- OPENWORKS / SHARP BOLT REGENERATOR — STUDIO COMMAND BAR (EDIT MODE)
-- Paste this entire file into Roblox Studio's Command Bar. No require() or ModuleScript.
-- Replaces ONLY five previously generated BoltMesh_* prefabs, plus their
-- corresponding five models in the existing 45-item gallery if present.
-- Keeps all gears, other prefabs, saves, and unrelated Workspace objects.
-- Bake content is session-scoped; permanently published assets require upload.
-- Requires Experience Settings > Security > Allow Mesh / Image APIs.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LIBRARY_NAME = "OPENWORKS_PrimitiveLibrary_DRAFT"
local GALLERY_NAME = "OPENWORKS_ProceduralPrefabGallery"
local BOLT_PREVIEW_NAME = "OPENWORKS_SharpBoltPreview"
local SCALES = {0.5, 0.75, 1, 1.25, 1.5}
local SHAFT_LENGTH = 2.0
local SHAFT_DIAMETER = 0.25
local HEAD_LENGTH = 0.17
local THREAD_TURNS = 11
local THREAD_DEPTH = 0.24  -- 24% radial V-groove cut
local SIDES = 60           -- 10 vertices per flat hex side
local SAMPLES_PER_TURN = 12
local GENERATOR_VERSION = 1 -- preserves existing prefab namespace
local BOLT_GEOMETRY_VERSION = 5

local function getFolder(parent, name)
    local found = parent:FindFirstChild(name)
    if found then
        assert(found:IsA("Folder"), "Expected Folder at " .. found:GetFullName())
        return found
    end
    local newFolder = Instance.new("Folder")
    newFolder.Name = name
    newFolder.Parent = parent
    return newFolder
end

local function makeBoltSource()
    local mesh = assert(AssetService:CreateEditableMesh(),
        "CreateEditableMesh failed: check Allow Mesh / Image APIs and memory budget")
    local vertices = {}
    local rings = {}
    local triangles = 0
    local normals = 0
    local shaftRadius = SHAFT_DIAMETER / 2
    local hexRadius = shaftRadius * 1.86
    local headBack = -SHAFT_LENGTH / 2 - HEAD_LENGTH
    local headFront = -SHAFT_LENGTH / 2
    local tipX = SHAFT_LENGTH / 2
    local threadStart = headFront + 0.31
    local threadEnd = tipX - 0.065
    local pitch = (threadEnd - threadStart) / THREAD_TURNS

    -- True hexagonal prism: six flat sides, and planar back/front surfaces.
    local function hexEdgeRadius(theta)
        local sector = math.pi / 3
        local delta = (theta % sector) - sector / 2
        return hexRadius * math.cos(math.pi / 6) / math.cos(delta)
    end

    -- Square crest, sharp planar flanks and narrow flat root.
    -- Phase depends on both shaft location and angle: one continuous helix.
    local function cutDepth(phase)
        if phase < 0.10 or phase >= 0.90 then return 0 end
        if phase < 0.45 then return (phase - 0.10) / 0.35 end
        if phase <= 0.55 then return 1 end
        return (0.90 - phase) / 0.35
    end

    local function radiusAt(x, theta)
        local phase = ((x - threadStart) / pitch - theta / (2 * math.pi)) % 1
        local fadeIn = math.clamp((x - threadStart) / (pitch * 0.55), 0, 1)
        local fadeOut = math.clamp((threadEnd - x) / (pitch * 0.55), 0, 1)
        return shaftRadius * (1 - THREAD_DEPTH * cutDepth(phase) * math.min(fadeIn, fadeOut))
    end

    local sections = {
        {x = headBack, kind = "hex"},
        {x = headFront, kind = "hex"},
        {x = headFront, kind = "shaft"}, -- planar hex shoulder, not a rounded collar
        {x = threadStart - pitch * 0.5, kind = "shaft"},
        {x = threadStart, kind = "shaft"},
    }
    for i = 1, THREAD_TURNS * SAMPLES_PER_TURN do
        local t = i / (THREAD_TURNS * SAMPLES_PER_TURN)
        table.insert(sections, {x = threadStart + (threadEnd - threadStart) * t, kind = "thread"})
    end
    -- A SHORT 0.025 stud machined chamfer, not an exaggerated conical nose.
    table.insert(sections, {x = tipX - 0.025, kind = "shaft"})
    table.insert(sections, {x = tipX, kind = "tip"})

    local function addVertex(v)
        local id = mesh:AddVertex(v)
        vertices[id] = v
        return id
    end

    local function triangle(a, b, c)
        local pa, pb, pc = vertices[a], vertices[b], vertices[c]
        local cross = (pb - pa):Cross(pc - pa)
        assert(cross.Magnitude > 1e-10, "Degenerate bolt triangle")
        local face = mesh:AddTriangle(a, b, c)
        -- Separate normal on every face: no smoothing across threads,
        -- hex sides, shoulder, chamfer or the flat tip.
        local normal = mesh:AddNormal(cross.Unit)
        mesh:SetFaceNormals(face, {normal, normal, normal})
        triangles += 1
        normals += 1
    end

    for si, section in ipairs(sections) do
        local ring = {}
        for n = 0, SIDES - 1 do
            local theta = n * 2 * math.pi / SIDES
            local radius
            if section.kind == "hex" then
                radius = hexEdgeRadius(theta)
            elseif section.kind == "thread" then
                radius = radiusAt(section.x, theta)
            elseif section.kind == "tip" then
                radius = shaftRadius * 0.84
            else
                radius = shaftRadius
            end
            ring[n + 1] = addVertex(Vector3.new(section.x,
                radius * math.cos(theta), radius * math.sin(theta)))
        end
        rings[si] = ring
    end

    for si = 1, #rings - 1 do
        local back = rings[si]
        local front = rings[si + 1]
        for n = 1, SIDES do
            local nextN = n % SIDES + 1
            triangle(back[n], back[nextN], front[n])
            triangle(back[nextN], front[nextN], front[n])
        end
    end

    local backCenter = addVertex(Vector3.new(headBack, 0, 0))
    local tipCenter = addVertex(Vector3.new(tipX, 0, 0))
    for n = 1, SIDES do
        local nextN = n % SIDES + 1
        triangle(backCenter, rings[1][nextN], rings[1][n])
        triangle(tipCenter, rings[#rings][n], rings[#rings][nextN])
    end

    assert(triangles < 20000, "Exceeded 20,000 triangle budget: " .. triangles)
    mesh:RemoveUnused() -- discard auto-created soft normals; keep hard face normals
    print(string.format("[OPENWORKS][BOLTS] Generated hard-surface mesh: %d triangles / %d normals", triangles, normals))

    local okBake, bakeStatus, baked = pcall(function()
        return AssetService:CreateDataModelContentAsync(Content.fromObject(mesh))
    end)
    if not okBake or bakeStatus ~= Enum.CreateContentResult.Success or not baked then
        mesh:Destroy()
        error("Failed to bake bolt mesh: " .. tostring(bakeStatus))
    end
    local okPart, source = pcall(function()
        return AssetService:CreateMeshPartAsync(baked, {
            CollisionFidelity = Enum.CollisionFidelity.Box,
            RenderFidelity = Enum.RenderFidelity.Precise,
        })
    end)
    mesh:Destroy() -- the five instances below clone static content
    assert(okPart and source, "CreateMeshPartAsync failed: " .. tostring(source))
    source.Name = "BoltSolid"
    source.Anchored = true
    source.CanCollide = false -- no oversized box collider inside fitted holes
    source.CanQuery = false
    source:SetAttribute("OpenworksCollisionMode","VisualOnly")
    source.CanTouch = false
    source.Material = Enum.Material.Metal
    source.MaterialVariant = ""
    source.Color = Color3.fromRGB(145, 154, 166)
    source.CastShadow = true
    source.RenderFidelity = Enum.RenderFidelity.Precise
    return source, triangles, pitch
end

local function makePrefab(source, triangles, pitch, scale)
    local diameterU, lengthU = scale, 8 * scale
    local model = Instance.new("Model")
    model.Name = string.format("BoltMesh_%03dU", math.round(diameterU * 100))
    model:SetAttribute("ProceduralPrefabVersion", GENERATOR_VERSION)
    model:SetAttribute("PrimitiveFamily", "Bolt")
    model:SetAttribute("CatalogGroup", "Fasteners")
    model:SetAttribute("CatalogName", string.format("Sharp Hex Bolt  ·  Ø%.2f × %.1f U", diameterU, lengthU))
    model:SetAttribute("ResizeMode", "None")
    model:SetAttribute("AxialAxis", "X")
    model:SetAttribute("BoltDiameterU", diameterU)
    model:SetAttribute("BoltLengthU", lengthU)
    model:SetAttribute("GeometryVersion", BOLT_GEOMETRY_VERSION)
    model:SetAttribute("Threaded", true)
    model:SetAttribute("ThreadTurns", THREAD_TURNS)
    model:SetAttribute("ThreadPitchStuds", pitch * scale)
    model:SetAttribute("Triangles", triangles)
    model:SetAttribute("FlatShaded", true)
    model:SetAttribute("StaticDataModelMesh", true)

    local visual = source:Clone()
    visual.Name = "BoltSolid"
    visual.Size = source.Size * scale
    visual.CanCollide=false
    visual.CanQuery=false
    visual.Massless=true
    visual:SetAttribute("OpenworksCollisionMode","VisualOnly")
    visual.Parent = model

    -- Keep the same invisible shaft origin, exact dimensions, and model
    -- PrimaryPart that BoltMath, Build, and fit relationships expect.
    local pivot = Instance.new("Part")
    pivot.Name = "Geometry"
    pivot.Shape = Enum.PartType.Cylinder
    pivot.Size = Vector3.new(SHAFT_LENGTH * scale,
        SHAFT_DIAMETER * scale, SHAFT_DIAMETER * scale)
    pivot.Anchored = true
    pivot.CanCollide = true
    pivot.CanQuery = true
    pivot.CanTouch = false
    pivot.CastShadow = false
    pivot.Transparency = 1
    pivot:SetAttribute("OpenworksCollisionMode","Proxy")
    pivot.Parent = model
    local head=Instance.new("Part")
    head.Name="HeadCollider"
    head.Shape=Enum.PartType.Cylinder
    head.Size=Vector3.new(HEAD_LENGTH*scale*0.94,
        SHAFT_DIAMETER*scale*1.86,SHAFT_DIAMETER*scale*1.86)
    head.CFrame=CFrame.new(-SHAFT_LENGTH*scale*0.5
        -HEAD_LENGTH*scale*0.5,0,0)
    head.Anchored=true
    head.CanCollide=true
    head.CanQuery=true
    head.CanTouch=false
    head.Transparency=1
    head.CastShadow=false
    head.Massless=true
    head:SetAttribute("OpenworksCollisionMode","Proxy")
    head.Parent=model
    model:SetAttribute("BoltHeadLengthStuds",HEAD_LENGTH*scale)
    model:SetAttribute("OpenworksCollisionVersion",2)
    model.PrimaryPart = pivot
    return model
end

local function run()
    print("[OPENWORKS][BOLTS] Regenerating ONLY 5 sharp-sided bolt prefabs...")
    local library = getFolder(ReplicatedStorage, LIBRARY_NAME)
    local fasteners = getFolder(library, "Fasteners")
    local source, triangles, pitch = makeBoltSource()
    local pending = {}
    local ok, err = pcall(function()
        for _, scale in ipairs(SCALES) do
            local model = makePrefab(source, triangles, pitch, scale)
            local old = fasteners:FindFirstChild(model.Name)
            assert(not old or (old:IsA("Model")
                and old:GetAttribute("ProceduralPrefabVersion") == GENERATOR_VERSION
                and old:GetAttribute("PrimitiveFamily") == "Bolt"),
                "Refusing to overwrite custom prefab " .. model.Name)
            table.insert(pending, {model = model, old = old})
        end
    end)
    source:Destroy()
    if not ok then
        for _, entry in ipairs(pending) do entry.model:Destroy() end
        error(err)
    end

    local gallery = Workspace:FindFirstChild(GALLERY_NAME)
    local preview = nil
    if not gallery then
        preview = Workspace:FindFirstChild(BOLT_PREVIEW_NAME)
        if preview then preview:Destroy() end
        preview = Instance.new("Model")
        preview.Name = BOLT_PREVIEW_NAME
        preview:SetAttribute("GalleryOnly", true)
        preview.Parent = Workspace
    end

    for index, entry in ipairs(pending) do
        local newPrefab = entry.model
        if entry.old then entry.old:Destroy() end
        newPrefab.Parent = fasteners

        local oldDisplay = gallery and gallery:FindFirstChild(newPrefab.Name)
        if oldDisplay and oldDisplay:IsA("Model") then
            local cf = oldDisplay:GetPivot()
            local display = newPrefab:Clone()
            display.Name = newPrefab.Name
            display:PivotTo(cf)
            for _, p in ipairs(display:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
                end
            end
            oldDisplay:Destroy()
            display.Parent = gallery
        elseif preview then
            local display = newPrefab:Clone()
            display:PivotTo(CFrame.new((index - 3) * 2.8, 3, -25))
            display.Parent = preview
        end
        print("[OPENWORKS][BOLTS] Rebuilt " .. newPrefab.Name)
    end

    if preview and Workspace.CurrentCamera then
        local camera = Workspace.CurrentCamera
        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = CFrame.lookAt(Vector3.new(0, 9, 1), Vector3.new(0, 3, -25))
    end
    print(string.format("[OPENWORKS][BOLTS] DONE: 5/5 sharp hex bolts, %d triangles each. Gears were untouched.", triangles))
    if gallery then
        print("[OPENWORKS][BOLTS] Existing gallery bolt displays refreshed.")
    else
        print("[OPENWORKS][BOLTS] Standalone preview: Workspace." .. BOLT_PREVIEW_NAME)
    end
end

local success, result = pcall(run)
if not success then
    warn("[OPENWORKS][BOLTS] FAILED: " .. tostring(result))
    error(result, 0)
end
