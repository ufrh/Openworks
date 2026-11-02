local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local ContextActionService = game:GetService('ContextActionService')

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local remote = ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('ToolDrag')

local dragging
local pending = false
local down = false
local elapsed = 0
local speed = math.rad(95)

local function toolPart(part)
    local current = part
    while current and current ~= workspace do
        if (current:IsA('Model') or current:IsA('BasePart'))
            and current:GetAttribute('isTool') == true then
            return part
        end
        current = current.Parent
    end
end

local function stop()
    down = false
    pending = false
    if dragging then
        dragging = nil
        remote:FireServer('End')
    end
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or down then
        return
    end

    local part = mouse.Target
    if not part or not toolPart(part) then
        return
    end

    down = true
    pending = true
    remote:FireServer('Start', part, mouse.Hit.Position)
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        stop()
    end
end)

remote.OnClientEvent:Connect(function(action, part, hit)
    if action == 'Ended' then
        dragging = nil
        pending = false
        return
    end

    if action ~= 'Started' then
        return
    end

    pending = false
    if not down then
        remote:FireServer('End')
        return
    end

    local camera = workspace.CurrentCamera
    dragging = {
        part = part,
        distance = math.clamp((hit - camera.CFrame.Position).Magnitude, 3, 14),
        rotation = part.CFrame.Rotation,
    }
    elapsed = 1
end)

local function modifier()
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

ContextActionService:BindActionAtPriority('OpenworksDragRotation', function(_, state, input)
    if dragging and modifier() then
        return Enum.ContextActionResult.Sink
    end
    return Enum.ContextActionResult.Pass
end, false, 3000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D)

ContextActionService:BindActionAtPriority('OpenworksDragDepth', function(_, state, input)
    if not dragging then
        return Enum.ContextActionResult.Pass
    end

    if state == Enum.UserInputState.Change then
        dragging.distance = math.clamp(dragging.distance - input.Position.Z * 0.8, 3, 14)
    end
    return Enum.ContextActionResult.Sink
end, false, 3000, Enum.UserInputType.MouseWheel)

RunService.RenderStepped:Connect(function(dt)
    if not dragging or not down then
        return
    end

    if not dragging.part.Parent then
        stop()
        return
    end

    if modifier() then
        local yaw = (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
            - (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0)
        local pitch = (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0)
            - (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)

        if yaw ~= 0 or pitch ~= 0 then
            dragging.rotation = CFrame.Angles(0, yaw * speed * dt, 0)
                * dragging.rotation * CFrame.Angles(pitch * speed * dt, 0, 0)
        end
    end

    elapsed += dt
    if elapsed < 1 / 30 then
        return
    end
    elapsed = 0

    local ray = mouse.UnitRay
    local position = ray.Origin + ray.Direction.Unit * dragging.distance
    remote:FireServer('Move', position, dragging.rotation)
end)

player.CharacterRemoving:Connect(stop)
