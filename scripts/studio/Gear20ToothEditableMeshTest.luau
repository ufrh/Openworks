-- OPENWORKS / Studio-only 20-tooth gear geometry test.
-- Paste the entire file into Roblox Studio's Command Bar in EDIT mode (not Play).
-- Creates FIVE involute spur gears with a shared, uniformly scaled topology.
-- Prototype uses EditableMesh; converts to static session content before cloning.
-- Safe to rerun: replaces only Workspace.OpenWorks_20T_Gear_Test.

local AssetService = game:GetService("AssetService")
local Workspace = game:GetService("Workspace")

local GROUP_NAME = "OpenWorks_20T_Gear_Test"
local TOOTH_COUNT = 20
local PRESSURE_ANGLE = math.rad(20)
local BASE_MODULE = 0.25
local SCALES = { 0.6, 0.8, 1.0, 1.2, 1.4 }
local FLANK_STEPS = 10
local TIP_STEPS = 5
local ROOT_GAP_STEPS = 4

local pitchRadius = TOOTH_COUNT * BASE_MODULE / 2
local baseRadius = pitchRadius * math.cos(PRESSURE_ANGLE)
local rootRadius = pitchRadius - 1.25 * BASE_MODULE
local tipRadius = pitchRadius + BASE_MODULE
local boreRadius = BASE_MODULE * 2.25
local halfWidth = (BASE_MODULE * 2.4) / 2
local pitchHalfAngle = math.pi / (2 * TOOTH_COUNT)
-- Root relief prevents identical polar angles and degenerate annulus triangles.
local ROOT_SHOULDER_ANGLE = math.rad(0.55)
local toothStep = 2 * math.pi / TOOTH_COUNT

assert(rootRadius > boreRadius, "Tooth root must be outside bore")
assert(tipRadius > baseRadius, "Tooth tip must be outside base circle")

-- Involute function inv(alpha) = tan(alpha)-alpha, calculated using t = tan(alpha).
local function involuteAtRadius(radius)
    if radius <= baseRadius then
        return 0
    end
    local t = math.sqrt((radius / baseRadius) ^ 2 - 1)
    return t - math.atan(t)
end

local involuteAtPitch = involuteAtRadius(pitchRadius)
local function halfToothAngle(radius)
    -- Tooth thickness equals half a circular pitch at the pitch diameter.
    return pitchHalfAngle + involuteAtPitch - involuteAtRadius(radius)
end

local perimeter = {}
local function append(radius, angle)
    table.insert(perimeter, { radius = radius, angle = angle })
end

-- CCW radial profile. Build a true involute on both flanks and circular
-- addendum/root arcs, then extrude the exact same outline into a solid annulus.
for tooth = 0, TOOTH_COUNT - 1 do
    local center = tooth * toothStep
    local halfBase = halfToothAngle(baseRadius)
    local halfTip = halfToothAngle(tipRadius)

    append(rootRadius, center - halfBase - ROOT_SHOULDER_ANGLE)
    for step = 0, FLANK_STEPS do
        local r = baseRadius + (tipRadius - baseRadius) * step / FLANK_STEPS
        append(r, center - halfToothAngle(r))
    end
    for step = 1, TIP_STEPS do
        local a = center - halfTip + 2 * halfTip * step / TIP_STEPS
        append(tipRadius, a)
    end
    for step = FLANK_STEPS - 1, 0, -1 do
        local r = baseRadius + (tipRadius - baseRadius) * step / FLANK_STEPS
        append(r, center + halfToothAngle(r))
    end
    append(rootRadius, center + halfBase + ROOT_SHOULDER_ANGLE)
    -- The remaining part of each tooth pitch is a circular root clearance.
    for step = 1, ROOT_GAP_STEPS - 1 do
        local shoulder = halfBase + ROOT_SHOULDER_ANGLE
        local a = center + shoulder + (toothStep - 2 * shoulder) * step / ROOT_GAP_STEPS
        append(rootRadius, a)
    end
end

local count = #perimeter
assert(count > 0 and count % TOOTH_COUNT == 0)
local editable = assert(AssetService:CreateEditableMesh(),
    "CreateEditableMesh failed. Run in Studio Command Bar with mesh APIs available.")

local rings = {}
for i, sample in ipairs(perimeter) do
    local a, r = sample.angle, sample.radius
    local c, s = math.cos(a), math.sin(a)
    rings[i] = {
        ot = editable:AddVertex(Vector3.new(r * c, halfWidth, r * s)),
        ob = editable:AddVertex(Vector3.new(r * c, -halfWidth, r * s)),
        it = editable:AddVertex(Vector3.new(boreRadius * c, halfWidth, boreRadius * s)),
        ib = editable:AddVertex(Vector3.new(boreRadius * c, -halfWidth, boreRadius * s)),
    }
end

local topNormal = editable:AddNormal(Vector3.new(0, 1, 0))
local bottomNormal = editable:AddNormal(Vector3.new(0, -1, 0))
local triangleCount = 0
local function addTriangle(a, b, c, normalId)
    local f = editable:AddTriangle(a, b, c)
    editable:SetFaceNormals(f, { normalId, normalId, normalId })
    triangleCount += 1
end

for i = 1, count do
    local j = i % count + 1
    local a, b = rings[i], rings[j]
    local pa, pb = perimeter[i], perimeter[j]
    local ax, az = pa.radius * math.cos(pa.angle), pa.radius * math.sin(pa.angle)
    local bx, bz = pb.radius * math.cos(pb.angle), pb.radius * math.sin(pb.angle)
    local dx, dz = bx - ax, bz - az
    local length = math.sqrt(dx * dx + dz * dz)
    assert(length > 1e-7, "Degenerate outline edge " .. i)

    -- Counterclockwise XZ outlines face +Y when triangulated this way.
    addTriangle(a.ot, a.it, b.ot, topNormal)
    addTriangle(b.ot, a.it, b.it, topNormal)
    addTriangle(a.ob, b.ob, a.ib, bottomNormal)
    addTriangle(b.ob, b.ib, a.ib, bottomNormal)

    -- Outer tooth walls; planar strip with one hard normal per boundary edge.
    local wallNormal = editable:AddNormal(Vector3.new(dz / length, 0, -dx / length))
    addTriangle(a.ot, b.ot, a.ob, wallNormal)
    addTriangle(b.ot, b.ob, a.ob, wallNormal)

    -- Central through-bore: cylinder wall normals point toward the shaft axis.
    local innerMidAngle = (pa.angle + (pb.angle < pa.angle and pb.angle + 2 * math.pi or pb.angle)) / 2
    local boreNormal = editable:AddNormal(Vector3.new(-math.cos(innerMidAngle), 0, -math.sin(innerMidAngle)))
    addTriangle(a.it, a.ib, b.it, boreNormal)
    addTriangle(b.it, a.ib, b.ib, boreNormal)
end

assert(triangleCount == count * 8, "Unexpected mesh triangle count")

-- Bake BEFORE constructing the clones. The Content below is *static* data-model
-- mesh content, not another reference to a live EditableMesh. It lasts only
-- until the Studio/server session ends; publish a mesh asset for permanence.
local okBake, bakeStatus, staticContent = pcall(function()
    return AssetService:CreateDataModelContentAsync(Content.fromObject(editable))
end)
assert(okBake and bakeStatus == Enum.CreateContentResult.Success and staticContent,
    "Could not bake static mesh content: " .. tostring(bakeStatus))

local okPart, template = pcall(function()
    return AssetService:CreateMeshPartAsync(staticContent, {
        CollisionFidelity = Enum.CollisionFidelity.Box,
    })
end)
assert(okPart and template, "Could not create static gear MeshPart: " .. tostring(template))
editable:Destroy()

local prior = Workspace:FindFirstChild(GROUP_NAME)
if prior then
    prior:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = GROUP_NAME
folder.Parent = Workspace

local camera = Workspace.CurrentCamera
local cameraPosition = camera and camera.CFrame.Position or Vector3.new(0, 10, 30)
local cameraLook = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
local cameraRight = camera and camera.CFrame.RightVector or Vector3.new(1, 0, 0)
local baseSize = template.Size
local gap = 1.1
local totalWidth = gap * (#SCALES - 1)
for _, scale in ipairs(SCALES) do
    totalWidth += baseSize.X * scale
end

-- Row faces the Studio camera, independent of the player's build orientation.
local centerPoint = cameraPosition + cameraLook * math.max(24, totalWidth * 1.4)
local cursor = -totalWidth / 2
for index, scale in ipairs(SCALES) do
    local diameter = TOOTH_COUNT * BASE_MODULE * scale
    local gear = template:Clone()
    gear.Name = string.format("Gear_%02d_20T_Pitch%.1f", index, diameter)
    gear.Size = baseSize * scale
    gear.Anchored = true
    gear.CanCollide = false -- Geometry-only preview, not a physics contact test.
    gear.CanTouch = false
    gear.CanQuery = true
    gear.Material = Enum.Material.Metal
    gear.Color = Color3.fromRGB(150, 160, 176)
    gear.CastShadow = true
    gear.RenderFidelity = Enum.RenderFidelity.Precise

    gear:SetAttribute("ToothCount", TOOTH_COUNT)
    gear:SetAttribute("Module", BASE_MODULE * scale)
    gear:SetAttribute("PressureAngleDegrees", 20)
    gear:SetAttribute("PitchDiameter", diameter)
    gear:SetAttribute("RootDiameter", rootRadius * 2 * scale)
    gear:SetAttribute("TipDiameter", tipRadius * 2 * scale)
    gear:SetAttribute("BoreDiameter", boreRadius * 2 * scale)
    gear:SetAttribute("FaceWidth", halfWidth * 2 * scale)
    gear:SetAttribute("GeometryType", "InvoluteSpurGear")
    gear:SetAttribute("MeshIsStaticSessionContent", true)

    local x = cursor + gear.Size.X / 2
    local position = centerPoint + cameraRight * x
    gear.CFrame = CFrame.lookAt(position, cameraPosition) * CFrame.Angles(-math.pi / 2, 0, 0)
    gear.Parent = folder
    cursor += gear.Size.X + gap
end

template:Destroy()
print(string.format("[OPENWORKS] 5 gears generated: 20 teeth each, %d outline vertices, %d triangles per gear.",
    count, triangleCount))
print("[OPENWORKS] All 5 share ONE static baked mesh scaled uniformly; see Workspace." .. GROUP_NAME)
print("[OPENWORKS] This is session-only mesh content; publish a Mesh asset before shipping the result.")