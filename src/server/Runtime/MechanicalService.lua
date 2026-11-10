--!strict
-- Phase 05 relationship authoring. Parts remain anchored in construction;
-- constraints are materialized now and activate when bodies are shipped
-- into a future physics-simulation phase.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Alignment = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("AlignmentMath"))

local Mechanical = {}
Mechanical.__index = Mechanical
local MAX_RELATIONSHIPS_PER_PLAYER = 128

local function axisFrame(point, axis)
    local x = axis.Unit
    local up = if math.abs(x:Dot(Vector3.yAxis)) > 0.9
        then Vector3.zAxis else Vector3.yAxis
    local y = (up - x * up:Dot(x)).Unit
    return CFrame.fromMatrix(point, x, y, x:Cross(y))
end

local function relationValid(kind)
    return kind == "Bearing" or kind == "Slider" or kind == "Fixed"
end

function Mechanical.new(deps)
    local folder = workspace:FindFirstChild("OPENWORKS_Relationships")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "OPENWORKS_Relationships"
        folder.Parent = workspace
    end
    return setmetatable({ D = deps, Folder = folder }, Mechanical)
end

function Mechanical:OwnedRelation(player, id)
    if type(id) ~= "string" or #id > 64 then return nil end
    for _, relation in ipairs(self.Folder:GetChildren()) do
        if relation:IsA("Folder") and relation:GetAttribute("RelationId") == id
            and relation:GetAttribute("OwnerUserId") == player.UserId then
            return relation
        end
    end
    return nil
end

function Mechanical:Count(player)
    local count = 0
    for _, relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId") == player.UserId then count += 1 end
    end
    return count
end

function Mechanical:Snapshot(relation)
    return {
        relationId = relation:GetAttribute("RelationId"),
        ownerUserId = relation:GetAttribute("OwnerUserId"),
        kind = relation:GetAttribute("Kind"),
        targetId = relation:GetAttribute("TargetId"),
        sourceId = relation:GetAttribute("SourceId"),
        componentId = relation:GetAttribute("ComponentId"),
        offsetUnits = relation:GetAttribute("OffsetUnits"),
    }
end

function Mechanical:DestroyRelation(relation)
    if not relation then return end
    for _, object in ipairs(relation:GetChildren()) do
        if object:IsA("ObjectValue") and object.Value
            and object.Value:IsA("Attachment") then
            object.Value:Destroy()
        end
    end
    relation:Destroy()
end

function Mechanical:Restore(player, spec)
    if type(spec) ~= "table" or not relationValid(spec.kind)
        or type(spec.relationId) ~= "string" or #spec.relationId > 64 then
        return false, "Invalid relationship data"
    end

    if self:OwnedRelation(player, spec.relationId) then
        return false, "Relationship already exists"
    end
    if self:Count(player) >= MAX_RELATIONSHIPS_PER_PLAYER then
        return false, "Relationship limit reached"
    end

    local target = self.D.findOwned(player, spec.targetId)
    local source = self.D.findOwned(player, spec.sourceId)
    if not source or not target or source == target then
        return false, "Relationship parts were deleted"
    end

    local folder = Instance.new("Folder")
    folder.Name = "Relationship_" .. spec.relationId
    folder:SetAttribute("RelationId", spec.relationId)
    folder:SetAttribute("OwnerUserId", player.UserId)
    folder:SetAttribute("Kind", spec.kind)
    folder:SetAttribute("TargetId", spec.targetId)
    folder:SetAttribute("SourceId", spec.sourceId)
    folder:SetAttribute("ComponentId", spec.componentId)
    folder:SetAttribute("OffsetUnits", spec.offsetUnits or 0)

    local targetPart, sourcePart = target.PrimaryPart, source.PrimaryPart
    if not targetPart or not sourcePart then
        folder:Destroy()
        return false, "Missing relationship geometry"
    end

    if spec.kind == "Fixed" then
        local weld = Instance.new("WeldConstraint")
        weld.Name = "Fixed"
        weld.Part0 = targetPart
        weld.Part1 = sourcePart
        weld.Parent = folder
    else
        local axisLocal = Alignment.TargetAxis(target)
        if not axisLocal or not Alignment.IsShaft(source) then
            folder:Destroy()
            return false, "Bearing/slider requires a shaft and an opening"
        end
        local axis = target:GetPivot():VectorToWorldSpace(axisLocal)
        local point = target:GetPivot().Position
        local worldCF = axisFrame(point, axis)
        local attachment0 = Instance.new("Attachment")
        attachment0.Name = "OPENWORKS_RelationHousing"
        attachment0.CFrame = targetPart.CFrame:ToObjectSpace(worldCF)
        attachment0.Parent = targetPart
        local attachment1 = Instance.new("Attachment")
        attachment1.Name = "OPENWORKS_RelationShaft"
        attachment1.CFrame = sourcePart.CFrame:ToObjectSpace(worldCF)
        attachment1.Parent = sourcePart

        for _, attachment in ipairs({ attachment0, attachment1 }) do
            local link = Instance.new("ObjectValue")
            link.Name = "ManagedAttachment"
            link.Value = attachment
            link.Parent = folder
        end

        local constraint = if spec.kind == "Bearing"
            then Instance.new("HingeConstraint")
            else Instance.new("PrismaticConstraint")
        constraint.Name = spec.kind
        constraint.Attachment0 = attachment0
        constraint.Attachment1 = attachment1
        constraint.Enabled = true
        constraint.Parent = folder
    end
    folder.Parent = self.Folder
    return true, folder
end

function Mechanical:Create(player, request)
    local d = self.D
    if not relationValid(request.kind) then
        return false, "Choose Bearing, Slider, or Fixed"
    end
    if type(request.targetId) ~= "string"
        or type(request.sourceId) ~= "string" then
        return false, "Choose two valid primitives"
    end

    local source = d.findOwned(player, request.sourceId)
    local target = d.findOwned(player, request.targetId)
    if not source or not target or source == target then
        return false, "Choose two different primitives you own"
    end
    if not d.nearPlayer(player, target:GetPivot().Position)
        or not d.nearPlayer(player, source:GetPivot().Position) then
        return false, "Parts are outside your building range"
    end
    -- Duplicate constraints between the same pair would over-constrain
    -- the physics graph when the construction is eventually shipped.
    for _, existing in ipairs(self.Folder:GetChildren()) do
        if existing:GetAttribute("OwnerUserId") == player.UserId
            and existing:GetAttribute("TargetId") == request.targetId
            and existing:GetAttribute("SourceId") == request.sourceId
            and existing:GetAttribute("Kind") == request.kind then
            return false, "That relationship already exists"
        end
    end

    local componentId = source:GetAttribute("ComponentId")
    if componentId and componentId == target:GetAttribute("ComponentId") then
        return false, "Relationship requires two separate rigid bodies"
    end

    local members = if componentId then d.components:Members(player, componentId)
        else { source }
    if #members == 0 or #members > 128 then
        return false, "Invalid source component"
    end
    for _, member in ipairs(members) do
        if member == target then return false, "Opening belongs to the moving body" end
    end

    local before, planned = {}, {}
    for _, member in ipairs(members) do table.insert(before, d.snapshot(member)) end

    if request.kind ~= "Fixed" then
        if not Alignment.IsOffsetValid(request.offsetUnits) then
            return false, "Invalid insertion offset"
        end
        local plan, reason = Alignment.Plan(members, source, target, request.offsetUnits)
        if not plan then return false, reason end
        for _, item in ipairs(plan.items) do
            local old = d.snapshot(item.model)
            local targetState = table.clone(old)
            targetState.steps = item.steps
            targetState.position = item.position
            targetState.assemblyPrecision = true
            targetState.freePosition = true
            local entry = d.Registry.Get(old.templateId)
            if not entry then return false, "Missing component template" end
            local valid, why = d.validState(player, entry, targetState)
            if not valid then return false, why end
            table.insert(planned, targetState)
        end
    else
        for _, state in ipairs(before) do table.insert(planned, state) end
    end

    local ignore = {}
    for _, member in ipairs(members) do ignore[member] = true end

    if request.kind ~= "Fixed" then
        for index, member in ipairs(members) do
            d.applyState(member, planned[index])
        end
        for _, member in ipairs(members) do
            if d.intersectsConstructed(member, ignore) then
                for index, old in ipairs(before) do d.applyState(members[index], old) end
                return false, "Mechanical relationship interferes with solid geometry"
            end
        end
    end

    local spec = {
        relationId = HttpService:GenerateGUID(false),
        ownerUserId = player.UserId,
        kind = request.kind,
        sourceId = request.sourceId,
        targetId = request.targetId,
        componentId = componentId,
        offsetUnits = if request.kind == "Fixed" then 0 else request.offsetUnits,
    }
    local created, result = self:Restore(player, spec)
    if not created then
        for index, old in ipairs(before) do d.applyState(members[index], old) end
        return false, result
    end
    d.commitAssembly(player, before, planned, spec)
    return true, spec.kind .. " relationship created (physics when shipped)"
end

function Mechanical:Remove(player, request)
    local relation = self:OwnedRelation(player, request.relationId)
    if not relation then return false, "Select a relationship you own" end
    local spec = self:Snapshot(relation)
    self:DestroyRelation(relation)
    self.D.commitAssembly(player, {}, {}, spec, true)
    return true, "Relationship removed"
end

function Mechanical:ApplyHistory(player, record, undo, restoreBatch)
    local removing = if record.removed then not undo else undo
    if removing then
        local relation = self:OwnedRelation(player, record.relation.relationId)
        if relation then self:DestroyRelation(relation) end
        local ok, why = restoreBatch(player, record, undo)
        if not ok then
            self:Restore(player, record.relation)
            return false, why
        end
        return true
    end

    local ok, why = restoreBatch(player, record, undo)
    if not ok then return false, why end
    local success, result = self:Restore(player, record.relation)
    if not success then
        restoreBatch(player, record, not undo)
        return false, result
    end
    return true
end

function Mechanical:RebuildRelations()
    -- Rebind constraints if an undo/redo replaced primary part instances.
    for _, relation in ipairs(self.Folder:GetChildren()) do
        if not relation:IsA("Folder") then continue end
        local userId = relation:GetAttribute("OwnerUserId")
        local player = game:GetService("Players"):GetPlayerByUserId(userId or -1)
        if player then
            local spec = self:Snapshot(relation)
            local source = self.D.findOwned(player, spec.sourceId)
            local target = self.D.findOwned(player, spec.targetId)
            if not source or not target then
                self:DestroyRelation(relation)
            else
                local constraint = relation:FindFirstChildWhichIsA("Constraint")
                local old0 = constraint and constraint.Attachment0
                local old1 = constraint and constraint.Attachment1
                if constraint and (
                    not old0 or not old1
                    or not old0:IsDescendantOf(target)
                    or not old1:IsDescendantOf(source)
                ) then
                    self:DestroyRelation(relation)
                    self:Restore(player, spec)
                elseif relation:FindFirstChildOfClass("WeldConstraint") then
                    local weld = relation:FindFirstChildOfClass("WeldConstraint")
                    weld.Part0 = target.PrimaryPart
                    weld.Part1 = source.PrimaryPart
                end
            end
        end
    end
end

function Mechanical:ClearPlayer(player)
    for _, relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId") == player.UserId then
            self:DestroyRelation(relation)
        end
    end
end

return Mechanical
