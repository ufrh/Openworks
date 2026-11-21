-- The first playable OpenWorks build controller.
-- 1 = Place, 2 = Select, G = Move, R/F = Resize, Backspace = Delete,
-- Ctrl+Z/Ctrl+Y = Undo/Redo. This is a prototype interaction surface;
-- final first-person handles and SmartFit arrive in later slices.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FORGE = require(ReplicatedStorage.FORGE)
local Units = require(ReplicatedStorage.OpenWorks.Shared.Units)

local BuildController = FORGE.Class("Controller", {
    Name = "BuildController",
})

local player = Players.LocalPlayer
local mode = "Place"
local document = nil
local selected = nil
local busy = false
local service
local ghost
local selectionHighlight
local status
local connections = {}
local hoveredPosition = nil

local function createUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "OpenWorksBuildUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = player:WaitForChild("PlayerGui")

    local instructions = Instance.new("TextLabel")
    instructions.Name = "Controls"
    instructions.AnchorPoint = Vector2.new(0.5, 1)
    instructions.Position = UDim2.new(0.5, 0, 1, -22)
    instructions.Size = UDim2.fromOffset(700, 60)
    instructions.BackgroundColor3 = Color3.fromRGB(17, 22, 30)
    instructions.BackgroundTransparency = 0.23
    instructions.BorderSizePixel = 0
    instructions.Font = Enum.Font.Code
    instructions.TextColor3 = Color3.fromRGB(228, 237, 248)
    instructions.TextSize = 15
    instructions.TextWrapped = true
    instructions.Text = "OPENWORKS"
    instructions.Parent = gui

    local crosshair = Instance.new("Frame")
    crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
    crosshair.Position = UDim2.fromScale(0.5, 0.5)
    crosshair.Size = UDim2.fromOffset(4, 4)
    crosshair.BackgroundColor3 = Color3.fromRGB(180, 218, 255)
    crosshair.BorderSizePixel = 0
    crosshair.Parent = gui

    return gui, instructions
end

local function message(extra)
    if not status then return end
    local count = if document then #document.blocks else 0
    status.Text = string.format(
        "OPENWORKS | %s | %d blocks | %s\n1 Place  2 Select  G Move  R/F Resize  Backspace Delete  Ctrl+Z/Y Undo/Redo%s",
        mode, count,
        if document and document.persistent then "Saving enabled" else "Local test / save unavailable",
        if extra then "\n" .. extra else ""
    )
end

local function findBlock(id)
    if not document then return nil end
    for _, block in ipairs(document.blocks) do
        if block.id == id then return block end
    end
    return nil
end

local function applySnapshot(incoming)
    if type(incoming) ~= "table" or incoming.ready ~= true then return end
    if document and incoming.revision < document.revision then return end
    document = incoming
    if selected and not findBlock(selected) then
        selected = nil
    end
    message()
end

local function submit(action, payload)
    if busy or not document then return end
    busy = true
    task.spawn(function()
        local ok, accepted, result = pcall(function()
            return service:Submit(action, payload or {}, document.revision)
        end)
        if not ok then
            message("Server request failed: " .. tostring(accepted))
        elseif accepted then
            applySnapshot(result)
            message(action .. " accepted")
        else
            message(tostring(result))
            local ok2, latest = pcall(function()
                return service:GetSnapshot()
            end)
            if ok2 then applySnapshot(latest) end
        end
        busy = false
    end)
end

local function getTarget()
    local camera = Workspace.CurrentCamera
    if not camera then return nil end
    local viewport = camera.ViewportSize
    local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignored = {}
    if player.Character then table.insert(ignored, player.Character) end
    if ghost then table.insert(ignored, ghost) end
    if mode == "Move" and selected then
        local runtime = Workspace:FindFirstChild("OpenWorksRuntime")
        local own = runtime and runtime:FindFirstChild(tostring(player.UserId))
        local moving = own and own:FindFirstChild(selected)
        if moving then table.insert(ignored, moving) end
    end
    params.FilterDescendantsInstances = ignored
    params.IgnoreWater = true
    return Workspace:Raycast(ray.Origin, ray.Direction * 65, params)
end

local function snapWorld(position)
    return Vector3.new(
        Units.SnapStuds(position.X),
        Units.SnapStuds(position.Y),
        Units.SnapStuds(position.Z)
    )
end

local function chosenPart()
    if not selected then return nil end
    local runtime = Workspace:FindFirstChild("OpenWorksRuntime")
    local own = runtime and runtime:FindFirstChild(tostring(player.UserId))
    return own and own:FindFirstChild(selected)
end

local function render()
    local hit = getTarget()
    hoveredPosition = nil
    local isPreview = mode == "Place" or (mode == "Move" and selected ~= nil)
    local size = Vector3.new(1, 1, 1)
    if mode == "Move" and selected then
        local block = findBlock(selected)
        if block then
            size = Vector3.new(
                Units.ToStuds(block.sx),
                Units.ToStuds(block.sy),
                Units.ToStuds(block.sz)
            )
        end
    end
    if isPreview and hit then
        -- Axis-aligned face placement, with a flush offset and grid snapping.
        local normal = hit.Normal
        local clearance = (math.abs(normal.X) * size.X
            + math.abs(normal.Y) * size.Y
            + math.abs(normal.Z) * size.Z) * 0.5
        local position = snapWorld(hit.Position + normal * clearance)
        if position.Y >= size.Y * 0.5 and position.Y < 512 then
            hoveredPosition = position
        end
    end
    if ghost then
        ghost.Size = size
        ghost.Transparency = if hoveredPosition then 0.55 else 1
        if hoveredPosition then ghost.CFrame = CFrame.new(hoveredPosition) end
    end
    if selectionHighlight then
        selectionHighlight.Adornee = chosenPart()
    end
end

local function click()
    if not document or busy then return end
    if mode == "Place" then
        if hoveredPosition then submit("Place", { position = hoveredPosition }) end
    elseif mode == "Move" then
        if hoveredPosition and selected then
            submit("Move", { id = selected, position = hoveredPosition })
            mode = "Select"
            message()
        end
    else
        local hit = getTarget()
        local instance = hit and hit.Instance
        local owner = instance and instance:GetAttribute("OpenWorksOwner")
        selected = if owner == player.UserId then instance:GetAttribute("OpenWorksId") else nil
        message(if selected then "Selected block" else "Nothing selected")
    end
end

local function onKey(input, gameProcessed)
    if gameProcessed or UserInputService:GetFocusedTextBox() then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        click()
        return
    end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    local control = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

    if control and input.KeyCode == Enum.KeyCode.Z then
        submit("Undo", {})
    elseif control and input.KeyCode == Enum.KeyCode.Y then
        submit("Redo", {})
    elseif input.KeyCode == Enum.KeyCode.One then
        mode = "Place"
        message()
    elseif input.KeyCode == Enum.KeyCode.Two then
        mode = "Select"
        message()
    elseif input.KeyCode == Enum.KeyCode.G and selected then
        mode = "Move"
        message()
    elseif input.KeyCode == Enum.KeyCode.Backspace and selected then
        submit("Delete", { id = selected })
    elseif input.KeyCode == Enum.KeyCode.R and selected then
        submit("Resize", { id = selected, delta = 250 })
    elseif input.KeyCode == Enum.KeyCode.F and selected then
        submit("Resize", { id = selected, delta = -250 })
    end
end

function BuildController:Start()
    player.CameraMode = Enum.CameraMode.LockFirstPerson
    local ui
    ui, status = createUI()
    self._UI = ui

    ghost = Instance.new("Part")
    ghost.Name = "OpenWorksPlacementGhost"
    ghost.Anchored = true
    ghost.CanCollide = false
    ghost.CanTouch = false
    ghost.CanQuery = false
    ghost.CastShadow = false
    ghost.Material = Enum.Material.ForceField
    ghost.Color = Color3.fromRGB(52, 146, 218)
    ghost.Transparency = 1
    ghost.Size = Vector3.new(1, 1, 1)
    ghost.Parent = Workspace

    selectionHighlight = Instance.new("Highlight")
    selectionHighlight.Name = "OpenWorksSelection"
    selectionHighlight.OutlineColor = Color3.fromRGB(66, 168, 255)
    selectionHighlight.FillColor = Color3.fromRGB(66, 168, 255)
    selectionHighlight.FillTransparency = 0.82
    selectionHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    selectionHighlight.Parent = Workspace

    service = FORGE.GetService("ConstructionService")
    table.insert(connections, service.DocumentChanged:Connect(applySnapshot))
    table.insert(connections, UserInputService.InputBegan:Connect(onKey))
    table.insert(connections, RunService.RenderStepped:Connect(render))

    message("Loading construction document...")
    task.spawn(function()
        while not document do
            local ok, response = pcall(function()
                return service:GetSnapshot()
            end)
            if ok then
                applySnapshot(response)
            else
                message("Waiting for server...")
            end
            if not document then task.wait(0.35) end
        end
    end)
end

function BuildController:Destroy()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    if ghost then ghost:Destroy() end
    if selectionHighlight then selectionHighlight:Destroy() end
    if self._UI then self._UI:Destroy() end
end

return BuildController
