local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')

local Grab = {}
Grab.__index = Grab

function Grab.new()
    return setmetatable({active = nil}, Grab)
end

function Grab:release()
    local state = self.active
    if not state then return end
    self.active = nil
    state.connection:Disconnect()
    state.position:Destroy()
    state.orientation:Destroy()
    state.grip:Destroy()
    state.target:Destroy()
end

function Grab:begin(part, hit, mouse)
    self:release()
    if not part or not part:IsA('BasePart') or part.Anchored then return false end
    local camera = workspace.CurrentCamera
    if not camera then return false end

    local distance = math.clamp((hit - camera.CFrame.Position).Magnitude, 2, 80)
    local grip = Instance.new('Attachment')
    grip.Name = 'StockGrip'
    grip.Position = part.CFrame:PointToObjectSpace(hit)
    grip.Parent = part

    local target = Instance.new('Part')
    target.Name = 'StockGrabTarget'
    target.Anchored = true
    target.Transparency = 1
    target.CanCollide = false
    target.CanTouch = false
    target.CanQuery = false
    target.Size = Vector3.one * 0.1
    target.CFrame = CFrame.new(hit) * part.CFrame.Rotation
    target.Parent = workspace

    local goal = Instance.new('Attachment')
    goal.Parent = target

    local position = Instance.new('AlignPosition')
    position.Name = 'StockGrabPosition'
    position.Attachment0 = grip
    position.Attachment1 = goal
    position.Mode = Enum.PositionAlignmentMode.TwoAttachment
    position.MaxForce = 1000000
    position.MaxVelocity = 50
    position.Responsiveness = 35
    position.ReactionForceEnabled = false
    position.ApplyAtCenterOfMass = false
    position.Parent = part

    local orientation = Instance.new('AlignOrientation')
    orientation.Name = 'StockGrabOrientation'
    orientation.Attachment0 = grip
    orientation.Attachment1 = goal
    orientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
    orientation.MaxTorque = 1000000
    orientation.MaxAngularVelocity = 30
    orientation.Responsiveness = 25
    orientation.Parent = part

    local state = {part = part, target = target, grip = grip, position = position,
        orientation = orientation, distance = distance}
    state.connection = RunService.RenderStepped:Connect(function()
        if not part.Parent or part.Anchored or not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            self:release()
            return
        end
        local cameraNow = workspace.CurrentCamera
        if not cameraNow then return end
        local ray = cameraNow:ViewportPointToRay(mouse.X, mouse.Y)
        target.CFrame = CFrame.new(ray.Origin + ray.Direction * state.distance) * target.CFrame.Rotation
    end)
    self.active = state
    return true
end

function Grab:changeDistance(delta)
    if self.active then
        self.active.distance = math.clamp(self.active.distance + delta, 2, 80)
    end
end

return Grab
