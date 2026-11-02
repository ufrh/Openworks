local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local ContextActionService = game:GetService('ContextActionService')

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Openworks = ReplicatedStorage:WaitForChild('Openworks')
local FORMMaterial = require(Openworks:WaitForChild('FORMMaterial'))
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

local function cancel()
    held = nil
    dragging = nil
    fabrication = nil
    pendingTool = nil
    guide.Parent = nil
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
    if tool:GetAttribute('OnWorkbench') ~= true then
        inspector:status('Place the tool on the workbench first')
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

inspector = Inspector.new(chooseTool, exitInspect, setFileSettings)

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

    if input.KeyCode == Enum.KeyCode.Q and fabrication and not processed then
        fabrication.axis = if fabrication.axis == 'X' then 'Z' else 'X'
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
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
                fabrication.offset += input.Delta.X * 0.006
            elseif fabrication.down then
                fabrication.stroke = math.clamp(fabrication.stroke + input.Delta.X * 0.03, -1, 1)
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
            fileSide = 1, pointerMoved = false,
        }
        inspector:setTool(a)
        if a == 'File' then
            setFileSettings(inspector.fileShape, inspector.fileRadius)
        end
        guide.Parent = workspace
        if a == 'Saw' then
            inspector:status('Hover the sheet to set a cut, then hold LMB to saw')
        else
            inspector:status('Hover an edge, hold LMB and stroke to file it')
        end
    elseif action == 'Progress' then
        if fabrication then
            inspector:status('Manual passes: ' .. math.floor(a * 100) .. '%')
        end
    elseif action == 'MachiningCompleted' then
        if fabrication then
            if fabrication.previousMouseBehavior then
                UserInputService.MouseBehavior = fabrication.previousMouseBehavior
                fabrication.previousMouseBehavior = nil
            end
            fabrication.down = false
            fabrication.stroke = 0
            fabrication.pointerMoved = false

            if fabrication.kind == 'Saw' and typeof(c) == 'Vector3'
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
        pendingTool = nil
        if inspector.material then inspector:status(a) end
    elseif action == 'Ended' then
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

    if inspector.material and not fabrication and os.clock() - inspector.lastRefresh > 0.65 then
        inspector.lastRefresh = os.clock()
        inspector:refreshTools()
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
                        local distanceX = size.X * 0.5 - math.abs(point.X)
                        local distanceZ = size.Z * 0.5 - math.abs(point.Z)
                        if distanceX <= distanceZ then
                            fabrication.axis = 'X'
                            fabrication.fileSide = if point.X >= 0 then 1 else -1
                        else
                            fabrication.axis = 'Z'
                            fabrication.fileSide = if point.Z >= 0 then 1 else -1
                        end
                    else
                        fabrication.offset = if fabrication.axis == 'X' then point.X else point.Z
                    end
                end
            end

            local span = if fabrication.axis == 'X' then size.X else size.Z
            local maximum = math.max(0, span * 0.5 - 0.17)
            fabrication.offset = math.clamp(fabrication.offset, -maximum, maximum)

            local guideHeight = size.Y * 0.5 + 0.025
            guide.Color = if fabrication.kind == 'File'
                then Color3.fromRGB(125, 215, 184)
                else Color3.fromRGB(239, 182, 81)
            if fabrication.kind == 'File' then
                if fabrication.axis == 'X' then
                    guide.Size = Vector3.new(0.06, 0.02, size.Z)
                    guide.CFrame = work.CFrame
                        * CFrame.new(fabrication.fileSide * size.X * 0.5,
                            guideHeight, 0)
                else
                    guide.Size = Vector3.new(size.X, 0.02, 0.06)
                    guide.CFrame = work.CFrame
                        * CFrame.new(0, guideHeight,
                            fabrication.fileSide * size.Z * 0.5)
                end
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
