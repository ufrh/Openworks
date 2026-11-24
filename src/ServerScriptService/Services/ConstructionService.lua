-- First OpenWorks vertical slice: server-owned block documents and edits.
-- All client requests are validated before authoritative document mutations.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local FORGE = require(ReplicatedStorage.FORGE)
local Shared = ReplicatedStorage.OpenWorks.Shared
local Units = require(Shared.Units)
local Document = require(Shared.BlockDocument)

local ConstructionService = FORGE.Class("Service", {
    Name = "ConstructionService",
    Dependencies = { "GeometryService", "PersistenceService" },
})

ConstructionService:CreateSignal("DocumentChanged")
ConstructionService:Secure("GetSnapshot", {
    Rate = { Capacity = 12, Refill = 3 },
})
ConstructionService:Secure("Submit", {
    Rate = { Capacity = 14, Refill = 10 },
    Schema = {
        { Type = "String", MinLength = 2, MaxLength = 16 },
        { Type = "Table", MaxEntries = 5 },
        { Type = "Number", Integer = true, Min = 0 },
    },
})

local profiles = {}
local connections = {}
local MAX_UNDO = 25

local function snapshot(profile)
    local state = Document.Snapshot(profile.document)
    state.ready = true
    state.persistent = profile.persistent
    return state
end

local function validPosition(player, position)
    if typeof(position) ~= "Vector3" then
        return false
    end
    if not Units.IsFinite(position.X) or not Units.IsFinite(position.Y)
        or not Units.IsFinite(position.Z) then
        return false
    end
    if math.abs(position.X) > 512 or math.abs(position.Y) > 512
        or math.abs(position.Z) > 512 or position.Y < 0.125 then
        return false
    end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root ~= nil and (root.Position - position).Magnitude <= 70
end

local function tickPosition(position)
    return Units.SnapTicks(Units.ToTicks(position.X)),
        Units.SnapTicks(Units.ToTicks(position.Y)),
        Units.SnapTicks(Units.ToTicks(position.Z))
end

local function pushUndo(profile)
    table.insert(profile.undo, Document.CopyBlocks(profile.document.blocks))
    if #profile.undo > MAX_UNDO then
        table.remove(profile.undo, 1)
    end
    table.clear(profile.redo)
end

local function change(player, action, payload, revision)
    local profile = profiles[player]
    if not profile then
        return false, "document still loading"
    end
    if revision ~= profile.document.revision then
        return false, "stale revision; refresh your snapshot"
    end

    local document = profile.document
    if action == "Undo" or action == "Redo" then
        local source = if action == "Undo" then profile.undo else profile.redo
        local dest = if action == "Undo" then profile.redo else profile.undo
        if #source == 0 then return false, "nothing to " .. string.lower(action) end
        table.insert(dest, Document.CopyBlocks(document.blocks))
        document.blocks = table.remove(source)
    elseif action == "Place" then
        if #document.blocks >= Document.MaxBlocks then
            return false, "prototype block limit reached (32)"
        end
        if not validPosition(player, payload.position) then
            return false, "invalid placement"
        end
        local x, y, z = tickPosition(payload.position)
        pushUndo(profile)
        table.insert(document.blocks, {
            id = HttpService:GenerateGUID(false),
            x = x, y = y, z = z,
            sx = Units.DefaultBlockTicks,
            sy = Units.DefaultBlockTicks,
            sz = Units.DefaultBlockTicks,
        })
    elseif action == "Delete" or action == "Resize" or action == "Move" then
        local id = payload.id
        if type(id) ~= "string" or #id > 80 then
            return false, "invalid block identifier"
        end
        local index, block = Document.Find(document, id)
        if not index then
            return false, "block not found in your document"
        end

        if action == "Delete" then
            pushUndo(profile)
            table.remove(document.blocks, index)
        elseif action == "Resize" then
            local delta = payload.delta
            if delta ~= 250 and delta ~= -250 then
                return false, "resize increments must be 0.25u"
            end
            if block.sx + delta < 250 or block.sy + delta < 250
                or block.sz + delta < 250 or block.sx + delta > 32000
                or block.sy + delta > 32000 or block.sz + delta > 32000 then
                return false, "resize outside prototype limits"
            end
            pushUndo(profile)
            block.sx += delta
            block.sy += delta
            block.sz += delta
        elseif action == "Move" then
            if not validPosition(player, payload.position) then
                return false, "invalid move"
            end
            local x, y, z = tickPosition(payload.position)
            pushUndo(profile)
            block.x, block.y, block.z = x, y, z
        end
    else
        return false, "unsupported command"
    end

    document.revision += 1
    profile.dirty = true

    -- Geometry is derived; rebuilding this small document is acceptable for
    -- the feasibility slice. Later slices will compile dirty subgraphs only.
    ConstructionService:GetDependency("GeometryService"):Sync(player, document)
    local nextSnapshot = snapshot(profile)
    ConstructionService:FireClient(player, "DocumentChanged", nextSnapshot)
    return true, nextSnapshot
end

local function loadPlayer(player)
    local document, persistent = ConstructionService:GetDependency("PersistenceService"):Load(player.UserId)
    if player.Parent ~= Players then return end
    local profile = {
        document = document,
        persistent = persistent,
        undo = {},
        redo = {},
        dirty = false,
        saving = false,
    }
    profiles[player] = profile
    ConstructionService:GetDependency("GeometryService"):Sync(player, document)
    ConstructionService:FireClient(player, "DocumentChanged", snapshot(profile))
end

local function savePlayer(player)
    local profile = profiles[player]
    if not profile or not profile.persistent then return end

    -- Serialize saves for this profile so an older write cannot finish last.
    while profile.saving do
        task.wait()
    end
    if not profile.dirty then return end

    profile.saving = true
    local savedDocument = Document.Snapshot(profile.document)
    local called, saved = pcall(function()
        return ConstructionService:GetDependency("PersistenceService"):Save(player.UserId, savedDocument)
    end)
    if not called then
        warn("[OpenWorks] Save failed unexpectedly: " .. tostring(saved))
    end
    if called and saved and profile.document.revision == savedDocument.revision then
        profile.dirty = false
    end
    profile.saving = false
end

function ConstructionService:Start()
    table.insert(connections, Players.PlayerAdded:Connect(function(player)
        task.spawn(loadPlayer, player)
    end))
    table.insert(connections, Players.PlayerRemoving:Connect(function(player)
        savePlayer(player)
        profiles[player] = nil
        self:GetDependency("GeometryService"):Release(player)
    end))

    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(loadPlayer, player)
    end

    -- Autosave dirty player documents. No write is attempted when Studio
    -- DataStore access is disabled or the initial load failed.
    task.spawn(function()
        while true do
            task.wait(60)
            if not self._Started then break end
            for player in pairs(profiles) do
                savePlayer(player)
            end
        end
    end)
end

function ConstructionService:Stop()
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
    for player in pairs(profiles) do
        savePlayer(player)
    end
end

function ConstructionService.Client.GetSnapshot(player)
    local profile = profiles[player]
    if not profile then
        return { ready = false }
    end
    return snapshot(profile)
end

function ConstructionService.Client.Submit(player, action, payload, revision)
    return change(player, action, payload, revision)
end

return ConstructionService
