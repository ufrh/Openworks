--!strict
-- Axis-constrained first-person movement via the same physical handle kit
-- as resize. Uses moving-camera ray/plane intersection; no pixel deltas.
-- On mouse up the pending ghost is committed as one atomic move.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Grid = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))
local PreviewFeedback = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("PreviewFeedback"))
local PhysicalHandles = require(script.Parent:WaitForChild("PhysicalHandles"))

local Move = {}
Move.__index = Move

local function dragNormal(camera, axis)
    local v = camera.CFrame.LookVector
    local perp = v - axis * v:Dot(axis)
    if perp.Magnitude < 0.03 then
        v = camera.CFrame.UpVector
        perp = v - axis * v:Dot(axis)
    end
    return perp.Unit
end

local function hitPlane(camera, point, normal)
    local viewport = camera.ViewportSize / 2
    local ray = camera:ViewportPointToRay(viewport.X, viewport.Y)
    local den = normal:Dot(ray.Direction)
    if math.abs(den) < 0.001 then return nil end
    local t = normal:Dot(point - ray.Origin) / den
    if t < 0 or t > 4096 then return nil end
    return ray.Origin + ray.Direction * t
end

function Move.new(parent)
    return setmetatable({
        Parent = parent,
        Visual = PhysicalHandles.new("Move"),
        Drag = nil,
        Connections = {},
        LastCheck = 0,
    }, Move)
end

function Move:IsAvailable()
    local c = self.Parent
    return c.Mode == "Edit" and not c.ScaleMode and not c.Pending
        and not c.CatalogOpen and not c.Busy
        and (c.Selected ~= nil or c.SelectedComponentId ~= nil)
        and not (c.Layered and c.Layered.Alignment)
end

function Move:Update()
    local c = self.Parent
    if self.Drag then
        if self.Parent.Mode ~= "Edit" then
            self:Cancel()
            return
        end
        self:UpdateDrag()
        self.Visual:Update(self.Drag.StartPivot, self.Drag.Bounds)
        return
    end
    if not self:IsAvailable() then
        for _, grip in ipairs(self.Visual.Grips) do
            grip.Highlight.Enabled = false
            for _, part in ipairs(grip.Model:GetDescendants()) do
                if part:IsA("BasePart") then part.Transparency = 1 end
            end
        end
        self.Visual.Selected = nil
        return
    end
    local cf = if c.GroupAnchor then c.GroupAnchor:GetPivot()
        elseif c.Selected then c.Selected:GetPivot() else nil
    if not cf then return end
    local size = c.CurrentSize
    if c.SelectedComponentId then
        local ComponentGeometry = require(ReplicatedStorage:WaitForChild("Openworks")
            :WaitForChild("Construction"):WaitForChild("ComponentGeometry"))
        local _, bounds = ComponentGeometry.Bounds(c.SelectedParts)
        size = bounds or size
    end
    self.Visual:Update(cf, size or Vector3.one)
end

function Move:BeginDrag()
    if not self:IsAvailable() then return false end
    self:Update()
    local grip = self.Visual:Pick()
    if not grip then return false end
    local c = self.Parent
    local pivot = if c.GroupAnchor then c.GroupAnchor:GetPivot()
        else c.Selected:GetPivot()
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local direction = grip.Direction
    local normal = dragNormal(camera, direction)
    local startHit = hitPlane(camera, pivot.Position, normal)
    if not startHit then return false end

    local bounds = c.CurrentSize or Vector3.one
    if c.SelectedComponentId then
        local Geometry = require(ReplicatedStorage:WaitForChild("Openworks")
            :WaitForChild("Construction"):WaitForChild("ComponentGeometry"))
        local _, size = Geometry.Bounds(c.SelectedParts)
        bounds = size or bounds
    end

    c:StartMove(false)
    if not c.Pending or not c.Preview then return false end
    c.GizmoMoving = true
    self.Drag = {
        StartPivot = pivot,
        Bounds = bounds,
        Axis = direction,
        Point = pivot.Position,
        Normal = normal,
        Offset = (startHit - pivot.Position):Dot(direction),
        LastMove = 0,
    }
    c:Message("Move grip: drag through world space; release to place")
    return true
end

function Move:UpdateDrag()
    local drag = self.Drag
    if not drag then return end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local hit = hitPlane(camera, drag.Point, drag.Normal)
    if not hit then return end
    local distance = (hit - drag.Point):Dot(drag.Axis) - drag.Offset
    local c = self.Parent
    local step = Grid.Unit * Grid.DefaultSizeStepU
    local snapped = math.round(distance / step) * step
    if math.abs(snapped - drag.LastMove) < 0.00001 then return end
    drag.LastMove = snapped

    local proposed = drag.StartPivot + drag.Axis * snapped
    if not c.Preview then return end
    c.Preview:PivotTo(proposed)
    c.PreviewCF = proposed
    local ignore = {}
    if c.SelectedComponentId then
        for _, part in ipairs(c.SelectedParts) do ignore[part] = true end
    elseif c.Selected then
        ignore[c.Selected] = true
    end
    c.PreviewValid, c.PreviewReason = PreviewFeedback.Check(c.Preview, ignore)
    PreviewFeedback.Paint(c.Preview, c.PreviewValid)
end

function Move:Cancel()
    if not self.Drag then return end
    self.Drag = nil
    local c = self.Parent
    c.GizmoMoving = false
    c:CancelPending()
end

function Move:FinishDrag()
    if not self.Drag then return end
    local c = self.Parent
    local changed = math.abs(self.Drag.LastMove) > 0.00001
    self.Drag = nil
    c.GizmoMoving = false
    if not changed or not c.PreviewValid then
        if not c.PreviewValid then
            c:Message(c.PreviewReason or "Red preview: move blocked")
        end
        c:CancelPending()
        return
    end
    if c.SelectedComponentId then
        c:ConfirmComponentPlacement()
    else
        c:ConfirmMove()
    end
end

function Move:Start()
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

function Move:Destroy()
    self:Cancel()
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    self.Visual:Destroy()
    table.clear(self.Connections)
end

return Move
