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
local ScorePath
local function loadScorePath()
    if ScorePath then return ScorePath end
    local module = Openworks:FindFirstChild('ScorePath')
    if not module or not module:IsA('ModuleScript') then return nil end
    local ok, result = pcall(require, module)
    if not ok then
        warn('[OPENWORKS:Scorer] ScorePath failed to load:', result)
        return nil
    end
    ScorePath = result
    return ScorePath
end

local function registerScorer(item)
    if item and (item:IsA('Model') or item:IsA('BasePart')) then
        item:SetAttribute('isTool', true)
        item:SetAttribute('FabricationKind', 'Scorer')
    end
end

registerScorer(workspace:FindFirstChild('Scorer'))
workspace.ChildAdded:Connect(function(item)
    if item.Name == 'Scorer' then registerScorer(item) end
end)
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
    if explicit == 'Saw' or explicit == 'File' or explicit == 'Scorer' then return explicit end
    local name = item.Name:lower()
    if name == 'scorer' then return 'Scorer' end
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
    local marker = contactMarker(tool,
        if kind == 'Scorer' then 'ScoreTip' else 'FileFace')
    if marker then return marker.WorldCFrame end

    if kind == 'Scorer' then
        local bounds, size
        if tool:IsA('Model') then
            bounds, size = tool:GetBoundingBox()
        else
            bounds, size = part.CFrame, part.Size
        end

        local tip
        for _, node in tool:GetDescendants() do
            if node:IsA('BasePart') then
                local name = node.Name:lower()
                if name == 'tip' or name == 'point' or name == 'nib'
                    or name == 'scoringtip' then
                    tip = node.Position
                    break
                end
            end
        end

        local shaft = bounds.UpVector
        local length = size.Y
        if size.X >= size.Y and size.X >= size.Z then
            shaft, length = bounds.RightVector, size.X
        elseif size.Z >= size.X and size.Z >= size.Y then
            shaft, length = bounds.LookVector, size.Z
        end
        local point = tip or (bounds.Position - shaft * length * 0.5)
        local bodyDirection = if tip and (bounds.Position - tip).Magnitude > 0.015
            then (bounds.Position - tip).Unit else shaft
        local right = bounds.RightVector
        if math.abs(right:Dot(bodyDirection)) > 0.95 then
            right = bounds.UpVector
        end
        right = (right - bodyDirection * right:Dot(bodyDirection)).Unit
        return CFrame.fromMatrix(point, right, bodyDirection,
            right:Cross(bodyDirection))
    end

    local bounds, size
    if tool:IsA('Model') then
        bounds, size = tool:GetBoundingBox()
    else
        bounds, size = part.CFrame, part.Size
    end
    return bounds * CFrame.new(0, -size.Y * 0.5, 0)
end

local function sawMountOffset(tool, part, restingFrame)
    local marker = contactMarker(tool, 'BladeEdge')
    if marker then
        return marker.WorldCFrame:ToObjectSpace(restingFrame)
    end

    local blade = nil
    if tool:IsA('BasePart') then blade = tool end
    if not blade then
        for _, candidate in tool:GetDescendants() do
            if candidate:IsA('BasePart') and candidate.Name:lower():find('blade', 1, true) then
                blade = candidate
                break
            end
        end
    end
    if not blade then blade = part end

    local size = blade.Size
    local axes = {
        {length = size.X, vector = blade.CFrame.RightVector},
        {length = size.Y, vector = blade.CFrame.UpVector},
        {length = size.Z, vector = blade.CFrame.LookVector},
    }
    table.sort(axes, function(a, b) return a.length > b.length end)
    local along = axes[1].vector
    local height = axes[2].vector
    local teeth = tool:FindFirstChild('Teeth', true)
    if teeth and teeth:IsA('BasePart') then
        if (teeth.Position - blade.Position):Dot(height) > 0 then
            height = -height
        end
    elseif height:Dot(Vector3.yAxis) < 0 then
        height = -height
    end

    local edgePoint = blade.Position - height * axes[2].length * 0.5
    local frame = CFrame.fromMatrix(edgePoint, along, height, along:Cross(height))
    return frame:ToObjectSpace(restingFrame)
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

local function exposedFace(part)
    local up = part.CFrame:VectorToObjectSpace(Vector3.yAxis)
    local dx, dy, dz = math.abs(up.X), math.abs(up.Y), math.abs(up.Z)
    if dx >= dy and dx >= dz then return 'X', if up.X >= 0 then 1 else -1 end
    if dz >= dy then return 'Z', if up.Z >= 0 then 1 else -1 end
    return 'Y', if up.Y >= 0 then 1 else -1
end

local function basis(axis)
    if axis == 'X' then return Vector3.xAxis end
    if axis == 'Y' then return Vector3.yAxis end
    return Vector3.zAxis
end

local function measure(v, axis)
    if axis == 'X' then return v.X end
    if axis == 'Y' then return v.Y end
    return v.Z
end

local function exposedEdge(part, wanted)
    local face, sign = exposedFace(part)
    local side = wanted
    if side == face then side = if face == 'X' then 'Z' else 'X' end
    local travel
    for _, axis in {'X', 'Y', 'Z'} do
        if axis ~= face and axis ~= side then travel = axis break end
    end
    return face, sign, side, travel
end

local function centerSolid(solid, center)
    local vertices = {}
    for i, vertex in solid.vertices do vertices[i] = vertex - center end
    local triangles = {}
    for i, triangle in solid.triangles do
        triangles[i] = {triangle[1], triangle[2], triangle[3]}
    end
    return {vertices = vertices, triangles = triangles}
end

local endScore

local function finish(player)
    local state = active[player]
    if not state then return end

    active[player] = nil
    locked[state.item] = nil
    if state.material then locked[state.material] = nil end

    if state.mode == 'Fabrication' then
        if state.kind == 'Scorer' and state.score then endScore(player, state) end
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

    local isWorkspaceScorer = tool == workspace:FindFirstChild('Scorer')
    if material:GetAttribute('OnWorkbench') ~= true
        or (tool:GetAttribute('OnWorkbench') ~= true and not isWorkspaceScorer) then
        reject('Material and tool must be available at the workbench')
        return
    end

    local kind = toolKind(tool)
    local work = findPart(material)
    local part = findPart(tool)
    local root = rootOf(player)

    if not kind then
        reject('Set FabricationKind to Saw, File, or Scorer')
        return
    end
    if kind == 'Scorer' and not loadScorePath() then
        reject('ScorePath module is missing or invalid; sync src/shared/ScorePath.lua')
        return
    end
    if not work or not part or not root
        or (kind ~= 'Scorer' and not movable(tool))
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
    local contact = if kind == 'Saw' then restingFrame
        else toolContact(tool, part, kind)
    local fileLengthLocal
    if kind == 'File' then
        local bounds, dimensions
        if tool:IsA('Model') then
            bounds, dimensions = tool:GetBoundingBox()
        else
            bounds, dimensions = part.CFrame, part.Size
        end
        local long = bounds.RightVector
        if dimensions.Y > dimensions.X and dimensions.Y >= dimensions.Z then
            long = bounds.UpVector
        elseif dimensions.Z > dimensions.X and dimensions.Z > dimensions.Y then
            long = bounds.LookVector
        end
        fileLengthLocal = restingFrame:VectorToObjectSpace(long)
    end
    local sawOffset = if kind == 'Saw'
        then sawMountOffset(tool, part, restingFrame) else nil

    local state = {
        mode = 'Fabrication',
        item = tool,
        part = part,
        kind = kind,
        material = material,
        work = work,
        restingFrame = restingFrame,
        contactOffset = contact:ToObjectSpace(restingFrame),
        fileLengthLocal = fileLengthLocal,
        sawOffset = sawOffset,
        positioning = false,
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

    remote:FireClient(player, 'FabricationStarted', kind, material, tool,
        collisionData, if kind == 'Scorer' then state.contactOffset else nil)
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

        local face, faceSign, axis = exposedEdge(work, state.axis)
        local side = state.fileSide
        local target = basis(axis) * (side * measure(work.Size, axis) * 0.5)
            + basis(face) * (faceSign * measure(work.Size, face) * 0.5)
        local worldHit = work.CFrame:PointToWorldSpace(target)
        local solid, stats
        local contourMode = false
        if modifiedSolids[work] then
            local Profile = require(Openworks:WaitForChild('PrismProfile'))
            local outline = Profile.extract(item.solid)
            if outline then
                local ContourFile = require(Openworks:WaitForChild('ContourFile'))
                local localPoint = state.filePoint or target
                solid, stats = ContourFile.apply(work, item,
                    localPoint, state.fileRadius, state.fileShape)
                contourMode = true
            end
        end
        if not contourMode then
            local spec, failure = FileShape.preview(item, worldHit, state.fileRadius)
            if not spec then return nil, failure end
            if state.fileShape == 'Chamfer' then
                solid, stats = FileShape.chamfer(item, spec)
            else
                solid, stats = FileShape.apply(item, spec)
            end
        end
        if not solid then return nil, stats end

        local previous = work:FindFirstChild('FORMFiledVisual')
        local visual = MeshRenderer.create(solid, work, previous or work,
            contourMode)
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
        work:SetAttribute('FORMContourMode', contourMode)
        work:SetAttribute('FilePasses', (work:GetAttribute('FilePasses') or 0) + 1)
        work:SetAttribute('FileProfile', state.fileShape)
        work:SetAttribute('FileRadiusMM', state.fileRadius)
        work:SetAttribute('LastFiledEdge', axis .. (if side == 1 then '+' else '-'))

        return work, string.format('%s edge %.2f mm — select another edge or Esc',
            state.fileShape, state.fileRadius)
    end

    local wasFiled = modifiedSolids[work] ~= nil
    local scoredCut = state.scoreCut
    local isCurve = scoredCut and scoredCut.kind == 'Curved'
    local needsMesh = wasFiled or (scoredCut ~= nil and scoredCut.axis == nil)

    local FORM = require(Openworks:WaitForChild('FORM'))
    local Stock = require(Openworks:WaitForChild('Stock'))
    local SawCut = require(Openworks:WaitForChild('SawCut'))

    local originalFrame = work.CFrame
    local dimensions = work.Size / Stock.SCALE
    local item = modifiedSolids[work]
    if item then
        item.frame = originalFrame
    else
        item = Stock.create(1, 'Block', 'Steel', {
            x = dimensions.X,
            y = dimensions.Y,
            z = dimensions.Z,
        }, originalFrame)
    end

    local normal = if state.axis == 'X' then originalFrame.RightVector
        else originalFrame.LookVector
    local point = originalFrame:PointToWorldSpace(
        if state.axis == 'X' then Vector3.new(state.offset, 0, 0)
        else Vector3.new(0, 0, state.offset))
    if scoredCut and scoredCut.kind == 'Straight' then
        point = originalFrame:PointToWorldSpace(scoredCut.point)
        normal = originalFrame:VectorToWorldSpace(scoredCut.normal)
    end

    local fragments, failure
    if state.autoCurveFragments then
        fragments = state.autoCurveFragments
    else
        local sourceProfile
        if wasFiled then
            local PrismProfile = require(Openworks:WaitForChild('PrismProfile'))
            sourceProfile = PrismProfile.extract(item.solid)
        end
        if isCurve or sourceProfile then
            local module = Openworks:FindFirstChild('PathCut')
            if not module or not module:IsA('ModuleScript') then
                return nil, 'Contour cutter module is not synchronized'
            end
            local loaded, cutter = pcall(require, module)
            if not loaded then
                return nil, 'Contour cutter failed to load: ' .. tostring(cutter)
            end
            local points
            if scoredCut and scoredCut.points then
                points = scoredCut.points
            else
                local span = if state.axis == 'X' then work.Size.Z else work.Size.X
                local y = work.Size.Y * 0.5
                points = if state.axis == 'X' then {
                    Vector3.new(state.offset, y, -span),
                    Vector3.new(state.offset, y, span),
                } else {
                    Vector3.new(-span, y, state.offset),
                    Vector3.new(span, y, state.offset),
                }
            end
            fragments, failure = cutter.split(work, points, nil,
                if wasFiled then item.solid else nil)
        else
            fragments, failure = SawCut.split(item, point, normal)
        end
    end
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
            solid = if needsMesh then centerSolid(solid, (low + high) * 0.5) else nil,
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

    local mainVisual, offcutVisual
    local previous = work:FindFirstChild('FORMFiledVisual')
    if needsMesh then
        local Renderer = require(Openworks:WaitForChild('FORMWorkpieceRender'))
        local mainSource = Instance.new('Part')
        mainSource.CFrame = main.frame
        mainSource.Size = main.size
        local offcutSource = Instance.new('Part')
        offcutSource.CFrame = offcut.frame
        offcutSource.Size = offcut.size

        local appearance = previous or work
        local ok, result, other = pcall(function()
            return Renderer.create(main.solid, mainSource, appearance, true),
                Renderer.create(offcut.solid, offcutSource, appearance, true)
        end)
        mainSource:Destroy()
        offcutSource:Destroy()
        if not ok then return nil, 'Unable to render shaped saw cut: ' .. tostring(result) end
        mainVisual, offcutVisual = result, other
    end

    work.Size = main.size
    work.CFrame = main.frame
    if needsMesh then
        if previous then previous:Destroy() end
        local weld = Instance.new('WeldConstraint')
        weld.Part0 = work
        weld.Part1 = mainVisual
        weld.Parent = mainVisual
        mainVisual.Parent = work
        work.Transparency = 1
        work.CanCollide = false
        work.CanQuery = false
        fragment.Transparency = 1
        fragment.CanCollide = false
        fragment.CanQuery = false
        local offcutWeld = Instance.new('WeldConstraint')
        offcutWeld.Part0 = fragment
        offcutWeld.Part1 = offcutVisual
        offcutWeld.Parent = offcutVisual
        offcutVisual.Parent = fragment
        modifiedSolids[work] = {
            frame = main.frame, solid = main.solid, shape = 'Block',
        }
        modifiedSolids[fragment] = {
            frame = offcut.frame, solid = offcut.solid, shape = 'Block',
        }
    end

    if needsMesh then
        local Profile = require(Openworks:WaitForChild('PrismProfile'))
        local mainOutline = Profile.extract(main.solid)
        local offcutOutline = Profile.extract(offcut.solid)
        work:SetAttribute('FORMContourMode', mainOutline ~= nil)
        fragment:SetAttribute('FORMContourMode', offcutOutline ~= nil)
    end

    if work:GetAttribute('FORMScorePaths') then
        work:SetAttribute(ScorePath.ATTRIBUTE, nil)
        local marks = work:FindFirstChild('OpenworksScoreMarks')
        if marks then marks:Destroy() end
    end

    fragment.Parent = work.Parent
    supportOnWorkbench(fragment)
    fragment.AssemblyLinearVelocity = Vector3.zero
    fragment.AssemblyAngularVelocity = Vector3.zero
    fragment.Anchored = false

    return work, 'Cut complete. Move the guide for another cut or press Esc'
end

local function beginAutomaticScore(player, state, reference)
    if state.kind ~= 'Saw' then return end
    if state.positioning or state.processing or state.autoCut then
        remote:FireClient(player, 'Feedback', 'Finish the current operation first')
        return
    end
    local work = state.work
    if not work or not work.Parent or typeof(reference) ~= 'Vector3'
        or not loadScorePath() then
        remote:FireClient(player, 'Feedback',
            'Automatic cutting is unavailable; check the workpiece and ScorePath module')
        return
    end

    local face, sign = ScorePath.face(work)
    if not ScorePath.valid(work, reference, face, sign) then
        remote:FireClient(player, 'Feedback', 'Aim at the exposed scored face')
        return
    end
    local root = rootOf(player)
    if not root or (root.Position - work.CFrame:PointToWorldSpace(reference)).Magnitude > 27 then
        remote:FireClient(player, 'Feedback', 'Scored cut is out of reach')
        return
    end

    local scored = ScorePath.guide(work, reference, 0.22)
    if not scored or not scored.points then
        remote:FireClient(player, 'Feedback', 'No saved score under the saw cursor')
        return
    end
    local length = ScorePath.sample(scored.points)
    if not length or length < 0.12 then
        remote:FireClient(player, 'Feedback', 'Score path is too short for an automatic cut')
        return
    end

    if work:GetAttribute('FORMNativeStock') ~= true
        or not work:IsA('Part') or work.Shape ~= Enum.PartType.Block then
        remote:FireClient(player, 'Feedback',
            'Automatic scoring currently requires native rectangular FORM stock')
        return
    end

    local preparedCurve
    local source = modifiedSolids[work]
    local silhouette
    if source then
        local PrismProfile = require(Openworks:WaitForChild('PrismProfile'))
        silhouette = PrismProfile.extract(source.solid)
    end

    if scored.kind == 'Curved' or silhouette then
        local module = Openworks:FindFirstChild('PathCut')
        if not module or not module:IsA('ModuleScript') then
            remote:FireClient(player, 'Feedback', 'Contour cutter is not synchronized')
            return
        end
        local loaded, cutter = pcall(require, module)
        if not loaded then
            remote:FireClient(player, 'Feedback',
                'Contour cutter unavailable: ' .. tostring(cutter))
            return
        end
        local ok, fragments, reason = pcall(cutter.split, work, scored.points,
            nil, source and source.solid)
        if not ok or not fragments then
            remote:FireClient(player, 'Feedback',
                'Cannot follow this score: ' .. tostring(if ok then reason else fragments))
            return
        end
        preparedCurve = fragments
    else
        local ok, preview, reason = pcall(function()
            local Stock = require(Openworks:WaitForChild('Stock'))
            local SawCut = require(Openworks:WaitForChild('SawCut'))
            local item = modifiedSolids[work] or Stock.create(1, 'Block', 'Steel', {
                x = work.Size.X / Stock.SCALE,
                y = work.Size.Y / Stock.SCALE,
                z = work.Size.Z / Stock.SCALE,
            }, work.CFrame)
            item.frame = work.CFrame
            return SawCut.preview(item,
                work.CFrame:PointToWorldSpace(scored.point),
                work.CFrame:VectorToWorldSpace(scored.normal))
        end)
        if not ok or not preview then
            remote:FireClient(player, 'Feedback',
                'Cannot saw this score: ' .. tostring(if ok then reason else preview))
            return
        end
    end

    state.autoCurveFragments = preparedCurve
    state.scoreCut = scored
    state.curvePath = nil
    state.curveTravel = 0
    state.processing = true
    state.awaitRelease = true
    state.reversals = 0
    state.direction = 0
    state.stroke = 0
    state.lastStroke = 0
    local duration = math.clamp(1.6 + length * 1.2, 2, 8)
    state.autoCut = {
        scored = scored,
        length = length,
        elapsed = 0,
        duration = duration,
        reported = 0,
    }
    remote:FireClient(player, 'AutoScoreStarted', scored.kind, duration)
end

local function advanceAutomaticScore(player, state, dt)
    local auto = state.autoCut
    if not auto then return end
    local work = state.work
    if not work or not work.Parent then
        state.autoCut = nil
        state.autoCurveFragments = nil
        state.scoreCut = nil
        state.processing = false
        return
    end

    auto.elapsed = math.min(auto.duration, auto.elapsed + math.min(dt, 0.1))
    local progress = math.clamp(auto.elapsed / auto.duration, 0, 1)
    local amplitude = math.min(auto.length * 0.025, 0.05)
    local feed = math.clamp(
        auto.length * progress + math.sin(auto.elapsed * 35) * amplitude,
        0, auto.length)
    local point, tangent = ScorePath.sample(auto.scored.points, feed)
    if point and tangent then
        local face, sign = ScorePath.face(work)
        local upward = work.CFrame:VectorToWorldSpace(ScorePath.normal(face, sign))
        local forward = work.CFrame:VectorToWorldSpace(tangent)
        forward = forward - upward * forward:Dot(upward)
        if forward.Magnitude > 0.001 then
            forward = forward.Unit
            local contact = work.CFrame:PointToWorldSpace(point) + upward * 0.012
            state.goalFrame = CFrame.fromMatrix(contact, forward,
                upward, forward:Cross(upward)) * state.sawOffset
        end
    end

    if progress >= 1 or auto.elapsed - auto.reported >= 0.1 then
        auto.reported = auto.elapsed
        remote:FireClient(player, 'AutoScoreProgress', progress)
    end
    if progress < 1 then return end

    state.autoCut = nil
    local ok, selected, message = pcall(cutSheet, state)
    if not ok then
        warn('[OPENWORKS:AutomaticSaw]', selected)
        message = 'Automatic cut failed: ' .. tostring(selected)
        selected = nil
    end
    state.autoCurveFragments = nil
    state.scoreCut = nil
    state.processing = false
    state.reversals = 0
    state.direction = 0
    state.lastStroke = 0
    state.awaitRelease = true
    if active[player] == state then
        remote:FireClient(player, 'AutoScoreFinished', selected,
            message or (if selected then 'Automatic cut complete' else 'Cut failed'))
    end
end

local function moveFabrication(player, state, stroke, offset, axis, isDown, fileSide, scoreReference)
    if not finite(stroke) or not finite(offset)
        or (axis ~= 'X' and axis ~= 'Z' and (state.kind ~= 'File' or axis ~= 'Y'))
        or type(isDown) ~= 'boolean'
        or (fileSide ~= 1 and fileSide ~= -1) then
        return
    end

    local work = state.work
    local root = rootOf(player)
    if not root or not work or not work.Parent or not state.item.Parent then
        finish(player)
        return
    end

    if state.positioning or state.autoCut then return end

    local now = os.clock()
    if now - state.lastMove < 1 / 40 then return end
    state.lastMove = now

    local size = work.Size
    if state.kind == 'File' and typeof(scoreReference) == 'Vector3'
        and validVector(scoreReference) then
        local h = work.Size * 0.5 + Vector3.new(0.08, 0.08, 0.08)
        if math.abs(scoreReference.X) <= h.X
            and math.abs(scoreReference.Y) <= h.Y
            and math.abs(scoreReference.Z) <= h.Z then
            state.filePoint = scoreReference
        end
    end
    local matched
    if state.kind == 'Saw' and loadScorePath()
        and typeof(scoreReference) == 'Vector3' then
        local face, sign = ScorePath.face(work)
        if ScorePath.valid(work, scoreReference, face, sign) then
            matched = ScorePath.guide(work, scoreReference, 0.22)
        end
    end
    if state.kind == 'Saw' and matched and matched.kind == 'Curved' then
        local length = ScorePath.sample(matched.points)
        if not length or length <= 0.12 then return end
        if state.curvePath ~= matched.points then
            state.curvePath = matched.points
            state.curveTravel = 0
            state.reversals = 0
            state.direction = 0
            state.lastStroke = 0
            state.lastTurn = 0
        end
        local sample, tangent = ScorePath.sample(matched.points, state.curveTravel)
        matched.point = sample
        matched.tangent = tangent
        state.scoreCut = matched
    else
        state.curvePath = nil
        state.curveTravel = 0
        state.scoreCut = if state.kind == 'Saw' and matched
            and matched.kind == 'Straight' then matched else nil
    end
    if state.scoreCut and state.scoreCut.axis then
        axis = state.scoreCut.axis
        offset = state.scoreCut.offset
    elseif state.kind == 'Saw' and loadScorePath() then
        local aligned = ScorePath.straight(work, axis, offset, 0.12)
        if aligned then offset = aligned end
    end
    local span = if axis == 'X' then size.X else size.Z
    local maximum = math.max(0, span * 0.5 - 0.17)
    state.axis = axis
    state.offset = math.clamp(offset, -maximum, maximum)
    stroke = math.clamp(stroke, -12, 12)

    state.fileSide = fileSide

    local face, faceSign, sideAxis, along = exposedEdge(work, axis)
    local travel
    local cross
    local upward
    local curveStrokeTangent
    if state.kind == 'File' then
        local halfTravel = measure(size, along) * 0.5
        stroke = math.clamp(stroke, -halfTravel, halfTravel)
        travel = basis(along) * stroke
        cross = basis(sideAxis) * (fileSide * (measure(size, sideAxis) * 0.5 + 0.002))
        if modifiedSolids[work] and state.filePoint then
            cross = Vector3.new(state.filePoint.X, 0, state.filePoint.Z)
        end
        upward = work.CFrame:VectorToWorldSpace(basis(face) * faceSign)
    else
        stroke = math.clamp(stroke, -1.5, 1.5)
        if state.scoreCut and state.scoreCut.kind == 'Curved' then
            local strokeDistance = math.clamp(stroke * 0.12, -0.18, 0.18)
            local sample, tangent = ScorePath.sample(state.scoreCut.points,
                (state.curveTravel or 0) + strokeDistance)
            cross = sample
            curveStrokeTangent = tangent
            travel = Vector3.zero
        elseif state.scoreCut then
            travel = state.scoreCut.tangent * stroke
            cross = state.scoreCut.point
        else
            travel = if axis == 'X' then Vector3.new(0, 0, stroke)
                else Vector3.new(stroke, 0, 0)
            cross = if axis == 'X' then Vector3.new(state.offset, 0, 0)
                else Vector3.new(0, 0, state.offset)
        end
        upward = Vector3.yAxis
    end

    local pos
    if state.kind == 'File' then
        pos = work.CFrame:PointToWorldSpace(cross + travel
            + basis(face) * faceSign * (measure(size, face) * 0.5 + 0.003))
    else
        local localPos = cross + travel
        local height = math.abs(work.CFrame.RightVector.Y) * size.X * 0.5
            + math.abs(work.CFrame.UpVector.Y) * size.Y * 0.5
            + math.abs(work.CFrame.LookVector.Y) * size.Z * 0.5
        pos = work.CFrame:PointToWorldSpace(localPos)
        if state.scoreCut then
            pos += Vector3.yAxis * 0.012
        else
            pos = Vector3.new(pos.X, work.Position.Y + height + 0.035, pos.Z)
        end
    end

    if (pos - root.Position).Magnitude > 30 then
        remote:FireClient(player, 'Feedback', 'Workpiece is out of reach')
        finish(player)
        return
    end

    local forward = if state.kind == 'File' then
        work.CFrame:VectorToWorldSpace(basis(along))
        elseif curveStrokeTangent then
        work.CFrame:VectorToWorldSpace(curveStrokeTangent)
        elseif state.scoreCut then
        work.CFrame:VectorToWorldSpace(state.scoreCut.tangent)
        elseif axis == 'X' then work.CFrame.LookVector
        else work.CFrame.RightVector
    local alongPath = forward.Unit
    local surfaceUp = upward.Unit
    alongPath = (alongPath - surfaceUp * alongPath:Dot(surfaceUp)).Unit
    local contactFrame = CFrame.fromMatrix(pos, alongPath,
        surfaceUp, alongPath:Cross(surfaceUp))
    if state.kind == 'Saw' then
        state.goalFrame = contactFrame * state.sawOffset
    else
        state.goalFrame = contactFrame
            * CFrame.Angles(math.rad(state.roll), 0, 0) * state.contactOffset
    end

    if state.kind == 'File' then
        local worldLong = state.goalFrame:VectorToWorldSpace(state.fileLengthLocal)
        local desired = forward.Unit
        if worldLong:Dot(desired) < 0 then desired = -desired end
        local correctionAxis = worldLong:Cross(desired)
        if correctionAxis.Magnitude > 0.001 then
            local angle = math.atan2(correctionAxis.Magnitude,
                math.clamp(worldLong:Dot(desired), -1, 1))
            state.goalFrame = CFrame.new(pos)
                * CFrame.fromAxisAngle(correctionAxis.Unit, angle)
                * CFrame.new(-pos) * state.goalFrame
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
    local curved = state.kind == 'Saw' and state.scoreCut
        and state.scoreCut.kind == 'Curved'
    local curveLength = if curved then ScorePath.sample(state.scoreCut.points) else nil

    if direction ~= 0 and state.direction ~= 0 and direction ~= state.direction
        and math.abs(stroke - state.lastTurn) > 0.2 then
        state.reversals += 1
        state.lastTurn = stroke
        if curved and curveLength then
            state.curveTravel = math.min(curveLength, (state.curveTravel or 0)
                + curveLength / 28)
            remote:FireClient(player, 'Progress', state.curveTravel / curveLength)
        else
            remote:FireClient(player, 'Progress', math.min(1, state.reversals / 5))
        end
    elseif state.direction == 0 and direction ~= 0 then
        state.lastTurn = stroke
    end

    if direction ~= 0 then state.direction = direction end
    state.lastStroke = stroke

    if curved then
        if not curveLength or (state.curveTravel or 0) < curveLength - 0.0001 then return end
    elseif state.reversals < 5 then
        return
    end
    if state.processing then return end

    local aimWorld = work.CFrame:PointToWorldSpace(
        if state.scoreCut then state.scoreCut.point
        elseif axis == 'X' then Vector3.new(state.offset, size.Y * 0.5, 0)
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

local function drawScore(work, paths)
    local previous = work:FindFirstChild('OpenworksScoreMarks')
    if previous then previous:Destroy() end
    local folder = Instance.new('Folder')
    folder.Name = 'OpenworksScoreMarks'
    folder.Parent = work

    for _, path in paths do
        local localNormal = ScorePath.normal(path.face, path.sign)
        local worldNormal = work.CFrame:VectorToWorldSpace(localNormal)
        local points = path.points
        for i = 2, #points do
            local a = work.CFrame:PointToWorldSpace(points[i - 1]) + worldNormal * 0.011
            local b = work.CFrame:PointToWorldSpace(points[i]) + worldNormal * 0.011
            local length = (b - a).Magnitude
            if length < 0.006 then continue end

            local groove = Instance.new('Part')
            groove.Name = 'Score'
            groove.Size = Vector3.new(0.014, 0.009, length)
            groove.CFrame = CFrame.lookAt((a + b) * 0.5, b)
            groove.Color = Color3.fromRGB(37, 48, 54)
            groove.Material = Enum.Material.SmoothPlastic
            groove.CanCollide = false
            groove.CanTouch = false
            groove.CanQuery = false
            groove.Massless = true
            groove.CastShadow = false
            groove.Anchored = false
            groove.Parent = folder

            local weld = Instance.new('WeldConstraint')
            weld.Part0 = work
            weld.Part1 = groove
            weld.Parent = groove
        end
    end
end

local function scorePosition(state, point, tangent)
    state.goalFrame = ScorePath.contactFrame(state.work, point, tangent)
        * state.contactOffset
    state.currentFrame = state.goalFrame
    state.item:PivotTo(state.currentFrame)
end

local function hoverScore(player, state, point)
    if state.positioning or state.processing or state.score then return end
    local work = state.work
    local face, sign = ScorePath.face(work)
    if not ScorePath.valid(work, point, face, sign) then return end
    local root = rootOf(player)
    if not root or (work.CFrame:PointToWorldSpace(point) - root.Position).Magnitude > 27 then return end
    if os.clock() - (state.lastScoreHover or 0) < 1 / 24 then return end
    state.lastScoreHover = os.clock()
    scorePosition(state, point)
end

local function beginScore(player, state, point)
    local work = state.work
    local face, sign = ScorePath.face(work)
    if state.positioning or state.processing or not ScorePath.valid(work, point, face, sign) then return end
    local root = rootOf(player)
    if not root or (work.CFrame:PointToWorldSpace(point) - root.Position).Magnitude > 27 then return end
    state.score = {face = face, sign = sign, points = {point}}
    state.lastScoreAt = os.clock()
    scorePosition(state, point)
end

local function extendScore(state, point)
    local score = state.score
    if not score or state.positioning or state.processing then return end
    local work = state.work
    local face, sign = ScorePath.face(work)
    if face ~= score.face or sign ~= score.sign
        or not ScorePath.valid(work, point, face, sign) then return end

    local now = os.clock()
    if now - (state.lastScoreAt or 0) < 1 / 45 then return end
    state.lastScoreAt = now

    local points = score.points
    if #points >= ScorePath.MAX_RAW_POINTS then
        local reduced = ScorePath.reduce(points, 0.006)
        if #reduced >= ScorePath.MAX_RAW_POINTS then
            local decimated = {reduced[1]}
            for i = 3, #reduced - 1, 2 do
                decimated[#decimated + 1] = reduced[i]
            end
            decimated[#decimated + 1] = reduced[#reduced]
            reduced = decimated
        end
        score.points = reduced
        points = reduced
    end
    local previous = points[#points]
    local movement = point - previous
    if movement.Magnitude < 0.018 then return end
    if movement.Magnitude > 0.65 then
        point = previous + movement.Unit * 0.65
    end
    points[#points + 1] = point
    scorePosition(state, point, movement)
end

endScore = function(player, state, finalPoint)
    local score = state.score
    if score and typeof(finalPoint) == 'Vector3'
        and ScorePath.valid(state.work, finalPoint, score.face, score.sign)
        and #score.points < ScorePath.MAX_RAW_POINTS then
        local last = score.points[#score.points]
        if (last - finalPoint).Magnitude >= 0.016
            and (last - finalPoint).Magnitude <= 0.35 then
            score.points[#score.points + 1] = finalPoint
        end
    end
    state.score = nil
    if not score or #score.points < 2 then return end
    local smoothed = ScorePath.smooth(state.work, score.points)
    if #smoothed < 2 then return end
    local length = 0
    for i = 2, #smoothed do
        length += (smoothed[i] - smoothed[i - 1]).Magnitude
    end
    if length < 0.08 then return end
    score.points = smoothed
    local paths = ScorePath.read(state.work)
    paths[#paths + 1] = score
    while #paths > ScorePath.MAX_PATHS do table.remove(paths, 1) end
    ScorePath.write(state.work, paths)
    drawScore(state.work, paths)
    remote:FireClient(player, 'ScoreSaved', #smoothed)
end

local function setMaterialPositioning(player, state, value)
    if state.processing or type(value) ~= 'boolean' then return end
    state.positioning = value
    state.awaitRelease = true
    state.reversals = 0
    state.direction = 0
    if value then state.goalFrame = state.restingFrame end
    remote:FireClient(player, 'MaterialPositioning', value)
end

local function moveMaterial(player, state, target)
    if not state.positioning or state.processing or not validVector(target) then return end
    local root = rootOf(player)
    local work = state.work
    if not root or not work or not work:IsA('BasePart')
        or (target - root.Position).Magnitude > 24 then return end

    local now = os.clock()
    if now - (state.lastMaterialMove or 0) < 1 / 30 then return end
    state.lastMaterialMove = now

    local bench = workspace:FindFirstChild('Workbench')
    local closest, score = nil, math.huge
    if not bench then return end
    for _, surface in bench:GetDescendants() do
        if surface:IsA('BasePart') and surface.Name:lower() == 'surface' then
            local localPos = surface.CFrame:PointToObjectSpace(target)
            local error = math.max(0, math.abs(localPos.X) - surface.Size.X * 0.5)
                + math.max(0, math.abs(localPos.Z) - surface.Size.Z * 0.5)
            if error < score then closest, score = surface, error end
        end
    end
    if not closest then return end

    local half = work.Size * 0.5
    local x = math.abs(work.CFrame.RightVector:Dot(closest.CFrame.RightVector)) * half.X
        + math.abs(work.CFrame.UpVector:Dot(closest.CFrame.RightVector)) * half.Y
        + math.abs(work.CFrame.LookVector:Dot(closest.CFrame.RightVector)) * half.Z
    local z = math.abs(work.CFrame.RightVector:Dot(closest.CFrame.LookVector)) * half.X
        + math.abs(work.CFrame.UpVector:Dot(closest.CFrame.LookVector)) * half.Y
        + math.abs(work.CFrame.LookVector:Dot(closest.CFrame.LookVector)) * half.Z
    local y = math.abs(work.CFrame.RightVector:Dot(closest.CFrame.UpVector)) * half.X
        + math.abs(work.CFrame.UpVector:Dot(closest.CFrame.UpVector)) * half.Y
        + math.abs(work.CFrame.LookVector:Dot(closest.CFrame.UpVector)) * half.Z
    local localTarget = closest.CFrame:PointToObjectSpace(target)
    local maxX = math.max(0, closest.Size.X * 0.5 - x - 0.025)
    local maxZ = math.max(0, closest.Size.Z * 0.5 - z - 0.025)
    local place = closest.CFrame:PointToWorldSpace(Vector3.new(
        math.clamp(math.round(localTarget.X / 0.04) * 0.04, -maxX, maxX),
        closest.Size.Y * 0.5 + y + 0.035,
        math.clamp(math.round(localTarget.Z / 0.04) * 0.04, -maxZ, maxZ)))
    work.CFrame = CFrame.new(place) * work.CFrame.Rotation
end

local function flipFabricationMaterial(player, state, axis)
    if state.processing or (axis ~= 'X' and axis ~= 'Z') then return end
    local work = state.work
    if not work or not work:IsA('BasePart') then return end

    local former = work.CFrame
    local delta = if axis == 'X' then CFrame.Angles(math.pi, 0, 0)
        else CFrame.Angles(0, 0, math.pi)
    work.CFrame = former * delta

    local size = work.Size * 0.5
    local bottom = work.Position.Y
        - math.abs(work.CFrame.RightVector.Y) * size.X
        - math.abs(work.CFrame.UpVector.Y) * size.Y
        - math.abs(work.CFrame.LookVector.Y) * size.Z
    local oldBottom = former.Position.Y
        - math.abs(former.RightVector.Y) * size.X
        - math.abs(former.UpVector.Y) * size.Y
        - math.abs(former.LookVector.Y) * size.Z
    work.CFrame += Vector3.new(0, oldBottom - bottom, 0)

    state.stroke = 0
    state.lastStroke = 0
    state.lastTurn = 0
    state.direction = 0
    state.reversals = 0
    state.awaitRelease = true
    state.offset = 0
    remote:FireClient(player, 'MaterialFlipped', work)
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
    state.filePoint = nil
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
    elseif action == 'FabricationScoreHover' and state.mode == 'Fabrication'
        and state.kind == 'Scorer' then
        hoverScore(player, state, ...)
    elseif action == 'FabricationScoreBegin' and state.mode == 'Fabrication'
        and state.kind == 'Scorer' then
        beginScore(player, state, ...)
    elseif action == 'FabricationScoreMove' and state.mode == 'Fabrication'
        and state.kind == 'Scorer' then
        extendScore(state, ...)
    elseif action == 'FabricationScoreEnd' and state.mode == 'Fabrication'
        and state.kind == 'Scorer' then
        endScore(player, state, ...)
    elseif action == 'FabricationAutoScore' and state.mode == 'Fabrication'
        and state.kind == 'Saw' then
        beginAutomaticScore(player, state, ...)
    elseif action == 'FabricationMove' and state.mode == 'Fabrication'
        and state.kind ~= 'Scorer' then
        moveFabrication(player, state, ...)
    elseif action == 'FabricationTarget' and state.mode == 'Fabrication' then
        switchFabricationMaterial(player, state, ...)
    elseif action == 'FabricationMaterialFlip' and state.mode == 'Fabrication' then
        flipFabricationMaterial(player, state, ...)
    elseif action == 'MaterialPositioning' and state.mode == 'Fabrication' then
        setMaterialPositioning(player, state, ...)
    elseif action == 'MaterialMove' and state.mode == 'Fabrication' then
        moveMaterial(player, state, ...)
    elseif action == 'FabricationSettings' and state.mode == 'Fabrication' then
        local profile, radius = ...
        if state.kind == 'File' and (profile == 'Round' or profile == 'Chamfer')
            and finite(radius) and radius >= 0.5 and radius <= 100 then
            state.fileShape = profile
            state.fileRadius = radius
        else
            remote:FireClient(player, 'Feedback', 'Invalid file profile or size')
        end
    elseif action == 'FabricationRotate' and state.mode == 'Fabrication'
        and state.kind == 'File' then
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

            if state.autoCut then advanceAutomaticScore(player, state, dt) end

            if state.kind == 'Saw' or state.kind == 'Scorer' then
                state.currentFrame = state.goalFrame
            else
                local alpha = 1 - math.exp(-17 * math.min(dt, 0.1))
                state.currentFrame = state.currentFrame:Lerp(state.goalFrame, alpha)
            end
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
