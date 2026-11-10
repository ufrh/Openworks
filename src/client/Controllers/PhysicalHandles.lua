--!strict
-- Reused visual language from archived FORM TransformGizmo:
-- actual Parts and ReplicatedStorage.Cone, filled Highlights without
-- outlines, plus thin SelectionBoxes ONLY around scale cubes.
-- Picking remains a crosshair-screen projection; translation is in 3D.
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
    part.Transparency = 1
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

            if mode == "Rotate" then
                grip.Segments = {}
                for n = 1, 32 do
                    local arc = makePart(model, "Ring_" .. tostring(n),
                        color, Enum.PartType.Cylinder)
                    arc.Material = Enum.Material.Neon
                    arc.Transparency = 0.15
                    table.insert(grip.Segments, arc)
                end
            elseif mode == "Move" then
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
                    grip.Tip.Transparency = 1
                    grip.Tip.Color = color
                else
                    grip.Tip = makePart(model, "Arrowhead", color, Enum.PartType.Block)
                end
            else
                grip.Cube = makePart(model, "ScaleCube", color, Enum.PartType.Block)
                grip.Border = Instance.new("SelectionBox")
                grip.Border.Adornee = grip.Cube
                grip.Border.Color3 = color
                grip.Border.LineThickness = 0.014
                grip.Border.SurfaceTransparency = 1
                grip.Border.Transparency = 0.18
                grip.Border.Visible = false
                grip.Border.Parent = model
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

function Handles:Update(cf, size, allowedAxis)
    local camera = workspace.CurrentCamera
    if not camera then return end
    local scale = math.clamp((camera.CFrame.Position - cf.Position).Magnitude * 0.035,
        0.12, 0.85)
    local longest = math.max(size.X, size.Y, size.Z)
    local screen = camera.ViewportSize * 0.5
    local best, bestDistance = nil, 75

    for _, grip in ipairs(self.Grips) do
        local axis, sign = grip.Axis, grip.Sign
        local allowed = allowedAxis == nil or allowedAxis(axis)
        local direction = cf:VectorToWorldSpace(AXES[axis] * sign)
        local endPoint
        local ringDistance = math.huge
        if self.Mode == "Rotate" then
            local ringAxis = cf:VectorToWorldSpace(AXES[axis])
            local reference = if math.abs(ringAxis:Dot(Vector3.yAxis)) > 0.94
                then Vector3.zAxis else Vector3.yAxis
            local u = ringAxis:Cross(reference).Unit
            local v = ringAxis:Cross(u).Unit
            local radius = longest * 0.6 + scale * 1.2
            for n, segment in ipairs(grip.Segments) do
                local angle = 2 * math.pi * (n - 0.5) / #grip.Segments
                local radial = u * math.cos(angle) + v * math.sin(angle)
                local tangent = -u * math.sin(angle) + v * math.cos(angle)
                local position = cf.Position + radial * radius
                segment.Size = Vector3.new(2 * math.pi * radius
                    / #grip.Segments * 1.02, scale * 0.075, scale * 0.075)
                segment.CFrame = rotateCylinder(position, tangent)
                local projected, visible = camera:WorldToViewportPoint(position)
                if visible and projected.Z > 0 then
                    local point = Vector2.new(projected.X, projected.Y)
                    local distance = (point - screen).Magnitude
                    if distance < ringDistance then
                        ringDistance = distance
                        endPoint = position
                    end
                end
            end
            grip.RingAxis = ringAxis
        elseif self.Mode == "Move" then
            local length = math.max(longest * 0.5 + 1.3 * scale, 4.5 * scale)
            local stemCenter = cf.Position + direction * (length * 0.5)
            grip.Stem.Size = Vector3.new(length, scale * 0.10, scale * 0.10)
            grip.Stem.CFrame = rotateCylinder(stemCenter, direction)
            local tipLength = scale * 1.05
            local tipCenter = cf.Position + direction * (length + tipLength * 0.5)
            grip.Tip.Size = Vector3.new(scale * 0.7, tipLength, scale * 0.7)
            grip.Tip.CFrame = CFrame.lookAt(tipCenter, tipCenter + direction)
                * CFrame.Angles(-math.pi/2, 0, 0)
            endPoint = tipCenter
        else
            local v = if axis == 1 then size.X elseif axis == 2 then size.Y else size.Z
            endPoint = cf.Position + direction * (v * 0.5 + scale * 0.65)
            grip.Cube.Size = Vector3.one * (scale * 0.45)
            grip.Cube.CFrame = CFrame.new(endPoint)
        end

        if endPoint then
            local projected, visible = camera:WorldToViewportPoint(endPoint)
            grip.Visible = allowed and visible and projected.Z > 0
            grip.Point = Vector2.new(projected.X, projected.Y)
        else
            grip.Visible = false
            grip.Point = nil
        end
        grip.Direction = direction
        grip.Face = cf.Position + direction *
            ((if axis == 1 then size.X elseif axis == 2 then size.Y else size.Z) * 0.5)
        local dist = if self.Mode == "Rotate" then ringDistance
            elseif grip.Point then (grip.Point - screen).Magnitude
            else math.huge
        if self.Mode == "Rotate" and dist > 30 then grip.Visible = false end
        if grip.Visible and dist < bestDistance then
            bestDistance = dist
            best = grip
        end
    end

    self.Selected = best
    self.SelectedDistance = if best then bestDistance else math.huge
    for _, grip in ipairs(self.Grips) do
        local emphasized = grip == best
        if self.Mode == "Rotate" then
            grip.Highlight.Enabled = false
            for _, segment in ipairs(grip.Segments) do
                segment.Transparency = if grip.Visible then (if emphasized then 0 else 0.15) else 1
            end
        else
            grip.Highlight.Enabled = grip.Visible
            if grip.Border then grip.Border.Visible = grip.Visible end
            grip.Highlight.FillTransparency = if emphasized then 0 else 0.18
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
