--!strict
-- Physical rotation rings backed by the archived FORM ring appearance.
-- Crosshair ray intersects the selected axis plane; ring dragging snaps
-- in quarter turns and commits ONE existing Update/ComponentTransform.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Grid = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))
local Geometry = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("ComponentGeometry"))
local PreviewFeedback = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("PreviewFeedback"))
local PhysicalHandles = require(script.Parent:WaitForChild("PhysicalHandles"))

local Rotate = {}
Rotate.__index = Rotate
local AXES = { "x", "y", "z" }

local function radialPoint(camera, pivot, normal)
    local view = camera.ViewportSize / 2
    local ray = camera:ViewportPointToRay(view.X, view.Y)
    local den = normal:Dot(ray.Direction)
    if math.abs(den) < 0.002 then return nil end
    local t = normal:Dot(pivot - ray.Origin) / den
    if t < 0 or t > 4096 then return nil end
    local radial = ray.Origin + ray.Direction * t - pivot
    if radial.Magnitude < 0.04 then return nil end
    return radial.Unit
end

local function stepCopy(s)
    return { x = s.x, y = s.y, z = s.z }
end

function Rotate.new(controller)
    return setmetatable({
        Parent = controller,
        Visual = PhysicalHandles.new("Rotate"),
        Connections = {},
        Drag = nil,
    }, Rotate)
end

function Rotate:IsAvailable()
    local c = self.Parent
    return c.Mode == "Edit" and not c.Pending and not c.CatalogOpen
        and not c.ScaleMode and not c.Busy
        and (c.Selected or c.SelectedComponentId)
        and not (c.Layered and c.Layered.Alignment)
end

function Rotate:Update()
    if self.Drag then
        if self.Parent.Mode ~= "Edit" then self:Cancel() return end
        self:UpdateDrag()
        self.Visual:Update(self.Drag.Pivot, self.Drag.Bounds)
        return
    end
    if not self:IsAvailable() then
        for _, grip in ipairs(self.Visual.Grips) do
            for _, segment in ipairs(grip.Segments) do segment.Transparency = 1 end
        end
        self.Visual.Selected = nil
        self.Visual.SelectedDistance = math.huge
        return
    end
    local c = self.Parent
    local pivot = if c.GroupAnchor then c.GroupAnchor:GetPivot()
        else c.Selected:GetPivot()
    local size = c.CurrentSize
    if c.SelectedComponentId then
        local _, bounds = Geometry.Bounds(c.SelectedParts)
        size = bounds or size
    end
    self.Visual:Update(pivot, size or Vector3.one)
end

function Rotate:BeginDrag()
    if not self:IsAvailable() then return false end
    self:Update()
    local grip = self.Visual:Pick()
    if not grip then return false end
    local move = self.Parent.MoveHandles
    if move and move.Visual:Pick()
        and move.Visual.SelectedDistance < self.Visual.SelectedDistance then
        return false
    end

    local c = self.Parent
    local camera = workspace.CurrentCamera
    local pivot = if c.GroupAnchor then c.GroupAnchor:GetPivot()
        else c.Selected:GetPivot()
    if not camera then return false end
    local axis = grip.RingAxis
    local radial = radialPoint(camera, pivot.Position, axis)
    if not radial then return false end
    local bounds = c.CurrentSize
    if c.SelectedComponentId then
        local _, size = Geometry.Bounds(c.SelectedParts)
        bounds = size or bounds
    end
    c:StartMove(false)
    if not c.Preview then return false end

    c.GizmoMoving = true
    self.Drag = {
        Pivot = pivot,
        Bounds = bounds or Vector3.one,
        Axis = axis,
        AxisName = AXES[grip.Axis],
        InitialRadial = radial,
        Steps = stepCopy(c.Steps),
        LastTurns = 0,
    }
    c.IgnoreClickUntil = os.clock() + 0.2
    c:Message("Rotate ring: move/look; release to confirm")
    return true
end

function Rotate:UpdateDrag()
    local d = self.Drag
    if not d then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local radial = radialPoint(camera, d.Pivot.Position, d.Axis)
    if not radial then return end
    local angle = math.atan2(d.Axis:Dot(d.InitialRadial:Cross(radial)),
        d.InitialRadial:Dot(radial))
    local turns = math.clamp(math.round(angle / (math.pi/2)), -2, 2)
    if turns == d.LastTurns then return end
    local c = self.Parent
    if not c.Preview then return end

    local steps = stepCopy(d.Steps)
    steps[d.AxisName] = (steps[d.AxisName] + turns) % 4
    local nextCF = CFrame.new(d.Pivot.Position) * Grid.Rotation(steps)
    c.Steps = steps
    c.Preview:PivotTo(nextCF)
    c.PreviewCF = nextCF
    d.LastTurns = turns

    local ignore = {}
    if c.SelectedComponentId then
        for _, part in ipairs(c.SelectedParts) do ignore[part] = true end
    elseif c.Selected then
        ignore[c.Selected] = true
    end
    c.PreviewValid, c.PreviewReason = PreviewFeedback.Check(c.Preview, ignore)
    PreviewFeedback.Paint(c.Preview, c.PreviewValid)
end

function Rotate:Cancel()
    if not self.Drag then return end
    local d = self.Drag
    self.Drag = nil
    local c = self.Parent
    c.Steps = stepCopy(d.Steps)
    c.GizmoMoving = false
    c:CancelPending()
end

function Rotate:FinishDrag()
    if not self.Drag then return end
    local d = self.Drag
    self.Drag = nil
    local c = self.Parent
    c.GizmoMoving = false
    if d.LastTurns == 0 or not c.PreviewValid then
        c.Steps = stepCopy(d.Steps)
        if not c.PreviewValid then
            c:Message(c.PreviewReason or "Red preview: rotation blocked")
        end
        c:CancelPending()
        return
    end
    if c.SelectedComponentId then c:ConfirmComponentPlacement()
    else c:ConfirmMove() end
end

function Rotate:Start()
    table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:BeginDrag()
        end
    end))
    table.insert(self.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:FinishDrag()
        end
    end))
    table.insert(self.Connections, RunService.RenderStepped:Connect(function()
        self:Update()
    end))
end

function Rotate:Destroy()
    self:Cancel()
    for _, conn in ipairs(self.Connections) do conn:Disconnect() end
    self.Visual:Destroy()
    table.clear(self.Connections)
end

return Rotate
