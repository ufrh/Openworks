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

local drag
local click
local requested = false
local fab
local elapsed = 0
local pendingTool

local highlight = Instance.new('Highlight')
highlight.Name = 'OpenworksSelectedMaterial'
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(225, 192, 126)
highlight.OutlineTransparency = 0.25
highlight.Enabled = false
highlight.Parent = workspace

local inspector

local function identify(part)
    local current = part
    while current and current ~= workspace do
        if current:IsA('Model') or current:IsA('BasePart') then
            if current:GetAttribute('isTool') == true then return current, 'Tool' end
            if FORMMaterial.isMarked(current) then return current, 'Material' end
        end
        current = current.Parent
    end
end

local function defaultMaterial()
    local chosen
    for _, node in workspace:GetDescendants() do
        if (node:IsA('BasePart') or node:IsA('Model'))
            and FORMMaterial.isMarked(node) and node:GetAttribute('OnWorkbench') == true then
            if chosen then return nil end
            chosen = node
        end
    end
    return chosen
end

local function endSession()
    remote:FireServer('End')
    fab = nil
    pendingTool = nil
    drag = nil
    requested = false
    click = nil
end

local function exitInspect()
    endSession()
    inspector:close()
    highlight.Enabled = false
    highlight.Adornee = nil
end

local function chooseTool(tool)
    local material = inspector.material
    if not material or not material.Parent or fab then return end
    if tool:GetAttribute('OnWorkbench') ~= true then
        inspector:status('Place the tool on the workbench first')
        return
    end
    pendingTool = tool
    inspector:status('Preparing physical tool...')
    remote:FireServer('FabricationStart', material, tool)
end

inspector = Inspector.new(chooseTool, exitInspect)

local function inspect(item)
    if not item or not item.Parent then return end
    endSession()
    inspector:open(item)
    highlight.Adornee = item
    highlight.Enabled = true
end

local function shortClick(item, kind)
    if kind == 'Material' then
        inspect(item)
        return
    end
    if kind == 'Tool' then
        local material = inspector.material or defaultMaterial()
        if not material then return end
        if not inspector.material then inspect(material) end
        chooseTool(item)
    end
end

local function dragBegin()
    if not click or requested then return end
    requested = true
    remote:FireServer('DragStart', click.part, click.hit)
end

UserInputService.InputBegan:Connect(function(input, processed)
    if input.KeyCode == Enum.KeyCode.Escape and inspector.material then
        exitInspect()
        return
    end
    if input.KeyCode == Enum.KeyCode.Q and fab and not processed then
        fab.axis = if fab.axis == 'X' then 'Z' else 'X'
        fab.stroke = 0
        inspector:status('Cut axis: ' .. fab.axis)
        return
    end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 or processed then return end

    if fab then
        fab.down = true
        return
    end

    local part = mouse.Target
    local item, kind = part and identify(part)
    if not item then return end

    click = {
        part = part,
        item = item,
        kind = kind,
        hit = mouse.Hit.Position,
        screen = UserInputService:GetMouseLocation(),
        started = os.clock(),
    }
    requested = false
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if fab then
        fab.down = false
        return
    end

    local old = click
    click = nil

    if requested or drag then
        remote:FireServer('End')
        drag = nil
        requested = false
    elseif old then
        shortClick(old.item, old.kind)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement or not fab then return end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
        fab.offset += input.Delta.X * 0.006
    elseif fab.down then
        fab.stroke = math.clamp(fab.stroke + input.Delta.X * 0.012, -1, 1)
    end
end)

remote.OnClientEvent:Connect(function(action, a, b, c)
    if action == 'DragStarted' then
        if not requested or not click then
            remote:FireServer('End')
            return
        end
        local camera = workspace.CurrentCamera
        drag = {
            part = a,
            distance = math.clamp((b - camera.CFrame.Position).Magnitude, 3, 14),
            rotation = a.CFrame.Rotation,
        }
    elseif action == 'FabricationStarted' then
        pendingTool = nil
        fab = {kind = a, material = b, tool = c, down = false, stroke = 0, offset = 0, axis = 'X'}
        inspector:setTool(a)
    elseif action == 'Progress' then
        if fab then inspector:status('Manual passes: ' .. math.floor(a * 100) .. '%') end
    elseif action == 'MachiningCompleted' then
        fab = nil
        pendingTool = nil
        if a and a.Parent then
            inspect(a)
            inspector:status(b or 'Material updated')
        elseif inspector.material then
            inspector:setTool(nil)
            inspector:status(b or 'Operation ended')
        end
    elseif action == 'Feedback' then
        pendingTool = nil
        if inspector.material then inspector:status(a) end
    elseif action == 'Ended' then
        drag = nil
        requested = false
        if fab then
            fab = nil
            if inspector.material then inspector:setTool(nil) end
        end
    end
end)

local function shiftDown()
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

ContextActionService:BindActionAtPriority('OpenworksRotateDrag', function()
    if drag and shiftDown() then return Enum.ContextActionResult.Sink end
    return Enum.ContextActionResult.Pass
end, false, 3000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D)

ContextActionService:BindActionAtPriority('OpenworksDragDepth', function(_, state, input)
    if not drag then return Enum.ContextActionResult.Pass end
    if state == Enum.UserInputState.Change then
        drag.distance = math.clamp(drag.distance - input.Position.Z * 0.8, 3, 14)
    end
    return Enum.ContextActionResult.Sink
end, false, 3000, Enum.UserInputType.MouseWheel)

RunService.RenderStepped:Connect(function(dt)
    if click and not requested then
        local distance = (UserInputService:GetMouseLocation() - click.screen).Magnitude
        if distance > 7 or os.clock() - click.started > 0.25 then
            dragBegin()
        end
    end

    if inspector.material and not fab and os.clock() - inspector.lastRefresh > 0.65 then
        inspector.lastRefresh = os.clock()
        inspector:refreshTools()
    end

    if drag and click then
        if shiftDown() then
            local yaw = (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
                - (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0)
            local pitch = (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0)
                - (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
            if yaw ~= 0 or pitch ~= 0 then
                drag.rotation = CFrame.Angles(0, yaw * math.rad(95) * dt, 0)
                    * drag.rotation * CFrame.Angles(pitch * math.rad(95) * dt, 0, 0)
            end
        end
    end

    if not drag and not fab then return end
    elapsed += dt
    if elapsed < 1 / 30 then return end
    elapsed = 0

    if drag and click then
        local ray = mouse.UnitRay
        remote:FireServer('DragMove', ray.Origin + ray.Direction.Unit * drag.distance, drag.rotation)
    elseif fab then
        remote:FireServer('FabricationMove', fab.stroke, fab.offset, fab.axis)
    end
end)

player.CharacterRemoving:Connect(function()
    exitInspect()
end)
