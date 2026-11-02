local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local Stock = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('Stock'))
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local SawTube = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('SawTube'))
local Renderer = require(script.Parent.FORMRenderer)
local Grab = require(script.Parent.StockGrab)

local UI = {}

local function button(parent, caption, callback)
    local control = Instance.new('TextButton')
    control.Size = UDim2.new(1, -12, 0, 30)
    control.BackgroundColor3 = Color3.fromRGB(48, 57, 57)
    control.TextColor3 = Color3.fromRGB(238, 230, 216)
    control.Font = Enum.Font.Code
    control.TextSize = 13
    control.Text = caption
    control.BorderSizePixel = 0
    control.Parent = parent
    control.MouseButton1Click:Connect(callback)
    return control
end

local function label(parent, text, height)
    local item = Instance.new('TextLabel')
    item.BackgroundTransparency = 1
    item.Size = UDim2.new(1, -12, 0, height or 24)
    item.Text = text
    item.Font = Enum.Font.Code
    item.TextSize = 13
    item.TextColor3 = Color3.fromRGB(216, 221, 213)
    item.TextWrapped = true
    item.Parent = parent
    return item
end

local function row(parent, names, onChoose)
    local holder = Instance.new('Frame')
    holder.Size = UDim2.new(1, -12, 0, 30)
    holder.BackgroundTransparency = 1
    holder.Parent = parent
    local layout = Instance.new('UIListLayout')
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 3)
    layout.Parent = holder
    for _, name in names do
        local control = button(holder, name, function() onChoose(name) end)
        control.Size = UDim2.new(1 / #names, -3, 1, 0)
    end
end

local function entry(parent, title, initial)
    local box = Instance.new('TextBox')
    box.Name = title
    box.Size = UDim2.new(1, -12, 0, 28)
    box.BackgroundColor3 = Color3.fromRGB(58, 67, 66)
    box.TextColor3 = Color3.fromRGB(241, 239, 224)
    box.PlaceholderText = title
    box.Text = tostring(initial)
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Code
    box.TextSize = 13
    box.Parent = parent
    return box
end

function UI.start()
    local player = Players.LocalPlayer
    local gui = Instance.new('ScreenGui')
    gui.Name = 'OpenworksStock'
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = player:WaitForChild('PlayerGui')

    local frame = Instance.new('ScrollingFrame')
    frame.Name = 'StockPanel'
    frame.AnchorPoint = Vector2.new(0, 0.5)
    frame.Position = UDim2.new(0, 14, 0.5, 0)
    frame.Size = UDim2.fromOffset(290, 370)
    frame.ScrollBarThickness = 4
    frame.CanvasSize = UDim2.fromOffset(0, 0)
    frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    frame.BackgroundColor3 = Color3.fromRGB(25, 31, 32)
    frame.BackgroundTransparency = 0.06
    frame.BorderSizePixel = 0
    frame.Parent = gui
    local stack = Instance.new('UIListLayout')
    stack.SortOrder = Enum.SortOrder.LayoutOrder
    stack.Padding = UDim.new(0, 5)
    stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
    stack.Parent = frame
    label(frame, 'OPENWORKS / RAW STOCK', 32)

    local shape, metal = 'Block', 'Steel'
    local current = {}
    local nextId = 0
    local selected
    local spacing = 6
    local world = Instance.new('Folder')
    world.Name = 'OPENWORKS Raw Stock'
    world.Parent = workspace

    local surface = Instance.new('Part')
    surface.Name = 'Stock Work Surface'
    surface.Anchored = true
    surface.CanCollide = true
    surface.Size = Vector3.new(36, 0.6, 20)
    surface.CFrame = CFrame.new(0, 3.2, 3)
    surface.Material = Enum.Material.Metal
    surface.Color = Color3.fromRGB(62, 68, 70)
    surface.Parent = world

    local bindings = {}
    local grab = Grab.new()
    local status = label(frame, 'Select a shape and material', 48)

    local sizeA = entry(frame, 'X / Outer diameter (mm)', 60)
    local sizeB = entry(frame, 'Y / Length (mm)', 20)
    local sizeC = entry(frame, 'Z / Bore diameter (mm)', 40)

    local function displayStatus(message)
        status.Text = message
        print('[STOCK] ' .. message)
    end

    local function refreshSelection()
        if selected and not current[selected] then selected = nil end
        for id, display in bindings do
            if display.part then
                display.part.Color = if id == selected then Color3.fromRGB(226, 178, 94)
                    else Stock.MATERIALS[current[id].material].color
            end
        end
        if selected then
            local item = current[selected]
            displayStatus(string.format('#%d %s / %s  %.1f mm³  %.4f kg',
                item.id, item.material, item.shape, item.volume, item.massKg))
        else
            displayStatus(string.format('%d independent pieces / select from the scene', next(current) and (function()
                local count = 0
                for _ in current do count += 1 end
                return count
            end)() or 0))
        end
    end

    local function countPieces()
        local n = 0
        for _ in current do n += 1 end
        return n
    end

    local function createDisplay(item)
        local part, editable
        local dims = item.dimensions
        if item.shape == 'Block' or item.shape == 'Sheet' then
            part = Instance.new('Part')
            part.Size = Vector3.new(dims.x, dims.y, dims.z) * Stock.SCALE
        elseif item.shape == 'Rod' then
            part = Instance.new('Part')
            part.Shape = Enum.PartType.Cylinder
            part.Size = Vector3.new(dims.length, dims.radius * 2, dims.radius * 2) * Stock.SCALE
        else
            local low, high = FORM.bounds(item.solid)
            local bounds = high - low
            local expected = bounds.X * bounds.Y * bounds.Z
            if math.abs(expected - item.volume) < math.max(0.02, expected * 1e-5)
                and bounds.X > 0.001 and bounds.Y > 0.001 and bounds.Z > 0.001 then
                part = Instance.new('Part')
                part.Size = bounds * Stock.SCALE
            else
                part, editable = Renderer.create(item.solid, Stock.SCALE, 0)
            end
        end
        part.Name = string.format('Stock %03d - %s', item.id, item.shape)
        part.Anchored = true
        part.CanCollide = true
        part.CanTouch = true
        local visualOffset = if item.shape == 'Rod' then CFrame.Angles(0, 0, math.rad(90))
            else CFrame.identity
        part.CFrame = item.frame * visualOffset
        part.CustomPhysicalProperties = PhysicalProperties.new(
            if item.material == 'Steel' then 7.85 else 2.7, 0.65, 0.15, 100, 100)
        part.Material = Enum.Material.SmoothPlastic
        part.Color = Stock.MATERIALS[item.material].color
        part:SetAttribute('StockId', item.id)
        return {part = part, editable = editable, visualOffset = visualOffset}
    end

    local function destroyDisplay(binding)
        if not binding then return end
        if grab.active and grab.active.part == binding.part then grab:release() end
        binding.part:Destroy()
        if binding.editable then
            pcall(function() binding.editable:Destroy() end)
        end
    end

    local function install(item, binding, anchored)
        assert(not current[item.id], 'Workpiece identity already allocated')
        nextId = math.max(nextId, item.id)
        current[item.id] = item
        bindings[item.id] = binding
        binding.part.Parent = world
        binding.part.Anchored = anchored == true
        selected = item.id
    end

    local function spawn(shapeName, materialName, dims, at)
        assert(nextId < 10000, 'Stock ID budget exceeded')
        assert(countPieces() < Stock.MAX_ITEMS, 'Maximum number of stock items reached')
        local item = Stock.create(nextId + 1, shapeName, materialName, dims, at)
        local binding = createDisplay(item)
        install(item, binding, false)
        refreshSelection()
        return item
    end

    local function cloneSolid(solid)
        local copy = {vertices = table.clone(solid.vertices), triangles = {}}
        for i, face in solid.triangles do copy.triangles[i] = table.clone(face) end
        return copy
    end

    local function fragmentRecord(id, source, solid, originalFrame, tubeProfile)
        local low, high = FORM.bounds(solid)
        local offset = (low + high) / 2
        local centered = cloneSolid(solid)
        for i, vertex in centered.vertices do centered.vertices[i] = vertex - offset end
        local vol = FORM.signedVolume(centered)
        assert(vol > 0 and FORM.validate(centered).ok, 'Invalid saw fragment')
        return {
            id = id, shape = 'Fabricated', material = source.material,
            dimensions = nil, solid = centered, frame = originalFrame * CFrame.new(offset * Stock.SCALE),
            tubeProfile = tubeProfile and SawTube.offsetProfile(tubeProfile, offset) or nil,
            volume = vol, massKg = vol * Stock.MATERIALS[source.material].density / 1000000,
        }
    end

    local function separate(part, solids, stats)
        local id = part:GetAttribute('StockId')
        local source = id and current[id]
        if not source or bindings[id].part ~= part then return nil, 'Workpiece no longer exists' end
        if countPieces() >= Stock.MAX_ITEMS then return nil, 'Stock limit reached' end
        if #solids ~= 2 then return nil, 'Saw must produce two pieces' end
        local profiles = stats and stats.tubeProfiles
        local first = fragmentRecord(nextId + 1, source, solids[1], source.frame,
            profiles and profiles[1])
        local second = fragmentRecord(nextId + 2, source, solids[2], source.frame,
            profiles and profiles[2])
        local prepared = {}
        local ok, err = pcall(function()
            prepared[1] = createDisplay(first)
            prepared[2] = createDisplay(second)
        end)
        if not ok then
            for _, binding in prepared do destroyDisplay(binding) end
            return nil, 'Could not render both cut pieces: ' .. tostring(err)
        end
        local original = bindings[id]
        local secured = part.Anchored
        local inheritedVelocity = part.AssemblyLinearVelocity
        local inheritedSpin = part.AssemblyAngularVelocity
        local holdFirst = first.volume >= second.volume
        destroyDisplay(original)
        bindings[id] = nil
        current[id] = nil
        install(first, prepared[1], secured and holdFirst)
        install(second, prepared[2], secured and not holdFirst)
        if not secured then
            for _, binding in prepared do
                binding.part.AssemblyLinearVelocity = inheritedVelocity
                binding.part.AssemblyAngularVelocity = inheritedSpin
            end
        end
        selected = if holdFirst then first.id else second.id
        refreshSelection()
        return true
    end

    local function refine(part, solid)
        local id = part and part:GetAttribute('StockId')
        local source = id and current[id]
        if not source or not bindings[id] or bindings[id].part ~= part then
            return nil, 'Workpiece no longer exists'
        end
        if not part.Anchored then return nil, 'Secure the metal before filing' end
        local ok, record = pcall(fragmentRecord, id, source, solid, source.frame)
        if not ok then return nil, 'Invalid filed geometry: ' .. tostring(record) end
        local created, binding = pcall(createDisplay, record)
        if not created then
            return nil, 'Could not render filed geometry: ' .. tostring(binding)
        end

        local original = bindings[id]
        destroyDisplay(original)
        current[id] = record
        bindings[id] = binding
        binding.part.Parent = world
        binding.part.Anchored = true
        selected = id
        refreshSelection()
        return true
    end

    local function selectedAction(action)
        if not selected or not current[selected] then
            displayStatus('Select a workpiece first')
            return
        end
        local ok, err = pcall(action, current[selected])
        if not ok then displayStatus('Operation failed: ' .. tostring(err)) return end
        refreshSelection()
    end

    row(frame, {'Block', 'Sheet', 'Rod', 'Tube'}, function(value)
        shape = value
        if value == 'Sheet' then
            sizeA.Text, sizeB.Text, sizeC.Text = '100', '5', '60'
        elseif value == 'Rod' then
            sizeA.Text, sizeB.Text = '12', '100'
        elseif value == 'Tube' then
            sizeA.Text, sizeB.Text, sizeC.Text = '12', '100', '6'
        else
            sizeA.Text, sizeB.Text, sizeC.Text = '60', '20', '40'
        end
        displayStatus('Shape: ' .. value)
    end)
    row(frame, {'Steel', 'Aluminum'}, function(value)
        metal = value
        displayStatus('Material: ' .. value)
    end)

    button(frame, 'SPAWN STOCK', function()
        local a, b, c = tonumber(sizeA.Text), tonumber(sizeB.Text), tonumber(sizeC.Text)
        local dimensions = if shape == 'Rod' then {radius = a / 2, length = b}
            elseif shape == 'Tube' then {radius = a / 2, innerRadius = c / 2, length = b}
            else {x = a, y = b, z = c}
        local ok, err = pcall(function()
            local count = 0
            for _ in current do count += 1 end
            local origin = CFrame.new((count % 5 - 2) * spacing, 7, -4 - math.floor(count / 5) * spacing)
            spawn(shape, metal, dimensions, origin)
        end)
        if not ok then displayStatus('Spawn failed: ' .. tostring(err)) end
    end)

    label(frame, 'CLICK + HOLD a piece to drag with physics. Mouse wheel changes reach.', 42)
    button(frame, 'TEMPORARILY SECURE / RELEASE', function()
        selectedAction(function(item)
            if grab.active and grab.active.part == bindings[item.id].part then grab:release() end
            local part = bindings[item.id].part
            part.Anchored = not part.Anchored
            if part.Anchored then
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
                displayStatus('Workpiece secured (temporary workholding)')
            else
                displayStatus('Workpiece released to physics')
            end
        end)
    end)

    button(frame, 'DUPLICATE SELECTED', function()
        selectedAction(function(item)
            if item.shape ~= 'Fabricated' then
                spawn(item.shape, item.material, item.dimensions,
                    item.frame + Vector3.new(1.5, 1, 0))
            else
                assert(countPieces() < Stock.MAX_ITEMS, 'Stock limit reached')
                local copy = fragmentRecord(nextId + 1, item, item.solid,
                    item.frame + Vector3.new(1.5, 1, 0), item.tubeProfile)
                install(copy, createDisplay(copy), false)
            end
        end)
    end)
    button(frame, 'DELETE SELECTED', function()
        selectedAction(function(item)
            destroyDisplay(bindings[item.id])
            bindings[item.id] = nil
            current[item.id] = nil
            selected = nil
        end)
    end)
    button(frame, 'SELECT NEXT PIECE', function()
        local ids = {}
        for id in current do ids[#ids + 1] = id end
        table.sort(ids)
        if #ids == 0 then selected = nil
        else
            local nextIndex = 1
            for i, id in ids do if id == selected then nextIndex = i % #ids + 1 break end end
            selected = ids[nextIndex]
        end
        refreshSelection()
    end)

    local mouse = player:GetMouse()
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if UserInputService:GetFocusedTextBox() then return end
        if player.Character and (player.Character:FindFirstChild('Hacksaw')
            or player.Character:FindFirstChild('Metal File')) then return end
        local target = mouse.Target
        if not target then return end
        local id = target:GetAttribute('StockId')
        if not id or not current[id] then return end
        selected = id
        refreshSelection()
        grab:begin(target, mouse.Hit.Position, mouse)
    end)
    RunService.Heartbeat:Connect(function()
        for id, binding in bindings do
            local item = current[id]
            if item and binding.part.Parent then
                Stock.move(item, binding.part.CFrame * binding.visualOffset:Inverse())
            end
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then grab:release() end
    end)
    UserInputService.InputChanged:Connect(function(input, processed)
        if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
        grab:changeDistance(-input.Position.Z * 0.75)
    end)

    local defaults = {
        {'Block', 'Steel', {x = 60, y = 20, z = 40}},
        {'Sheet', 'Aluminum', {x = 90, y = 4, z = 60}},
        {'Rod', 'Steel', {radius = 6, length = 80}},
        {'Tube', 'Aluminum', {radius = 8, innerRadius = 5, length = 80}},
    }
    for i, preset in defaults do
        local ok, err = pcall(spawn, preset[1], preset[2], preset[3],
            CFrame.new((i - 2.5) * spacing, 7, 4))
        if not ok then warn('[STOCK] Initial stock ' .. i .. ' failed: ' .. tostring(err)) end
    end
    refreshSelection()
    return {
        gui = gui,
        get = function(part)
            if not part then return nil end
            local id = part:GetAttribute('StockId')
            if id and bindings[id] and bindings[id].part == part then return current[id] end
            return nil
        end,
        selected = function()
            return selected and bindings[selected] and bindings[selected].part or nil
        end,
        frame = function(part)
            local id = part and part:GetAttribute('StockId')
            local binding = id and bindings[id]
            if not binding or binding.part ~= part then return nil end
            local frame = part.CFrame * binding.visualOffset:Inverse()
            Stock.move(current[id], frame)
            return frame
        end,
        select = function(part)
            local id = part and part:GetAttribute('StockId')
            if not id or not bindings[id] or bindings[id].part ~= part then return false end
            selected = id
            refreshSelection()
            return true
        end,
        separate = separate,
        refine = refine,
        status = displayStatus,
    }
end

return UI
