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

local previewSegments = {}
local function clearPreview()
    for _, child in previewSegments do child:Destroy() end
    table.clear(previewSegments)
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

local function drawSmoothedPreview(work, points)
    points = ScorePath.reduce(points, 0.006)
    local face, sign = ScorePath.face(work)
    local normal = work.CFrame:VectorToWorldSpace(ScorePath.normal(face, sign))
    local index = 0
    for i = 2, #points do
        local a = work.CFrame:PointToWorldSpace(points[i - 1]) + normal * 0.017
        local b = work.CFrame:PointToWorldSpace(points[i]) + normal * 0.017
        local length = (b - a).Magnitude
        if length < 0.004 then continue end
        index += 1
        local segment = previewSegments[index]
        if not segment then
            segment = Instance.new('Part')
            segment.Name = 'ScorePreview'
            segment.Anchored = true
            segment.CanCollide = false
            segment.CanTouch = false
            segment.CanQuery = false
            segment.CastShadow = false
            segment.Material = Enum.Material.Neon
            segment.Color = Color3.fromRGB(242, 188, 106)
            segment.Transparency = 0.12
            segment.Parent = scorePreview
            previewSegments[index] = segment
        end
        segment.Size = Vector3.new(0.019, 0.014, length)
        segment.CFrame = CFrame.lookAt((a + b) * 0.5, b)
        segment.Parent = scorePreview
    end
    for i = index + 1, #previewSegments do
        previewSegments[i].Parent = nil
    end
end

local curvedPreview = Instance.new('Folder')
curvedPreview.Name = 'OpenworksCurvedSawGuide'
curvedPreview.Parent = workspace
local previewWork, previewPoints

local function clearCurvedGuide()
    for _, child in curvedPreview:GetChildren() do child:Destroy() end
    previewWork, previewPoints = nil, nil
end

local function showCurvedGuide(work, points)
    if not work or not points then clearCurvedGuide() return end
    if previewWork == work and previewPoints == points then return end
    clearCurvedGuide()
    previewWork, previewPoints = work, points
    local visualPoints = ScorePath.reduce(points, 0.006)
    local face, sign = ScorePath.face(work)
    local up = work.CFrame:VectorToWorldSpace(ScorePath.normal(face, sign))
    for i = 2, #visualPoints do
        local a = work.CFrame:PointToWorldSpace(visualPoints[i - 1]) + up * 0.022
        local b = work.CFrame:PointToWorldSpace(visualPoints[i]) + up * 0.022
        local len = (b - a).Magnitude
        if len > 0.007 then
            local part = Instance.new('Part')
            part.Name = 'ScoreGuide'
            part.Size = Vector3.new(0.026, 0.014, len)
            part.CFrame = CFrame.lookAt((a + b) * 0.5, b)
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Material = Enum.Material.Neon
            part.Color = Color3.fromRGB(82, 225, 176)
            part.CastShadow = false
            part.Parent = curvedPreview
        end
    end
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
    clearCurvedGuide()
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
        or material == fabrication.material or fabrication.down
        or fabrication.autoPending or fabrication.autoRunning then return end

    pendingMaterial = material
    if not send('FabricationTarget', material) then
        pendingMaterial = nil
        inspector:status('Interaction receiver is offline; cannot switch material')
    end
end

local function flipMaterial(axis)
    if fabrication and not fabrication.down and not pendingMaterial then
        send('FabricationMaterialFlip', axis)
    end
end

inspector = Inspector.new(chooseTool, exitInspect,
    setFileSettings, chooseMaterial, flipMaterial)

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
        if not fabrication.down and not fabrication.autoPending
            and not fabrication.autoRunning then
            send('FabricationMaterialFlip', if input.KeyCode == Enum.KeyCode.X then 'X' else 'Z')
        end
        return
    end

    if input.KeyCode == Enum.KeyCode.P and fabrication and not processed then
        if fabrication.autoPending or fabrication.autoRunning then return end
        send('MaterialPositioning', not fabrication.positioning)
        return
    end

    if input.KeyCode == Enum.KeyCode.Q and fabrication and not processed then
        if fabrication.autoPending or fabrication.autoRunning then return end
        fabrication.axis = if fabrication.axis == 'X' then 'Z' else 'X'
        fabrication.scoreGuide = nil
        fabrication.scoreLine = nil
        fabrication.scoreReference = nil
        clearCurvedGuide()
        fabrication.pointerMoved = true
        fabrication.stroke = 0
        inspector:status('Cut axis: ' .. fabrication.axis)
        return
    end

    if input.KeyCode == Enum.KeyCode.R and fabrication
        and fabrication.kind == 'File' and not processed then
        local backwards = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        send('FabricationRotate', if backwards then -1 else 1)
        inspector:status('File roll adjusted 90 degrees')
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

        if pendingMaterial or fabrication.autoPending or fabrication.autoRunning then return end
        if fabrication.kind == 'Saw' and loadScorePath() then
            local work = scoreWork()
            local point = work and scorePoint(work)
            local matched = point and ScorePath.guide(work, point, 0.22)
            if matched then
                fabrication.autoPending = true
                fabrication.down = false
                fabrication.stroke = 0
                if not send('FabricationAutoScore', point) then
                    fabrication.autoPending = false
                    inspector:status('Interaction receiver offline; automatic sawing unavailable')
                else
                    inspector:status('Preparing automatic cut along ' .. matched.kind:lower() .. ' score')
                end
                return
            end
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
                tip = point, lastAt = os.clock(),
                samples = {point}, previewAt = 0,
            }
            fabrication.down = true
            send('FabricationScoreBegin', point)
            return
        end
        if fabrication.kind == 'File' then
            send('FabricationFileLock', fabrication.filePoint)
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
            if fabrication.autoPending or fabrication.autoRunning then return end
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
        if fabrication.kind == 'File' then
            send('FabricationFileUnlock')
            fabrication.fileLocked = false
            fabrication.fileSnap = nil
        end
        if fabrication.kind == 'Scorer' and fabrication.score then
            send('FabricationScoreEnd', fabrication.score and fabrication.score.tip or nil)
            fabrication.score = nil
            clearPreview()
        end
        fabrication.materialDrag = nil
        fabrication.down = false
        fabrication.stroke = 0
        fabrication.pointerMoved = true
        if fabrication.previousMouseBehavior then
            UserInputService.MouseBehavior = fabrication.previousMouseBehavior
            fabrication.previousMouseBehavior = nil
        end
    end
end)

UserInputService.WindowFocusReleased:Connect(function()
    dropHeld(false)
    if fabrication and fabrication.down then
        if fabrication.kind == 'File' then
            send('FabricationFileUnlock')
            fabrication.fileLocked = false
            fabrication.fileSnap = nil
        end
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

remote.OnClientEvent:Connect(function(action, a, b, c, d, e)
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
            clearCurvedGuide()
        applyFabricationCollision(d or {})
        fabrication = {
            kind = a, material = b, tool = c,
            down = false, stroke = 0, offset = 0, axis = 'X',
            autoPending = false, autoRunning = false,
            fileSide = 1, pointerMoved = true, positioning = false,
            scoreGuide = nil, scoreLine = nil, scoreReference = nil,
            filePoint = nil, fileSnap = nil, fileLocked = false,
            scoreContactOffset = if typeof(e) == 'CFrame' then e else CFrame.identity,
        }
        inspector:setTool(a)
        if a == 'Scorer' then
            local function show(part)
                if part:IsA('BasePart') then part.LocalTransparencyModifier = 0 end
            end
            show(c)
            for _, part in c:GetDescendants() do show(part) end
        end
        if a == 'File' then
            setFileSettings(inspector.fileShape, inspector.fileRadius)
        end
        guide.Parent = workspace
        if a == 'Saw' then
            inspector:status('Click a saved score for automatic cutting. Saw unmarked metal manually.')
        elseif a == 'Scorer' then
            inspector:status('Hold LMB on the metal and trace a score. Release to save.')
        else
            inspector:status('Hover until an edge glows green, then hold LMB and file along it')
        end
    elseif action == 'FileEdgeGuide' then
        if fabrication and fabrication.kind == 'File'
            and not fabrication.fileLocked and not fabrication.down then
            fabrication.fileSnap = if typeof(a) == 'Vector3'
                and typeof(b) == 'Vector3'
                then {point = a, tangent = b} else nil
        end
    elseif action == 'FileEdgeLocked' then
        if fabrication and fabrication.kind == 'File' and fabrication.down then
            fabrication.fileLocked = typeof(a) == 'Vector3'
            fabrication.fileSnap = if fabrication.fileLocked
                and typeof(b) == 'Vector3'
                then {point = a, tangent = b} else nil
            if fabrication.fileLocked then
                inspector:status('EDGE LOCKED — file strokes follow the contour')
            else
                inspector:status('No edge nearby. Move closer to a material edge.')
            end
        end
    elseif action == 'AutoScoreStarted' then
        if fabrication and fabrication.kind == 'Saw' then
            fabrication.autoPending = false
            fabrication.autoRunning = true
            fabrication.down = false
            fabrication.stroke = 0
            inspector:status('Automatically cutting ' .. tostring(a):lower() .. ' score')
        end
    elseif action == 'AutoScoreProgress' then
        if fabrication and fabrication.kind == 'Saw' and fabrication.autoRunning then
            inspector:status('Automatic sawing: ' .. math.floor(math.clamp(a, 0, 1) * 100) .. '%')
        end
    elseif action == 'AutoScoreFinished' then
        if fabrication and fabrication.kind == 'Saw' then
            fabrication.autoPending = false
            fabrication.autoRunning = false
            fabrication.down = false
            fabrication.stroke = 0
            fabrication.scoreGuide = nil
            fabrication.scoreLine = nil
            fabrication.scoreReference = nil
            fabrication.pointerMoved = true
            clearCurvedGuide()
            inspector:status(b or (if a then 'Automatic cut complete' else 'Automatic cut failed'))
        end
    elseif action == 'ScoreSaved' then
        if fabrication and fabrication.kind == 'Scorer' then
            inspector:status('Score saved (' .. tostring(a) .. ' path points).')
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
        clearCurvedGuide()
        if fabrication then
            fabrication.down = false
            fabrication.stroke = 0
            fabrication.offset = 0
            fabrication.filePoint = nil
            fabrication.fileSnap = nil
            fabrication.fileLocked = false
            fabrication.pointerMoved = true
            fabrication.scoreGuide = nil
            fabrication.scoreLine = nil
            fabrication.scoreReference = nil
            if fabrication.previousMouseBehavior then
                UserInputService.MouseBehavior = fabrication.previousMouseBehavior
                fabrication.previousMouseBehavior = nil
            end
            inspector:status('Workpiece flipped. Top-facing surface is now active.')
        end
    elseif action == 'FabricationTargetChanged' then
        clearCurvedGuide()
        pendingMaterial = nil
        if fabrication and a and a.Parent then
            fabrication.material = a
            fabrication.down = false
            fabrication.stroke = 0
            fabrication.offset = 0
            fabrication.filePoint = nil
            fabrication.fileSnap = nil
            fabrication.fileLocked = false
            fabrication.pointerMoved = true
            fabrication.scoreGuide = nil
            fabrication.scoreLine = nil
            fabrication.scoreReference = nil
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
            if fabrication.kind == 'Saw' and fabrication.scoreGuide == 'Curved' then
                inspector:status('Cutting along curved score: ' .. math.floor(a * 100) .. '%')
            else
                inspector:status('Manual passes: ' .. math.floor(a * 100) .. '%')
            end
        end
    elseif action == 'MachiningCompleted' then
        if fabrication then
            local scoredComplete = fabrication.kind == 'Saw'
                and fabrication.scoreReference ~= nil and a ~= nil
            local keepSawing = fabrication.kind == 'Saw' and fabrication.down
                and not scoredComplete
            if scoredComplete then
                clearCurvedGuide()
                fabrication.scoreGuide = nil
                fabrication.scoreLine = nil
                fabrication.scoreReference = nil
            end
            if not keepSawing then
                if fabrication.previousMouseBehavior then
                    UserInputService.MouseBehavior = fabrication.previousMouseBehavior
                    fabrication.previousMouseBehavior = nil
                end
                fabrication.down = false
                fabrication.stroke = 0
                fabrication.pointerMoved = true
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
        if fabrication and fabrication.kind == 'Saw' then
            fabrication.autoPending = false
        end
        if inspector.material then inspector:status(a) end
    elseif action == 'Ended' then
        clearPreview()
            clearCurvedGuide()
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
                local alpha = 1 - math.exp(-24 * elapsedScore)
                local move = desired * alpha
                if move.Magnitude > 0.22 then
                    move = move.Unit * 0.22
                end
                if move.Magnitude > 0.004 then
                    local nextTip = score.tip + move
                    score.previous = score.tip
                    score.tip = nextTip
                    local samples = score.samples
                    if not samples or (nextTip - samples[#samples]).Magnitude >= 0.007 then
                        samples[#samples + 1] = nextTip
                        if #samples > ScorePath.MAX_RAW_POINTS then
                            local reduced = ScorePath.reduce(samples, 0.006)
                            if #reduced > ScorePath.MAX_RAW_POINTS then
                                local downsampled = {reduced[1]}
                                for i = 3, #reduced - 1, 2 do
                                    downsampled[#downsampled + 1] = reduced[i]
                                end
                                downsampled[#downsampled + 1] = reduced[#reduced]
                                reduced = downsampled
                            end
                            score.samples = reduced
                        end
                    end
                    score.lastSentAt = score.lastSentAt or 0
                    if os.clock() - score.lastSentAt >= 1 / 30 then
                        score.lastSentAt = os.clock()
                        send('FabricationScoreMove', nextTip)
                    end
                end
                if os.clock() - score.previewAt >= 1 / 12 then
                    score.previewAt = os.clock()
                    drawSmoothedPreview(work,
                        ScorePath.smooth(work, score.samples))
                end
            else
                fabrication.scoreHoverAt = fabrication.scoreHoverAt or 0
                if os.clock() - fabrication.scoreHoverAt >= 1 / 20 then
                    fabrication.scoreHoverAt = os.clock()
                    send('FabricationScoreHover', point)
                end
            end

            local tracked = if fabrication.score then fabrication.score.tip else point
            guide.CFrame = CFrame.new(work.CFrame:PointToWorldSpace(tracked)
                + normal * 0.018)
            if fabrication.tool and fabrication.tool.Parent then
                local score = fabrication.score
                local tangent = score and score.previous
                    and (score.tip - score.previous) or nil
                fabrication.scorerFrame = ScorePath.contactFrame(work, tracked, tangent)
                    * fabrication.scoreContactOffset
                fabrication.tool:PivotTo(fabrication.scorerFrame)
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
            if fabrication.pointerMoved and not fabrication.down
                and not fabrication.autoPending and not fabrication.autoRunning then
                fabrication.pointerMoved = false
                if fabrication.kind == 'File' then
                    fabrication.filePoint = nil
                end

                local camera = workspace.CurrentCamera
                local mousePosition = UserInputService:GetMouseLocation()
                local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
                local rayParams = RaycastParams.new()
                rayParams.FilterType = Enum.RaycastFilterType.Exclude
                rayParams.FilterDescendantsInstances = {fabrication.tool, guide}
                local hit = workspace:Raycast(ray.Origin, ray.Direction * 150, rayParams)
                if fabrication.kind == 'File'
                    and (not hit or not (hit.Instance == work
                        or hit.Instance:IsDescendantOf(work))) then
                    fabrication.fileSnap = nil
                end

                if hit and (hit.Instance == work or hit.Instance:IsDescendantOf(work)) then
                    local point = work.CFrame:PointToObjectSpace(hit.Position)
                    if fabrication.kind == 'File' then
                        fabrication.filePoint = point
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
                    fabrication.scoreLine = if matched and matched.kind == 'Straight'
                        then matched else nil
                    fabrication.scoreReference = if matched then hovered else nil
                    if matched and matched.kind == 'Curved' then
                        showCurvedGuide(work, matched.points)
                    else
                        clearCurvedGuide()
                    end

                    if matched and matched.kind == 'Straight' then
                        if matched.axis then
                            fabrication.axis = matched.axis
                            fabrication.offset = matched.offset
                        end
                        if previousGuide ~= 'Straight' then
                            inspector:status('STRAIGHT SCORE ENGAGED — saw blade follows the marked line')
                        end
                    else
                        if matched and matched.kind == 'Curved'
                            and previousGuide ~= 'Curved' then
                            inspector:status('CURVED SCORE ENGAGED — hold LMB and saw back and forth to advance')
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
            if fabrication.kind == 'Saw' and loadScorePath() then
                local face, sign = ScorePath.face(work)
                if face == 'Y' then guideHeight *= sign end
            end
            guide.Transparency = if fabrication.kind == 'Saw'
                and fabrication.scoreGuide == 'Straight' then 0.04 else 0.15
            guide.Color = if fabrication.kind == 'File'
                then Color3.fromRGB(125, 215, 184)
                elseif fabrication.kind == 'Saw' and fabrication.scoreGuide == 'Straight'
                then Color3.fromRGB(82, 225, 176)
                else Color3.fromRGB(239, 182, 81)
            if fabrication.kind == 'Saw' and fabrication.scoreGuide == 'Curved' then
                guide.Parent = nil
            elseif fabrication.kind == 'Saw' and fabrication.scoreLine then
                guide.Parent = workspace
                local line = fabrication.scoreLine
                local direction = work.CFrame:VectorToWorldSpace(line.tangent)
                local worldPoint = work.CFrame:PointToWorldSpace(
                    line.point + Vector3.new(0, guideHeight - line.point.Y, 0))
                guide.Size = Vector3.new(0.027, 0.018, line.length)
                guide.CFrame = CFrame.lookAt(worldPoint,
                    worldPoint + direction, work.CFrame.UpVector)
            elseif fabrication.kind == 'File' then
                guide.Parent = workspace
                if fabrication.fileSnap then
                    local snap = fabrication.fileSnap
                    local surfaceUp = work.CFrame:VectorToWorldSpace(
                        Vector3.new(0, if work.CFrame.UpVector.Y >= 0 then 1 else -1, 0))
                    local tangent = work.CFrame:VectorToWorldSpace(snap.tangent).Unit
                    local point = work.CFrame:PointToWorldSpace(snap.point)
                        + surfaceUp * 0.024
                    guide.Size = Vector3.new(0.045, 0.018, 0.75)
                    guide.CFrame = CFrame.lookAt(point,
                        point + tangent, surfaceUp)
                    guide.Color = Color3.fromRGB(82, 225, 176)
                    guide.Transparency = 0.03
                else
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
                if fabrication.filePoint then
                    center = fabrication.filePoint
                        + vectors[face] * (sign * 0.025)
                end
                local travel = vectors[along]
                local top = vectors[face] * sign
                guide.Size = Vector3.new(extent[along], 0.02, 0.055)
                guide.CFrame = work.CFrame
                    * CFrame.fromMatrix(center, travel, top, travel:Cross(top))
                end
            elseif fabrication.axis == 'X' then
                guide.Parent = workspace
                guide.Size = Vector3.new(
                    if fabrication.scoreGuide == 'Straight' then 0.026 else 0.055, 0.02, size.Z)
                guide.CFrame = work.CFrame * CFrame.new(fabrication.offset, guideHeight, 0)
            else
                guide.Parent = workspace
                guide.Size = Vector3.new(size.X, 0.02,
                    if fabrication.scoreGuide == 'Straight' then 0.026 else 0.055)
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
    elseif fabrication and not fabrication.autoPending and not fabrication.autoRunning then
        send('FabricationMove',
            fabrication.stroke, fabrication.offset, fabrication.axis,
            fabrication.down, fabrication.fileSide,
            if fabrication.kind == 'File' then fabrication.filePoint
                else fabrication.scoreReference)
    end
end)

RunService:BindToRenderStep('OpenworksScorerPose',
    Enum.RenderPriority.Camera.Value + 2, function()
        local state = fabrication
        if state and state.kind == 'Scorer' and state.scorerFrame
            and state.tool and state.tool.Parent then
            state.tool:PivotTo(state.scorerFrame)
        end
    end)

player.CharacterRemoving:Connect(exitInspect)
print('[OPENWORKS:Interaction] Client ready')
