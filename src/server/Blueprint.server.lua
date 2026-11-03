local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local Openworks = ReplicatedStorage:WaitForChild('Openworks')
local Geometry = require(Openworks:WaitForChild('BlueprintGeometry'))

local remote = Openworks:FindFirstChild('BlueprintEvent')
if not remote then
    remote = Instance.new('RemoteEvent')
    remote.Name = 'BlueprintEvent'
    remote.Parent = Openworks
end

local sessions = {}
local sheetLocks = {}
local toolLocks = {}
local rulerLocks = {}

local function near(player, part, limit)
    local character = player.Character
    local root = character and character:FindFirstChild('HumanoidRootPart')
    local humanoid = character and character:FindFirstChildOfClass('Humanoid')
    return root and humanoid and humanoid.Health > 0
        and (root.Position - part.Position).Magnitude <= (limit or 27)
end

local function restoreTool(session)
    if not session.tool then return end
    local tool = session.tool
    toolLocks[tool] = nil
    if tool.Parent then
        tool.CFrame = session.toolOriginal.frame
        tool.CanCollide = session.toolOriginal.collide
        tool.CanTouch = session.toolOriginal.touch
        tool.CanQuery = session.toolOriginal.query
        tool.Anchored = session.toolOriginal.anchored
    end
    session.tool = nil
    session.toolOriginal = nil
end

local function releaseRuler(session)
    local ruler = session.ruler
    if not ruler then return end
    rulerLocks[ruler] = nil
    if ruler.Parent then
        ruler.CanCollide = session.rulerOriginal.collide
        ruler.CanTouch = session.rulerOriginal.touch
        ruler.CanQuery = session.rulerOriginal.query
        ruler.Anchored = session.rulerOriginal.anchored
    end
    session.ruler = nil
    session.rulerOriginal = nil
end

local function close(player)
    local session = sessions[player]
    if not session then return end
    sessions[player] = nil
    sheetLocks[session.sheet] = nil
    releaseRuler(session)
    restoreTool(session)
    if session.sheet.Parent then
        session.sheet.Anchored = session.wasAnchored
    end
    if player.Parent then remote:FireClient(player, 'Closed') end
end

local function report(player, message)
    remote:FireClient(player, 'Status', message)
end

local function toolKind(tool)
    local kind = typeof(tool) == 'Instance' and tool:IsA('BasePart')
        and tool:GetAttribute('DraftingKind') or nil
    if kind == 'Pencil' or kind == 'Eraser' then return kind end
end

local function isSheet(sheet)
    return typeof(sheet) == 'Instance' and sheet:IsA('BasePart')
        and sheet:GetAttribute('isBlueprint') == true
        and sheet:IsDescendantOf(workspace)
end

remote.OnServerEvent:Connect(function(player, action, ...)
    if action == 'Close' then close(player) return end

    if action == 'Open' then
        local sheet = ...
        if not isSheet(sheet) or sheet:GetAttribute('OnWorkbench') ~= true
            or not near(player, sheet) or sheetLocks[sheet] then
            report(player, 'Put the blueprint on the workbench before drafting')
            return
        end
        close(player)
        local session = {
            sheet = sheet,
            wasAnchored = sheet.Anchored,
            lastPose = 0,
        }
        sessions[player] = session
        sheetLocks[sheet] = player
        sheet.Anchored = true
        Geometry.render(sheet)
        remote:FireClient(player, 'Opened', sheet)
        return
    end

    local session = sessions[player]
    if not session or not isSheet(session.sheet)
        or not near(player, session.sheet) then
        if session then close(player) end
        return
    end
    local sheet = session.sheet

    if action == 'SelectTool' then
        local tool = ...
        local kind = toolKind(tool)
        if not kind or not tool:IsDescendantOf(workspace)
            or tool:GetAttribute('OnWorkbench') ~= true
            or not near(player, tool) or (toolLocks[tool] and toolLocks[tool] ~= player) then
            report(player, 'Put a drafting pencil or eraser on the workbench')
            return
        end
        if tool == session.tool then
            remote:FireClient(player, 'ToolSelected', tool, kind)
            return
        end
        restoreTool(session)
        session.toolOriginal = {
            frame = tool.CFrame, anchored = tool.Anchored,
            collide = tool.CanCollide, touch = tool.CanTouch,
            query = tool.CanQuery,
        }
        session.tool = tool
        session.kind = kind
        toolLocks[tool] = player
        tool.Anchored = true
        tool.CanCollide = false
        tool.CanTouch = false
        tool.CanQuery = false
        remote:FireClient(player, 'ToolSelected', tool, kind)
        return
    end

    if action == 'RulerStart' then
        local ruler = ...
        if typeof(ruler) ~= 'Instance' or not ruler:IsA('BasePart')
            or ruler:GetAttribute('DraftingKind') ~= 'Ruler'
            or ruler:GetAttribute('OnWorkbench') ~= true
            or not near(player, ruler)
            or (rulerLocks[ruler] and rulerLocks[ruler] ~= player) then
            report(player, 'Place a physical ruler on the workbench')
            return
        end
        releaseRuler(session)
        session.ruler = ruler
        session.rulerOriginal = {
            anchored = ruler.Anchored, collide = ruler.CanCollide,
            touch = ruler.CanTouch, query = ruler.CanQuery,
        }
        rulerLocks[ruler] = player
        ruler.Anchored = true
        ruler.CanCollide = false
        ruler.CanTouch = false
        ruler.CanQuery = false
        session.lastRulerMove = 0
        return
    elseif action == 'RulerMove' then
        local point, rotation = ...
        local ruler = session.ruler
        if not ruler or typeof(point) ~= 'Vector2'
            or not Geometry.inside(sheet, point)
            or type(rotation) ~= 'number' or rotation ~= rotation
            or math.abs(rotation) > math.pi * 2 then return end
        local now = os.clock()
        if now - session.lastRulerMove < 1 / 30 then return end
        session.lastRulerMove = now
        ruler.CFrame = sheet.CFrame * CFrame.new(
            point.X * Geometry.SCALE, sheet.Size.Y * 0.5 + ruler.Size.Y * 0.5 + 0.01,
            point.Y * Geometry.SCALE) * CFrame.Angles(0, rotation, 0)
        return
    elseif action == 'RulerEnd' then
        releaseRuler(session)
        return
    end

    if not session.tool or not session.tool.Parent then return end

    if action == 'Pose' then
        local point = ...
        if typeof(point) ~= 'Vector2' or not Geometry.inside(sheet, point) then return end
        local now = os.clock()
        if now - session.lastPose < 1 / 20 then return end
        session.lastPose = now
        remote:FireAllClients('ToolPose', session.tool, sheet, point, player.UserId)
        return
    end

    if action == 'Draw' and session.kind == 'Pencil' then
        local startPoint, endPoint, ruler = ...
        if typeof(startPoint) ~= 'Vector2' or typeof(endPoint) ~= 'Vector2'
            or typeof(ruler) ~= 'Instance' or not ruler:IsA('BasePart')
            or not ruler:IsDescendantOf(workspace)
            or not near(player, ruler) then
            report(player, 'Invalid physical drafting stroke')
            return
        end
        local guide = Geometry.rulerGuide(sheet, ruler, startPoint)
        if not guide then
            report(player, 'Hold the pencil along a ruler edge on the paper')
            return
        end
        local a = Geometry.snap(guide, startPoint)
        local b = Geometry.snap(guide, endPoint)
        if not Geometry.append(sheet, a, b) then
            report(player, 'Line is outside the sheet, too short, or sheet is full')
        else
            remote:FireClient(player, 'Recorded', #Geometry.read(sheet))
        end
    elseif action == 'Erase' and session.kind == 'Eraser' then
        local point = ...
        if typeof(point) ~= 'Vector2' then return end
        if Geometry.erase(sheet, point, 5) then
            remote:FireClient(player, 'Recorded', #Geometry.read(sheet))
        else
            report(player, 'Move the eraser nearer a drawn line')
        end
    end
end)

Players.PlayerRemoving:Connect(close)
Players.PlayerAdded:Connect(function(player)
    player.CharacterRemoving:Connect(function() close(player) end)
end)
for _, player in Players:GetPlayers() do
    player.CharacterRemoving:Connect(function() close(player) end)
end

local clock = 0
RunService.Heartbeat:Connect(function(dt)
    clock += dt
    if clock < 0.4 then return end
    clock = 0
    for player, session in sessions do
        if not session.sheet.Parent or not near(player, session.sheet, 33) then
            close(player)
        end
    end
end)

if RunService:IsStudio() then
    task.defer(function()
        local ok, passed, message = pcall(function()
            return require(Openworks:WaitForChild('BlueprintRegression')).run()
        end)
        if ok and passed then
            print('[OPENWORKS:Blueprint]', message)
        else
            warn('[OPENWORKS:Blueprint] Geometry regression failed:',
                if ok then message else passed)
        end
    end)

    task.defer(function()
        local bench = workspace:WaitForChild('Workbench', 20)
        if not bench then return end
        local surface
        for _, node in bench:GetDescendants() do
            if node:IsA('BasePart') and node.Name:lower() == 'surface'
                and (not surface or node.Size.X * node.Size.Z > surface.Size.X * surface.Size.Z) then
                surface = node
            end
        end
        if not surface then
            warn('[OPENWORKS:Blueprint] No workbench surface for drafting kit')
            return
        end

        for _, node in workspace:GetDescendants() do
            if node:GetAttribute('isBlueprint') == true then return end
        end

        local folder = Instance.new('Folder')
        folder.Name = 'OpenworksDraftingKit'
        folder.Parent = workspace
        local width = math.min(5, surface.Size.X * 0.5)
        local depth = math.min(3.5, surface.Size.Z * 0.6)
        if width < 1.5 or depth < 1.2 then
            warn('[OPENWORKS:Blueprint] Workbench is too small for drafting')
            folder:Destroy()
            return
        end

        local base = surface.Size.Y * 0.5
        local function part(name, size, color, localX, localZ, height)
            local node = Instance.new('Part')
            node.Name = name
            node.Size = size
            node.Material = Enum.Material.SmoothPlastic
            node.Color = color
            node.TopSurface = Enum.SurfaceType.Smooth
            node.BottomSurface = Enum.SurfaceType.Smooth
            node.CFrame = surface.CFrame * CFrame.new(localX,
                base + size.Y * 0.5 + (height or 0.06), localZ)
            node.Anchored = false
            node.CanCollide = true
            node.CanTouch = true
            node.CanQuery = true
            node.Parent = folder
            return node
        end

        local function detail(basePart, name, size, localFrame, color, transparency, material)
            local piece = Instance.new('Part')
            piece.Name = name
            piece.Size = size
            piece.CFrame = basePart.CFrame * localFrame
            piece.Color = color
            piece.Transparency = transparency or 0
            piece.Material = material or Enum.Material.SmoothPlastic
            piece.Anchored = false
            piece.Massless = true
            piece.CanCollide = false
            piece.CanTouch = false
            piece.CanQuery = false
            piece.CastShadow = false
            piece.Parent = basePart

            local weld = Instance.new('WeldConstraint')
            weld.Part0 = basePart
            weld.Part1 = piece
            weld.Parent = piece
        end

        local function rulerDetails(ruler)
            local dark = Color3.fromRGB(38, 42, 46)
            local gold = Color3.fromRGB(255, 225, 140)
            local top = ruler.Size.Y * 0.5 + 0.007
            for _, side in {-1, 1} do
                detail(ruler, 'LongEdge_' .. side,
                    Vector3.new(ruler.Size.X, 0.013, 0.022),
                    CFrame.new(0, top, side * (ruler.Size.Z * 0.5 - 0.019)),
                    dark)
            end

            detail(ruler, 'CenterGoldInset',
                Vector3.new(ruler.Size.X - 0.14, 0.009, 0.019),
                CFrame.new(0, top + 0.001, ruler.Size.Z * 0.16),
                gold, 0.08)
            local limit = math.floor((ruler.Size.X * 0.5 - 0.06) / 0.2)
            for step = -limit, limit do
                local longest = step % 5 == 0
                local tickLength = if longest then 0.18
                    elseif step % 2 == 0 then 0.12 else 0.065
                detail(ruler, 'Tick_' .. step,
                    Vector3.new(if longest then 0.017 else 0.011,
                        0.010, tickLength),
                    CFrame.new(step * 0.2, top + 0.001,
                        -ruler.Size.Z * 0.24 + tickLength * 0.5),
                    dark)
            end
        end

        local sheetX = -surface.Size.X * 0.12
        local sheet = part('Blueprint Sheet',
            Vector3.new(width, 0.055, depth),
            Color3.fromRGB(212, 231, 241), sheetX, 0, 0.03)
        sheet:SetAttribute('isBlueprint', true)
        Geometry.write(sheet, {})
        Geometry.render(sheet)
        detail(sheet, 'DraftingClip',
            Vector3.new(width * 0.42, 0.04, 0.11),
            CFrame.new(0, sheet.Size.Y * 0.5 + 0.025,
                -depth * 0.47),
            Color3.fromRGB(112, 132, 146), 0, Enum.Material.Metal)

        local ruler = part('Drafting Ruler',
            Vector3.new(width * 0.82, 0.13, 0.36),
            Color3.fromRGB(245, 180, 62), sheetX, -depth * 0.19, 0.16)
        ruler.Material = Enum.Material.Metal
        ruler:SetAttribute('isTool', true)
        ruler:SetAttribute('DraftingKind', 'Ruler')
        rulerDetails(ruler)

        local pencil = part('Drafting Pencil',
            Vector3.new(0.12, 0.12, 1.1),
            Color3.fromRGB(223, 178, 67),
            math.min(surface.Size.X * 0.38, sheetX + width * 0.65),
            -surface.Size.Z * 0.19, 0.07)
        pencil:SetAttribute('isTool', true)
        pencil:SetAttribute('DraftingKind', 'Pencil')
        detail(pencil, 'PencilStripe',
            Vector3.new(0.025, 0.125, pencil.Size.Z * 0.70),
            CFrame.new(0.05, 0, 0), Color3.fromRGB(153, 101, 32))
        detail(pencil, 'GraphiteNib',
            Vector3.new(0.062, 0.062, 0.1),
            CFrame.new(0, 0, -pencil.Size.Z * 0.5 - 0.025),
            Color3.fromRGB(47, 47, 47))
        detail(pencil, 'SilverFerrule',
            Vector3.new(0.121, 0.121, 0.10),
            CFrame.new(0, 0, pencil.Size.Z * 0.5 - 0.075),
            Color3.fromRGB(180, 189, 193), 0, Enum.Material.Metal)

        local eraser = part('Drafting Eraser',
            Vector3.new(0.4, 0.14, 0.48),
            Color3.fromRGB(211, 135, 129),
            math.min(surface.Size.X * 0.38, sheetX + width * 0.65),
            surface.Size.Z * 0.19, 0.06)
        eraser:SetAttribute('isTool', true)
        eraser:SetAttribute('DraftingKind', 'Eraser')
        detail(eraser, 'PaperSleeve',
            Vector3.new(0.41, 0.015, 0.30),
            CFrame.new(0, eraser.Size.Y * 0.5 + 0.008, 0),
            Color3.fromRGB(241, 226, 204))

        print('[OPENWORKS:Blueprint] Drafting kit placed on the workbench')
    end)
end
