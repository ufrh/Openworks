local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local Openworks = ReplicatedStorage:WaitForChild('Openworks')
local FORMMaterial = require(Openworks:WaitForChild('FORMMaterial'))

-- Physics interaction must boot independently from machining geometry modules.

local remote = Instance.new('RemoteEvent')
remote.Name = 'PhysicalInteraction'
remote.Parent = Openworks

local active = {}
local locked = {}

local function finite(n)
    return type(n) == 'number' and n == n and math.abs(n) < 1e6
end

local function validVector(v)
    return typeof(v) == 'Vector3' and finite(v.X) and finite(v.Y) and finite(v.Z)
end

local function validRotation(cf)
    if typeof(cf) ~= 'CFrame' or cf.Position.Magnitude > 0.01 then
        return false
    end
    for _, n in {cf:GetComponents()} do
        if not finite(n) then return false end
    end
    return true
end

local function rootOf(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass('Humanoid')
    if not humanoid or humanoid.Health <= 0 then return nil end
    return character:FindFirstChild('HumanoidRootPart')
end

local function classify(part)
    local node = part
    while node and node ~= workspace do
        if node:IsA('Model') or node:IsA('BasePart') then
            if node:GetAttribute('isTool') == true then return node, 'Tool' end
            if FORMMaterial.isMarked(node) then return node, 'Material' end
        end
        node = node.Parent
    end
end

local function findPart(item)
    if item:IsA('BasePart') then return item end
    if not item:IsA('Model') then return nil end
    if item.PrimaryPart then return item.PrimaryPart end
    return item:FindFirstChildWhichIsA('BasePart', true)
end

local function movable(item)
    if not item or not item:IsDescendantOf(workspace) then return false end
    if item:IsA('BasePart') then return not item.Anchored end
    if not item:IsA('Model') then return false end
    local parts = 0
    for _, node in item:GetDescendants() do
        if node:IsA('BasePart') then
            if node.Anchored then return false end
            parts += 1
        end
    end
    return parts > 0
end

local function toolKind(item)
    local explicit = item:GetAttribute('FabricationKind')
    if explicit == 'Saw' or explicit == 'File' then return explicit end
    local name = item.Name:lower()
    if name:find('saw', 1, true) then return 'Saw' end
    if name:find('file', 1, true) then return 'File' end
end

local function contactMarker(item, name)
    local marker = item:FindFirstChild(name, true)
    if marker and marker:IsA('Attachment') then
        return marker
    end
end

local function setToolCollision(item, state)
    state.collisions = {}
    if item:IsA('BasePart') then
        state.collisions[item] = item.CanCollide
        item.CanCollide = false
        return
    end
    for _, node in item:GetDescendants() do
        if node:IsA('BasePart') then
            state.collisions[node] = node.CanCollide
            node.CanCollide = false
        end
    end
end

local function makeMotor(part, hit)
    local target = Instance.new('Part')
    target.Name = 'OpenworksInteractionTarget'
    target.Size = Vector3.new(0.12, 0.12, 0.12)
    target.CFrame = CFrame.new(hit) * part.CFrame.Rotation
    target.Transparency = 1
    target.Anchored = true
    target.CanCollide = false
    target.CanTouch = false
    target.CanQuery = false
    target.Parent = workspace

    local grab = Instance.new('Attachment')
    grab.Name = 'OpenworksGrab'
    grab.Position = part.CFrame:PointToObjectSpace(hit)
    grab.Parent = part

    local destination = Instance.new('Attachment')
    destination.Parent = target

    local position = Instance.new('AlignPosition')
    position.Name = 'OpenworksPosition'
    position.Mode = Enum.PositionAlignmentMode.TwoAttachment
    position.Attachment0 = grab
    position.Attachment1 = destination
    position.MaxForce = math.clamp(part.AssemblyMass * 22000, 40000, 400000)
    position.MaxVelocity = 42
    position.Responsiveness = 25
    position.RigidityEnabled = false
    position.ApplyAtCenterOfMass = false
    position.Parent = part

    local rotation = Instance.new('AlignOrientation')
    rotation.Name = 'OpenworksRotation'
    rotation.Mode = Enum.OrientationAlignmentMode.TwoAttachment
    rotation.Attachment0 = grab
    rotation.Attachment1 = destination
    rotation.MaxTorque = math.clamp(part.AssemblyMass * 100000, 30000, 400000)
    rotation.MaxAngularVelocity = 15
    rotation.Responsiveness = 20
    rotation.RigidityEnabled = false
    rotation.Parent = part

    return {
        part = part, target = target, grab = grab, destination = destination,
        position = position, rotation = rotation, lastMove = 0, lastInput = os.clock(),
    }
end

local function destroyMotor(state)
    for _, key in {'position', 'rotation', 'grab', 'destination', 'target'} do
        if state[key] then state[key]:Destroy() end
    end
    if state.part and state.part.Parent then
        local ok, allowed = pcall(function() return state.part:CanSetNetworkOwnership() end)
        if ok and allowed then
            pcall(function() state.part:SetNetworkOwnershipAuto() end)
        end
    end
end

local function finish(player)
    local state = active[player]
    if not state then return end
    active[player] = nil
    locked[state.item] = nil
    if state.material then locked[state.material] = nil end
    if state.collisions then
        for part, wasCollidable in state.collisions do
            if part.Parent then part.CanCollide = wasCollidable end
        end
    end
    destroyMotor(state)
    if player.Parent then remote:FireClient(player, 'Ended') end
end

local function acquire(player, item, part, hit)
    if locked[item] then return nil, 'Object is already being used' end
    if not movable(item) then return nil, 'Assembly has anchored parts; unanchor the tool or material' end
    local root = rootOf(player)
    if not root then return nil, 'Character is not ready' end
    if (hit - root.Position).Magnitude > 22 then return nil, 'Move closer before grabbing' end
    local ok, allowed = pcall(function() return part:CanSetNetworkOwnership() end)
    if not ok or not allowed then return nil, 'Assembly cannot be physically moved; check anchored weld connections' end
    local state = makeMotor(part, hit)
    local success = pcall(function() part:SetNetworkOwner(player) end)
    if not success then
        destroyMotor(state)
        return nil, 'Failed to assign physics ownership'
    end
    state.item = item
    active[player] = state
    locked[item] = player
    return state
end

local function startDrag(player, part, hit)
    finish(player)

    local function reject(message)
        remote:FireClient(player, 'DragDenied', message)
    end

    if typeof(part) ~= 'Instance' or not part:IsA('BasePart') or not validVector(hit) then
        reject('Invalid object selection')
        return
    end

    local item = classify(part)
    if not item then
        reject('Object is not tagged as a tool or FORM material')
        return
    end

    local localHit = part.CFrame:PointToObjectSpace(hit)
    local half = part.Size * 0.5 + Vector3.new(0.7, 0.7, 0.7)
    if math.abs(localHit.X) > half.X or math.abs(localHit.Y) > half.Y or math.abs(localHit.Z) > half.Z then
        reject('Grab point falls outside the selected part')
        return
    end

    local state, reason = acquire(player, item, part, hit)
    if not state then
        reject(reason or 'Unable to grab object')
        return
    end

    state.mode = 'Drag'
    remote:FireClient(player, 'DragStarted', part, hit)
end

local function startFabrication(player, material, tool)
    finish(player)
    if typeof(material) ~= 'Instance' or typeof(tool) ~= 'Instance' then return end
    if not (material:IsA('Model') or material:IsA('BasePart')) then return end
    if not (tool:IsA('Model') or tool:IsA('BasePart')) then return end
    if not FORMMaterial.isMarked(material) or tool:GetAttribute('isTool') ~= true then return end
    if material:GetAttribute('OnWorkbench') ~= true or tool:GetAttribute('OnWorkbench') ~= true then
        remote:FireClient(player, 'Feedback', 'Both material and tool must rest on the workbench')
        return
    end
    local kind = toolKind(tool)
    local work = findPart(material)
    local part = findPart(tool)
    local root = rootOf(player)
    if not kind then
        remote:FireClient(player, 'Feedback', 'Set FabricationKind to Saw or File on this tool')
        return
    end
    if not work or not part or not root or not movable(tool) or locked[material] then
        remote:FireClient(player, 'Feedback', 'Material or tool is not available')
        return
    end
    if (root.Position - work.Position).Magnitude > 24 or (root.Position - part.Position).Magnitude > 24 then
        remote:FireClient(player, 'Feedback', 'Move closer to the workbench')
        return
    end

    local state = acquire(player, tool, part, part.Position)
    if not state then
        remote:FireClient(player, 'Feedback', 'Tool is busy or cannot be moved')
        return
    end

    state.mode = 'Fabrication'
    state.kind = kind
    state.material = material
    state.work = work

    local marker = contactMarker(tool, if kind == 'Saw' then 'BladeEdge' else 'FileFace')
    state.grab.CFrame = if marker then part.CFrame:ToObjectSpace(marker.WorldCFrame)
        else CFrame.new(0, -part.Size.Y * 0.5, 0)
    state.target.CFrame = part.CFrame * state.grab.CFrame

    setToolCollision(tool, state)
    state.offset = 0
    state.stroke = 0
    state.lastStroke = 0
    state.direction = 0
    state.reversals = 0
    state.axis = 'X'
    locked[material] = player
    remote:FireClient(player, 'FabricationStarted', kind, material, tool)
end

local function cutSheet(state)
    local work = state.work
    if not work or not work.Parent or not work:IsA('Part') or work.Shape ~= Enum.PartType.Block
        or work:GetAttribute('FORMNativeStock') ~= true then
        return nil, 'Machining this material needs a FORM render adapter'
    end

    local kind = state.kind
    if kind == 'File' then
        local shave = math.min(0.025, work.Size.Y * 0.12)
        if work.Size.Y - shave < 0.06 then return nil, 'Sheet is too thin to file further' end
        work.Size -= Vector3.new(0, shave, 0)
        work.CFrame *= CFrame.new(0, -shave * 0.5, 0)
        work:SetAttribute('FilePasses', (work:GetAttribute('FilePasses') or 0) + 1)
        return work, 'Filed a thin surface layer'
    end

    local FORM = require(Openworks:WaitForChild('FORM'))
    local Stock = require(Openworks:WaitForChild('Stock'))
    local SawCut = require(Openworks:WaitForChild('SawCut'))

    local oldCF = work.CFrame
    local oldSize = work.Size
    local dimensions = oldSize / Stock.SCALE
    local item = Stock.create(1, 'Block', 'Steel',
        {x = dimensions.X, y = dimensions.Y, z = dimensions.Z}, oldCF)
    local normal = if state.axis == 'X' then oldCF.RightVector else oldCF.LookVector
    local point = oldCF:PointToWorldSpace(if state.axis == 'X'
        then Vector3.new(state.offset, 0, 0) else Vector3.new(0, 0, state.offset))

    local ok, fragments, summary = pcall(SawCut.split, item, point, normal)
    if not ok or not fragments then return nil, tostring(if ok then summary else fragments) end

    local output = {}
    for _, solid in fragments do
        local low, high = FORM.bounds(solid)
        local size = (high - low) * Stock.SCALE
        if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then return nil, 'Invalid fragment bounds' end
        local part = Instance.new('Part')
        part.Name = work.Name .. ' - Offcut'
        part.Size = size
        part.CFrame = oldCF * CFrame.new((low + high) * 0.5 * Stock.SCALE)
        part.Material = work.Material
        part.Color = work.Color
        part.CustomPhysicalProperties = work.CustomPhysicalProperties
        part.CanCollide = true
        part.CanQuery = true
        part.Anchored = false
        part:SetAttribute('FORMNativeStock', true)
        FORMMaterial.mark(part)
        table.insert(output, part)
    end

    local velocity = work.AssemblyLinearVelocity
    local angular = work.AssemblyAngularVelocity
    for _, part in output do
        part.Parent = work.Parent
        part.AssemblyAngularVelocity = angular
        part.AssemblyLinearVelocity = velocity + angular:Cross(part.Position - work.Position)
    end
    work:Destroy()
    return output[1], 'FORM saw cut completed'
end

local function moveFabrication(player, state, stroke, offset, axis)
    if not finite(stroke) or not finite(offset) or (axis ~= 'X' and axis ~= 'Z') then return end
    local work = state.work
    local root = rootOf(player)
    if not root or not work or not work.Parent or not movable(state.item) then
        finish(player)
        return
    end

    local now = os.clock()
    if now - state.lastMove < 1 / 40 then return end
    state.lastMove = now
    state.lastInput = now

    local size = work.Size
    local span = if axis == 'X' then size.X else size.Z
    local maximum = math.max(0, span * 0.5 - 0.17)
    state.axis = axis
    state.offset = math.clamp(offset, -maximum, maximum)
    stroke = math.clamp(stroke, -1, 1)

    local travel = if axis == 'X' then Vector3.new(0, 0, stroke * 0.9)
        else Vector3.new(stroke * 0.9, 0, 0)
    local cross = if axis == 'X' then Vector3.new(state.offset, 0, 0)
        else Vector3.new(0, 0, state.offset)
    local pos = work.CFrame:PointToWorldSpace(cross + travel
        + Vector3.new(0, size.Y * 0.5 + 0.12, 0))
    if (pos - root.Position).Magnitude > 30 then finish(player) return end

    local strokeDirection = if axis == 'X' then work.CFrame.LookVector
        else work.CFrame.RightVector
    local upward = work.CFrame.UpVector
    state.target.CFrame = CFrame.fromMatrix(pos, strokeDirection,
        upward, strokeDirection:Cross(upward))

    local difference = stroke - state.lastStroke
    local direction = if difference > 0.05 then 1 elseif difference < -0.05 then -1 else 0
    if direction ~= 0 and state.direction ~= 0 and state.direction ~= direction
        and math.abs(stroke - state.lastTurn) > 0.28 then
        state.reversals += 1
        state.lastTurn = stroke
        remote:FireClient(player, 'Progress', math.min(1, state.reversals / 12))
    elseif state.direction == 0 and direction ~= 0 then
        state.lastTurn = stroke
    end
    if direction ~= 0 then state.direction = direction end
    state.lastStroke = stroke

    if state.reversals >= 12 then
        local ok, replacement, message = pcall(cutSheet, state)
        if not ok then
            warn('[OPENWORKS:Fabrication]', replacement)
            message = 'Fabrication failed: ' .. tostring(replacement)
            replacement = nil
        end
        finish(player)
        remote:FireClient(player, 'MachiningCompleted', replacement, message)
    end
end

remote.OnServerEvent:Connect(function(player, action, ...)
    if action == 'DragStart' then
        startDrag(player, ...)
        return
    end
    if action == 'FabricationStart' then
        startFabrication(player, ...)
        return
    end

    local state = active[player]
    if not state then return end
    if action == 'End' then
        finish(player)
    elseif action == 'DragMove' and state.mode == 'Drag' then
        local point, rotation = ...
        if not validVector(point) or not validRotation(rotation) then finish(player) return end
        local now = os.clock()
        if now - state.lastMove < 1 / 40 then return end
        state.lastMove = now
        state.lastInput = now
        local root = rootOf(player)
        if not root then finish(player) return end
        local delta = point - root.Position
        if delta.Magnitude > 28 then point = root.Position + delta.Unit * 28 end
        state.target.CFrame = CFrame.new(point) * rotation
    elseif action == 'FabricationMove' and state.mode == 'Fabrication' then
        moveFabrication(player, state, ...)
    end
end)

RunService.Heartbeat:Connect(function()
    for player, state in active do
        local root = rootOf(player)
        if not root or not state.part.Parent
            or (state.part.Position - root.Position).Magnitude > 38
            or os.clock() - state.lastInput > 3 then
            finish(player)
        end
    end
end)

local function watch(player)
    player.CharacterRemoving:Connect(function() finish(player) end)
end
Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do watch(player) end
Players.PlayerRemoving:Connect(function() finish(player) end)

print('[OPENWORKS:Interaction] Server ready')
