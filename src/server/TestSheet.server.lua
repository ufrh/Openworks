local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

if not RunService:IsStudio() then
    return
end

local openworks = ReplicatedStorage:WaitForChild('Openworks')
local FORMMaterial = require(openworks:WaitForChild('FORMMaterial'))

task.defer(function()
    local ok, result, message = pcall(function()
        return require(openworks:WaitForChild('GeometryRegression')).run()
    end)
    if not ok then
        warn('[OPENWORKS:FORM] Geometry regression failed:', result)
    elseif result then
        print('[OPENWORKS:FORM]', message)
    else
        warn('[OPENWORKS:FORM] Geometry regression failed:', message)
    end
end)

task.defer(function()
    local ok, passed, message = pcall(function()
        return require(openworks:WaitForChild('MaterialLayoutRegression')).run()
    end)
    if ok and passed then
        print('[OPENWORKS:Layout]', message)
    else
        warn('[OPENWORKS:Layout] Regression failed:',
            if ok then message else passed)
    end
end)

local remote = Instance.new('RemoteEvent')
remote.Name = 'SpawnTestSheet'
remote.Parent = openworks

local sheets = Instance.new('Folder')
sheets.Name = 'OPENWORKS Test Sheets'
sheets.Parent = workspace

local owned = {}
local lastSpawn = {}

local function largestSurface()
    local bench = workspace:FindFirstChild('Workbench')
    if not bench then
        return nil
    end

    local best, area = nil, 0

    for _, descendant in bench:GetDescendants() do
        if descendant:IsA('BasePart') and descendant.Name:lower() == 'surface' then
            local candidateArea = descendant.Size.X * descendant.Size.Z
            if candidateArea > area then
                best = descendant
                area = candidateArea
            end
        end
    end

    return best
end

remote.OnServerEvent:Connect(function(player)
    local now = os.clock()
    if now - (lastSpawn[player] or -math.huge) < 0.75 then
        remote:FireClient(player, false, 'Try again in a moment')
        return
    end
    lastSpawn[player] = now

    local surface = largestSurface()
    if not surface then
        warn('[OPENWORKS:TestSheet] No surface found below Workspace.Workbench')
        remote:FireClient(player, false, 'No Workbench surface found')
        return
    end

    local ok, result = pcall(function()
        local sheet = Instance.new('Part')
        sheet.Name = 'Test Steel Sheet'
        sheet.Size = Vector3.new(
            math.max(0.2, math.min(3.5, surface.Size.X * 0.6)),
            0.18,
            math.max(0.2, math.min(2.5, surface.Size.Z * 0.6))
        )
        sheet.CFrame = surface.CFrame
            * CFrame.new(0, surface.Size.Y / 2 + sheet.Size.Y / 2 + 0.7, 0)
        sheet.Anchored = false
        sheet.CanCollide = true
        sheet.CanTouch = true
        sheet.CanQuery = true
        sheet.Material = Enum.Material.Metal
        sheet.Color = Color3.fromRGB(163, 174, 181)
        sheet.TopSurface = Enum.SurfaceType.Smooth
        sheet.BottomSurface = Enum.SurfaceType.Smooth
        sheet:SetAttribute('FORMNativeStock', true)
        FORMMaterial.mark(sheet)
        sheet.Parent = sheets
        return sheet
    end)

    if not ok then
        warn('[OPENWORKS:TestSheet] Spawn failed:', result)
        remote:FireClient(player, false, 'Spawn failed; check Output')
        return
    end

    local previous = owned[player]
    owned[player] = result
    if previous and previous ~= result then
        previous:Destroy()
    end

    print('[OPENWORKS:TestSheet] Spawned', result:GetFullName(), result.Position)
    remote:FireClient(player, true, 'Sheet created above the workbench')
end)

Players.PlayerRemoving:Connect(function(player)
    if owned[player] then
        owned[player]:Destroy()
    end
    owned[player] = nil
    lastSpawn[player] = nil
end)
