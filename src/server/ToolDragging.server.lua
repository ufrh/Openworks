local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local openworks = ReplicatedStorage:WaitForChild('Openworks')
local remote = Instance.new('RemoteEvent')
remote.Name = 'ToolDrag'
remote.Parent = openworks

local held = {}
local owners = {}

local function finite(n)
    return type(n) == 'number' and n == n and math.abs(n) < 1e7
end

local function validVector(v)
    return typeof(v) == 'Vector3' and finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function validRotation(v)
    if typeof(v) ~= 'CFrame' or v.Position.Magnitude > 0.001 then
        return false
    end

    for _, n in {v:GetComponents()} do
        if not finite(n) then
            return false
        end
    end

    return true
end

local function playerRoot(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass('Humanoid')
    if not humanoid or humanoid.Health <= 0 then
        return nil
    end

    return character:FindFirstChild('HumanoidRootPart')
end

local function toolItem(part)
    local current = part
    while current and current ~= workspace do
        if (current:IsA('Model') or current:IsA('BasePart'))
            and current:GetAttribute('isTool') == true then
            return current
        end
        current = current.Parent
    end
end

local function eligible(item, part)
    if not item or not item:IsDescendantOf(workspace) then
        return false
    end

    if not part:IsA('BasePart') or not part:IsDescendantOf(item) and part ~= item then
        return false
    end

    if item:IsA('BasePart') then
        return not item.Anchored
    end

    for _, object in item:GetDescendants() do
        if object:IsA('BasePart') and object.Anchored then
            return false
        end
    end

    return true
end

local function release(player)
    local state = held[player]
    if not state then
        return
    end

    held[player] = nil
    owners[state.item] = nil

    if state.part.Parent then
        local ok, canSet = pcall(function()
            return state.part:CanSetNetworkOwnership()
        end)
        if ok and canSet then
            pcall(function()
                state.part:SetNetworkOwnershipAuto()
            end)
        end
    end

    state.position:Destroy()
    state.orientation:Destroy()
    state.attachment:Destroy()
    state.target:Destroy()

    if player.Parent then
        remote:FireClient(player, 'Ended')
    end
end

local function start(player, part, hit)
    release(player)

    if typeof(part) ~= 'Instance' or not part:IsA('BasePart') or not validVector(hit) then
        return
    end

    local item = toolItem(part)
    local root = playerRoot(player)

    if not root or not eligible(item, part) or owners[item] then
        return
    end

    if (hit - root.Position).Magnitude > 22 then
        return
    end

    local localPoint = part.CFrame:PointToObjectSpace(hit)
    local half = part.Size * 0.5 + Vector3.new(0.7, 0.7, 0.7)

    if math.abs(localPoint.X) > half.X or math.abs(localPoint.Y) > half.Y
        or math.abs(localPoint.Z) > half.Z then
        return
    end

    local allowed, canSet = pcall(function()
        return part:CanSetNetworkOwnership()
    end)
    if not allowed or not canSet then
        warn('[OPENWORKS:Drag] Unable to move tool assembly:', item.Name)
        return
    end

    local target = Instance.new('Part')
    target.Name = 'OpenworksDragTarget'
    target.Size = Vector3.new(0.1, 0.1, 0.1)
    target.CFrame = CFrame.new(hit) * part.CFrame.Rotation
    target.Transparency = 1
    target.Anchored = true
    target.CanCollide = false
    target.CanQuery = false
    target.CanTouch = false
    target.Parent = workspace

    local attachment = Instance.new('Attachment')
    attachment.Name = 'OpenworksGrabPoint'
    attachment.Position = localPoint
    attachment.Parent = part

    local goalAttachment = Instance.new('Attachment')
    goalAttachment.Parent = target

    local mass = part.AssemblyMass

    local position = Instance.new('AlignPosition')
    position.Name = 'OpenworksDragPosition'
    position.Mode = Enum.PositionAlignmentMode.TwoAttachment
    position.Attachment0 = attachment
    position.Attachment1 = goalAttachment
    position.MaxForce = math.clamp(mass * 22000, 40000, 400000)
    position.MaxVelocity = 45
    position.Responsiveness = 25
    position.RigidityEnabled = false
    position.ApplyAtCenterOfMass = false
    position.Parent = part

    local orientation = Instance.new('AlignOrientation')
    orientation.Name = 'OpenworksDragOrientation'
    orientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
    orientation.Attachment0 = attachment
    orientation.Attachment1 = goalAttachment
    orientation.MaxTorque = math.clamp(mass * 100000, 30000, 400000)
    orientation.MaxAngularVelocity = 15
    orientation.Responsiveness = 20
    orientation.RigidityEnabled = false
    orientation.Parent = part

    local success = pcall(function()
        part:SetNetworkOwner(player)
    end)
    if not success then
        position:Destroy()
        orientation:Destroy()
        attachment:Destroy()
        target:Destroy()
        return
    end

    held[player] = {
        item = item,
        part = part,
        target = target,
        attachment = attachment,
        position = position,
        orientation = orientation,
        lastMove = 0,
        lastInput = os.clock(),
    }
    owners[item] = player
    remote:FireClient(player, 'Started', part, hit)
end

remote.OnServerEvent:Connect(function(player, action, ...)
    if action == 'Start' then
        start(player, ...)
        return
    end

    local state = held[player]
    if not state then
        return
    end

    if action == 'End' then
        release(player)
        return
    end

    if action ~= 'Move' then
        return
    end

    local point, rotation = ...
    if not validVector(point) or not validRotation(rotation) then
        release(player)
        return
    end

    local now = os.clock()
    if now - state.lastMove < 1 / 35 then
        return
    end
    state.lastMove = now
    state.lastInput = now

    local root = playerRoot(player)
    if not root or not eligible(state.item, state.part) then
        release(player)
        return
    end

    local delta = point - root.Position
    if delta.Magnitude > 28 then
        point = root.Position + delta.Unit * 28
    end

    state.target.CFrame = CFrame.new(point) * rotation
end)

RunService.Heartbeat:Connect(function()
    for player, state in held do
        local root = playerRoot(player)
        if not root or not state.item.Parent or os.clock() - state.lastInput > 1.5
            or (state.part.Position - root.Position).Magnitude > 36 then
            release(player)
        end
    end
end)

local function watchPlayer(player)
    player.CharacterRemoving:Connect(function()
        release(player)
    end)
end

Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
    watchPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
    release(player)
end)
