--!strict
-- Reused visual language from archived FORM TransformGizmo:
-- actual visible Parts and ReplicatedStorage.Cone. Move arrows use cylinder
-- stems and cone heads; scale uses matte saturated spheres with no bloom.
-- Highlights have colored fill and no outline. Picking is screen-space,
-- but translation and resizing are strictly world-space.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Grid = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))

local Handles = {}
Handles.__index = Handles

local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
local COLORS = {
    Color3.fromRGB(225, 108, 105),
    Color3.fromRGB(105, 208, 143),
    Color3.fromRGB(109, 167, 248),
}
local NAMES = { "X", "Y", "Z" }

local function makePart(parent, name, color, shape)
    local part = Instance.new("Part")
    part.Name = name
    part.Shape = shape
    part.Size = Vector3.one * 0.1
    part.Anchored = true
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    -- Actual visible geometry. Fully transparent handles could disappear
    -- entirely depending on Highlight rendering behavior.
    part.Transparency = 0.06
    part.CastShadow = false
    part.Material = Enum.Material.SmoothPlastic
    part.Color = color
    part.Parent = parent
    return part
end

local function newHighlight(model, color)
    local h = Instance.new("Highlight")
    h.Name = "HandleFill"
    h.Adornee = model
    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    h.FillColor = color
    h.FillTransparency = 0
    h.OutlineTransparency = 1
    h.Enabled = false
    h.Parent = model
    return h
end

local function coneTemplate()
    local cone = ReplicatedStorage:FindFirstChild("Cone")
    if cone and cone:IsA("BasePart") then return cone end
    return nil
end

function Handles.new(mode)
    local folder = Instance.new("Folder")
    folder.Name = "OPENWORKS_" .. mode .. "_PhysicalHandles"
    folder.Parent = workspace

    local self = setmetatable({
        Folder = folder,
        Mode = mode,
        Grips = {},
        Selected = nil,
        SelectedDistance = math.huge,
    }, Handles)
    local cone = coneTemplate()
    if mode == "Move" and not cone then
        warn("[OPENWORKS] ReplicatedStorage.Cone missing; showing block arrowheads")
    end

    for axis = 1, 3 do
        for _, sign in ipairs(if mode == "Scale" then { -1, 1 } else { 1 }) do
            local color = COLORS[axis]
            local model = Instance.new("Model")
            model.Name = mode .. NAMES[axis] .. (if sign > 0 then "+" else "-")
            model.Parent = folder
            local grip = {
                Axis = axis, Sign = sign,
                Model = model, Color = color,
                Visible = false, Point = nil,
            }

            if mode == "Move" then
                grip.Stem = makePart(model, "Shaft", color, Enum.PartType.Cylinder)
                if cone then
                    grip.Tip = cone:Clone()
                    grip.Tip.Name = "Arrowhead"
                    grip.Tip.Parent = model
                    grip.Tip.Anchored = true
                    grip.Tip.CanCollide = false
                    grip.Tip.CanTouch = false
                    grip.Tip.CanQuery = false
                    grip.Tip.CastShadow = false
                    grip.Tip.Transparency = 0.06
                    grip.Tip.Material = Enum.Material.SmoothPlastic
                    grip.Tip.Color = color
                else
                    grip.Tip = makePart(model, "Arrowhead", color, Enum.PartType.Block)
                end
            else
                -- Scale handles should actually be NEON, not matte proxies.
                grip.Sphere = makePart(model, "ScaleSphere", color, Enum.PartType.Ball)
                grip.Sphere.Material=Enum.Material.Neon
                grip.Sphere.Transparency=0
            end
            grip.Highlight = newHighlight(model, color)
            table.insert(self.Grips, grip)
        end
    end
    return self
end

local function rotateCylinder(center, axis)
    return CFrame.lookAt(center, center + axis)
        * CFrame.Angles(0, math.pi/2, 0)
end

local function distanceFromSegment(point: Vector2, a: Vector2, b: Vector2)
    local segment = b - a
    local lengthSquared = segment:Dot(segment)
    if lengthSquared < 0.0001 then return (point - b).Magnitude end
    local t = math.clamp((point - a):Dot(segment) / lengthSquared, 0, 1)
    return (point - (a + segment * t)).Magnitude
end

function Handles:Update(cf, size, allowedAxis)
    local camera = workspace.CurrentCamera
    if not camera then return end
    local distanceToCamera = (camera.CFrame.Position - cf.Position).Magnitude
    local scale = math.clamp(distanceToCamera * 0.05, 0.16, 0.9)
    local screen = camera.ViewportSize * 0.5
    local best, bestDistance = nil, math.huge

    for _, grip in ipairs(self.Grips) do
        local axis, sign = grip.Axis, grip.Sign
        local allowed = allowedAxis == nil or allowedAxis(axis)
        local direction = cf:VectorToWorldSpace(AXES[axis] * sign)
        local endpoint
        local distance = math.huge
        local visible = false

        if self.Mode == "Move" then
            -- Draw arrows just beyond the actual face, not at an arbitrary
            -- offset based on the longest dimension of the whole object.
            local half = (if axis == 1 then size.X
                elseif axis == 2 then size.Y else size.Z) * 0.5
            local start = cf.Position + direction * (half + scale * 0.35)
            local stemLength = scale * 2.4
            local shaftCenter = start + direction * (stemLength * 0.5)
            grip.Stem.Size = Vector3.new(stemLength, scale * 0.18, scale * 0.18)
            grip.Stem.CFrame = rotateCylinder(shaftCenter, direction)
            local tipLength = scale * 0.95
            local tipCenter = start + direction * (stemLength + tipLength * 0.5)
            grip.Tip.Size = Vector3.new(scale * 0.9, tipLength, scale * 0.9)
            grip.Tip.CFrame = CFrame.lookAt(tipCenter, tipCenter + direction)
                * CFrame.Angles(-math.pi/2, 0, 0)
            endpoint = tipCenter

            local a, aVisible = camera:WorldToViewportPoint(
                start + direction * (scale * 0.35))
            local b, bVisible = camera:WorldToViewportPoint(endpoint)
            visible = aVisible or bVisible
            if a.Z > 0 and b.Z > 0 then
                distance = distanceFromSegment(
                    screen, Vector2.new(a.X,a.Y), Vector2.new(b.X,b.Y))
            end
        else
            local half = (if axis == 1 then size.X
                elseif axis == 2 then size.Y else size.Z) * 0.5
            endpoint = cf.Position + direction * (half + scale * 0.65)
            grip.Sphere.Size = Vector3.one * (scale * 0.55)
            grip.Sphere.CFrame = CFrame.new(endpoint)
            local projected, onScreen = camera:WorldToViewportPoint(endpoint)
            visible = onScreen and projected.Z > 0
            if visible then
                distance = (screen - Vector2.new(projected.X,projected.Y)).Magnitude
            end
        end

        grip.Visible = allowed and visible
        grip.Direction = direction
        grip.Point = endpoint
        grip.PickDistance = distance
        -- Keep a reasonable hit radius so selecting a primitive itself does
        -- not accidentally drag a grip across the whole viewport.
        local maxDistance = if self.Mode == "Move" then 24 else 34
        if grip.Visible and distance <= maxDistance and distance < bestDistance then
            best, bestDistance = grip, distance
        end
    end

    self.Selected = best
    self.SelectedDistance = bestDistance
    for _, grip in ipairs(self.Grips) do
        local hovered = grip == best
        grip.Highlight.Enabled = self.Mode~="Scale" and grip.Visible
        grip.Highlight.FillTransparency = if hovered then 0 else 0.25
        for _, item in ipairs(grip.Model:GetDescendants()) do
            if item:IsA("BasePart") then
                item.Transparency = if grip.Visible
                    then (if self.Mode=="Scale" then 0 else 0.06) else 1
                if self.Mode=="Scale" then
                    item.Color=if hovered then grip.Color:Lerp(Color3.new(1,1,1),0.22)
                        else grip.Color
                end
            end
        end
    end
end

function Handles:Pick()
    return self.Selected
end

function Handles:Destroy()
    self.Folder:Destroy()
end

return Handles
