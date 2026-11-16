--!strict
-- OPENWORKS: game-runtime DC motor primitive. Published static mesh visuals,
-- native solid collision/query proxies. Never builds EditableMeshes in play.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")
local Geometry = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("MotorMeshGeometry"))

local Motor = {}
local ROOT = "OPENWORKS_PrimitiveLibrary_DRAFT"
local MANIFEST = "OPENWORKS_PublishedMotorMeshes"
local ID = "DCMotor"
local VERSION = 3

local COLORS = {
    RearCan = Color3.fromRGB(118, 126, 132),
    Housing = Color3.fromRGB(187, 190, 191),
    Endbell = Color3.fromRGB(150, 158, 163),
}
local function native(model: Model, name: string, shape: Enum.PartType, size: Vector3,
        cf: CFrame, color: Color3, proxy: boolean?): Part
    local p = Instance.new("Part")
    p.Name = name
    p.Shape = shape
    p.Size = size
    p.CFrame = cf
    p.Material = Enum.Material.Metal
    p.Color = color
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.Anchored = true
    p.CanCollide = true
    p.CanQuery = true
    p.CanTouch = false
    p.CastShadow = true
    if proxy then
        p:SetAttribute("OpenworksCollisionMode","Proxy")
        p.Transparency = 1
        p.CastShadow = false
    else
        p:SetAttribute("OpenworksKeepFactoryAppearance",true)
        if name:match("^Fallback") then
            p:SetAttribute("OpenworksCollisionMode","VisualOnly")
            p.CanCollide = false
            p.CanQuery = false
        end
    end
    p.Parent = model
    return p
end
local function published(): {[string]: number}?
    local folder = ReplicatedStorage:FindFirstChild(MANIFEST)
    if not folder or folder:GetAttribute("Ready") ~= true
        or folder:GetAttribute("GeometryVersion") ~= VERSION then return nil end
    local ids = {}
    for _, key in ipairs(Geometry.Keys) do
        local value = folder:FindFirstChild(key)
        if not value or not value:IsA("StringValue") or not value.Value:match("^%d+$") then
            return nil
        end
        local id = tonumber(value.Value)
        if not id or id <= 0 then return nil end
        ids[key] = id
    end
    return ids
end
local function meshPart(model: Model, key: string, assetId: number): MeshPart
    local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(assetId), {
        CollisionFidelity = Enum.CollisionFidelity.Box,
        RenderFidelity = Enum.RenderFidelity.Precise,
    })
    part.Name = "Visual_" .. key
    part.CFrame = CFrame.new(Geometry.Offsets[key])
    part.Color = COLORS[key]
    part.Material = Enum.Material.Metal
    part.DoubleSided = false
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
    part.CastShadow = true
    part:SetAttribute("OpenworksCollisionMode","VisualOnly")
    part:SetAttribute("OpenworksKeepFactoryAppearance",true)
    part:SetAttribute("MotorMeshKey",key)
    part:SetAttribute("MotorMeshAssetId",tostring(assetId))
    part.Parent = model
    return part
end
local function build(): Model
    local model = Instance.new("Model")
    model.Name = ID
    model:SetAttribute("PrimitiveFamily","Motor")
    model:SetAttribute("CatalogGroup","Actuators")
    model:SetAttribute("CatalogName","Brushed DC Motor")
    model:SetAttribute("ResizeMode","None")
    model:SetAttribute("ActuatorKind","ElectricMotor")
    model:SetAttribute("ActuatorOutputAxis","X")
    model:SetAttribute("OutputShaftDiameterStuds",0.32)
    model:SetAttribute("OutputShaftLengthStuds",0.74)
    model:SetAttribute("MotorPrefabVersion",VERSION)
    model:SetAttribute("MotorVisualOnly",true) -- no powered mechanical coupling yet
    model:SetAttribute("StudioPrecompiled",true)

    -- Persistent, actual-volume geometry for selection and collisions.
    local body = native(model,"Geometry",Enum.PartType.Cylinder,
        Vector3.new(2.98,2.06,2.06),CFrame.new(-0.33,0,0),
        Color3.fromRGB(125,133,141),true)
    model.PrimaryPart = body
    native(model,"OutputShaft",Enum.PartType.Cylinder,
        Vector3.new(0.74,0.32,0.32),CFrame.new(1.71,0,0),
        Color3.fromRGB(172,182,188))
    local shaft = model:FindFirstChild("OutputShaft") :: Part
    local attachment = Instance.new("Attachment")
    attachment.Name = "ActuatorOutput"
    attachment.CFrame = CFrame.new(0.37,0,0)
    attachment.Parent = shaft

    -- A real brushed motor is CLOSED at the rear. Earlier versions
    -- displayed a giant empty cylinder because its rear was just a tube.
    -- Solid components sit beneath the vented metal shell, and are visible
    -- through the openings without becoming extra physics bodies.
    local rearCap = native(model,"RearInsulatingEndCap",Enum.PartType.Cylinder,
        Vector3.new(0.16,1.84,1.84),CFrame.new(-1.79,0,0),
        Color3.fromRGB(53,59,63))
    rearCap:SetAttribute("OpenworksCollisionMode","VisualOnly")
    rearCap.CanCollide=false
    rearCap.CanQuery=false

    local armature = native(model,"InternalArmature",Enum.PartType.Cylinder,
        Vector3.new(0.86,1.49,1.49),CFrame.new(-1.06,0,0),
        Color3.fromRGB(58,62,66))
    armature:SetAttribute("OpenworksCollisionMode","VisualOnly")
    armature.CanCollide=false
    armature.CanQuery=false

    -- Subtle brass electrical terminals project from the CLOSED rear cap.
    for i,z in ipairs({-0.35,0.35}) do
        local terminal = native(model,"Terminal_"..i,Enum.PartType.Block,
            Vector3.new(0.22,0.18,0.12),CFrame.new(-1.94,0,z),
            Color3.fromRGB(167,126,67))
        terminal:SetAttribute("OpenworksCollisionMode","VisualOnly")
        terminal.CanCollide=false
        terminal.CanQuery=false
    end

    local ids = published()
    local ok = false
    if ids then
        local result,err = pcall(function()
            for _,key in ipairs(Geometry.Keys) do
                meshPart(model,key,ids[key])
            end
        end)
        if result then
            ok = true
        else
            warn("[OPENWORKS][MOTOR] Mesh assets not ready; using solid fallback: "
                ..tostring(err))
            for _,part in ipairs(model:GetChildren()) do
                if part:IsA("MeshPart") then part:Destroy() end
            end
        end
    end
    if not ok then
        -- Always buildable before publication. Fallback uses ONLY solid native
        -- Parts and intentionally omits the detailed open-vent mesh.
        native(model,"FallbackRearCan",Enum.PartType.Cylinder,
            Vector3.new(1.38,1.98,1.98),CFrame.new(-1.11,0,0),
            COLORS.RearCan)
        native(model,"FallbackHousing",Enum.PartType.Cylinder,
            Vector3.new(1.46,2.18,2.18),CFrame.new(0.28,0,0),
            COLORS.Housing)
        native(model,"FallbackEndbell",Enum.PartType.Cylinder,
            Vector3.new(0.18,2.04,2.04),CFrame.new(1.06,0,0),
            COLORS.Endbell)
        native(model,"FallbackBearing",Enum.PartType.Cylinder,
            Vector3.new(0.29,0.75,0.75),CFrame.new(1.26,0,0),
            COLORS.Endbell)
    end
    model:SetAttribute("PublishedMotorVisual",ok)
    return model
end

function Motor.Ensure(forceRebuild: boolean?)
    local root = ReplicatedStorage:FindFirstChild(ROOT)
    if not root then
        root = Instance.new("Folder")
        root.Name = ROOT
        root.Parent = ReplicatedStorage
    end
    local category = root:FindFirstChild("Actuators")
    if not category then
        category = Instance.new("Folder")
        category.Name = "Actuators"
        category.Parent = root
    end
    local prior = category:FindFirstChild(ID)
    if prior then
        if not forceRebuild then return prior end
        local priorVersion = prior:GetAttribute("MotorPrefabVersion")
        assert(prior:IsA("Model") and (priorVersion == VERSION or priorVersion == 1 or priorVersion == 2),
            "Refusing to overwrite a custom motor primitive")
    end
    local fresh = build()
    if prior then prior:Destroy() end
    fresh.Parent = category
    print("[OPENWORKS][MOTOR] Brushed DC motor primitive ready ("
        ..(if fresh:GetAttribute("PublishedMotorVisual") then "published mesh" else "native fallback")
        ..")")
    return fresh
end
return Motor
