--!strict
-- First-person resize gizmo. The mouse NEVER unlocks for scaling.
-- Aim the central crosshair at a projected face handle, hold left mouse,
-- and drag with relative MouseMovement while still turning the camera.
-- One server edit on release.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Grid = require(
    game:GetService("ReplicatedStorage"):WaitForChild("Openworks")
        :WaitForChild("Construction"):WaitForChild("GridMath")
)

local Gizmo = {}
Gizmo.__index = Gizmo

local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
local AXIS_NAMES = { "X", "Y", "Z" }
local COLORS = {
    Color3.fromRGB(224, 106, 100),
    Color3.fromRGB(113, 202, 137),
    Color3.fromRGB(115, 164, 245),
}

-- In Scale mode, select the nearest on-screen face grip even when the
-- crosshair is not exactly over its 28px label. No inactive clicks.
local PICK_RADIUS = math.huge
-- Fixed sensitivity, independent of camera distance and zoom.
-- Previously screen-space projection could demand dozens/hundreds of
-- pixels for a single U when the part was close to the camera.
local PIXELS_PER_UNIT = 7

local function withAxis(size, axis, value)
    if axis == 1 then return Vector3.new(value, size.Y, size.Z) end
    if axis == 2 then return Vector3.new(size.X, value, size.Z) end
    return Vector3.new(size.X, size.Y, value)
end

local function nextSize(mode, initial, axis, amount)
    local delta = amount * Grid.Unit
    if mode == "XYZ_1U" then
        return withAxis(initial, axis, initial[AXIS_NAMES[axis]] + delta)
    elseif mode == "UniformDiameter_1U" then
        return Vector3.new(initial.X + delta, initial.X + delta, initial.X + delta)
    elseif mode == "LengthAndDiameter_1U" then
        if axis == 1 then return Vector3.new(initial.X + delta, initial.Y, initial.Z) end
        return Vector3.new(initial.X, initial.Y + delta, initial.Y + delta)
    elseif mode == "LengthOnly_1U" and axis == 1 then
        return Vector3.new(initial.X + delta, initial.Y, initial.Z)
    end
    return nil
end

local function canUse(mode, axis)
    return mode ~= "None"
        and (mode ~= "LengthOnly_1U" or axis == 1)
        and (mode ~= "UniformDiameter_1U" or axis == 1)
        and (mode ~= "LengthAndDiameter_1U" or axis ~= 3)
end

function Gizmo.new(gui, onChange, onCommit, onDragStarted)
    local self = setmetatable({
        Gui = gui,
        OnChange = onChange,
        OnCommit = onCommit,
        OnDragStarted = onDragStarted,
        Handles = {},
        Connections = {},
        CFrame = CFrame.identity,
        Size = Vector3.one,
        Mode = "None",
        TemplateSize = Vector3.one,
        Active = false,
        Hovered = nil,
        Drag = nil,
    }, Gizmo)

    for axis = 1, 3 do
        for _, sign in ipairs({ -1, 1 }) do
            -- Display-only labels: input always goes through the center
            -- crosshair and the native first-person mouse, not GUI clicking.
            local grip = Instance.new("TextLabel")
            grip.Name = "Scale_" .. AXIS_NAMES[axis] .. (if sign == 1 then "Plus" else "Minus")
            grip.AnchorPoint = Vector2.new(0.5, 0.5)
            grip.Size = UDim2.fromOffset(28, 28)
            grip.BorderSizePixel = 0
            grip.BackgroundColor3 = COLORS[axis]
            grip.BackgroundTransparency = 0.13
            grip.Font = Enum.Font.GothamBold
            grip.Text = AXIS_NAMES[axis] .. (if sign == 1 then "+" else "-")
            grip.TextSize = 11
            grip.TextColor3 = Color3.new(1, 1, 1)
            grip.ZIndex = 40
            grip.Visible = false
            grip.Parent = gui

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = grip

            local outline = Instance.new("UIStroke")
            outline.Color = Color3.fromRGB(238, 245, 255)
            outline.Transparency = 0.25
            outline.Thickness = 1
            outline.Parent = grip

            table.insert(self.Handles, {
                Axis = axis,
                Sign = sign,
                Object = grip,
                Stroke = outline,
                Point = nil,
                Direction = nil,
                Visible = false,
            })
        end
    end

    table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input)
        if not self.Active or self.Drag then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            -- Native Roblox Tools frequently mark LMB as processed.
            -- A gizmo interaction must not depend on that processed flag.
            self:BeginDrag()
        end
    end))

    table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input)
        if self.Drag and input.UserInputType == Enum.UserInputType.MouseMovement then
            -- InputObject.Delta is Vector3, while a projected screen axis
            -- is Vector2. Calling Vector3:Dot(Vector2) throws at runtime.
            self:UpdateDrag(Vector2.new(input.Delta.X, input.Delta.Y))
        end
    end))

    table.insert(self.Connections, UserInputService.InputEnded:Connect(function(input)
        if self.Drag and input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:FinishDrag()
        end
    end))

    table.insert(self.Connections, RunService.RenderStepped:Connect(function()
        if self.Active then self:UpdateHandles() end
    end))

    return self
end

function Gizmo:Open(cf, size, mode, templateSize)
    self.Drag = nil
    self.Active = true
    self.CFrame = cf
    self.Size = size
    self.Mode = mode
    self.TemplateSize = templateSize
    self:UpdateHandles()
end

function Gizmo:Close()
    self.Active = false
    self.Drag = nil
    self.Hovered = nil

    for _, handle in ipairs(self.Handles) do
        handle.Object.Visible = false
    end
end

function Gizmo:UpdateHandles()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local center = camera.ViewportSize / 2
    local nearest, nearestDistance = nil, PICK_RADIUS

    for _, handle in ipairs(self.Handles) do
        local axis, sign = handle.Axis, handle.Sign
        local grip = handle.Object
        if not canUse(self.Mode, axis) then
            handle.Visible = false
            grip.Visible = false
            continue
        end

        local outward = self.CFrame:VectorToWorldSpace(AXES[axis] * sign)
        local face = self.CFrame.Position
            + outward * self.Size[AXIS_NAMES[axis]] / 2
        local projected, visible = camera:WorldToViewportPoint(face)
        local beyond = camera:WorldToViewportPoint(face + outward)
        local direction = Vector2.new(beyond.X - projected.X, beyond.Y - projected.Y)

        if direction.Magnitude < 0.5 then
            local angle = axis * math.pi * 2 / 3
            direction = Vector2.new(math.cos(angle), math.sin(angle)) * sign
        end

        direction = direction.Unit
        local screenPoint = Vector2.new(projected.X, projected.Y) + direction * 30
        handle.Point = screenPoint
        handle.Direction = direction
        -- Resizing is a discrete 1-U operation, not a physically sized
        -- cursor gizmo. Keep the mouse travel required per Unit consistent
        -- at all FOV values and distances.
        handle.PixelsPerUnit = PIXELS_PER_UNIT
        handle.Visible = visible and projected.Z > 0
        grip.Position = UDim2.fromOffset(screenPoint.X, screenPoint.Y)
        grip.Visible = handle.Visible

        if handle.Visible then
            local distance = (screenPoint - center).Magnitude
            if distance < nearestDistance then
                nearest = handle
                nearestDistance = distance
            end
        end
    end

    self.Hovered = if self.Drag then self.Drag.Handle else nearest

    for _, handle in ipairs(self.Handles) do
        local hovered = handle == self.Hovered
        handle.Object.Size = UDim2.fromOffset(if hovered then 39 else 28, if hovered then 39 else 28)
        handle.Object.BackgroundTransparency = if hovered then 0 else 0.13
        handle.Stroke.Thickness = if hovered then 2.5 else 1
    end
end

function Gizmo:BeginDrag()
    if not self.Active or self.Drag then return false end
    self:UpdateHandles()
    local handle = self.Hovered
    if not handle or not handle.Visible then return false end
    local camera = workspace.CurrentCamera
    if not camera then return false end

    local outward = self.CFrame:VectorToWorldSpace(AXES[handle.Axis] * handle.Sign)

    self.Drag = {
        Handle = handle,
        StartCF = self.CFrame,
        StartSize = self.Size,
        Axis = handle.Axis,
        Direction = outward,
        ScreenDirection = handle.Direction,
        PixelsPerUnit = handle.PixelsPerUnit,
        PixelTravel = 0,
    }

    -- Do not touch CameraType or Camera.CFrame. Native first-person
    -- mouse-look remains active while the handle follows the drag.
    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    if self.OnDragStarted then self.OnDragStarted(handle.Axis, handle.Sign) end
    return true
end

function Gizmo:UpdateDrag(delta: Vector2)
    local drag = self.Drag
    if not drag then return end

    -- Locked mouse position does not move. Convert InputObject.Delta's
    -- XY components to Vector2 before projecting onto the screen axis.
    drag.PixelTravel += delta:Dot(drag.ScreenDirection)

    local steps = math.floor(drag.PixelTravel / drag.PixelsPerUnit + 0.5)
    local size = nextSize(self.Mode, drag.StartSize, drag.Axis, steps)

    if not size or not Grid.ValidSize(self.TemplateSize, size, self.Mode) then
        return
    end

    local dragged = drag.StartCF + drag.Direction * (steps * Grid.Unit / 2)
    -- Diameter and uniform scale can resize two or three axes at once.
    -- Keep every resulting center on the proper half-Unit grid parity, or
    -- the server correctly rejects an otherwise valid-looking face drag.
    local rotation = drag.StartCF.Rotation
    local position = Grid.SnapCenter(dragged.Position, size, rotation)
    local cf = CFrame.new(position) * rotation
    self.CFrame = cf
    self.Size = size
    self.OnChange(cf, size)
end

function Gizmo:FinishDrag()
    local drag = self.Drag
    if not drag then return end

    self.Drag = nil

    local changed = (self.CFrame.Position - drag.StartCF.Position).Magnitude > 0.0001
        or (self.Size - drag.StartSize).Magnitude > 0.0001
    if not changed then return end

    local accepted = self.OnCommit(self.CFrame, self.Size, drag.StartCF, drag.StartSize)
    if not accepted then
        self.CFrame = drag.StartCF
        self.Size = drag.StartSize
        self.OnChange(self.CFrame, self.Size)
    end
end

function Gizmo:Destroy()
    self:Close()
    for _, connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    for _, handle in ipairs(self.Handles) do
        handle.Object:Destroy()
    end
    table.clear(self.Handles)
    table.clear(self.Connections)
end

return Gizmo
