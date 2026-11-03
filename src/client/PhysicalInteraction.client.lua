local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local ContextActionService = game:GetService('ContextActionService')

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Openworks = ReplicatedStorage:WaitForChild('Openworks')
local FORMMaterial = require(Openworks:WaitForChild('FORMMaterial'))
local ScorePath
local function loadScorePath()
    if ScorePath then return ScorePath end
    local module = Openworks:FindFirstChild('ScorePath')
    if not module or not module:IsA('ModuleScript') then return nil end
    local ok, result = pcall(require, module)
    if not ok then
        warn('[OPENWORKS:Scorer] ScorePath module failed:', result)
        return nil
    end
    ScorePath = result
    return ScorePath
end
local Inspector = require(script.Parent:WaitForChild('InspectionCamera'))
local remote = Openworks:WaitForChild('PhysicalInteraction')
local receiverWarned = false

local function send(action, ...)
    local heartbeat = remote:GetAttribute('HeartbeatAt')
    local alive = type(heartbeat) == 'number'
        and math.abs(workspace:GetServerTimeNow() - heartbeat) < 1.8

    if remote:GetAttribute('Ready') ~= true or not alive then
        if not receiverWarned then
            warn('[OPENWORKS:Interaction] Server receiver is offline or stale; input paused')
            receiverWarned = true
        end
        return false
    end

    receiverWarned = false
    remote:FireServer(action, ...)
    return true
end

local held
local dragging
local fabrication
local pendingTool
local pendingMaterial
local fabricationCollision
local elapsed = 0

local function applyFabricationCollision(entries)
    fabricationCollision = {}
    for _, entry in entries do
        local part = entry[1]
        if typeof(part) == 'Instance' and part:IsA('BasePart') then
            fabricationCollision[part] = {
                collide = entry[2],
                touch = entry[3],
                query = entry[4],
            }
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
        end
    end
end

local function restoreFabricationCollision()
    if not fabricationCollision then return end

    for part, original in fabricationCollision do
        if part.Parent then
            part.CanQuery = true
            part.CanCollide = original.collide
            part.CanTouch = original.touch
            part.CanQuery = original.query
        end
    end

    fabricationCollision = nil
end

local guide = Instance.new('Part')
guide.Name = 'OpenworksCutGuide'
guide.Anchored = true
guide.CanCollide = false
guide.CanTouch = false
guide.CanQuery = false
guide.CastShadow = false
guide.Material = Enum.Material.Neon
guide.Color = Color3.fromRGB(239, 182, 81)
guide.Transparency = 0.15
guide.Size = Vector3.new(0.05, 0.018, 1)
guide.Parent = workspace
guide.Parent = nil

local highlight = Instance.new('Highlight')
highlight.Name = 'OpenworksSelectedMaterial'
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(225, 192, 126)
highlight.OutlineTransparency = 0.25
highlight.Enabled = false
highlight.Parent = workspace

local inspector

local function identify(part)
    local node = part
    while node and node ~= workspace do
        if node:IsA('BasePart') or node:IsA('Model') then
            if node:GetAttribute('isTool') == true then return node, 'Tool' end
            if FORMMaterial.isMarked(node) then return node, 'Material' end
        end
        node = node.Parent
    end
end

local function defaultMaterial()
    local chosen
    for _, node in workspace:GetDescendants() do
        if (node:IsA('BasePart') or node:IsA('Model'))
            and FORMMaterial.isMarked(node)
            and node:GetAttribute('OnWorkbench') == true then
            if chosen then return nil end
            chosen = node
        end
    end
    return chosen
end

local scorePreview = Instance.new('Folder')
scorePreview.Name = 'OpenworksScorePreview'
scorePreview.Parent = workspace

local function clearPreview()
    for _, child in scorePreview:GetChildren() do child:Destroy() end
end

local function scoreWork()
    if not fabrication or not fabrication.material then return nil end
    local item = fabrication.material
    if item:IsA('BasePart') then return item end
    return item.PrimaryPart or item:FindFirstChildWhichIsA('BasePart', true)
end

local function scorePoint(work)
    if not work or not work.Parent then return nil end
    local axis, sign = ScorePath.face(work)
    local normal = work.CFrame:VectorToWorldSpace(ScorePath.normal(axis, sign))
    local half = work.Size * 0.5
    local extent = if axis == 'X' then half.X
        elseif axis == 'Y' then half.Y else half.Z
    local plane = work.CFrame:PointToWorldSpace(ScorePath.normal(axis, sign) * extent)
    local pointer = UserInputService:GetMouseLocation()
    local camera = workspace.CurrentCamera
    local ray = camera:ViewportPointToRay(pointer.X, pointer.Y)
    local denominator = ray.Direction:Dot(normal)
    if math.abs(denominator) < 0.015 then return nil end
    local t = (plane - ray.Origin):Dot(normal) / denominator
    if t < 0 or t > 160 then return nil end
    return ScorePath.project(work, ray.Origin + ray.Direction * t)
end

local function drawPreview(work, a, b)
    if #scorePreview:GetChildren() >= ScorePath.MAX_POINTS then return end
    local distance = (b - a).Magnitude
    if distance < 0.02 then return end
    local face, sign = ScorePath.face(work)
    local normal = work.CFrame:VectorToWorldSpace(ScorePath.normal(face, sign))
    local start = work.CFrame:PointToWorldSpace(a) + normal * 0.017
    local finish = work.CFrame:PointToWorldSpace(b) + normal * 0.017
    local segment = Instance.new('Part')
    segment.Name = 'ScorePreview'
    segment.Size = Vector3.new(0.019, 0.014, distance)
    segment.CFrame = CFrame.lookAt((start + finish) * 0.5, finish)
    segment.Anchored = true
    segment.CanCollide = false
    segment.CanTouch = false
    segment.CanQuery = false
    segment.CastShadow = false
    segment.Material = Enum.Material.Neon
    segment.Color = Color3.fromRGB(242, 188, 106)
    segment.Transparency = 0.12
    segment.Parent = scorePreview
end

local function cancel()
    held = nil
    dragging = nil
    if fabrication and fabrication.kind == 'Scorer' then send('FabricationScoreEnd', fabrication.score and fabrication.score.tip or nil) end
    fabrication = nil
    pendingTool = nil
    pendingMaterial = nil
    guide.Parent = nil
    clearPreview()
    send('End')
end

local function exitInspect()
    local previous = fabrication
    cancel()
    if previous and previous.previousMouseBehavior then
        UserInputService.MouseBehavior = previous.previousMouseBehavior
    end
    inspector:close()
    highlight.Adornee = nil
    highlight.Enabled = false
end

local function chooseTool(tool)
    local material = inspector.material
    if not material or not material.Parent or fabrication then return end
    if tool:GetAttribute('OnWorkbench') ~= true
        and tool ~= workspace:FindFirstChild('Scorer') then
        inspector:status('Place the tool on the workbench first')
        return
    end
    if tool:GetAttribute('FabricationKind') == 'Scorer' and not loadScorePath() then
        inspector:status('ScorePath module unavailable; check Rojo sync for src/shared/ScorePath.lua')
        return
    end
    pendingTool = tool
    inspector:status('Preparing physical tool...')
    if not send('FabricationStart', material, tool) then
        pendingTool = nil
        inspector:status('Interaction receiver offline; restart Play if this persists')
    end
end

local function setFileSettings(profile, radius)
    if fabrication and fabrication.kind == 'File' then
        send('FabricationSettings', profile, radius)
    end
end

local function chooseMaterial(material)
    if not fabrication or pendingMaterial or not material or not material.Parent
        or material == fabrication.material or fabrication.down then return end

    pendingMaterial = material
    if not send('FabricationTarget', material) then
        pendingMaterial = nil
        inspector:status('Interaction receiver is offline; cannot switch material')
    end
end

local function flipSaw()
    if fabrication and fabrication.kind == 'Saw' and not pendingMaterial then
        send('FabricationSawFlip')
    end
end

local function flipMaterial(axis)
    if fabrication and not fabrication.down and not pendingMaterial then
        send('FabricationMaterialFlip', axis)
    end
end

inspector = Inspector.new(chooseTool, exitInspect,
    setFileSettings, chooseMaterial, flipSaw, flipMaterial)

local function inspect(material)
    if not material or not material.Parent then return end
    if fabrication or dragging then send('End') end
    fabrication = nil
    dragging = nil
    inspector:open(material)
    highlight.Adornee = material
    highlight.Enabled = true
end

local function select(item, kind)
    if kind == 'Material' then
        inspect(item)
    elseif kind == 'Tool' then
        local material = inspector.material or defaultMaterial()
        if not material then return end
        if not inspector.material then inspect(material) end
        chooseTool(item)
    end
end

task.spawn(function()
    local bench = workspace:WaitForChild('Workbench', 15)
    local proxies = bench and bench:WaitForChild('OpenworksDetectionProxies', 15)
    if proxies then mouse.TargetFilter = proxies end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if input.KeyCode == Enum.KeyCode.Escape and inspector.material then
        exitInspect()
        return
    end

    if input.KeyCode == Enum.KeyCode.Tab and fabrication and not processed then
        inspector:refreshMaterials()
        local materials = inspector.materials
        if #materials > 1 and not fabrication.down then
            local index = 1
            for i, item in materials do
                if item == fabrication.material then
                    index = i
                    break
                end
            end
            local reverse = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
            local step = if reverse then -1 else 1
            chooseMaterial(materials[((index - 1 + step) % #materials) + 1])
        end
        return
    end

    if fabrication and not processed
        and (input.KeyCode == Enum.KeyCode.X or input.KeyCode == Enum.KeyCode.Z) then
        if not fabrication.down then
            send('FabricationMaterialFlip', if input.KeyCode == Enum.KeyCode.X then 'X' else 'Z')
        end
        return
    end

    if input.KeyCode == Enum.KeyCode.P and fabrication and not processed then
        send('MaterialPositioning', not fabrication.positioning)
        return
    end

    if input.KeyCode == Enum.KeyCode.F and fabrication
        and fabrication.kind == 'Saw' and not processed then
        flipSaw()
        return
    end

    if input.KeyCode == Enum.KeyCode.Q and fabrication and not processed then
        fabrication.axis = if fabrication.axis == 'X' then 'Z' else 'X'
        fabrication.scoreGuide = nil
        fabrication.stroke = 0
        inspector:status('Cut axis: ' .. fabrication.axis)
        return
    end

    if input.KeyCode == Enum.KeyCode.R and fabrication and not processed then
        local backwards = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        send('FabricationRotate', if backwards then -1 else 1)
        inspector:status('Saw roll adjusted 90 degrees')
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseButton1 or processed then return end
    if fabrication then
        if fabrication.positioning then
            local work = fabrication.material
            if work and work:IsA('BasePart') then
                local hit = mouse.Hit.Position
                fabrication.materialDrag = {
                    elevation = work.Position.Y,
                    offset = work.Position - hit,
                }
            end
            return
        end
        local target = mouse.Target
        if target then
            local selected, kind = identify(target)
            if kind == 'Material' and selected ~= fabrication.material then
                chooseMaterial(selected)
                return
            end
        end

        if pendingMaterial then return end
        if fabrication.kind == 'Saw' and fabrication.scoreGuide == 'Curved' then
            inspector:status('Curved scores require a swept-kerf cutter; move off the score for a straight cut')
            return
        end
        if fabrication.kind == 'Scorer' then
            local work = scoreWork()
            local point = scorePoint(work)
            if not point then
                inspector:status('Move the pointer onto the exposed metal face')
                return
            end
            clearPreview()
            fabrication.score = {
                tip = point, lastDrawn = point, lastAt = os.clock(),
            }
            fabrication.down = true
            send('FabricationScoreBegin', point)
            return
        end
        fabrication.down = true
        if not inspector.rightHeld and not inspector.middleHeld then
            fabrication.previousMouseBehavior = UserInputService.MouseBehavior
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
        end
        return
    end

    local part = mouse.Target
    local item, kind
    if part then
        item, kind = identify(part)
    end
    if not item then return end

    held = {
        part = part,
        item = item,
        kind = kind,
        hit = mouse.Hit.Position,
        started = os.clock(),
        screen = UserInputService:GetMouseLocation(),
        moved = false,
    }

    -- Begin real physics immediately. A brief click ends the grab and selects the item.
    if not send('DragStart', part, held.hit) then
        held = nil
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if held and (UserInputService:GetMouseLocation() - held.screen).Magnitude > 6 then
            held.moved = true
        end

        if fabrication and not inspector.rightHeld and not inspector.middleHeld then
            if fabrication.kind == 'Scorer' then
                fabrication.pointerMoved = true
                return
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                fabrication.offset += input.Delta.X * 0.006
            elseif fabrication.down then
                fabrication.stroke = math.clamp(fabrication.stroke + input.Delta.X * 0.008, -12, 12)
            else
                fabrication.pointerMoved = true
            end
        end
    end
end)

local function dropHeld(allowSelect)
    local previous = held
    local wasDragging = dragging ~= nil
    held = nil
    dragging = nil

    if previous or wasDragging then
        send('End')
    end

    if allowSelect and previous and not previous.moved
        and os.clock() - previous.started < 0.24 then
        select(previous.item, previous.kind)
    end
end

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

    if held or dragging then
        dropHeld(true)
        return
    end

    if fabrication then
        if fabrication.kind == 'Scorer' and fabrication.score then
            send('FabricationScoreEnd', fabrication.score and fabrication.score.tip or nil)
            fabrication.score = nil
            clearPreview()
        end
        fabrication.materialDrag = nil
        fabrication.down = false
        fabrication.stroke = 0
        if fabrication.previousMouseBehavior then
            UserInputService.MouseBehavior = fabrication.previousMouseBehavior
            fabrication.previousMouseBehavior = nil
        end
    end
end)

UserInputService.WindowFocusReleased:Connect(function()
    dropHeld(false)
    if fabrication and fabrication.down then
        if fabrication.kind == 'Scorer' then
            send('FabricationScoreEnd', fabrication.score and fabrication.score.tip or nil)
            fabrication.score = nil
            clearPreview()
        end
        fabrication.down = false
        fabrication.stroke = 0
        if fabrication.previousMouseBehavior then
            UserInputService.MouseBehavior = fabrication.previousMouseBehavior
            fabrication.previousMouseBehavior = nil
        end
    end
end)

remote.OnClientEvent:Connect(function(action, a, b, c, d)
    if action == 'DragStarted' then
        if not held or held.part ~= a then
            send('End')
            return
        end

        local camera = workspace.CurrentCamera
        dragging = {
            part = a,
            distance = math.clamp((b - camera.CFrame.Position).Magnitude, 3, 14),
            rotation = a.CFrame.Rotation,
        }
    elseif action == 'DragDenied' then
        if held then
            warn('[OPENWORKS:Drag] ' .. tostring(a))
            held = nil
            dragging = nil
        end
    elseif action == 'FabricationStarted' then
        pendingTool = nil
        applyFabricationCollision(d or {})
        fabrication = {
            kind = a, material = b, tool = c,
            down = false, stroke = 0, offset = 0, axis = 'X',
            fileSide = 1, pointerMoved = true, positioning = false,
            scoreGuide = nil,
        }
        inspector:setTool(a)
        if a == 'File' then
            setFileSettings(inspector.fileShape, inspector.fileRadius)
        end
        guide.Parent = workspace
        if a == 'Saw' then
            inspector:status('Hover to choose a cut. Straight scores attract the saw.')
        elseif a == 'Scorer' then
            inspector:status('Hold LMB on the metal and trace a score. Release to save.')
        else
            inspector:status('Hover an edge, hold LMB and stroke to file it')
        end
    elseif action == 'ScoreSaved' then
        if fabrication and fabrication.kind == 'Scorer' then
            inspector:status('Score saved (' .. tostring(a) .. ' path points). Curved cuts are not available yet.')
        end
    elseif action == 'MaterialPositioning' then
        if fabrication then
            fabrication.positioning = a == true
            fabrication.materialDrag = nil
            fabrication.down = false
            guide.Parent = if fabrication.positioning then nil else workspace
            inspector:status(if fabrication.positioning
                then 'POSITION MATERIAL: drag sheet, X/Z flip, P to finish'
                else 'Workpiece positioned. Resume machining.')
        end
    elseif action == 'MaterialFlipped' then
        if fabrication then
            fabrication.down = false
            fabrication.stroke = 0
            fabrication.offset = 0
            fabrication.pointerMoved = true
            if fabrication.previousMouseBehavior then
                UserInputService.MouseBehavior = fabrication.previousMouseBehavior
                fabrication.previousMouseBehavior = nil
            end
            inspector:status('Workpiece flipped. Top-facing surface is now active.')
        end
    elseif action == 'SawFlipChanged' then
        if fabrication and fabrication.kind == 'Saw' then
            inspector:status(if a
                then 'Saw flipped 180° — press F to reverse'
                else 'Saw unflipped — press F to reverse')
        end
    elseif action == 'FabricationTargetChanged' then
        pendingMaterial = nil
        if fabrication and a and a.Parent then
            fabrication.material = a
            fabrication.down = false
            fabrication.stroke = 0
            fabrication.offset = 0
            fabrication.pointerMoved = true
            if fabrication.previousMouseBehavior then
                UserInputService.MouseBehavior = fabrication.previousMouseBehavior
                fabrication.previousMouseBehavior = nil
            end
            inspector:focusMaterial(a)
            highlight.Adornee = a
            inspector:status('Now machining: ' .. a.Name)
        end
    elseif action == 'Progress' then
        if fabrication then
            inspector:status('Manual passes: ' .. math.floor(a * 100) .. '%')
        end
    elseif action == 'MachiningCompleted' then
        if fabrication then
            local keepSawing = fabrication.kind == 'Saw' and fabrication.down
            if not keepSawing then
                if fabrication.previousMouseBehavior then
                    UserInputService.MouseBehavior = fabrication.previousMouseBehavior
                    fabrication.previousMouseBehavior = nil
                end
                fabrication.down = false
                fabrication.stroke = 0
                fabrication.pointerMoved = false
            end

            if not keepSawing and fabrication.kind == 'Saw' and typeof(c) == 'Vector3'
                and a and a:IsA('BasePart') and a.Parent then
                local aim = c
                local camera = workspace.CurrentCamera
                local cursor = UserInputService:GetMouseLocation()
                local ray = camera:ViewportPointToRay(cursor.X, cursor.Y)
                local normal = a.CFrame.UpVector
                local top = a.Position + normal * a.Size.Y * 0.5
                local denominator = ray.Direction:Dot(normal)

                if math.abs(denominator) > 0.01 then
                    local t = (top - ray.Origin):Dot(normal) / denominator
                    if t > 0 then
                        local hit = ray.Origin + ray.Direction * t
                        local localHit = a.CFrame:PointToObjectSpace(hit)
                        if math.abs(localHit.X) <= a.Size.X * 0.5
                            and math.abs(localHit.Z) <= a.Size.Z * 0.5 then
                            aim = hit
                        end
                    end
                end

                local localAim = a.CFrame:PointToObjectSpace(aim)
                local extent = if fabrication.axis == 'X' then a.Size.X else a.Size.Z
                local target = if fabrication.axis == 'X' then localAim.X else localAim.Z
                fabrication.offset = math.clamp(target,
                    -math.max(0, extent * 0.5 - 0.17),
                    math.max(0, extent * 0.5 - 0.17))
            end

            inspector:status(b or 'Finished. Aim at the next cut and continue.')
        end
    elseif action == 'Feedback' then
        pendingMaterial = nil
        pendingTool = nil
        if inspector.material then inspector:status(a) end
    elseif action == 'Ended' then
        clearPreview()
        pendingMaterial = nil
        restoreFabricationCollision()
        dragging = nil
        if fabrication then
            if fabrication.previousMouseBehavior then
                UserInputService.MouseBehavior = fabrication.previousMouseBehavior
            end
            guide.Parent = nil
            fabrication = nil
            if inspector.material then inspector:setTool(nil) end
        end
    end
end)

local function shifting()
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

ContextActionService:BindActionAtPriority('OpenworksRotateDrag', function()
    if dragging and shifting() then return Enum.ContextActionResult.Sink end
    return Enum.ContextActionResult.Pass
end, false, 3000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D)

ContextActionService:BindActionAtPriority('OpenworksDragDepth', function(_, state, input)
    if not dragging then return Enum.ContextActionResult.Pass end
    if state == Enum.UserInputState.Change then
        dragging.distance = math.clamp(dragging.distance - input.Position.Z * 0.8, 3, 14)
    end
    return Enum.ContextActionResult.Sink
end, false, 3000, Enum.UserInputType.MouseWheel)

RunService.RenderStepped:Connect(function(dt)
    if fabricationCollision then
        for part in fabricationCollision do
            if part.Parent then
                part.CanCollide = false
                part.CanTouch = false
                part.CanQuery = false
            end
        end
    end

    if inspector.material and os.clock() - inspector.lastRefresh > 0.65 then
        inspector.lastRefresh = os.clock()
        if fabrication then
            inspector:refreshMaterials()
        else
            inspector:refreshTools()
        end
    end

    if dragging and held and shifting() then
        local yaw = (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
            - (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0)
        local pitch = (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0)
            - (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
        if yaw ~= 0 or pitch ~= 0 then
            dragging.rotation = CFrame.Angles(0, yaw * math.rad(95) * dt, 0)
                * dragging.rotation * CFrame.Angles(pitch * math.rad(95) * dt, 0, 0)
        end
    end

    if fabrication and fabrication.positioning then
        guide.Parent = nil
        if fabrication.materialDrag then
            local drag = fabrication.materialDrag
            local pointer = UserInputService:GetMouseLocation()
            local ray = workspace.CurrentCamera:ViewportPointToRay(pointer.X, pointer.Y)
            if math.abs(ray.Direction.Y) > 0.01 then
                local t = (drag.elevation - ray.Origin.Y) / ray.Direction.Y
                if t > 0 then
                    local point = ray.Origin + ray.Direction * t + drag.offset
                    elapsed += dt
                    if elapsed >= 1 / 30 then
                        elapsed = 0
                        send('MaterialMove', point)
                    end
                end
            end
        end
        return
    end

    if fabrication and fabrication.kind == 'Scorer' then
        local work = scoreWork()
        local point = scorePoint(work)
        if work and point then
            guide.Parent = workspace
            local face, sign = ScorePath.face(work)
            local normal = work.CFrame:VectorToWorldSpace(ScorePath.normal(face, sign))
            guide.Size = Vector3.new(0.06, 0.014, 0.06)
            guide.Color = Color3.fromRGB(244, 187, 98)
            guide.CFrame = CFrame.new(work.CFrame:PointToWorldSpace(point) + normal * 0.018)

            if fabrication.down and fabrication.score then
                local score = fabrication.score
                local elapsedScore = math.clamp(os.clock() - score.lastAt, 1 / 120, 0.06)
                score.lastAt = os.clock()
                local desired = point - score.tip
                local alpha = 1 - math.exp(-12 * elapsedScore)
                local move = desired * alpha
                if score.previous then
                    local direction = score.tip - score.previous
                    if direction.Magnitude > 0.008 then
                        local along = direction.Unit
                        local parallel = along * move:Dot(along)
                        move = parallel + (move - parallel) * 0.48
                    end
                end
                if move.Magnitude > 0.006 then
                    local nextTip = score.tip + move
                    score.previous = score.tip
                    score.tip = nextTip
                    if (nextTip - score.lastDrawn).Magnitude > 0.02 then
                        drawPreview(work, score.lastDrawn, nextTip)
                        score.lastDrawn = nextTip
                    end
                    score.lastSentAt = score.lastSentAt or 0
                    if os.clock() - score.lastSentAt >= 1 / 30 then
                        score.lastSentAt = os.clock()
                        send('FabricationScoreMove', nextTip)
                    end
                end
            end
        else
            guide.Parent = nil
        end
        return
    end

    if fabrication then
        local item = fabrication.material
        local work = if item and item:IsA('BasePart') then item
            elseif item and item:IsA('Model') then item.PrimaryPart
            else nil

        if not work or not work.Parent then
            guide.Parent = nil
        else
            local size = work.Size
            if fabrication.pointerMoved and not fabrication.down then
                fabrication.pointerMoved = false

                local camera = workspace.CurrentCamera
                local mousePosition = UserInputService:GetMouseLocation()
                local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Exclude
                rayParams.FilterDescendantsInstances = {fabrication.tool, guide}
                local hit = workspace:Raycast(ray.Origin, ray.Direction * 150, rayParams)

                if hit and (hit.Instance == work or hit.Instance:IsDescendantOf(work)) then
                    local point = work.CFrame:PointToObjectSpace(hit.Position)
                    if fabrication.kind == 'File' then
                        local normal = work.CFrame:VectorToObjectSpace(Vector3.yAxis)
                        local face = if math.abs(normal.X) >= math.abs(normal.Y)
                            and math.abs(normal.X) >= math.abs(normal.Z) then 'X'
                            elseif math.abs(normal.Z) >= math.abs(normal.Y) then 'Z'
                            else 'Y'
                        local distances = {
                            X = size.X * 0.5 - math.abs(point.X),
                            Y = size.Y * 0.5 - math.abs(point.Y),
                            Z = size.Z * 0.5 - math.abs(point.Z),
                        }
                        local candidate
                        for _, checkAxis in {'X', 'Y', 'Z'} do
                            if checkAxis ~= face and
                                (not candidate or distances[checkAxis] < distances[candidate]) then
                                candidate = checkAxis
                            end
                        end
                        fabrication.axis = candidate
                        local coordinate = if candidate == 'X' then point.X
                            elseif candidate == 'Y' then point.Y else point.Z
                        fabrication.fileSide = if coordinate >= 0 then 1 else -1
                    elseif fabrication.kind ~= 'Saw' then
                        fabrication.offset = if fabrication.axis == 'X' then point.X else point.Z
                    end
                end

                if fabrication.kind == 'Saw' then
                    local hovered = loadScorePath() and scorePoint(work)
                    local matched = hovered and ScorePath.guide(work, hovered, 0.22)
                    local previousGuide = fabrication.scoreGuide
                    fabrication.scoreGuide = matched and matched.kind or nil

                    if matched and matched.kind == 'Straight' then
                        fabrication.axis = matched.axis
                        fabrication.offset = matched.offset
                        if previousGuide ~= 'Straight' then
                            inspector:status('STRAIGHT SCORE ENGAGED — saw blade follows the marked line')
                        end
                    else
                        if matched and matched.kind == 'Curved'
                            and previousGuide ~= 'Curved' then
                            inspector:status('CURVED SCORE — visible guide only; swept cutting not implemented')
                        elseif not matched and previousGuide then
                            inspector:status('Freehand straight cut — hover a score to align')
                        end
                        if hit and (hit.Instance == work or hit.Instance:IsDescendantOf(work)) then
                            local point = work.CFrame:PointToObjectSpace(hit.Position)
                            fabrication.offset = if fabrication.axis == 'X' then point.X else point.Z
                        end
                    end
                end
            end

            local span = if fabrication.axis == 'X' then size.X else size.Z
            local maximum = math.max(0, span * 0.5 - 0.17)
            fabrication.offset = math.clamp(fabrication.offset, -maximum, maximum)

            local guideHeight = size.Y * 0.5 + 0.025
            guide.Color = if fabrication.kind == 'File'
                then Color3.fromRGB(125, 215, 184)
                elseif fabrication.kind == 'Saw' and fabrication.scoreGuide == 'Straight'
                then Color3.fromRGB(82, 225, 176)
                else Color3.fromRGB(239, 182, 81)
            if fabrication.kind == 'File' then
                local up = work.CFrame:VectorToObjectSpace(Vector3.yAxis)
                local face = if math.abs(up.X) >= math.abs(up.Y)
                    and math.abs(up.X) >= math.abs(up.Z) then 'X'
                    elseif math.abs(up.Z) >= math.abs(up.Y) then 'Z'
                    else 'Y'
                local sign = if (if face == 'X' then up.X
                    elseif face == 'Y' then up.Y else up.Z) >= 0 then 1 else -1
                local sideAxis = fabrication.axis
                if sideAxis == face then
                    sideAxis = if face == 'X' then 'Z' else 'X'
                    fabrication.axis = sideAxis
                end
                local along
                for _, a in {'X', 'Y', 'Z'} do
                    if a ~= face and a ~= sideAxis then along = a break end
                end
                local vectors = {X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis}
                local extent = {X = size.X, Y = size.Y, Z = size.Z}
                local center = vectors[face] * sign * (extent[face] * 0.5 + 0.025)
                    + vectors[sideAxis] * fabrication.fileSide * extent[sideAxis] * 0.5
                local travel = vectors[along]
                local top = vectors[face] * sign
                guide.Size = Vector3.new(extent[along], 0.02, 0.055)
                guide.CFrame = work.CFrame
                    * CFrame.fromMatrix(center, travel, top, travel:Cross(top))
            elseif fabrication.axis == 'X' then
                guide.Size = Vector3.new(0.055, 0.02, size.Z)
                guide.CFrame = work.CFrame * CFrame.new(fabrication.offset, guideHeight, 0)
            else
                guide.Size = Vector3.new(size.X, 0.02, 0.055)
                guide.CFrame = work.CFrame * CFrame.new(0, guideHeight, fabrication.offset)
            end
        end
    end

    if not dragging and not fabrication then return end
    elapsed += dt
    if elapsed < 1 / 30 then return end
    elapsed = 0

    if dragging and held then
        local ray = mouse.UnitRay
        send('DragMove',
            ray.Origin + ray.Direction.Unit * dragging.distance, dragging.rotation)
    elseif fabrication then
        send('FabricationMove',
            fabrication.stroke, fabrication.offset, fabrication.axis,
            fabrication.down, fabrication.fileSide)
    end
end)

player.CharacterRemoving:Connect(exitInspect)
print('[OPENWORKS:Interaction] Client ready')
