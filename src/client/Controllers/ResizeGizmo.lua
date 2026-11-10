--!strict
-- Mouse-driven face resize gizmo for Build previews and Edit selections.
-- Screen-projected grips, opposing face anchored, 1 U steps, one server request
-- on mouse release (the caller owns the authoritative commit).

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Grid = require(
    game:GetService("ReplicatedStorage"):WaitForChild("Openworks")
        :WaitForChild("Construction"):WaitForChild("GridMath")
)

local Gizmo = {}
Gizmo.__index = Gizmo

local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
local COLORS = {
    Color3.fromRGB(224, 106, 100),
    Color3.fromRGB(113, 202, 137),
    Color3.fromRGB(115, 164, 245),
}

local function withAxis(size, axis, value)
    if axis == 1 then return Vector3.new(value, size.Y, size.Z) end
    if axis == 2 then return Vector3.new(size.X, value, size.Z) end
    return Vector3.new(size.X, size.Y, value)
end

local function nextSize(mode, initial, axis, amount)
    local delta = amount * Grid.Unit
    if mode == "XYZ_1U" then
        return withAxis(initial, axis, initial[({ "X", "Y", "Z" })[axis]] + delta)
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

function Gizmo.new(gui, onChange, onCommit)
    local self = setmetatable({
        Gui = gui,
        OnChange = onChange,
        OnCommit = onCommit,
        Handles = {},
        Connections = {},
        CFrame = CFrame.identity,
        Size = Vector3.one,
        Mode = "None",
        TemplateSize = Vector3.one,
        Active = false,
        Drag = nil,
    }, Gizmo)

    for axis = 1, 3 do
        for _, sign in ipairs({ -1, 1 }) do
            local grip = Instance.new("TextButton")
            grip.Name = "Scale_" .. ({ "X", "Y", "Z" })[axis] .. (if sign == 1 then "Plus" else "Minus")
            grip.AnchorPoint = Vector2.new(0.5, 0.5)
            grip.Size = UDim2.fromOffset(32, 32)
            grip.BorderSizePixel = 0
            grip.BackgroundColor3 = COLORS[axis]
            grip.BackgroundTransparency = 0.1
            grip.Font = Enum.Font.GothamBold
            grip.Text = ({ "X", "Y", "Z" })[axis] .. (if sign == 1 then "+" else "-")
            grip.TextSize = 12
            grip.TextColor3 = Color3.new(1, 1, 1)
            grip.AutoButtonColor = true
            grip.ZIndex = 40
            grip.Visible = false
            grip.Parent = gui

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = grip

            local outline = Instance.new("UIStroke")
            outline.Color = Color3.fromRGB(238, 245, 255)
            outline.Transparency = 0.2
            outline.Thickness = 1
            outline.Parent = grip

            table.insert(self.Connections, grip.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    self:BeginDrag(axis, sign)
                end
            end))
            table.insert(self.Handles, { Axis = axis, Sign = sign, Object = grip })
        end
    end

    table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input)
        if self.Drag and input.UserInputType == Enum.UserInputType.MouseMovement then
            self:UpdateDrag()
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
    for _, handle in ipairs(self.Handles) do
        handle.Object.Visible = false
    end
end

function Gizmo:UpdateHandles()
    local camera = workspace.CurrentCamera
    if not camera then return end
    for _, handle in ipairs(self.Handles) do
        local axis, sign = handle.Axis, handle.Sign
        local usable = self.Mode ~= "None"
            and (self.Mode ~= "LengthOnly_1U" or axis == 1)
            and (self.Mode ~= "UniformDiameter_1U" or axis == 1)
            and (self.Mode ~= "LengthAndDiameter_1U" or axis ~= 3)

        local grip = handle.Object
        if not usable then
            grip.Visible = false
            continue
        end

        local dir = self.CFrame:VectorToWorldSpace(AXES[axis] * sign)
        local face = self.CFrame.Position + dir * self.Size[({ "X", "Y", "Z" })[axis]] / 2
        local origin, visible = camera:WorldToViewportPoint(face)
        local beyond = camera:WorldToViewportPoint(face + dir)

        local direction = Vector2.new(beyond.X - origin.X, beyond.Y - origin.Y)
        if direction.Magnitude < 0.5 then
            -- Face-on axes project to a point. Fan those handles outward.
            local angle = axis * math.pi * 2 / 3
            direction = Vector2.new(math.cos(angle), math.sin(angle)) * sign
        end

        direction = direction.Unit
        local screen = Vector2.new(origin.X, origin.Y) + direction * 30
        grip.Position = UDim2.fromOffset(screen.X, screen.Y)
        grip.Visible = visible
    end
end

function Gizmo:BeginDrag(axis, sign)
    if not self.Active or self.Drag then return end
    local camera = workspace.CurrentCamera
    if not camera then return end

    local direction = self.CFrame:VectorToWorldSpace(AXES[axis] * sign)
    local face = self.CFrame.Position
        + direction * self.Size[({ "X", "Y", "Z" })[axis]] / 2
    local projected = camera:WorldToViewportPoint(face)
    local projectedNext = camera:WorldToViewportPoint(face + direction)
    local projectedAxis = Vector2.new(
        projectedNext.X - projected.X,
        projectedNext.Y - projected.Y
    )

    if projectedAxis.Magnitude < 0.5 then
        projectedAxis = Vector2.new(0, -1)
    end

    self.Drag = {
        StartMouse = UserInputService:GetMouseLocation(),
        StartCF = self.CFrame,
        StartSize = self.Size,
        Axis = axis,
        Direction = direction,
        ScreenDirection = projectedAxis.Unit,
        PixelsPerUnit = math.max(9, projectedAxis.Magnitude * Grid.Unit),
    }
end

function Gizmo:UpdateDrag()
    local drag = self.Drag
    if not drag then return end

    local delta = UserInputService:GetMouseLocation() - drag.StartMouse
    local steps = math.floor(delta:Dot(drag.ScreenDirection) / drag.PixelsPerUnit + 0.5)
    local size = nextSize(self.Mode, drag.StartSize, drag.Axis, steps)

    if not size or not Grid.ValidSize(self.TemplateSize, size, self.Mode) then
        return
    end

    local cf = drag.StartCF + drag.Direction * (steps * Grid.Unit / 2)
    self.CFrame = cf
    self.Size = size
    self.OnChange(cf, size)
end

function Gizmo:FinishDrag()
    local drag = self.Drag
    if not drag then return end

    self.Drag = nil
    local moved = (self.CFrame.Position - drag.StartCF.Position).Magnitude > 0.0001
        or (self.Size - drag.StartSize).Magnitude > 0.0001
    if not moved then return end

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
