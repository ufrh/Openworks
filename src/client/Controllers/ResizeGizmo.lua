--!strict
-- First-person resize gizmo. The mouse NEVER unlocks for scaling.
-- Aim the central crosshair at a real 3D scale cube, hold left mouse,
-- drag using the crosshair ray's intersection with a world-space plane.
-- Camera rotation AND player movement both change the projected world point.
-- One server edit on release.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local PhysicalHandles = require(script.Parent:WaitForChild("PhysicalHandles"))

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

-- A plane through the grabbed face, containing its resize axis.
-- The normal is chosen to face the camera while remaining perpendicular
-- to the resize axis; this avoids the unstable line-to-ray closest-point
-- calculation when the player looks almost directly along the axis.
local function dragPlaneNormal(cameraCF: CFrame, axis: Vector3): Vector3
    local view = cameraCF.LookVector
    local projected = view - axis * view:Dot(axis)
    if projected.Magnitude < 0.05 then
        local up = cameraCF.UpVector
        projected = up - axis * up:Dot(axis)
    end
    if projected.Magnitude < 0.05 then
        local right = cameraCF.RightVector
        projected = right - axis * right:Dot(axis)
    end
    return projected.Unit
end

-- World-space mouse/crosshair intersection. The plane stays fixed during a
-- drag; evaluating the moving first-person camera ray each frame means WASD,
-- jumping and camera rotation all participate in the resize interaction.
local function crosshairPlaneHit(camera: Camera, planePoint: Vector3, planeNormal: Vector3): Vector3?
    local midpoint = camera.ViewportSize * 0.5
    local ray = camera:ViewportPointToRay(midpoint.X, midpoint.Y)
    local denominator = planeNormal:Dot(ray.Direction)
    if math.abs(denominator) < 0.001 then return nil end
    local depth = planeNormal:Dot(planePoint - ray.Origin) / denominator
    if depth < 0 or depth > 4096 then return nil end
    return ray.Origin + ray.Direction * depth
end

local function withAxis(size, axis, value)
    if axis == 1 then return Vector3.new(value, size.Y, size.Z) end
    if axis == 2 then return Vector3.new(size.X, value, size.Z) end
    return Vector3.new(size.X, size.Y, value)
end

local function nextSize(mode, initial, axis, amount, incrementU)
    local delta = amount * Grid.Unit * incrementU
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
        Visual = PhysicalHandles.new("Scale"),
        Connections = {},
        CFrame = CFrame.identity,
        Size = Vector3.one,
        Mode = "None",
        TemplateSize = Vector3.one,
        Active = false,
        Hovered = nil,
        Drag = nil,
        IncrementU = Grid.DefaultSizeStepU,
        FineDiameter = false,
    }, Gizmo)

    table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input)
        if self.Active and not self.Drag
            and input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:BeginDrag()
        end
    end))
    table.insert(self.Connections, UserInputService.InputEnded:Connect(function(input)
        if self.Drag and input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:FinishDrag()
        end
    end))
    table.insert(self.Connections, RunService.RenderStepped:Connect(function()
        if self.Active then
            if self.Drag then self:UpdateDrag() end
            self:UpdateHandles()
        end
    end))
    return self
end

function Gizmo:Open(cf, size, mode, templateSize, incrementU, fineDiameter)
    self.Drag = nil
    self.IncrementU = incrementU or Grid.DefaultSizeStepU
    self.FineDiameter = fineDiameter == true
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

    for _, grip in ipairs(self.Visual.Grips) do
        grip.Highlight.Enabled = false
        for _, item in ipairs(grip.Model:GetDescendants()) do
            if item:IsA("BasePart") then item.Transparency = 1 end
        end
    end
end

function Gizmo:UpdateHandles()
    if not self.Active then return end
    self.Visual:Update(self.CFrame, self.Size, function(axis)
        return canUse(self.Mode, axis)
    end)
    self.Hovered = if self.Drag then self.Drag.Handle else self.Visual:Pick()
end

function Gizmo:BeginDrag()
    if not self.Active or self.Drag then return false end
    self:UpdateHandles()
    local handle = self.Hovered
    if not handle or not handle.Visible then return false end
    local camera = workspace.CurrentCamera
    if not camera then return false end

    local outward = self.CFrame:VectorToWorldSpace(AXES[handle.Axis] * handle.Sign)
    local startFace = self.CFrame.Position
        + outward * self.Size[AXIS_NAMES[handle.Axis]] / 2
    local planeNormal = dragPlaneNormal(camera.CFrame, outward)
    local startHit = crosshairPlaneHit(camera, startFace, planeNormal)
    if not startHit then return false end

    self.Drag = {
        Handle = handle,
        StartCF = self.CFrame,
        StartSize = self.Size,
        Axis = handle.Axis,
        Direction = outward,
        PlanePoint = startFace,
        PlaneNormal = planeNormal,
        StartAxisCoordinate = (startHit - startFace):Dot(outward),
        LastSteps = 0,
        StepU = self.IncrementU,
    }

    -- Never freeze the camera. Moving or looking around changes the world
    -- intersection and therefore the resize, even without MouseMovement.
    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
    if self.OnDragStarted then self.OnDragStarted(handle.Axis, handle.Sign) end
    return true
end

function Gizmo:UpdateDrag()
    local drag = self.Drag
    if not drag then return end
    local camera = workspace.CurrentCamera
    if not camera then return end

    local hit = crosshairPlaneHit(camera, drag.PlanePoint, drag.PlaneNormal)
    if not hit then return end

    local axisCoordinate = (hit - drag.PlanePoint):Dot(drag.Direction)
    local distance = axisCoordinate - drag.StartAxisCoordinate
    local steps = math.floor(distance / (Grid.Unit * drag.StepU) + 0.5)

    if steps == drag.LastSteps then return end

    local size = nextSize(self.Mode, drag.StartSize, drag.Axis, steps, drag.StepU)
    if not size or not Grid.ValidSize(self.TemplateSize, size,
        self.Mode, self.FineDiameter) then
        return
    end

    -- The grabbed face moves along its world-space outward axis while the
    -- opposite face remains anchored. The grid function only resolves
    -- center parity; no pixel scaling or camera locking is involved.
    local shifted = drag.StartCF.Position
        + drag.Direction * (steps * Grid.Unit * drag.StepU / 2)
    local rotation = drag.StartCF.Rotation
    -- Preserve the opposite face exactly. The server validates dimensions
    -- and interference, not arbitrary center-grid parity.
    local cf = CFrame.new(shifted) * rotation

    drag.LastSteps = steps
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
    self.Visual:Destroy()
    table.clear(self.Connections)
end

return Gizmo
