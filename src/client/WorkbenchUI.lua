local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')

local Workshop = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('Workshop'))
local Renderer = require(script.Parent.FORMRenderer)
local Toolpath = require(script.Parent.Toolpath)

local UI = {}
local SCALE = 0.04
local WORLD = CFrame.new(0, 7, -12)

local COLORS = {
    panel = Color3.fromRGB(24, 29, 30),
    raised = Color3.fromRGB(41, 49, 49),
    text = Color3.fromRGB(230, 231, 220),
    muted = Color3.fromRGB(161, 178, 172),
    selected = Color3.fromRGB(73, 108, 93),
    gold = Color3.fromRGB(226, 184, 116),
}

local PRESETS = {
    drill = {kind = 'drill', center = {x = 0, y = 0, z = 0},
        radius = 7, height = 70, segments = 12},
    pocket = {kind = 'pocket', center = {x = 22, y = 23, z = -7},
        size = {x = 16, y = 16, z = 16}},
    slot = {kind = 'slot', from = {x = -32, y = 0, z = -10},
        to = {x = -17, y = 0, z = -10}, radius = 3, height = 70, segments = 12},
    profile = {kind = 'profile', points = {
        {x = -29, y = 0, z = 12}, {x = -13, y = 0, z = 12},
        {x = -13, y = 0, z = 1}}, radius = 2.5, height = 70, segments = 12},
    saw = {kind = 'saw', point = {x = 45, y = 0, z = 0}, axis = 'X', direction = 1},
    chamfer = {kind = 'chamfer', axisA = 'X', axisB = 'Z', signA = 1, signB = 1, distance = 4},
    fillet = {kind = 'fillet', axisA = 'X', axisB = 'Z', signA = -1, signB = 1, radius = 4, segments = 6},
}

local FIELDS = {
    drill = {'center.x', 'center.y', 'center.z', 'radius', 'height', 'segments'},
    pocket = {'center.x', 'center.y', 'center.z', 'size.x', 'size.y', 'size.z'},
    slot = {'from.x', 'from.y', 'from.z', 'to.x', 'to.y', 'to.z', 'radius', 'height', 'segments'},
    profile = {'points', 'radius', 'height', 'segments'},
    saw = {'point.x', 'point.y', 'point.z', 'axis', 'direction'},
    chamfer = {'axisA', 'signA', 'axisB', 'signB', 'distance'},
    fillet = {'axisA', 'signA', 'axisB', 'signB', 'radius', 'segments'},
}

local function copy(src)
    local result = {}
    for k, v in src do result[k] = if type(v) == 'table' then copy(v) else v end
    return result
end

local function valueAt(source, path)
    local result = source
    for key in string.gmatch(path, '[^%.]+') do result = result[key] end
    return result
end

local function setAt(target, path, value)
    local current = target
    local keys = string.split(path, '.')
    for i = 1, #keys - 1 do current = current[keys[i]] end
    current[keys[#keys]] = value
end

local function pointsText(points)
    local output = {}
    for _, p in points do
        output[#output + 1] = string.format('%g,%g,%g', p.x, p.y, p.z)
    end
    return table.concat(output, '; ')
end

local function decodePoints(text)
    local output = {}
    for segment in string.gmatch(text, '[^;]+') do
        local values = {}
        for item in string.gmatch(segment, '[^,]+') do
            local number = tonumber(string.match(item, '^%s*(.-)%s*$'))
            assert(number, 'Each profile point must contain three numbers')
            values[#values + 1] = number
        end
        assert(#values == 3, 'Profile points must use x,y,z')
        output[#output + 1] = {x = values[1], y = values[2], z = values[3]}
    end
    return output
end

local function text(parent, name, value, size, color, height)
    local item = Instance.new('TextLabel')
    item.Name = name
    item.Size = UDim2.new(1, 0, 0, height or 24)
    item.BackgroundTransparency = 1
    item.Text = value
    item.TextColor3 = color or COLORS.text
    item.Font = Enum.Font.Code
    item.TextSize = size or 14
    item.TextWrapped = true
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.Parent = parent
    return item
end

local function input(parent, name, initial)
    local frame = Instance.new('Frame')
    frame.Name = name
    frame.Size = UDim2.new(1, -2, 0, 33)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local title = Instance.new('TextLabel')
    title.Size = UDim2.new(0.43, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.Code
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = COLORS.muted
    title.Text = name
    title.Parent = frame

    local edit = Instance.new('TextBox')
    edit.Name = 'Value'
    edit.Position = UDim2.new(0.43, 0, 0, 1)
    edit.Size = UDim2.new(0.57, 0, 1, -2)
    edit.BackgroundColor3 = COLORS.raised
    edit.TextColor3 = COLORS.text
    edit.PlaceholderColor3 = COLORS.muted
    edit.ClearTextOnFocus = false
    edit.Font = Enum.Font.Code
    edit.TextSize = 13
    edit.Text = tostring(initial or '')
    edit.Parent = frame
    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = edit
    return edit
end

local function button(parent, name, label, callback)
    local control = Instance.new('TextButton')
    control.Name = name
    control.Size = UDim2.new(1, -2, 0, 31)
    control.BorderSizePixel = 0
    control.BackgroundColor3 = COLORS.raised
    control.TextColor3 = COLORS.text
    control.Text = label
    control.Font = Enum.Font.Code
    control.TextSize = 13
    control.Parent = parent
    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = control
    if callback then control.MouseButton1Click:Connect(callback) end
    return control
end

local function stacked(parent, spacing)
    local layout = Instance.new('UIListLayout')
    layout.Padding = UDim.new(0, spacing or 5)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = parent
    return layout
end

local function panel(parent, width, left)
    local frame = Instance.new('ScrollingFrame')
    frame.Name = if left then 'Operations' else 'Project'
    frame.Position = if left then UDim2.new(0, 18, 0, 25) else UDim2.new(1, -width - 18, 0, 25)
    frame.Size = UDim2.new(0, width, 1, -50)
    frame.BorderSizePixel = 0
    frame.BackgroundColor3 = COLORS.panel
    frame.BackgroundTransparency = 0.05
    frame.ScrollBarThickness = 3
    frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    frame.CanvasSize = UDim2.fromOffset(0, 0)
    frame.Parent = parent

    local padding = Instance.new('UIPadding')
    padding.PaddingTop = UDim.new(0, 14)
    padding.PaddingBottom = UDim.new(0, 18)
    padding.PaddingLeft = UDim.new(0, 13)
    padding.PaddingRight = UDim.new(0, 13)
    padding.Parent = frame
    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = frame
    stacked(frame, 6)
    return frame
end

function UI.start()
    local job = Workshop.new()
    local initiallyAdded, initialReason = job:insert(PRESETS.drill)
    if not initiallyAdded then warn('[WORKSHOP] Initial drill failed: ' .. tostring(initialReason)) end

    local selectedIndex = nil
    local currentTool = 'drill'
    local editor = copy(PRESETS.drill)
    local fields = {}
    local busy = false
    local materialMode = 1
    local smoothAngle = 30
    local materialModes = {Enum.Material.Metal, Enum.Material.SmoothPlastic, Enum.Material.Neon}
    local part, editable, toolOverlay
    local showToolpath = true

    local gui = Instance.new('ScreenGui')
    gui.Name = 'OpenworksWorkshop'
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.Parent = Players.LocalPlayer:WaitForChild('PlayerGui')

    local left = panel(gui, 347, true)
    local right = panel(gui, 322, false)
    text(left, 'Title', 'OPENWORKS  /  MACHINING', 20, COLORS.gold, 34)
    local status = text(left, 'Status', 'Initializing...', 12, COLORS.muted, 48)
    text(left, 'Tools', '01  /  SELECT TOOL', 14, COLORS.gold, 25)

    local toolList = Instance.new('Frame')
    toolList.Name = 'ToolList'
    toolList.BackgroundTransparency = 1
    toolList.Size = UDim2.new(1, 0, 0, 247)
    toolList.Parent = left
    stacked(toolList, 4)

    text(left, 'Parameters', '02  /  TOOL PARAMETERS (MM)', 14, COLORS.gold, 26)
    local form = Instance.new('Frame')
    form.Name = 'ParameterFields'
    form.BackgroundTransparency = 1
    form.AutomaticSize = Enum.AutomaticSize.Y
    form.Size = UDim2.new(1, 0, 0, 0)
    form.Parent = left
    stacked(form, 4)

    text(right, 'ProjectTitle', 'WORKPIECE  /  PROJECT', 18, COLORS.gold, 32)
    local nameEdit = input(right, 'Project name', job.name)
    text(right, 'StockTitle', 'STOCK DIMENSIONS (MM)', 13, COLORS.gold, 24)
    local stockX = input(right, 'Stock X', job.stock.x)
    local stockY = input(right, 'Stock Y', job.stock.y)
    local stockZ = input(right, 'Stock Z', job.stock.z)
    text(right, 'TimelineTitle', 'OPERATION TIMELINE', 14, COLORS.gold, 26)

    local timeline = Instance.new('Frame')
    timeline.Name = 'Timeline'
    timeline.BackgroundTransparency = 1
    timeline.AutomaticSize = Enum.AutomaticSize.Y
    timeline.Size = UDim2.new(1, 0, 0, 0)
    timeline.Parent = right
    stacked(timeline, 4)

    local total = text(right, 'Summary', '', 12, COLORS.muted, 54)

    local modal = Instance.new('Frame')
    modal.Name = 'JSONProject'
    modal.AnchorPoint = Vector2.new(0.5, 0.5)
    modal.Position = UDim2.fromScale(0.5, 0.5)
    modal.Size = UDim2.new(0.64, 0, 0.65, 0)
    modal.BackgroundColor3 = COLORS.panel
    modal.BorderSizePixel = 0
    modal.Visible = false
    modal.ZIndex = 50
    modal.Parent = gui
    local round = Instance.new('UICorner')
    round.CornerRadius = UDim.new(0, 10)
    round.Parent = modal

    local jsonTitle = Instance.new('TextLabel')
    jsonTitle.BackgroundTransparency = 1
    jsonTitle.Size = UDim2.new(1, -24, 0, 40)
    jsonTitle.Position = UDim2.fromOffset(12, 8)
    jsonTitle.Text = 'PROJECT JSON / SELECT ALL + COPY, OR PASTE TO IMPORT'
    jsonTitle.Font = Enum.Font.Code
    jsonTitle.TextSize = 15
    jsonTitle.TextColor3 = COLORS.gold
    jsonTitle.TextXAlignment = Enum.TextXAlignment.Left
    jsonTitle.ZIndex = 51
    jsonTitle.Parent = modal

    local jsonBox = Instance.new('TextBox')
    jsonBox.Name = 'JSON'
    jsonBox.Position = UDim2.new(0, 12, 0, 50)
    jsonBox.Size = UDim2.new(1, -24, 1, -102)
    jsonBox.BackgroundColor3 = COLORS.raised
    jsonBox.TextColor3 = COLORS.text
    jsonBox.TextXAlignment = Enum.TextXAlignment.Left
    jsonBox.TextYAlignment = Enum.TextYAlignment.Top
    jsonBox.Font = Enum.Font.Code
    jsonBox.TextSize = 12
    jsonBox.MultiLine = true
    jsonBox.ClearTextOnFocus = false
    jsonBox.TextWrapped = true
    jsonBox.TextEditable = true
    jsonBox.ZIndex = 51
    jsonBox.Parent = modal

    local closeJson = Instance.new('TextButton')
    closeJson.Position = UDim2.new(0.5, 6, 1, -44)
    closeJson.Size = UDim2.new(0.5, -18, 0, 34)
    closeJson.Text = 'CLOSE'
    closeJson.BackgroundColor3 = COLORS.raised
    closeJson.TextColor3 = COLORS.text
    closeJson.Font = Enum.Font.Code
    closeJson.TextSize = 14
    closeJson.ZIndex = 52
    closeJson.Parent = modal
    closeJson.MouseButton1Click:Connect(function() modal.Visible = false end)

    local importJson = closeJson:Clone()
    importJson.Name = 'Import'
    importJson.Text = 'IMPORT JSON'
    importJson.Position = UDim2.new(0, 12, 1, -44)
    importJson.Size = UDim2.new(0.5, -18, 0, 34)
    importJson.Parent = modal

    local function report(message, errorState)
        status.Text = message
        status.TextColor3 = if errorState then Color3.fromRGB(245, 149, 126) else COLORS.muted
        print('[WORKSHOP] ' .. message)
    end

    local function syncName()
        if #nameEdit.Text < 1 or #nameEdit.Text > 48 then error('Project name requires 1-48 characters') end
        job.name = nameEdit.Text
    end

    local function refreshModel()
        local mesh, reason, detail
        local ok, err = pcall(function()
            mesh, reason, detail = job.machine:mesh()
        end)
        if not ok then warn('[WORKSHOP] Unified mesh error: ' .. tostring(err)) end
        if ok and not mesh then warn('[WORKSHOP] Unified mesh rejected: ' .. tostring(reason)) end

        local renderOk, newPart, newEditable, shading = pcall(function()
            if ok and mesh then return Renderer.create(mesh, SCALE, smoothAngle) end
            return Renderer.createMany(job.machine:pieces(), SCALE, smoothAngle)
        end)

        if renderOk and newPart then
            local prior, priorEditable = part, editable
            part, editable = newPart, newEditable
            part.Name = 'OPENWORKS Workpiece'
            part.Anchored = true
            part.CanCollide = false
            part.CFrame = WORLD
            part.Color = Color3.fromRGB(78, 156, 120)
            part.Material = materialModes[materialMode]
            part.Parent = workspace
            if prior then prior:Destroy() end
            if priorEditable then pcall(function() priorEditable:Destroy() end) end
            if shading and shading.planarization then
                print(string.format('[WORKSHOP] Planarized %d vertices; max shift %.6f mm',
                    shading.planarization.snappedVertices, shading.planarization.maxAxisShift))
            end
        else
            warn('[WORKSHOP] Render failed: ' .. tostring(newPart))
        end
        return ok and mesh ~= nil
    end

    local function fromFields()
        local result = copy(PRESETS[currentTool])
        for _, key in FIELDS[currentTool] do
            local value = fields[key].Text
            if key == 'points' then
                setAt(result, key, decodePoints(value))
            elseif key == 'axis' or key == 'axisA' or key == 'axisB' then
                setAt(result, key, string.upper(string.match(value, '^%s*(.-)%s*$')))
            else
                local converted = tonumber(value)
                assert(converted ~= nil, 'Not a number: ' .. key)
                setAt(result, key, converted)
            end
        end
        Workshop.compile(result)
        return result
    end

    local function showTool(kind, operation)
        currentTool = kind
        editor = copy(operation or PRESETS[kind])
        for _, child in form:GetChildren() do
            if not child:IsA('UIListLayout') then child:Destroy() end
        end
        fields = {}
        for _, key in FIELDS[kind] do
            local value = valueAt(editor, key)
            fields[key] = input(form, key, if key == 'points' then pointsText(value) else value)
        end
        for _, child in toolList:GetChildren() do
            if child:IsA('TextButton') then
                child.BackgroundColor3 = if child.Name == kind then COLORS.selected else COLORS.raised
            end
        end
    end

    local function refreshToolpath()
        if toolOverlay then toolOverlay:Destroy() toolOverlay = nil end
        if not showToolpath then return end

        local op
        if selectedIndex and job.operations[selectedIndex] then
            op = job.operations[selectedIndex]
        else
            local ok, preview = pcall(fromFields)
            if ok then op = preview end
        end
        if op then
            local ok, newFolder = pcall(Toolpath.render, op, job.stock, WORLD, SCALE)
            if ok then toolOverlay = newFolder else warn('[WORKSHOP] Toolpath: ' .. tostring(newFolder)) end
        end
    end

    local function refreshTimeline()
        for _, child in timeline:GetChildren() do
            if not child:IsA('UIListLayout') then child:Destroy() end
        end
        for index, operation in job.operations do
            local removed = if job.machine.history[index] then job.machine.history[index].removed else 0
            local label = string.format('%02d  %s  /  -%.1f mm³%s',
                index, string.upper(operation.kind), removed,
                if index > job.cursor then '  (undone)' else '')
            local control = button(timeline, 'Op' .. index, label, function()
                if index > job.cursor then return end
                selectedIndex = index
                showTool(operation.kind, operation)
                refreshTimeline()
                refreshToolpath()
                report('Selected operation ' .. index .. ' for editing')
            end)
            control.BackgroundColor3 = if index == selectedIndex then COLORS.selected else COLORS.raised
            if index > job.cursor then control.TextColor3 = COLORS.muted end
        end
        if #job.operations == 0 then text(timeline, 'Empty', 'No operations yet', 12, COLORS.muted, 26) end

        local summary = job:summary()
        total.Text = string.format('%d operations (%d retained)  /  %d convex pieces\nRemoved %.2f mm³  /  Remaining %.2f mm³',
            summary.operations, summary.totalOperations, summary.pieces,
            summary.removed, summary.volume)
    end

    local function refreshAll(message)
        local unified = refreshModel()
        refreshTimeline()
        refreshToolpath()
        report((message or 'Ready') .. '  |  ' .. (if unified then 'UNIFIED' else 'FALLBACK'))
    end

    local function act(label, callback)
        if busy then return end
        busy = true
        local called, ok, reason = pcall(callback)
        if not called then
            report(label .. ': ' .. tostring(ok), true)
        elseif not ok then
            report(label .. ': ' .. tostring(reason or 'Rejected'), true)
        else
            refreshAll(label .. ': success')
        end
        busy = false
    end

    for _, kind in {'drill', 'pocket', 'slot', 'profile', 'saw', 'chamfer', 'fillet'} do
        button(toolList, kind, string.upper(kind), function()
            selectedIndex = nil
            showTool(kind)
            refreshTimeline()
            refreshToolpath()
            report('New ' .. kind .. ' operation')
        end)
    end

    showTool('drill')
    button(left, 'Add', 'ADD OPERATION TO TIMELINE', function()
        act('Add operation', function()
            local operation = fromFields()
            local valid, reason = job:insert(operation)
            if valid then
                selectedIndex = job.cursor
                showTool(currentTool, job.operations[selectedIndex])
            end
            return valid, reason
        end)
    end)
    button(left, 'Update', 'UPDATE SELECTED OPERATION', function()
        act('Update operation', function()
            if not selectedIndex then return false, 'SELECT_AN_OPERATION' end
            local valid, reason = job:edit(selectedIndex, fromFields())
            return valid, reason
        end)
    end)
    button(left, 'Preview', 'REFRESH TOOL PATH / PARAMETERS', function()
        local ok, reason = pcall(fromFields)
        if not ok then report('Tool path: ' .. tostring(reason), true) return end
        selectedIndex = nil
        refreshTimeline()
        refreshToolpath()
        report('Tool path preview updated')
    end)
    button(left, 'TogglePath', 'TOGGLE TOOL-PATH OVERLAY', function()
        showToolpath = not showToolpath
        refreshToolpath()
    end)

    button(right, 'NewStock', 'NEW STOCK / CLEAR OPERATIONS', function()
        act('New stock', function()
            local dimensions = {x = tonumber(stockX.Text), y = tonumber(stockY.Text), z = tonumber(stockZ.Text)}
            syncName()
            local ok = job:resetStock(dimensions)
            selectedIndex = nil
            return ok
        end)
    end)

    button(right, 'Remove', 'DELETE SELECTED OPERATION', function()
        act('Delete operation', function()
            if not selectedIndex then return false, 'SELECT_AN_OPERATION' end
            local valid, reason = job:remove(selectedIndex)
            if valid then selectedIndex = nil end
            return valid, reason
        end)
    end)

    button(right, 'Up', 'MOVE SELECTED OPERATION UP', function()
        act('Reorder up', function()
            if not selectedIndex then return false, 'SELECT_AN_OPERATION' end
            local valid, reason = job:move(selectedIndex, -1)
            if valid then selectedIndex -= 1 end
            return valid, reason
        end)
    end)
    button(right, 'Down', 'MOVE SELECTED OPERATION DOWN', function()
        act('Reorder down', function()
            if not selectedIndex then return false, 'SELECT_AN_OPERATION' end
            local valid, reason = job:move(selectedIndex, 1)
            if valid then selectedIndex += 1 end
            return valid, reason
        end)
    end)
    button(right, 'Undo', 'UNDO OPERATION   [Z]', function()
        act('Undo', function()
            local ok, reason = job:undo()
            if ok then selectedIndex = nil end
            return ok, reason
        end)
    end)
    button(right, 'Redo', 'REDO OPERATION   [Y]', function()
        act('Redo', function()
            local ok, reason = job:redo()
            if ok then selectedIndex = nil end
            return ok, reason
        end)
    end)
    button(right, 'Material', 'CYCLE MATERIAL   [M]', function()
        materialMode = materialMode % #materialModes + 1
        if part then part.Material = materialModes[materialMode] end
        report('Material: ' .. materialModes[materialMode].Name)
    end)
    button(right, 'Shading', 'FLAT / SMOOTH SHADING   [N]', function()
        smoothAngle = if smoothAngle == 0 then 30 else 0
        refreshAll(if smoothAngle == 0 then 'Flat normals' else 'Protected smooth normals')
    end)

    local function storage(action, json)
        local remote = ReplicatedStorage.Openworks:FindFirstChild('WorkshopStorage')
        if not remote or not remote:IsA('RemoteFunction') then
            report('Storage remote unavailable; use JSON export/import', true)
            return
        end
        if busy then return end
        busy = true
        local ok, result = pcall(function() return remote:InvokeServer(action, json) end)
        if not ok or type(result) ~= 'table' or not result.ok then
            report('Project storage: ' .. tostring(if ok and result then result.message else result), true)
        elseif action == 'load' then
            local project, reason = Workshop.deserialize(result.data)
            if project then
                job = project
                selectedIndex = nil
                nameEdit.Text = job.name
                stockX.Text, stockY.Text, stockZ.Text = tostring(job.stock.x),
                    tostring(job.stock.y), tostring(job.stock.z)
                showTool('drill')
                refreshAll('Loaded saved project')
            else
                report('Load rejected: ' .. tostring(reason), true)
            end
        else
            report('Project saved to server')
        end
        busy = false
    end

    button(right, 'Save', 'SAVE PROJECT TO SERVER', function()
        local ok, data = pcall(function() syncName() return job:serialize() end)
        if not ok then report('Save failed: ' .. tostring(data), true) return end
        storage('save', data)
    end)
    button(right, 'Load', 'LOAD SAVED PROJECT', function()
        storage('load')
    end)
    button(right, 'Export', 'EXPORT PROJECT JSON', function()
        local ok, data = pcall(function() syncName() return job:serialize() end)
        if not ok then report('Export failed: ' .. tostring(data), true) return end
        jsonBox.Text = data
        modal.Visible = true
        report('JSON ready: select all and copy')
    end)
    button(right, 'Import', 'IMPORT PROJECT JSON', function()
        jsonBox.Text = ''
        modal.Visible = true
        report('Paste JSON into the text box and press IMPORT JSON')
    end)

    importJson.MouseButton1Click:Connect(function()
        if busy then return end
        busy = true
        local called, project, reason = pcall(Workshop.deserialize, jsonBox.Text)
        if not called or not project then
            report('Import rejected: ' .. tostring(if called then reason else project), true)
            busy = false
            return
        end
        job = project
        nameEdit.Text = job.name
        stockX.Text, stockY.Text, stockZ.Text = tostring(job.stock.x), tostring(job.stock.y), tostring(job.stock.z)
        selectedIndex = nil
        showTool('drill')
        modal.Visible = false
        refreshAll('Imported project')
        busy = false
    end)

    UserInputService.InputBegan:Connect(function(inputEvent, processed)
        if processed or UserInputService:GetFocusedTextBox() or modal.Visible then return end
        local quickTools = {
            [Enum.KeyCode.One] = 'drill',
            [Enum.KeyCode.Two] = 'pocket',
            [Enum.KeyCode.Three] = 'slot',
            [Enum.KeyCode.Four] = 'chamfer',
            [Enum.KeyCode.Five] = 'fillet',
            [Enum.KeyCode.Six] = 'saw',
            [Enum.KeyCode.Seven] = 'profile',
        }
        local quickTool = quickTools[inputEvent.KeyCode]
        if quickTool then
            selectedIndex = nil
            showTool(quickTool)
            refreshTimeline()
            refreshToolpath()
            report('Selected ' .. quickTool .. ' tool')
        elseif inputEvent.KeyCode == Enum.KeyCode.Z then
            act('Undo', function() selectedIndex = nil return job:undo() end)
        elseif inputEvent.KeyCode == Enum.KeyCode.Y then
            act('Redo', function() selectedIndex = nil return job:redo() end)
        elseif inputEvent.KeyCode == Enum.KeyCode.M then
            materialMode = materialMode % #materialModes + 1
            if part then part.Material = materialModes[materialMode] end
            report('Material: ' .. materialModes[materialMode].Name)
        elseif inputEvent.KeyCode == Enum.KeyCode.N then
            smoothAngle = if smoothAngle == 0 then 30 else 0
            refreshAll('Shading mode switched')
        end
    end)

    refreshAll('Machining workspace ready')
    return gui
end

return UI
