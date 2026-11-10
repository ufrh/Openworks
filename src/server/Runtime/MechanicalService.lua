--!strict
-- Phase 05 relationship authoring. Parts remain anchored in construction;
-- constraints are materialized now and activate when bodies are shipped
-- into a future physics-simulation phase.
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Alignment = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("AlignmentMath"))
local JointFrames = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("JointFrames"))
local Bore = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("BoreClearance"))

local Mechanical = {}
Mechanical.__index = Mechanical
local MAX_RELATIONSHIPS_PER_PLAYER = 128

local function relationValid(kind)
    return kind == "Bearing" or kind == "Slider"
        or kind == "Cylindrical" or kind == "Fixed" or kind == "Gear"
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
        rollDegrees = relation:GetAttribute("RollDegrees") or 0,
        lowerLimit = relation:GetAttribute("LowerLimit"),
        upperLimit = relation:GetAttribute("UpperLimit"),
        limitsEnabled = relation:GetAttribute("LimitsEnabled") == true,
        driveScale = relation:GetAttribute("DriveScale") or 1,
        gearRatio = relation:GetAttribute("GearRatio"),
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
    folder:SetAttribute("RollDegrees", spec.rollDegrees or 0)
    folder:SetAttribute("LowerLimit", spec.lowerLimit)
    folder:SetAttribute("UpperLimit", spec.upperLimit)
    folder:SetAttribute("LimitsEnabled", spec.limitsEnabled == true)
    folder:SetAttribute("DriveScale", spec.driveScale or 1)
    folder:SetAttribute("GearRatio", spec.gearRatio)

    local targetPart, sourcePart = target.PrimaryPart, source.PrimaryPart
    if not targetPart or not sourcePart then
        folder:Destroy()
        return false, "Missing relationship geometry"
    end

    if spec.kind == "Gear" then
        if not source:GetAttribute("GearTeeth")
            or not target:GetAttribute("GearTeeth") then
            folder:Destroy()
            return false, "A Gear relationship requires two gear primitives"
        end
        -- Gear-to-gear motion is synchronized in the simulation runtime,
        -- never falsely represented as a native Roblox GearConstraint.
    elseif spec.kind == "Fixed" then
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
        local worldCF = JointFrames.ForOpening(target)
        if not worldCF then
            folder:Destroy()
            return false, "Opening has no valid joint orientation"
        end
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
            elseif spec.kind == "Slider"
            then Instance.new("PrismaticConstraint")
            else Instance.new("CylindricalConstraint")
        constraint.Name = spec.kind
        constraint.Attachment0 = attachment0
        constraint.Attachment1 = attachment1
        constraint.Enabled = true
        constraint.LimitsEnabled = spec.limitsEnabled == true
        if constraint.LimitsEnabled then
            if constraint:IsA("HingeConstraint") then
                constraint.LowerAngle = spec.lowerLimit or -180
                constraint.UpperAngle = spec.upperLimit or 180
            else
                constraint.LowerLimit = (spec.lowerLimit or -4) * self.D.Grid.Unit
                constraint.UpperLimit = (spec.upperLimit or 4) * self.D.Grid.Unit
            end
        end
        constraint.Parent = folder
    end
    folder.Parent = self.Folder
    return true, folder
end

function Mechanical:Create(player, request)
    local d = self.D
    -- Gear meshes have distinct geometry/teeth validation and must use
    -- CreateGearMesh, never the shaft-in-hole relationship pathway.
    if request.kind == "Gear" then
        return false, "Use Gear Mesh (K) to connect two gears"
    end
    if not relationValid(request.kind) then
        return false, "Choose Bearing, Slider, Cylindrical, or Fixed"
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
        local plan, reason = Alignment.Plan(
            members, source, target, request.offsetUnits, request.rollDegrees
        )
        if not plan then return false, reason end
        for _, item in ipairs(plan.items) do
            local old = d.snapshot(item.model)
            local targetState = table.clone(old)
            targetState.steps = item.steps
            targetState.position = item.position
            targetState.orientation = item.orientation
            targetState.grounded = old.grounded
            targetState.shaftRollDegrees = if member == source
                then request.rollDegrees or 0 else old.shaftRollDegrees
            targetState.alignedOffsetU = if member == source
                then request.offsetUnits else old.alignedOffsetU
            targetState.alignedOpeningId = if member == source
                then target:GetAttribute("InstanceId") else old.alignedOpeningId
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
            if d.intersectsConstructed(member, ignore, target,
                source:GetAttribute("InstanceId")) then
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
        rollDegrees = request.rollDegrees or 0,
    }
    local created, result = self:Restore(player, spec)
    if not created then
        for index, old in ipairs(before) do d.applyState(members[index], old) end
        return false, result
    end
    d.commitAssembly(player, before, planned, spec)
    return true, spec.kind .. " relationship created (physics when shipped)"
end

-- Independent gear mesh: both gear primitives must have the same
-- tooth module, coaxial-parallel shafts and compatible pitch-circle spacing.
-- Teeth are real separate Parts; ratio coupling is done by paired hinge
-- drives in SimulationService (Roblox has no native GearConstraint).
function Mechanical:CreateGearMesh(player, request)
    local d = self.D
    local first = d.findOwned(player, request.sourceId)
    local second = d.findOwned(player, request.targetId)
    if not first or not second or first == second then
        return false, "Choose two different gears you own"
    end
    local n1, n2 = first:GetAttribute("GearTeeth"), second:GetAttribute("GearTeeth")
    if type(n1) ~= "number" or type(n2) ~= "number" then
        return false, "Gear Mesh requires two Transmission gears"
    end
    if first:GetAttribute("ComponentId") ~= nil
        and first:GetAttribute("ComponentId") == second:GetAttribute("ComponentId") then
        return false, "Gears must belong to separate rotating bodies"
    end
    if not d.nearPlayer(player, first:GetPivot().Position)
        or not d.nearPlayer(player, second:GetPivot().Position) then
        return false, "Gear is outside build range"
    end
    local module1 = first:GetAttribute("GearModuleStuds")
    local module2 = second:GetAttribute("GearModuleStuds")
    if type(module1) ~= "number" or math.abs(module1 - module2) > 0.001 then
        return false, "Gears have different tooth pitches"
    end
    local a, b = first:GetPivot(), second:GetPivot()
    local axis = a.RightVector
    if math.abs(axis:Dot(b.RightVector)) < 0.999 then
        return false, "Gear shafts must be parallel"
    end
    local diff = b.Position - a.Position
    local axial = math.abs(diff:Dot(axis))
    local radial = (diff - axis * diff:Dot(axis)).Magnitude
    local targetDistance = (n1 + n2) * module1 / (2 * math.pi)
    if math.abs(radial - targetDistance) > 0.09 or axial > 0.18 then
        return false, string.format(
            "Place gear centers %.2f studs apart in their shared plane",
            targetDistance
        )
    end
    for _, relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId") == player.UserId
            and relation:GetAttribute("Kind") == "Gear"
            and ((relation:GetAttribute("SourceId") == request.sourceId
                and relation:GetAttribute("TargetId") == request.targetId)
                or (relation:GetAttribute("SourceId") == request.targetId
                and relation:GetAttribute("TargetId") == request.sourceId)) then
            return false, "Those gears are already meshed"
        end
    end
    local spec = {
        relationId = HttpService:GenerateGUID(false),
        ownerUserId = player.UserId,
        kind = "Gear",
        sourceId = request.sourceId,
        targetId = request.targetId,
        gearRatio = -n1 / n2,
    }
    local ok, reason = self:Restore(player, spec)
    if not ok then return false, reason end
    d.commitAssembly(player, {}, {}, spec)
    return true, string.format("Gear mesh %.0f:%.0f • ratio %.3f",
        n1,n2, spec.gearRatio)
end

-- Precisely adjust an existing shaft on its real opening axis; all members
-- of the moving component follow the same SE(3) transform. Axial offset
-- and shaft roll may change together, without recreating the relationship.
function Mechanical:PoseShaft(player, request)
    local d = self.D
    local source = d.findOwned(player, request.sourceId)
    local target = d.findOwned(player, request.targetId)
    if not source or not target or source == target
        or not Alignment.IsShaft(source) or not Alignment.TargetAxis(target) then
        return false, "Choose a shaft inside a valid opening"
    end
    local offset = request.offsetUnits
    local roll = request.rollDegrees
    if not Alignment.IsOffsetValid(offset)
        or type(roll) ~= "number" or roll ~= roll or math.abs(roll) > 360 then
        return false, "Invalid insertion or rotation angle"
    end
    if not d.nearPlayer(player, target:GetPivot().Position) then
        return false, "Opening out of range"
    end
    local relation
    for _, current in ipairs(self.Folder:GetChildren()) do
        if current:GetAttribute("OwnerUserId") == player.UserId
            and current:GetAttribute("SourceId") == request.sourceId
            and current:GetAttribute("TargetId") == request.targetId
            and (current:GetAttribute("Kind") == "Bearing"
                or current:GetAttribute("Kind") == "Slider"
                or current:GetAttribute("Kind") == "Cylindrical") then
            relation = current
            break
        end
    end
    if not relation and source:GetAttribute("AlignedOpeningId")
        ~= request.targetId then
        return false, "Align or connect the shaft first"
    end
    local componentId = source:GetAttribute("ComponentId")
    local members = if componentId then d.components:Members(player,componentId)
        else {source}
    local axis = target:GetPivot():VectorToWorldSpace(Alignment.TargetAxis(target)).Unit
    local pivot = target:GetPivot().Position
    local previousRoll = source:GetAttribute("ShaftRollDegrees") or 0
    local previousOffset = source:GetAttribute("AlignedOffsetU") or 0
    local delta = CFrame.new(axis * ((offset - previousOffset) * d.Grid.Unit))
        * CFrame.new(pivot)
        * CFrame.fromAxisAngle(axis, math.rad(roll - previousRoll))
        * CFrame.new(-pivot)

    local before, planned, ignored = {}, {}, {}
    for _, member in ipairs(members) do
        local old = d.snapshot(member)
        local moved = delta * member:GetPivot()
        local nextState = table.clone(old)
        nextState.position = moved.Position
        nextState.orientation = moved.Rotation
        nextState.freePosition = true
        if member == source then
            nextState.shaftRollDegrees = roll
            nextState.alignedOffsetU = offset
            nextState.alignedOpeningId = request.targetId
        end
        local entry = d.Registry.Get(old.templateId)
        if not entry then return false, "Missing component primitive" end
        local valid, why = d.validState(player, entry, nextState)
        if not valid then return false, why end
        table.insert(before, old)
        table.insert(planned, nextState)
        ignored[member] = true
    end
    for i, member in ipairs(members) do d.applyState(member,planned[i]) end
    for _, member in ipairs(members) do
        if d.intersectsConstructed(member, ignored, target, request.sourceId) then
            for i, restore in ipairs(members) do d.applyState(restore,before[i]) end
            return false, "Pose interferes with the opening or another member"
        end
    end
    if relation then
        relation:SetAttribute("OffsetUnits", offset)
        relation:SetAttribute("RollDegrees", roll)
    end
    d.commitBatch(player,before,planned)
    return true, string.format("Insertion %.1f U • shaft angle %.1f°",offset,roll)
end

function Mechanical:AdjustJoint(player, request)
    local joint = self:OwnedRelation(player,request.relationId)
    if not joint then return false, "Select a joint you own" end
    local kind = joint:GetAttribute("Kind")
    if kind ~= "Bearing" and kind ~= "Slider" and kind ~= "Cylindrical" then
        return false, "This relationship has no travel limits"
    end
    local lower,upper = request.lowerLimit,request.upperLimit
    local on = request.limitsEnabled
    if type(on) ~= "boolean"
        or type(lower) ~= "number" or type(upper) ~= "number"
        or lower ~= lower or upper ~= upper or lower >= upper then
        return false, "Invalid joint limits"
    end
    local max = if kind == "Bearing" then 180 else 32
    if lower < -max or upper > max then return false, "Joint limits outside range" end
    local old = self:Snapshot(joint)
    joint:SetAttribute("LimitsEnabled", on)
    joint:SetAttribute("LowerLimit",lower)
    joint:SetAttribute("UpperLimit",upper)
    local constraint = joint:FindFirstChildWhichIsA("Constraint")
    if constraint then
        constraint.LimitsEnabled = on
        if kind == "Bearing" then
            constraint.LowerAngle = lower
            constraint.UpperAngle = upper
        else
            constraint.LowerLimit = lower * self.D.Grid.Unit
            constraint.UpperLimit = upper * self.D.Grid.Unit
        end
    end
    if self.D.commitJointEdit then
        self.D.commitJointEdit(player,old,self:Snapshot(joint))
    end
    return true, "Joint limits updated"
end

function Mechanical:ApplyJointEdit(player, record, undo)
    local spec = if undo then record.before else record.after
    local relation = self:OwnedRelation(player, spec.relationId)
    if not relation then return false, "Joint was deleted" end
    relation:SetAttribute("LowerLimit",spec.lowerLimit)
    relation:SetAttribute("UpperLimit",spec.upperLimit)
    relation:SetAttribute("LimitsEnabled",spec.limitsEnabled == true)
    local constraint = relation:FindFirstChildWhichIsA("Constraint")
    if constraint then
        constraint.LimitsEnabled = spec.limitsEnabled == true
        if spec.kind == "Bearing" then
            constraint.LowerAngle = spec.lowerLimit or -180
            constraint.UpperAngle = spec.upperLimit or 180
        elseif spec.kind == "Slider" or spec.kind == "Cylindrical" then
            constraint.LowerLimit = (spec.lowerLimit or -4) * self.D.Grid.Unit
            constraint.UpperLimit = (spec.upperLimit or 4) * self.D.Grid.Unit
        end
    end
    return true
end

-- A dedicated post-alignment micro-fit operation. A client cannot grant
-- itself fine sizing permission: it must own BOTH parts and have an authored
-- relationship or a server-recorded Align connection between them.
function Mechanical:Fit(player, request)
    local d = self.D
    if type(request.sourceId) ~= "string" or type(request.targetId) ~= "string"
        or (request.step ~= 1 and request.step ~= -1) then
        return false, "Choose an aligned shaft and use the wheel to fit it"
    end
    local source = d.findOwned(player, request.sourceId)
    local target = d.findOwned(player, request.targetId)
    if not source or not target or source == target
        or not Alignment.IsShaft(source) or not Alignment.TargetAxis(target) then
        return false, "Fit requires your Cylinder shaft inside a supported opening"
    end
    if not d.nearPlayer(player, source:GetPivot().Position)
        or not d.nearPlayer(player, target:GetPivot().Position) then
        return false, "Shaft is outside your building range"
    end

    local connected = source:GetAttribute("AlignedOpeningId")
        == target:GetAttribute("InstanceId")
    if not connected then
        for _, relation in ipairs(self.Folder:GetChildren()) do
            if relation:GetAttribute("OwnerUserId") == player.UserId
                and relation:GetAttribute("SourceId") == request.sourceId
                and relation:GetAttribute("TargetId") == request.targetId
                and (relation:GetAttribute("Kind") == "Bearing"
                    or relation:GetAttribute("Kind") == "Slider") then
                connected = true
                break
            end
        end
    end
    if not connected then
        return false, "Align or connect this shaft to the opening first"
    end

    local maxDiameter, why = Bore.MaxShaftDiameter(source, target)
    if not maxDiameter then return false, why end

    local current = source.PrimaryPart.Size
    local stepU = 0.05
    local oldDiameterU = current.Y / d.Grid.Unit
    -- Diameter is uniform in Y/Z; X is never altered by fitting.
    local nextTicks = math.round(oldDiameterU / stepU) + request.step
    local nextDiameter = nextTicks * stepU * d.Grid.Unit
    if nextDiameter < 0.25 * d.Grid.Unit - 1e-6 then
        return false, "Minimum shaft diameter reached (0.25 U)"
    end
    if nextDiameter > maxDiameter + 1e-6 then
        local remainingU = math.max(0, (maxDiameter - current.Y) / d.Grid.Unit)
        return false, string.format(
            "Snug fit reached — %.2f U clearance remaining", remainingU)
    end

    local before = d.snapshot(source)
    local proposed = table.clone(before)
    proposed.size = Vector3.new(current.X, nextDiameter, nextDiameter)
    proposed.fitPrecision = true

    local entry = d.Registry.Get(before.templateId)
    if not entry then return false, "Missing shaft template" end
    local valid, reason = d.validState(player, entry, proposed)
    if not valid then return false, reason end

    d.applyState(source, proposed)
    local fits, fitReason = Bore.ShaftFits(source, target)
    if not fits or d.intersectsConstructed(
        source, source, target, source:GetAttribute("InstanceId")
    ) then
        d.applyState(source, before)
        return false, fitReason or "Shaft interferes with another solid"
    end

    local after = d.snapshot(source)
    d.commitRecord(player, before, after)
    return true, string.format(
        "Shaft %.2f U diameter • %.2f U clearance",
        nextDiameter / d.Grid.Unit,
        math.max(0, (maxDiameter - nextDiameter) / d.Grid.Unit)
    )
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
            if source and (spec.kind == "Bearing" or spec.kind == "Slider"
                or spec.kind == "Cylindrical") then
                relation:SetAttribute("OffsetUnits",
                    source:GetAttribute("AlignedOffsetU") or spec.offsetUnits)
                relation:SetAttribute("RollDegrees",
                    source:GetAttribute("ShaftRollDegrees") or spec.rollDegrees)
            end
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
