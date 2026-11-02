local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local Openworks = ReplicatedStorage:WaitForChild('Openworks')

local remote = Openworks:FindFirstChild('PhysicalInteraction')
if not remote or not remote:IsA('RemoteEvent') then
    remote = Instance.new('RemoteEvent')
    remote.Name = 'PhysicalInteraction'
    remote.Parent = Openworks
end

remote:SetAttribute('Ready', false)

local onRequest
remote.OnServerEvent:Connect(function(player, action, ...)
    if not onRequest then return end

    local ok, reason = pcall(onRequest, player, action, ...)
    if not ok then
        warn('[OPENWORKS:Interaction] Request failed:', action, reason)
        remote:FireClient(player, 'Feedback', 'Interaction failed; check server Output')
    end
end)

local FORMMaterial = require(Openworks:WaitForChild('FORMMaterial'))
local active = {}
local locked = {}
local modifiedSolids = setmetatable({}, {__mode = 'k'})

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

local function toolContact(tool, part, kind)
    local marker = contactMarker(tool, if kind == 'Saw' then 'BladeEdge' else 'FileFace')
    if marker then return marker.WorldCFrame end

    local blade
    if kind == 'Saw' then
        for _, node in tool:GetDescendants() do
            if node:IsA('BasePart') and (node.Name == 'Blade'
                or node.Name == 'SawBlade' or node.Name == 'BladePart') then
                blade = node
                break
            end
        end
        if not blade and tool:IsA('BasePart') then blade = tool end
    end

    local bounds, size
    if blade then
        bounds, size = blade.CFrame, blade.Size
    elseif tool:IsA('Model') then
        bounds, size = tool:GetBoundingBox()
    else
        bounds, size = part.CFrame, part.Size
    end

    local rotation = CFrame.identity
    if size.Z > math.max(size.X, size.Y) * 1.12 then
        rotation = CFrame.Angles(0, math.rad(-90), 0)
    elseif size.Y > math.max(size.X, size.Z) * 1.12 then
        rotation = CFrame.Angles(0, 0, math.rad(90))
    end

    return bounds * CFrame.new(0, -size.Y * 0.5, 0) * rotation
end

local function setToolCollision(item, state)
    state.collisions = {}

    local function disable(part)
        state.collisions[part] = {
            collide = part.CanCollide,
            touch = part.CanTouch,
            query = part.CanQuery,
        }
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
    end

    if item:IsA('BasePart') then
        disable(item)
    else
        for _, node in item:GetDescendants() do
            if node:IsA('BasePart') then disable(node) end
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

local function destroyMotor(state, returnOwnership)
    for _, key in {'position', 'rotation', 'grab', 'destination', 'target'} do
        if state[key] then state[key]:Destroy() end
    end
    if returnOwnership ~= false and state.part and state.part.Parent then
        local ok, allowed = pcall(function() return state.part:CanSetNetworkOwnership() end)
        if ok and allowed then
            pcall(function() state.part:SetNetworkOwnershipAuto() end)
        end
    end
end

local function allParts(item)
    if item:IsA('BasePart') then return {item} end
    local parts = {}
    for _, node in item:GetDescendants() do
        if node:IsA('BasePart') then table.insert(parts, node) end
    end
    return parts
end

local function supportOnWorkbench(item)
    local bench = workspace:FindFirstChild('Workbench')
    if not bench then return end

    local bounds, size
    if item:IsA('BasePart') then
        bounds, size = item.CFrame, item.Size
    else
        bounds, size = item:GetBoundingBox()
    end

    local bestSurface
    local bestDelta = math.huge
    for _, surface in bench:GetDescendants() do
        if not (surface:IsA('BasePart') and surface.Name:lower() == 'surface') then
            continue
        end
        local localPosition = surface.CFrame:PointToObjectSpace(bounds.Position)
        if math.abs(localPosition.X) > surface.Size.X * 0.5
            or math.abs(localPosition.Z) > surface.Size.Z * 0.5 then
            continue
        end

        local upward = surface.CFrame.UpVector
        local half = size * 0.5
        local verticalRadius = math.abs(bounds.RightVector:Dot(upward)) * half.X
            + math.abs(bounds.UpVector:Dot(upward)) * half.Y
            + math.abs(bounds.LookVector:Dot(upward)) * half.Z
        local bottom = (bounds.Position - surface.Position):Dot(upward) - verticalRadius
        local top = surface.Size.Y * 0.5 + 0.04
        local delta = top - bottom

        if math.abs(delta) < math.abs(bestDelta) then
            bestSurface = surface
            bestDelta = delta
        end
    end

    if bestSurface and bestDelta > 0 and bestDelta < 3 then
        item:PivotTo(item:GetPivot() + bestSurface.CFrame.UpVector * bestDelta)
    end
end

local function finish(player)
    local state = active[player]
    if not state then return end

    active[player] = nil
    locked[state.item] = nil
    if state.material then locked[state.material] = nil end

    if state.mode == 'Fabrication' then
        if state.item and state.item.Parent then
            state.item:PivotTo(state.restingFrame)
            supportOnWorkbench(state.item)

            for part in state.anchoredParts do
                if part.Parent then
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                end
            end

            for part, wasAnchored in state.anchoredParts do
                if part.Parent then part.Anchored = wasAnchored end
            end
        end

        if state.collisions then
            for part, original in state.collisions do
                if part.Parent then
                    part.CanQuery = true
                    part.CanCollide = original.collide
                    part.CanTouch = original.touch
                    part.CanQuery = original.query
                end
            end
        end

        if state.material and state.material.Parent then
            supportOnWorkbench(state.material)
        end

        for materialPart, wasAnchored in state.materialAnchors do
            if materialPart.Parent then
                materialPart.AssemblyLinearVelocity = Vector3.zero
                materialPart.AssemblyAngularVelocity = Vector3.zero
                materialPart.Anchored = wasAnchored
            end
        end
    else
        destroyMotor(state)
        if state.mode == 'Drag' then
            print('[OPENWORKS:Drag] Released:', state.item.Name)
        end
    end

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

    local function reject(message)
        remote:FireClient(player, 'Feedback', message)
    end

    if not material:IsDescendantOf(workspace) or not tool:IsDescendantOf(workspace) then
        reject('Tool and material must be in Workspace')
        return
    end

    if material:GetAttribute('OnWorkbench') ~= true or tool:GetAttribute('OnWorkbench') ~= true then
        reject('Both tool and material must rest on the workbench')
        return
    end

    local kind = toolKind(tool)
    local work = findPart(material)
    local part = findPart(tool)
    local root = rootOf(player)

    if not kind then
        reject('Set FabricationKind to Saw or File')
        return
    end
    if not work or not part or not root or not movable(tool)
        or locked[material] or locked[tool] then
        reject('Material or tool is not available')
        return
    end
    if (root.Position - work.Position).Magnitude > 24
        or (root.Position - part.Position).Magnitude > 24 then
        reject('Move closer to the workbench')
        return
    end

    local toolParts = allParts(tool)
    if #toolParts == 0 then
        reject('No physical tool parts found')
        return
    end

    local restingFrame = tool:GetPivot()
    local contact = toolContact(tool, part, kind)
    local toolBounds, toolSize
    if kind == 'Saw' then
        if tool:IsA('Model') then
            toolBounds, toolSize = tool:GetBoundingBox()
        else
            toolBounds, toolSize = tool.CFrame, tool.Size
        end
    end

    local state = {
        mode = 'Fabrication',
        item = tool,
        part = part,
        kind = kind,
        material = material,
        work = work,
        restingFrame = restingFrame,
        contactOffset = contact:ToObjectSpace(restingFrame),
        sawFlip = tool:GetAttribute('SawFlip180') ~= false,
        toolBoundsOffset = if toolBounds then restingFrame:ToObjectSpace(toolBounds) else nil,
        toolBoundsSize = toolSize,
        currentFrame = restingFrame,
        goalFrame = restingFrame,
        anchoredParts = {},
        materialAnchors = {},
        offset = 0,
        stroke = 0,
        lastStroke = 0,
        lastTurn = 0,
        direction = 0,
        reversals = 0,
        axis = 'X',
        roll = 0,
        awaitRelease = false,
        fileSide = 1,
        fileShape = 'Round',
        fileRadius = 1.25,
        processing = false,
        lastMove = 0,
    }

    setToolCollision(tool, state)
    for _, toolPart in toolParts do
        state.anchoredParts[toolPart] = toolPart.Anchored
        toolPart.AssemblyLinearVelocity = Vector3.zero
        toolPart.AssemblyAngularVelocity = Vector3.zero
        toolPart.Anchored = true
    end

    for _, materialPart in allParts(material) do
        state.materialAnchors[materialPart] = materialPart.Anchored
        materialPart.AssemblyLinearVelocity = Vector3.zero
        materialPart.AssemblyAngularVelocity = Vector3.zero
        materialPart.Anchored = true
    end
    supportOnWorkbench(material)

    active[player] = state
    locked[tool] = player
    locked[material] = player

    local collisionData = {}
    for toolPart, original in state.collisions do
        table.insert(collisionData, {
            toolPart, original.collide, original.touch, original.query,
        })
    end

    remote:FireClient(player, 'FabricationStarted', kind, material, tool, collisionData)
end

local function cutSheet(state)
    local work = state.work
    if not work or not work.Parent or not work:IsA('Part')
        or work.Shape ~= Enum.PartType.Block or work:GetAttribute('FORMNativeStock') ~= true then
        return nil, 'This material needs a FORM render adapter before machining'
    end

    if state.kind == 'File' then
        local Stock = require(Openworks:WaitForChild('Stock'))
        local FileShape = require(Openworks:WaitForChild('FileShape'))
        local MeshRenderer = require(Openworks:WaitForChild('FORMWorkpieceRender'))

        local item = modifiedSolids[work]
        if not item then
            local dimensions = work.Size / Stock.SCALE
            item = Stock.create(1, 'Block', 'Steel', {
                x = dimensions.X, y = dimensions.Y, z = dimensions.Z,
            }, work.CFrame)
        end
        item.frame = work.CFrame

        local axis, side = state.axis, state.fileSide
        local half = work.Size * 0.5
        local target = if axis == 'X' then Vector3.new(side * half.X, half.Y, 0)
            else Vector3.new(0, half.Y, side * half.Z)
        local worldHit = work.CFrame:PointToWorldSpace(target)
        local spec, failure = FileShape.preview(item, worldHit, state.fileRadius)
        if not spec then return nil, failure end

        local solid, stats
        if state.fileShape == 'Chamfer' then
            solid, stats = FileShape.chamfer(item, spec)
        else
            solid, stats = FileShape.apply(item, spec)
        end
        if not solid then return nil, stats end

        local previous = work:FindFirstChild('FORMFiledVisual')
        local visual = MeshRenderer.create(solid, work, previous or work)
        local weld = Instance.new('WeldConstraint')
        weld.Part0 = work
        weld.Part1 = visual
        weld.Parent = visual

        visual.Parent = work
        if previous then previous:Destroy() end
        work.Transparency = 1
        work.CanCollide = false
        work.CanQuery = false

        item.solid = solid
        modifiedSolids[work] = item
        work:SetAttribute('FilePasses', (work:GetAttribute('FilePasses') or 0) + 1)
        work:SetAttribute('FileProfile', state.fileShape)
        work:SetAttribute('FileRadiusMM', state.fileRadius)
        work:SetAttribute('LastFiledEdge', axis .. (if side == 1 then '+' else '-'))

        return work, string.format('%s edge %.2f mm — select another edge or Esc',
            state.fileShape, state.fileRadius)
    end

    if modifiedSolids[work] then
        return nil, 'This filed shape needs the mesh-aware saw adapter; use unfiled stock for cutting'
    end

    local FORM = require(Openworks:WaitForChild('FORM'))
    local Stock = require(Openworks:WaitForChild('Stock'))
    local SawCut = require(Openworks:WaitForChild('SawCut'))

    local originalFrame = work.CFrame
    local dimensions = work.Size / Stock.SCALE
    local item = Stock.create(1, 'Block', 'Steel', {
        x = dimensions.X,
        y = dimensions.Y,
        z = dimensions.Z,
    }, originalFrame)

    local normal = if state.axis == 'X' then originalFrame.RightVector
        else originalFrame.LookVector
    local point = originalFrame:PointToWorldSpace(
        if state.axis == 'X' then Vector3.new(state.offset, 0, 0)
        else Vector3.new(0, 0, state.offset))

    local fragments, failure = SawCut.split(item, point, normal)
    if not fragments then return nil, failure end

    local candidates = {}
    for _, solid in fragments do
        local low, high = FORM.bounds(solid)
        local size = (high - low) * Stock.SCALE
        if size.X < 0.05 or size.Y < 0.05 or size.Z < 0.05 then
            return nil, 'Cut would create an unsupported thin fragment'
        end
        table.insert(candidates, {
            size = size,
            frame = originalFrame * CFrame.new((low + high) * 0.5 * Stock.SCALE),
            volume = FORM.signedVolume(solid),
        })
    end

    table.sort(candidates, function(a, b)
        return a.volume > b.volume
    end)

    if #candidates ~= 2 then return nil, 'Expected two physical fragments' end

    local main = candidates[1]
    local offcut = candidates[2]

    local fragment = Instance.new('Part')
    fragment.Name = work.Name .. ' - Offcut'
    fragment.Size = offcut.size
    fragment.CFrame = offcut.frame
    fragment.Material = work.Material
    fragment.MaterialVariant = work.MaterialVariant
    fragment.Color = work.Color
    fragment.Transparency = work.Transparency
    fragment.Reflectance = work.Reflectance
    fragment.CustomPhysicalProperties = work.CustomPhysicalProperties
    fragment.CollisionGroup = work.CollisionGroup
    fragment.Anchored = true
    fragment.CanCollide = true
    fragment.CanTouch = true
    fragment.CanQuery = true
    fragment:SetAttribute('FORMNativeStock', true)
    FORMMaterial.mark(fragment)

    work.Size = main.size
    work.CFrame = main.frame

    fragment.Parent = work.Parent
    supportOnWorkbench(fragment)
    fragment.AssemblyLinearVelocity = Vector3.zero
    fragment.AssemblyAngularVelocity = Vector3.zero
    fragment.Anchored = false

    return work, 'Cut complete. Move the guide for another cut or press Esc'
end

local function moveFabrication(player, state, stroke, offset, axis, isDown, fileSide)
    if not finite(stroke) or not finite(offset)
        or (axis ~= 'X' and axis ~= 'Z') or type(isDown) ~= 'boolean'
        or (fileSide ~= 1 and fileSide ~= -1) then
        return
    end

    local work = state.work
    local root = rootOf(player)
    if not root or not work or not work.Parent or not state.item.Parent then
        finish(player)
        return
    end

    local now = os.clock()
    if now - state.lastMove < 1 / 40 then return end
    state.lastMove = now

    local size = work.Size
    local span = if axis == 'X' then size.X else size.Z
    local maximum = math.max(0, span * 0.5 - 0.17)
    state.axis = axis
    state.offset = math.clamp(offset, -maximum, maximum)
    stroke = math.clamp(stroke, -1, 1)

    state.fileSide = fileSide

    local travelLength = if axis == 'X' then size.Z else size.X
    local travelRange = math.max(0.12, travelLength * 0.5 - 0.04)
    local travel = if axis == 'X' then Vector3.new(0, 0, stroke * travelRange)
        else Vector3.new(stroke * travelRange, 0, 0)

    local cross
    if state.kind == 'File' then
        cross = if axis == 'X'
            then Vector3.new(fileSide * (size.X * 0.5 + 0.012), 0, 0)
            else Vector3.new(0, 0, fileSide * (size.Z * 0.5 + 0.012))
    else
        cross = if axis == 'X' then Vector3.new(state.offset, 0, 0)
            else Vector3.new(0, 0, state.offset)
    end

    local height = if state.kind == 'File' then 0.015 else 0.12
    local pos = work.CFrame:PointToWorldSpace(cross + travel
        + Vector3.new(0, size.Y * 0.5 + height, 0))

    if (pos - root.Position).Magnitude > 30 then
        remote:FireClient(player, 'Feedback', 'Workpiece is out of reach')
        finish(player)
        return
    end

    local forward = if axis == 'X' then work.CFrame.LookVector
        else work.CFrame.RightVector
    local upward = work.CFrame.UpVector
    local sawFlip = if state.kind == 'Saw' and state.sawFlip then 180 else 0
    local contactFrame = CFrame.fromMatrix(pos, forward,
        upward, forward:Cross(upward))
        * CFrame.Angles(math.rad(state.roll + sawFlip), 0, 0)

    state.goalFrame = contactFrame * state.contactOffset

    if state.kind == 'Saw' then
        local bounds = state.goalFrame * state.toolBoundsOffset
        local half = state.toolBoundsSize * 0.5
        local lowest = bounds.Position.Y
            - math.abs(bounds.RightVector.Y) * half.X
            - math.abs(bounds.UpVector.Y) * half.Y
            - math.abs(bounds.LookVector.Y) * half.Z

        local top = work.Position.Y
            + math.abs(work.CFrame.RightVector.Y) * size.X * 0.5
            + math.abs(work.CFrame.UpVector.Y) * size.Y * 0.5
            + math.abs(work.CFrame.LookVector.Y) * size.Z * 0.5

        if lowest < top + 0.03 then
            state.goalFrame += Vector3.new(0, top + 0.03 - lowest, 0)
        end
    end

    if not isDown then
        state.awaitRelease = false
        state.direction = 0
        state.lastStroke = 0
        state.lastTurn = 0
        return
    end

    if state.awaitRelease or state.processing then return end

    local delta = stroke - state.lastStroke
    local direction = if delta > 0.035 then 1 elseif delta < -0.035 then -1 else 0

    if direction ~= 0 and state.direction ~= 0 and direction ~= state.direction
        and math.abs(stroke - state.lastTurn) > 0.2 then
        state.reversals += 1
        state.lastTurn = stroke
        remote:FireClient(player, 'Progress', math.min(1, state.reversals / 5))
    elseif state.direction == 0 and direction ~= 0 then
        state.lastTurn = stroke
    end

    if direction ~= 0 then state.direction = direction end
    state.lastStroke = stroke

    if state.reversals < 5 or state.processing then return end

    local aimWorld = work.CFrame:PointToWorldSpace(
        if axis == 'X' then Vector3.new(state.offset, size.Y * 0.5, 0)
        else Vector3.new(0, size.Y * 0.5, state.offset))

    state.processing = true
    state.awaitRelease = true
    local ok, selected, message = pcall(cutSheet, state)
    if not ok then
        message = 'Fabrication failed: ' .. tostring(selected)
        warn('[OPENWORKS:Fabrication]', selected)
        selected = nil
    end

    state.stroke = stroke
    state.lastStroke = stroke
    state.lastTurn = stroke
    state.direction = 0
    state.reversals = 0
    state.processing = false

    if state.kind == 'Saw' and selected and active[player] == state then
        state.awaitRelease = false
    end

    if active[player] == state then
        remote:FireClient(player, 'MachiningCompleted', selected, message, aimWorld)
    end
end

local function switchFabricationMaterial(player, state, material)
    if state.processing then
        remote:FireClient(player, 'Feedback', 'Finish the current operation before switching')
        return
    end

    if typeof(material) ~= 'Instance'
        or not (material:IsA('BasePart') or material:IsA('Model'))
        or not material:IsDescendantOf(workspace)
        or not FORMMaterial.isMarked(material) then
        remote:FireClient(player, 'Feedback', 'Select a FORM material on the workbench')
        return
    end
    if material == state.material then return end
    if material:GetAttribute('OnWorkbench') ~= true then
        remote:FireClient(player, 'Feedback', 'That material is not resting on the workbench')
        return
    end
    if locked[material] then
        remote:FireClient(player, 'Feedback', 'That material is already in use')
        return
    end

    local part = findPart(material)
    local root = rootOf(player)
    if not part or not part:IsA('BasePart') or not root
        or (part.Position - root.Position).Magnitude > 24 then
        remote:FireClient(player, 'Feedback', 'The selected material is out of reach')
        return
    end

    local candidateParts = allParts(material)
    if #candidateParts == 0 then return end
    local oldMaterial = state.material
    state.processing = true

    if oldMaterial and oldMaterial.Parent then
        supportOnWorkbench(oldMaterial)
    end
    for oldPart, wasAnchored in state.materialAnchors do
        if oldPart.Parent then
            oldPart.AssemblyLinearVelocity = Vector3.zero
            oldPart.AssemblyAngularVelocity = Vector3.zero
            oldPart.Anchored = wasAnchored
        end
    end
    locked[oldMaterial] = nil

    local anchors = {}
    for _, nextPart in candidateParts do
        anchors[nextPart] = nextPart.Anchored
        nextPart.AssemblyLinearVelocity = Vector3.zero
        nextPart.AssemblyAngularVelocity = Vector3.zero
        nextPart.Anchored = true
    end
    supportOnWorkbench(material)

    state.material = material
    state.work = part
    state.materialAnchors = anchors
    state.offset = 0
    state.stroke = 0
    state.lastStroke = 0
    state.lastTurn = 0
    state.direction = 0
    state.reversals = 0
    state.awaitRelease = true
    state.lastMove = 0
    state.processing = false
    locked[material] = player

    remote:FireClient(player, 'FabricationTargetChanged', material)
end

onRequest = function(player, action, ...)
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
    elseif action == 'FabricationTarget' and state.mode == 'Fabrication' then
        switchFabricationMaterial(player, state, ...)
    elseif action == 'FabricationSettings' and state.mode == 'Fabrication' then
        local profile, radius = ...
        if state.kind == 'File' and (profile == 'Round' or profile == 'Chamfer')
            and finite(radius) and radius >= 0.5 and radius <= 12 then
            state.fileShape = profile
            state.fileRadius = radius
        else
            remote:FireClient(player, 'Feedback', 'Invalid file profile or size')
        end
    elseif action == 'FabricationSawFlip' and state.mode == 'Fabrication'
        and state.kind == 'Saw' then
        state.sawFlip = not state.sawFlip
        state.item:SetAttribute('SawFlip180', state.sawFlip)
        remote:FireClient(player, 'SawFlipChanged', state.sawFlip)
    elseif action == 'FabricationRotate' and state.mode == 'Fabrication' then
        local step = ...
        if step == 1 or step == -1 then
            state.roll = (state.roll + step * 90) % 360
            state.lastInput = os.clock()
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    for player, state in active do
        local root = rootOf(player)
        if not root or not state.part.Parent
            or (state.part.Position - root.Position).Magnitude > 38 then
            finish(player)
            continue
        end

        if state.mode == 'Fabrication' then
            if not state.item.Parent or not state.work.Parent then
                finish(player)
                continue
            end

            for part in state.collisions do
                if part.Parent then
                    part.CanCollide = false
                    part.CanTouch = false
                    part.CanQuery = false
                    part.Anchored = true
                end
            end

            local alpha = 1 - math.exp(-17 * math.min(dt, 0.1))
            state.currentFrame = state.currentFrame:Lerp(state.goalFrame, alpha)
            state.item:PivotTo(state.currentFrame)
        elseif os.clock() - state.lastInput > 3 then
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

remote:SetAttribute('HeartbeatAt', workspace:GetServerTimeNow())
remote:SetAttribute('Ready', true)

local heartbeatElapsed = 0
RunService.Heartbeat:Connect(function(dt)
    heartbeatElapsed += dt
    if heartbeatElapsed >= 0.4 then
        heartbeatElapsed = 0
        if remote.Parent then
            remote:SetAttribute('HeartbeatAt', workspace:GetServerTimeNow())
        end
    end
end)

print('[OPENWORKS:Interaction] Server ready on', remote:GetFullName())
