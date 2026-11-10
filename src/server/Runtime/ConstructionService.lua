--!strict
-- Server-authoritative Phase 02 construction. Studio prebaked geometry only.
-- Requests never contain trusted instances or arbitrary physical dimensions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Registry = require(construction:WaitForChild("PrimitiveRegistry"))
local Grid = require(construction:WaitForChild("GridMath"))
local Config = require(construction:WaitForChild("BuildConfig"))

local Service = {}
local folder
local remote
local histories = {}
local lastRequest = {}

local function historyFor(player)
    local state = histories[player]
    if not state then
        state = { undo = {}, redo = {} }
        histories[player] = state
    end
    return state
end

local function ownedCount(player)
    local n = 0
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
            n += 1
        end
    end
    return n
end

local function hasEquippedTool(player, id)
    local character = player.Character
    if not character then return false end
    for _, object in ipairs(character:GetChildren()) do
        if object:IsA("Tool") and object:GetAttribute("OpenworksToolId") == id then
            return true
        end
    end
    return false
end

local function accessFor(player, action)
    if action == "Place" then
        return hasEquippedTool(player, "Build") or hasEquippedTool(player, "Edit")
    end
    return hasEquippedTool(player, "Edit") or hasEquippedTool(player, "Build")
end

local function nearPlayer(player, position)
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    return head and (head.Position - position).Magnitude <= Grid.MaxDistance
end

local function findOwned(player, id)
    if type(id) ~= "string" or #id > 64 then return nil end
    for _, model in ipairs(folder:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("InstanceId") == id
            and model:GetAttribute("OwnerUserId") == player.UserId then
            return model
        end
    end
    return nil
end

local function snapshot(model)
    local primary = model.PrimaryPart
    return {
        instanceId = model:GetAttribute("InstanceId"),
        templateId = model:GetAttribute("TemplateId"),
        position = model:GetPivot().Position,
        steps = {
            x = model:GetAttribute("RotX") or 0,
            y = model:GetAttribute("RotY") or 0,
            z = model:GetAttribute("RotZ") or 0,
        },
        size = primary.Size,
    }
end

local function createFromTemplate(player, templateId, instanceId)
    local entry = Registry.Get(templateId)
    if not entry then return nil, "Unknown primitive template" end
    if ownedCount(player) >= Config.MaxPartsPerPlayer then
        return nil, "Construction limit reached"
    end

    local model = entry.Model:Clone()
    model.Name = templateId
    model:SetAttribute("TemplateId", templateId)
    model:SetAttribute("InstanceId", instanceId or HttpService:GenerateGUID(false))
    model:SetAttribute("OwnerUserId", player.UserId)

    local primary = model.PrimaryPart or model:FindFirstChild("Geometry")
    if not primary or not primary:IsA("BasePart") then
        model:Destroy()
        return nil, "Template is missing its geometry"
    end

    model.PrimaryPart = primary
    primary.Anchored = true
    primary.CanCollide = true
    primary.CanQuery = true
    primary.CanTouch = false

    return model
end

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.RespectCanCollide = false
overlap.MaxParts = 0

local function intersectsConstructed(candidate, except)
    -- Exact occupied-volume test rather than CSG bounding box.
    -- Slight shrink distinguishes face-to-face placement from penetration.
    local primary = candidate.PrimaryPart
    local probe = primary:Clone()
    probe.Name = "OPENWORKS_OverlapProbe"
    probe.Size = Vector3.new(
        math.max(0.015, primary.Size.X - 0.006),
        math.max(0.015, primary.Size.Y - 0.006),
        math.max(0.015, primary.Size.Z - 0.006)
    )
    probe.CFrame = primary.CFrame
    probe.Transparency = 1
    probe.CanCollide = false
    probe.CanTouch = false
    probe.CanQuery = false
    probe.Anchored = true
    probe.Parent = workspace

    overlap.FilterDescendantsInstances = { folder }
    local ok, results = pcall(function()
        return workspace:GetPartsInPart(probe, overlap)
    end)
    probe:Destroy()
    if not ok then
        warn("[OPENWORKS] Precise overlap test failed: " .. tostring(results))
        return true
    end

    for _, part in ipairs(results) do
        if not except or not part:IsDescendantOf(except) then
            return true
        end
    end
    return false
end

local function validState(player, entry, proposed)
    if type(proposed) ~= "table"
        or not Grid.ValidPosition(proposed.position)
        or not Grid.ValidSteps(proposed.steps)
        or typeof(proposed.size) ~= "Vector3" then
        return false, "Invalid construction state"
    end
    if not nearPlayer(player, proposed.position) then
        return false, "Target is too far away"
    end

    local original = entry.Model.PrimaryPart
    if not original then return false, "Missing primitive geometry" end
    if not Grid.ValidSize(original.Size, proposed.size, entry.ResizeMode) then
        return false, "Size does not match allowed Unit increments"
    end

    local rotation = Grid.Rotation(proposed.steps)
    if not Grid.IsSnapped(proposed.position, proposed.size, rotation) then
        return false, "Position is not aligned to the Unit grid"
    end
    return true
end

local function applyState(model, data)
    model.PrimaryPart.Size = data.size
    model:PivotTo(CFrame.new(data.position) * Grid.Rotation(data.steps))
    model:SetAttribute("RotX", data.steps.x)
    model:SetAttribute("RotY", data.steps.y)
    model:SetAttribute("RotZ", data.steps.z)
end

local function commitRecord(player, before, after)
    local state = historyFor(player)
    table.insert(state.undo, { before = before, after = after })
    if #state.undo > Config.UndoLimit then
        table.remove(state.undo, 1)
    end
    table.clear(state.redo)
end

local function place(player, payload)
    if type(payload.templateId) ~= "string" then return false, "Missing template ID" end
    local entry = Registry.Get(payload.templateId)
    if not entry then return false, "Unknown primitive" end
    local template = entry.Model.PrimaryPart
    local proposed = {
        position = payload.position,
        steps = payload.steps,
        size = payload.size or (template and template.Size),
    }

    local valid, reason = validState(player, entry, proposed)
    if not valid then return false, reason end

    local model, why = createFromTemplate(player, payload.templateId)
    if not model then return false, why end
    applyState(model, proposed)

    if intersectsConstructed(model) then
        model:Destroy()
        return false, "Placement intersects existing geometry"
    end

    model.Parent = folder
    local after = snapshot(model)
    commitRecord(player, nil, after)
    return true, after.instanceId
end

local function update(player, payload)
    local model = findOwned(player, payload.instanceId)
    if not model then return false, "Select a piece you own" end

    local entry = Registry.Get(model:GetAttribute("TemplateId"))
    if not entry then return false, "Primitive template missing" end

    local proposed = {
        position = payload.position,
        steps = payload.steps,
        size = payload.size,
    }
    local valid, reason = validState(player, entry, proposed)
    if not valid then return false, reason end

    local before = snapshot(model)
    applyState(model, proposed)

    if intersectsConstructed(model, model) then
        applyState(model, before)
        return false, "Edit intersects another piece"
    end

    local after = snapshot(model)
    commitRecord(player, before, after)
    return true, after.instanceId
end

local function delete(player, payload)
    local model = findOwned(player, payload.instanceId)
    if not model then return false, "Select a piece you own" end
    local before = snapshot(model)
    model:Destroy()
    commitRecord(player, before, nil)
    return true, "Deleted"
end

local function restore(player, data)
    local model = findOwned(player, data.instanceId)
    if not model then
        local reason
        model, reason = createFromTemplate(player, data.templateId, data.instanceId)
        if not model then return false, reason end
    end
    local entry = Registry.Get(data.templateId)
    if not entry then model:Destroy() return false, "Template unavailable" end
    local valid, reason = validState(player, entry, data)
    if not valid then
        if not model.Parent then model:Destroy() end
        return false, reason
    end

    local before = if model.Parent then snapshot(model) else nil
    applyState(model, data)

    if intersectsConstructed(model, model) then
        if before then
            applyState(model, before)
        else
            model:Destroy()
        end
        return false, "Undo/redo blocked by another piece"
    end

    model.Parent = folder
    return true
end

local function applyRecord(player, record, undo)
    local target = if undo then record.before else record.after
    local other = if undo then record.after else record.before
    if target == nil then
        local model = findOwned(player, other.instanceId)
        if not model then return false, "Piece no longer exists" end
        model:Destroy()
        return true
    end
    return restore(player, target)
end

local function historyAction(player, isUndo)
    local state = historyFor(player)
    local source = if isUndo then state.undo else state.redo
    local destination = if isUndo then state.redo else state.undo
    local record = source[#source]
    if not record then return false, "Nothing to " .. (if isUndo then "undo" else "redo") end

    local ok, reason = applyRecord(player, record, isUndo)
    if not ok then return false, reason end

    table.remove(source)
    table.insert(destination, record)
    return true, if isUndo then "Undone" else "Redone"
end

local function handle(player, payload)
    if type(payload) ~= "table" or type(payload.action) ~= "string" then
        return { ok = false, message = "Invalid request" }
    end

    local action = payload.action
    if action ~= "Place" and action ~= "Update" and action ~= "Delete"
        and action ~= "Undo" and action ~= "Redo" then
        return { ok = false, message = "Unknown action" }
    end
    if not accessFor(player, action) then
        return { ok = false, message = "Equip Build or Edit" }
    end

    local now = os.clock()
    if now - (lastRequest[player] or 0) < Config.MinActionInterval then
        return { ok = false, message = "Try again" }
    end
    lastRequest[player] = now

    local ok, result, extra = pcall(function()
        if action == "Place" then return place(player, payload) end
        if action == "Update" then return update(player, payload) end
        if action == "Delete" then return delete(player, payload) end
        return historyAction(player, action == "Undo")
    end)

    if not ok then
        warn("[OPENWORKS] Construction request error: " .. tostring(result))
        return { ok = false, message = "Construction error (check Output)" }
    end
    local message = tostring(extra or "")
    if result and action == "Place" then message = "Placed" end
    if result and action == "Update" then message = "Updated" end
    return { ok = result == true, message = message, instanceId = if result and action == "Place" then extra else nil }
end

function Service.Start()
    folder = workspace:FindFirstChild(Config.FolderName)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = Config.FolderName
        folder.Parent = workspace
    end

    -- The gallery is an Edit-mode inspection aid, never buildable world geometry.
    -- This only moves it during Play; the Studio place remains unchanged.
    local gallery = workspace:FindFirstChild(Config.GalleryName)
    if gallery then
        gallery.Parent = game:GetService("ServerStorage")
    end

    local oldRemote = ReplicatedStorage:FindFirstChild(Config.RequestName)
    if oldRemote then oldRemote:Destroy() end

    remote = Instance.new("RemoteFunction")
    remote.Name = Config.RequestName
    remote.OnServerInvoke = handle
    remote.Parent = ReplicatedStorage

    Players.PlayerRemoving:Connect(function(player)
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
                model:Destroy()
            end
        end
        histories[player] = nil
        lastRequest[player] = nil
    end)

    print("[OPENWORKS] ConstructionService ready: server-owned pieces and history")
end

return Service
