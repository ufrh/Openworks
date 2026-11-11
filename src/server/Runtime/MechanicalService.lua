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
local Smart = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("SmartPlacement"))
local GearMath = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GearMath"))
local HandCrankMath = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("HandCrankMath"))
local ComponentGeometry = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("ComponentGeometry"))
local BoltMath = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("BoltMath"))
local SpringMath = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("SpringMath"))
local MultiFit = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("MultiFitMath"))

local Mechanical = {}
Mechanical.__index = Mechanical
local MAX_RELATIONSHIPS_PER_PLAYER = 128

local function relationValid(kind)
    return kind == "Bearing" or kind == "Slider"
        or kind == "Cylindrical" or kind == "Fixed" or kind == "Gear"
        or kind == "Spring" or kind == "Weld" or kind == "Bolt"
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
        gearRatio = relation:GetAttribute("GearRatio"),
        springMode = relation:GetAttribute("SpringMode"),
        stiffness = relation:GetAttribute("Stiffness"),
        damping = relation:GetAttribute("Damping"),
        freeLength = relation:GetAttribute("FreeLength"),
        boltId = relation:GetAttribute("BoltId"),
        secondTargetId = relation:GetAttribute("SecondTargetId"),
        fitPointsJSON = relation:GetAttribute("FitPointsJSON"),
        fitPointCount = relation:GetAttribute("FitPointCount"),
        fitTravelU = relation:GetAttribute("FitTravelU"),
        fitSetId = relation:GetAttribute("FitSetId"),
        fitSetIndex = relation:GetAttribute("FitSetIndex"),
        fitSetCount = relation:GetAttribute("FitSetCount"),
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
    folder:SetAttribute("GearRatio", spec.gearRatio)
    folder:SetAttribute("SpringMode",spec.springMode)
    folder:SetAttribute("Stiffness",spec.stiffness)
    folder:SetAttribute("Damping",spec.damping)
    folder:SetAttribute("FreeLength",spec.freeLength)
    folder:SetAttribute("BoltId",spec.boltId)
    folder:SetAttribute("SecondTargetId",spec.secondTargetId)
    folder:SetAttribute("FitPointsJSON",spec.fitPointsJSON)
    folder:SetAttribute("FitPointCount",spec.fitPointCount)
    folder:SetAttribute("FitTravelU",spec.fitTravelU)
    folder:SetAttribute("FitSetId",spec.fitSetId)
    folder:SetAttribute("FitSetIndex",spec.fitSetIndex)
    folder:SetAttribute("FitSetCount",spec.fitSetCount)

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
    elseif spec.kind == "Fixed" or spec.kind=="Weld"
        or spec.kind=="Bolt" then
        local weld = Instance.new("WeldConstraint")
        weld.Name = "Fixed"
        weld.Part0 = targetPart
        weld.Part1 = sourcePart
        weld.Parent = folder
        if spec.kind=="Bolt" and spec.secondTargetId then
            local other=self.D.findOwned(player,spec.secondTargetId)
            if not other or not other.PrimaryPart or other==target or other==source
                or not BoltMath.Fits(source,other) then
                folder:Destroy()
                return false,"The bolt does not reach the second opening"
            end
            local secondary=Instance.new("WeldConstraint")
            secondary.Name="BoltedSecondBody"
            secondary.Part0=sourcePart
            secondary.Part1=other.PrimaryPart
            secondary.Parent=folder
        end
    elseif spec.kind=="Spring" then
        local mode,why=SpringMath.Validate(source,target)
        if not mode then
            folder:Destroy()
            return false,why or "Spring endpoints are unavailable"
        end
        -- All restored spring relationships use the general free model.
        folder:SetAttribute("SpringMode",mode)
        local world0,world1=SpringMath.Frames(source,target,mode)
        local att0=Instance.new("Attachment")
        att0.Name="SpringFixedEnd"
        att0.CFrame=targetPart.CFrame:ToObjectSpace(CFrame.new(world0))
        att0.Parent=targetPart
        local att1=Instance.new("Attachment")
        att1.Name="SpringMovingEnd"
        att1.CFrame=sourcePart.CFrame:ToObjectSpace(CFrame.new(world1))
        att1.Parent=sourcePart
        for _,a in ipairs({att0,att1}) do
            local ref=Instance.new("ObjectValue")
            ref.Name="ManagedAttachment"
            ref.Value=a
            ref.Parent=folder
        end
        local spring=Instance.new("SpringConstraint")
        spring.Name="Spring"
        spring.Attachment0=att0
        spring.Attachment1=att1
        spring.Stiffness=spec.stiffness or 120
        spring.Damping=spec.damping or 14
        spring.FreeLength=spec.freeLength or (world1-world0).Magnitude
        spring.MaxForce=40000
        spring.LimitsEnabled=true
        spring.MinLength=0.01
        spring.MaxLength=math.max(spring.FreeLength*1.8,0.25)
        spring.Visible=true
        spring.Color=BrickColor.new("Bright orange")
        spring.Coils=8
        spring.Radius=SpringMath.Radius(source,target,mode)
        spring.Thickness=math.clamp(spring.Radius*0.085,0.012,0.065)
        spring.Parent=folder
        -- No special-case auto guide. Slider or Cylindrical relationships
        -- are independently authored if linear motion needs guidance.
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
        constraint.Enabled=true
        -- Relationships permit motion; they do not create motive power.
        -- Future actuator components will be authored separately.
        constraint.ActuatorType=Enum.ActuatorType.None
        -- A slider/cylinder ALWAYS has hard mechanical travel stops.
        -- User limits can narrow them but can never permit the shaft
        -- to slide entirely clear of its real opening.
        local linear=constraint:IsA("PrismaticConstraint")
            or constraint:IsA("CylindricalConstraint")
        local low,high
        if linear then
            low,high=Alignment.OffsetBounds(source,target)
            if not low or high-low<0.5 then
                folder:Destroy()
                return false,"Shaft is too short for a sliding relationship"
            end
            local at=source:GetAttribute("AlignedOffsetU") or 0
            low-=at
            high-=at
            if type(spec.fitTravelU)=="number" then
                low=math.max(low,-spec.fitTravelU)
                high=math.min(high,spec.fitTravelU)
            end
            if low>=high then
                folder:Destroy()
                return false,"Multiple guides leave no safe linear travel"
            end
        end
        constraint.LimitsEnabled=linear or spec.limitsEnabled==true
        if constraint.LimitsEnabled then
            if constraint:IsA("HingeConstraint") then
                constraint.LowerAngle = spec.lowerLimit or -180
                constraint.UpperAngle = spec.upperLimit or 180
            else
                constraint.LowerLimit = math.max(low or -4,
                    spec.lowerLimit or (low or -4))*self.D.Grid.Unit
                constraint.UpperLimit = math.min(high or 4,
                    spec.upperLimit or (high or 4))*self.D.Grid.Unit
            end
        end
        constraint.Parent = folder
    end
    folder.Parent = self.Folder
    return true, folder
end

function Mechanical:Create(player, request)
    local d = self.D
    -- New spring/bolt/weld mechanisms require their own geometry validation.
    -- Prevent the older generic route from bypassing prefab/plate rules.
    if type(request)~="table" or
        (request.kind~="Bearing" and request.kind~="Slider"
            and request.kind~="Cylindrical") then
        return false,
            "Use dedicated spring, bolt, weld or gear connection controls"
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
        return false, "Choose two different mechanical endpoints"
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
            targetState.shaftRollDegrees = if item.model == source
                then request.rollDegrees or 0 else old.shaftRollDegrees
            targetState.alignedOffsetU = if item.model == source
                then request.offsetUnits else old.alignedOffsetU
            targetState.alignedOpeningId = if item.model == source
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
        local fits,why=Bore.ShaftFits(source,target)
        if not fits then
            for index,old in ipairs(before) do d.applyState(members[index],old) end
            return false,why or "Shaft does not fit its housing"
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

-- ONE server-verified drag release replaces manual housing->shaft/gear
-- selection. The whole operation (move/create + relationship) has ONE
-- assembly undo entry. newSource is set ONLY by trusted ConstructionService,
-- never from the client request.
-- One authoritative drag-release transaction. Ordinary hole/shaft snapping
-- merges the two rigid bodies; intentionally chosen motion joints keep bodies
-- independent. Undo/redo restores both the pose AND component membership.
function Mechanical:SmartMate(player, request, newSource)
    local d=self.D
    if type(request)~="table" or type(request.sourceId)~="string"
        or type(request.targetId)~="string" then
        return false,"Missing attachment endpoints"
    end
    local source=d.findOwned(player,request.sourceId)
    local target=d.findOwned(player,request.targetId)
    if not source or not target or source==target then
        return false,"Choose two different constructions you own"
    end
    if not d.nearPlayer(player,source:GetPivot().Position)
        or not d.nearPlayer(player,target:GetPivot().Position) then
        return false,"Attachment is outside construction range"
    end

    local mode=request.mateKind
    if mode=="Hub" and request.relationKind~="Rotation"
        and request.relationKind~="Rigid" then
        return false,"Choose Rotation or Rigid for a gear/shaft mount"
    end
    if mode=="Surface" then
        return false,"Touching parts are never welded automatically. Use Weld."
    end
    if mode~="Bore" and mode~="Gear"
        and mode~="Hub" and mode~="Surface" then
        return false,"Unsupported attachment"
    end
    local reverse=mode=="Bore" and request.reverse==true
    local shaft=if mode=="Hub" then
        (if Alignment.IsShaft(source) then source else target)
        else (if reverse then target else source)
    local opening=if mode=="Hub" then
        (if source:GetAttribute("GearTeeth") then source else target)
        else (if reverse then source else target)
    local typeName=if mode=="Bore" then (request.relationKind or "Cylindrical")
        elseif mode=="Gear" then "Gear"
        elseif mode=="Hub" then
            (if request.relationKind=="Rotation" then "Bearing" else "Weld")
        else "Fixed"
    -- Gear/shaft mounts become explicit Hinge or Weld physics links,
    -- never a component grouping or an implicit fixed connection.
    if mode=="Bore" and typeName~="Bearing"
        and typeName~="Slider" and typeName~="Cylindrical"
        and typeName~="FreeFit" then
        return false,"Choose Rotate + Slide, Slide, Rotate or Fit Only"
    end
    if typeName~="FreeFit"
        and self:Count(player)>=MAX_RELATIONSHIPS_PER_PLAYER then
        return false,"Relationship limit reached"
    end

    local movingComponent=source:GetAttribute("ComponentId")
    local targetComponent=target:GetAttribute("ComponentId")
    if movingComponent and movingComponent==targetComponent then
        return false,"The parts are already in the same rigid component"
    end
    local members=if movingComponent
        then d.components:Members(player,movingComponent) else {source}
    if #members==0 or #members>128 then
        return false,"Moving construction is unavailable"
    end
    local excluded={}
    for _,member in ipairs(members) do
        if member==target then return false,"Cannot mate a component to itself" end
        excluded[member]=true
    end
    local before, planned = {}, {}
    for _,member in ipairs(members) do
        if not newSource then table.insert(before,d.snapshot(member)) end
    end
    local offset,roll=0,0
    local delta
    if mode=="Bore" then
        if not Alignment.IsShaft(shaft) or not Alignment.TargetAxis(opening) then
            return false,"A Cylinder shaft and real opening are required"
        end
        offset=request.offsetUnits
        roll=request.rollDegrees or 0
        if not Alignment.IsOffsetValid(offset)
            or type(roll)~="number" or roll~=roll
            or math.abs(roll)>360 then
            return false,"Invalid shaft insertion or roll"
        end
        local plan,reason
        -- The client supplies the exact preview pose of the selected moving
        -- primitive. Reconstruct its entire component transform, rather than
        -- re-solving roll from a different visual starting orientation.
        -- This is NOT trusted: all bounds, every hole and unrelated solid
        -- collision are independently verified immediately below.
        if typeof(request.position)=="Vector3"
            and typeof(request.orientation)=="CFrame"
            and d.Grid.ValidPosition(request.position) then
            local desired=CFrame.new(request.position)
                *request.orientation.Rotation
            local movement=desired*source:GetPivot():Inverse()
            if movingComponent and typeof(request.groupPivot)=="CFrame" then
                local groupPivot=request.groupPivot
                if not d.Grid.ValidPosition(groupPivot.Position) then
                    return false,"Component snap pivot is outside build range"
                end
                local anchor=ComponentGeometry.CentralPrimitive(members)
                local groupMove=groupPivot*anchor:GetPivot():Inverse()
                local aligned=groupMove*source:GetPivot()
                if (aligned.Position-desired.Position).Magnitude>0.04
                    or aligned.RightVector:Dot(desired.RightVector)<0.999
                    or aligned.UpVector:Dot(desired.UpVector)<0.999 then
                    return false,"Group snap and selected hole disagree; rescan alignment"
                end
                movement=groupMove
            end
            plan={items={}}
            for _,member in ipairs(members) do
                local world=movement*member:GetPivot()
                table.insert(plan.items,{
                    model=member,position=world.Position,
                    orientation=world.Rotation,
                    steps=Alignment.MatchSteps(world.Rotation) or {
                        x=member:GetAttribute("RotX") or 0,
                        y=member:GetAttribute("RotY") or 0,
                        z=member:GetAttribute("RotZ") or 0,
                    },
                })
            end
        elseif reverse then
            plan,reason=Alignment.ReversePlan(
                members,opening,shaft,offset,roll
            )
        else
            plan,reason=Alignment.Plan(
                members,shaft,opening,offset,roll
            )
        end
        if not plan then
            return false,reason or "Could not align the components"
        end
        for _,item in ipairs(plan.items) do
            local old=d.snapshot(item.model)
            local state=table.clone(old)
            state.position=item.position
            state.steps=item.steps
            state.orientation=item.orientation
            state.assemblyPrecision=true
            state.freePosition=true
            if item.model==shaft then
                state.alignedOpeningId=opening:GetAttribute("InstanceId")
                state.alignedOffsetU=offset
                state.shaftRollDegrees=roll
            end
            table.insert(planned,state)
        end
    elseif mode=="Gear" or mode=="Hub" then
        if typeof(request.approach)~="Vector3"
            or not d.Grid.ValidPosition(request.approach) then
            return false,"Move closer to the compatible gear/shaft"
        end
        local pose,why
        if mode=="Gear" then
            pose,why=Smart.GearPose(source,target,request.approach)
        else
            pose,why=Smart.HubPose(source,target,request.approach)
        end
        if not pose then return false,why or "No compatible attachment" end
        delta=pose*source:GetPivot():Inverse()
    else
        if typeof(request.position)~="Vector3"
            or not d.Grid.ValidPosition(request.position) then
            return false,"Invalid surface position"
        end
        local threshold=source.PrimaryPart.Size.Magnitude
            +target.PrimaryPart.Size.Magnitude+0.35
        if (request.position-target:GetPivot().Position).Magnitude>threshold then
            return false,"Place faces against each other to attach"
        end
        delta=if typeof(request.orientation)=="CFrame"
            then (CFrame.new(request.position)*request.orientation.Rotation)
                *source:GetPivot():Inverse()
            else CFrame.new(request.position-source:GetPivot().Position)
    end

    if mode~="Bore" then
        for _,member in ipairs(members) do
            local state=table.clone(d.snapshot(member))
            local cf=delta*member:GetPivot()
            state.position=cf.Position
            state.orientation=cf.Rotation
            state.freePosition=true
            table.insert(planned,state)
        end
    end

    for _,state in ipairs(planned) do
        local entry=d.Registry.Get(state.templateId)
        if not entry then return false,"Missing primitive template" end
        local valid,why=d.validState(player,entry,state)
        if not valid then return false,why end
    end

    local existing
    for _,rel in ipairs(self.Folder:GetChildren()) do
        if rel:GetAttribute("OwnerUserId")==player.UserId
            and ((rel:GetAttribute("SourceId")==request.sourceId
                and rel:GetAttribute("TargetId")==request.targetId)
                or (rel:GetAttribute("SourceId")==request.targetId
                and rel:GetAttribute("TargetId")==request.sourceId)) then
            existing=rel
            break
        end
    end
    -- Existing fits are reconciled after ALL guide points are matched.
    -- In particular an old 1-joint/4-hole construction may gain its
    -- three missing physical joints without duplicating the first.

    local function restoreMoving()
        if not newSource then
            for i,member in ipairs(members) do
                d.applyState(member,before[i])
            end
        end
    end

    for i,member in ipairs(members) do
        d.applyState(member,planned[i])
    end
    if mode=="Bore" then
        local fits,why=Bore.ShaftFits(shaft,opening)
        if not fits then restoreMoving() return false,why end
    elseif mode=="Gear" then
        local fits,why=GearMath.Meshable(source,target)
        if not fits then restoreMoving() return false,why end
    elseif mode=="Hub" then
        local fits,why=Smart.HubFits(source,target)
        if not fits then restoreMoving() return false,why end
    else
        -- An untrusted client may not send arbitrary target IDs to create
        -- a Fixed connection between distant and unrelated pieces.
        local params=OverlapParams.new()
        params.FilterType=Enum.RaycastFilterType.Include
        params.FilterDescendantsInstances={target}
        local touching=false
        for _,member in ipairs(members) do
            for _,part in ipairs(member:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    local probe=part:Clone()
                    probe.Size=part.Size+Vector3.one*0.055
                    probe.Transparency=1
                    probe.CanCollide=false
                    probe.CanTouch=false
                    probe.CanQuery=true
                    probe.Anchored=true
                    probe.Parent=workspace
                    local ok,hits=pcall(function()
                        return workspace:GetPartsInPart(probe,params)
                    end)
                    probe:Destroy()
                    if ok and #hits>0 then touching=true break end
                end
            end
            if touching then break end
        end
        if not touching then
            restoreMoving()
            return false,"Attach by contacting an actual target face"
        end
    end

    local fitPairs=nil
    local fitMap=nil
    if mode=="Bore" then
        local all={}
        for _,candidate in ipairs(d.folder:GetChildren()) do
            if candidate:IsA("Model")
                and candidate:GetAttribute("OwnerUserId")==player.UserId then
                table.insert(all,candidate)
            end
        end
        local reason
        local stationary=MultiFit.Scope(target,all)
        local candidates
        candidates,reason=MultiFit.Find(members,stationary,nil,excluded)
        if not candidates then
            restoreMoving()
            return false,reason or "Multi-point fitting failed"
        end
        fitPairs=MultiFit.Unique(candidates,request.sourceId,request.targetId)
        local complete,why=MultiFit.Completeness(
            members,stationary,fitPairs,reverse)
        if not complete then
            restoreMoving()
            return false,why
        end
        local primary
        for _,pair in ipairs(fitPairs) do
            if pair.movingId==request.sourceId
                and pair.stationaryId==request.targetId then
                primary=pair break
            end
        end
        if not primary then
            restoreMoving()
            return false,"Primary shaft/hole fit is no longer aligned"
        end
        if math.abs(primary.depthU-offset)>0.04 then
            restoreMoving()
            return false,"Fitted depth does not match the selected insertion"
        end
        if request.fitTargets~=nil then
            if type(request.fitTargets)~="table"
                or #request.fitTargets>MultiFit.MaxPairs then
                restoreMoving()
                return false,"Invalid multi-point fit selection"
            end
            local confirmed={}
            for _,pair in ipairs(fitPairs) do
                confirmed[pair.stationaryId]=true
            end
            for _,id in ipairs(request.fitTargets) do
                if type(id)~="string" or #id>64 or not confirmed[id] then
                    restoreMoving()
                    return false,"One or more guide holes shifted; realign the plate"
                end
            end
        end
        fitMap=MultiFit.AllowMap(fitPairs)
    end

    for _,member in ipairs(members) do
        if d.intersectsConstructed(member,excluded,
            if mode=="Bore" and not reverse then opening else nil,
            if mode=="Bore" and not reverse then shaft:GetAttribute("InstanceId")
                else nil,
            fitMap) then
            restoreMoving()
            return false,"Attachment intersects another solid"
        end
    end

    -- The fixed shaft in reverse alignment stays at its exact authored pose,
    -- but its alignment metadata still belongs to the same undo operation.
    local fixedShaftBefore
    if reverse then
        fixedShaftBefore=d.snapshot(shaft)
        shaft:SetAttribute("AlignedOpeningId",opening:GetAttribute("InstanceId"))
        shaft:SetAttribute("AlignedOffsetU",offset)
        shaft:SetAttribute("ShaftRollDegrees",roll)
    end

    if reverse then table.insert(before,fixedShaftBefore) end
    local fitted={}
    for _,pair in ipairs(fitPairs or {}) do
        table.insert(fitted,{
            movingId=pair.movingId,
            stationaryId=pair.stationaryId,
        })
    end
    local fittedTravel=if fitPairs and #fitPairs>1
        then MultiFit.SymmetricTravel(fitPairs) else nil
    if (typeName=="Slider" or typeName=="Cylindrical")
        and fittedTravel and fittedTravel<0.25 then
        if reverse then d.applyState(shaft,fixedShaftBefore) end
        restoreMoving()
        return false,"The fitted rods leave no sliding travel; change insertion depth"
    end
    if typeName=="FreeFit" then
        local after={}
        for _,member in ipairs(members) do
            table.insert(after,d.snapshot(member))
        end
        if reverse then table.insert(after,d.snapshot(shaft)) end
        d.commitBatch(player,before,after)
        return true,string.format("%d aligned hole/shaft fits • no joint or weld",
            #fitted)
    end
    local createdSpecs={}
    local desiredSpecs={}
    local fitSetId=if mode=="Bore" and #fitPairs>1
        then HttpService:GenerateGUID(false) else nil
    if mode=="Bore" then
        -- Every independently fitted hole/shaft pair gets its OWN real
        -- native relationship. One master slider with cosmetic dots made
        -- the other three guide rods ineffective in simulation.
        for index,pair in ipairs(fitPairs) do
            local candidateSpec={
                relationId=HttpService:GenerateGUID(false),
                ownerUserId=player.UserId,
                kind=typeName,
                sourceId=pair.shaft:GetAttribute("InstanceId"),
                targetId=pair.hole:GetAttribute("InstanceId"),
                componentId=pair.shaft:GetAttribute("ComponentId"),
                offsetUnits=pair.depthU,
                rollDegrees=roll,
                fitPointsJSON=HttpService:JSONEncode({{
                    movingId=pair.movingId,
                    stationaryId=pair.stationaryId,
                }}),
                fitPointCount=1,
                fitTravelU=fittedTravel,
                fitSetId=fitSetId,
                fitSetIndex=index,
                fitSetCount=#fitPairs,
            }
            table.insert(desiredSpecs,candidateSpec)
        end
    else
        table.insert(desiredSpecs,{
            relationId=HttpService:GenerateGUID(false),
            ownerUserId=player.UserId,
            kind=typeName,
            sourceId=if mode=="Hub"
                then shaft:GetAttribute("InstanceId") else request.sourceId,
            targetId=if mode=="Hub"
                then opening:GetAttribute("InstanceId") else request.targetId,
            componentId=if mode=="Hub" then shaft:GetAttribute("ComponentId")
                else movingComponent,
            offsetUnits=offset,
            rollDegrees=roll,
            gearRatio=if mode=="Gear"
                then -(source:GetAttribute("GearTeeth")
                    /target:GetAttribute("GearTeeth")) else nil,
        })
    end

    local existingByPair={}
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId then
            local a=relation:GetAttribute("SourceId")
            local b=relation:GetAttribute("TargetId")
            existingByPair[tostring(a)..":"..tostring(b)]=relation
            existingByPair[tostring(b)..":"..tostring(a)]=relation
        end
    end
    local need={}
    local reused={}
    for _,candidate in ipairs(desiredSpecs) do
        local key=candidate.sourceId..":"..candidate.targetId
        local prior=existingByPair[key]
        if prior then
            if prior:GetAttribute("Kind")~=typeName then
                if reverse then d.applyState(shaft,fixedShaftBefore) end
                restoreMoving()
                return false,"An existing relationship has a different motion type"
            end
            table.insert(reused,{relation=prior,spec=candidate})
        else
            table.insert(need,candidate)
        end
    end
    if self:Count(player)+#need>MAX_RELATIONSHIPS_PER_PLAYER then
        if reverse then d.applyState(shaft,fixedShaftBefore) end
        restoreMoving()
        return false,"Not enough relationship slots for all fitted rods"
    end
    for _,candidate in ipairs(need) do
        local made,why=self:Restore(player,candidate)
        if not made then
            for _,created in ipairs(createdSpecs) do
                local relation=self:OwnedRelation(player,created.relationId)
                if relation then self:DestroyRelation(relation) end
            end
            if reverse then d.applyState(shaft,fixedShaftBefore) end
            restoreMoving()
            return false,why
        end
        table.insert(createdSpecs,candidate)
    end
    -- Upgrade old single-joint multi-fits in place, but record their old
    -- metadata so undo restores the original authored single-joint state.
    local relationEdits={}
    for _,item in ipairs(reused) do
        local old=self:Snapshot(item.relation)
        local candidate=item.spec
        item.relation:SetAttribute("OffsetUnits",candidate.offsetUnits)
        item.relation:SetAttribute("FitPointsJSON",candidate.fitPointsJSON)
        item.relation:SetAttribute("FitPointCount",candidate.fitPointCount)
        item.relation:SetAttribute("FitTravelU",candidate.fitTravelU)
        item.relation:SetAttribute("FitSetId",candidate.fitSetId)
        item.relation:SetAttribute("FitSetIndex",candidate.fitSetIndex)
        item.relation:SetAttribute("FitSetCount",candidate.fitSetCount)
        table.insert(relationEdits,{
            before=old,after=self:Snapshot(item.relation),
        })
    end
    local after={}
    for _,member in ipairs(members) do table.insert(after,d.snapshot(member)) end
    if reverse then table.insert(after,d.snapshot(shaft)) end
    if #createdSpecs==0 and #relationEdits==0 then
        d.commitBatch(player,before,after)
        return true,string.format("%d existing %s connections repositioned",
            #desiredSpecs,typeName)
    end
    -- One authored operation, one undo/redo entry, all joints or none.
    d.commitAssembly(player,before,after,createdSpecs,false,relationEdits)
    return true,if mode=="Bore" then
        string.format("%d individual %s relationships connected (one per rod/hole)",
            #desiredSpecs,typeName)
        elseif mode=="Hub" then
            (if typeName=="Bearing" then "Gear mounted • rotation only"
                else "Gear mounted • rigidly welded to shaft")
        else typeName.." connected"
end

local function sameBody(left,right)
    local id=left:GetAttribute("ComponentId")
    return type(id)=="string" and id~=""
        and id==right:GetAttribute("ComponentId")
end

local function validEndpoints(self,player,request)
    local d=self.D
    local source=d.findOwned(player,request.sourceId)
    local target=d.findOwned(player,request.targetId)
    if not source or not target or source==target then
        return nil,nil,"Select two different parts you own"
    end
    -- Component grouping is not physical welding; individually grouped
    -- primitives may still need an explicitly authored weld or spring.
    if not d.nearPlayer(player,source:GetPivot().Position)
        or not d.nearPlayer(player,target:GetPivot().Position) then
        return nil,nil,"Both parts must be within construction range"
    end
    if self:Count(player)>=MAX_RELATIONSHIPS_PER_PLAYER then
        return nil,nil,"Relationship limit reached"
    end
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId
            and ((relation:GetAttribute("SourceId")==request.sourceId
                and relation:GetAttribute("TargetId")==request.targetId)
                or (relation:GetAttribute("SourceId")==request.targetId
                and relation:GetAttribute("TargetId")==request.sourceId))
            and relation:GetAttribute("Kind")==request.kind then
            return nil,nil,"These parts already have this connection"
        end
    end
    return source,target
end

function Mechanical:CreateSpring(player,request)
    if type(request)~="table" then return false,"Invalid spring request" end
    request.kind="Spring"
    local source,target,reason=validEndpoints(self,player,request)
    if not source then return false,reason end
    local mode,why=SpringMath.Validate(source,target)
    if not mode then return false,why end
    local point0,point1=SpringMath.Frames(source,target,mode)
    local settings,problem=SpringMath.Settings(
        request,(point1-point0).Magnitude
    )
    if not settings then return false,problem end
    local spec={
        relationId=HttpService:GenerateGUID(false),
        ownerUserId=player.UserId,kind="Spring",
        sourceId=request.sourceId,targetId=request.targetId,
        componentId=source:GetAttribute("ComponentId"),
        springMode=mode,stiffness=settings.stiffness,
        damping=settings.damping,freeLength=settings.freeLength,
    }
    local created,err=self:Restore(player,spec)
    if not created then return false,err end
    self.D.commitAssembly(player,{}, {},spec)
    return true,"Spring connected between both components (no automatic travel guide)"
end

function Mechanical:TuneSpring(player,request)
    local relation=self:OwnedRelation(player,request.relationId)
    if not relation or relation:GetAttribute("Kind")~="Spring" then
        return false,"Choose a spring in Simulate Properties"
    end
    local stiffness=request.stiffness
    local damping=request.damping
    local freeLength=if type(request.freeLength)=="number"
        then request.freeLength
        else relation:GetAttribute("FreeLength") or 0.5
    if type(stiffness)~="number" or stiffness~=stiffness
        or stiffness<10 or stiffness>3000
        or type(damping)~="number" or damping~=damping
        or damping<0 or damping>300
        or type(freeLength)~="number" or freeLength~=freeLength
        or freeLength<0.05 or freeLength>self.D.Grid.MaxDistance*2 then
        return false,"Spring stiffness 10–3000 / damping 0–300 / rest length within construction range"
    end
    local before=self:Snapshot(relation)
    relation:SetAttribute("Stiffness",stiffness)
    relation:SetAttribute("Damping",damping)
    relation:SetAttribute("FreeLength",freeLength)
    local spring=relation:FindFirstChildOfClass("SpringConstraint")
    if spring then
        spring.Stiffness=stiffness
        spring.Damping=damping
        spring.FreeLength=freeLength
        spring.MaxLength=math.max(freeLength*1.8,0.25)
    end
    self.D.commitJointEdit(player,before,self:Snapshot(relation))
    return true,string.format("Spring %.0f stiffness / %.0f damping / %.2f U rest",
        stiffness,damping,freeLength/self.D.Grid.Unit)
end

-- A user-authorized end-to-end coupling is a REAL rigid Weld relationship.
-- Neither ComponentId nor a shaft-bearing joint supplies this connection.
function Mechanical:CoupleHandCrank(player,request,newSource)
    if type(request)~="table" then return false,"Invalid hand-crank coupling" end
    local d=self.D
    local source=d.findOwned(player,request.sourceId)
    local target=d.findOwned(player,request.targetId)
    if not source or not target or source==target
        or not HandCrankMath.IsCrank(source)
        or not HandCrankMath.IsOutputShaft(target) then
        return false,"Choose a HandCrank output and a separate cylinder shaft"
    end
    if not d.nearPlayer(player,source:GetPivot().Position)
        or not d.nearPlayer(player,target:GetPivot().Position) then
        return false,"Both parts must be in building range"
    end
    if self:Count(player)>=MAX_RELATIONSHIPS_PER_PLAYER then
        return false,"Mechanical relationship limit reached"
    end
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId
            and (relation:GetAttribute("Kind")=="Weld"
                or relation:GetAttribute("Kind")=="Fixed")
            and ((relation:GetAttribute("SourceId")==request.sourceId
                and relation:GetAttribute("TargetId")==request.targetId)
                or (relation:GetAttribute("SourceId")==request.targetId
                    and relation:GetAttribute("TargetId")==request.sourceId)) then
            return false,"Crank output is already coupled to this shaft"
        end
    end

    local before,after={},{}
    local members={source}
    local changed=false
    if not newSource and typeof(request.position)=="Vector3"
        and typeof(request.orientation)=="CFrame" then
        -- Edit-mode SmartDrop sends the exact snapped preview pose.
        -- Move the crank's ENTIRE editor component with the same delta,
        -- never just its axle inside an existing grouped assembly.
        local group=source:GetAttribute("ComponentId")
        if type(group)=="string" and group~="" then
            members=d.components:Members(player,group)
        end
        local desired=CFrame.new(request.position)*request.orientation.Rotation
        local delta=desired*source:GetPivot():Inverse()
        local excluding={}
        for _,member in ipairs(members) do excluding[member]=true end
        local plans={}
        for _,member in ipairs(members) do
            local old=d.snapshot(member)
            local state=table.clone(old)
            local pose=delta*member:GetPivot()
            state.position=pose.Position
            state.orientation=pose.Rotation
            state.freePosition=true
            state.assemblyPrecision=true
            local entry=d.Registry.Get(state.templateId)
            if not entry then return false,"Crank part template unavailable" end
            local valid,why=d.validState(player,entry,state)
            if not valid then return false,why end
            table.insert(plans,state)
            table.insert(before,old)
        end
        for i,member in ipairs(members) do
            d.applyState(member,plans[i])
        end
        changed=true
        local function rollback()
            for i,member in ipairs(members) do
                d.applyState(member,before[i])
            end
        end
        for _,member in ipairs(members) do
            if d.intersectsConstructed(member,excluding) then
                rollback()
                return false,"Crank/group intersects another construction"
            end
        end
        local fits,why=HandCrankMath.Fits(source,target)
        if not fits then rollback() return false,why end
    else
        local fits,why=HandCrankMath.Fits(source,target)
        if not fits then return false,why end
        if newSource and d.intersectsConstructed(source,{[source]=true}) then
            return false,"Hand crank intersects another built part"
        end
    end

    local spec={
        relationId=HttpService:GenerateGUID(false),
        ownerUserId=player.UserId,kind="Weld",
        sourceId=request.sourceId,targetId=request.targetId,
        componentId=source:GetAttribute("ComponentId"),
    }
    local ok,reason=self:Restore(player,spec)
    if not ok then
        if changed then
            for i,member in ipairs(members) do
                d.applyState(member,before[i])
            end
        end
        return false,reason
    end
    if newSource then
        d.commitAssembly(player,{}, {d.snapshot(source)},spec)
    else
        if changed then
            for _,member in ipairs(members) do
                table.insert(after,d.snapshot(member))
            end
        end
        d.commitAssembly(player,before,after,spec)
    end
    return true,"Hand crank physically coupled to shaft end • manual torque enabled"
end

function Mechanical:CreateWeld(player,request)
    request.kind="Weld"
    local source,target,reason=validEndpoints(self,player,request)
    if not source then return false,reason end
    -- The parts must be in REAL contact; being nearby is insufficient.
    local close=false
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Include
    overlap.FilterDescendantsInstances={target}
    for _,part in ipairs(source:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            local probe=part:Clone()
            probe.Size=part.Size+Vector3.one*0.065
            probe.Anchored=true
            probe.CanCollide=false
            probe.CanQuery=true
            probe.Parent=workspace
            local ok,hit=pcall(function()
                return workspace:GetPartsInPart(probe,overlap)
            end)
            probe:Destroy()
            if ok and #hit>0 then close=true break end
        end
    end
    if not close then return false,"Weld requires touching solid surfaces" end
    local spec={
        relationId=HttpService:GenerateGUID(false),
        ownerUserId=player.UserId,kind="Weld",
        sourceId=request.sourceId,targetId=request.targetId,
        componentId=source:GetAttribute("ComponentId"),
    }
    local ok,err=self:Restore(player,spec)
    if not ok then return false,err end
    self.D.commitAssembly(player,{}, {},spec)
    return true,"Welded • permanent rigid connection"
end

function Mechanical:CreateBolt(player,request)
    request.kind="Bolt"
    local first,second,why=validEndpoints(self,player,request)
    if not first then return false,why end
    local axis0=Alignment.TargetAxis(first)
    local axis1=Alignment.TargetAxis(second)
    if not axis0 or not axis1 then
        return false,"Bolts require two drilled or hollow openings"
    end
    local cf0,cf1=first:GetPivot(),second:GetPivot()
    local direction=cf0:VectorToWorldSpace(axis0).Unit
    local opposite=cf1:VectorToWorldSpace(axis1).Unit
    if math.abs(direction:Dot(opposite))<0.999 then
        return false,"Bolt holes must share a parallel axis"
    end
    local delta=cf1.Position-cf0.Position
    local distance=delta:Dot(direction)
    local transverse=(delta-direction*distance).Magnitude
    if transverse>self.D.Grid.Unit*0.12 then
        return false,"Bolt holes must be directly coaxial"
    end
    if math.abs(distance)<self.D.Grid.Unit*0.1 then
        return false,"Bolt connection requires distinct physical hole positions"
    end
    if distance<0 then direction=-direction end
    local hole0=Bore.OpeningDiameter(first)
    local hole1=Bore.OpeningDiameter(second)
    if not hole0 or not hole1 then
        return false,"Hole geometry has no measurable bolt clearance"
    end
    local bestId,bestDiameter,bestLen
    for _,entry in ipairs({
        {id="Bolt_050U",u=0.5,length=4},
        {id="Bolt_100U",u=1,length=8},
        {id="Bolt_150U",u=1.5,length=12},
    }) do
        local diameter=entry.u*self.D.Grid.Unit
        local length=entry.length*self.D.Grid.Unit
        if diameter<=math.min(hole0,hole1)-0.002
            and length>=math.abs(distance)
                +(math.abs(axis0.X)*first.PrimaryPart.Size.X
                    +math.abs(axis0.Y)*first.PrimaryPart.Size.Y
                    +math.abs(axis0.Z)*first.PrimaryPart.Size.Z)*0.5
                +(math.abs(axis1.X)*second.PrimaryPart.Size.X
                    +math.abs(axis1.Y)*second.PrimaryPart.Size.Y
                    +math.abs(axis1.Z)*second.PrimaryPart.Size.Z)*0.5
                +self.D.Grid.Unit*0.1
            and (not bestDiameter or diameter>bestDiameter) then
            bestId=entry.id
            bestDiameter=diameter
            bestLen=length
        end
    end
    if not bestId then
        return false,"No bolt prefab fits both hole diameters and reach"
    end
    local bolt,problem=self.D.createFromTemplate(player,bestId)
    if not bolt then return false,problem end
    local before={}
    local group=first:GetAttribute("ComponentId")
    if type(group)~="string" or group=="" then
        group=HttpService:GenerateGUID(false)
        table.insert(before,self.D.snapshot(first))
        first:SetAttribute("ComponentId",group)
        first:SetAttribute("ComponentAnchorId",first:GetAttribute("InstanceId"))
    end
    local origin=cf0.Position+direction*math.abs(distance)*0.5
    local reference=if math.abs(direction:Dot(Vector3.yAxis))<0.9
        then Vector3.yAxis else Vector3.zAxis
    local up=(reference-direction*direction:Dot(reference)).Unit
    local pose=CFrame.fromMatrix(origin,direction,up,direction:Cross(up))
    local template=self.D.Registry.Get(bestId)
    local size=template.Model.PrimaryPart.Size
    local state={
        position=pose.Position,orientation=pose.Rotation,
        steps=Alignment.MatchSteps(pose.Rotation) or {x=0,y=0,z=0},
        size=size,
        componentId=group,
        componentAnchorId=first:GetAttribute("ComponentAnchorId")
            or first:GetAttribute("InstanceId"),
        assemblyId=first:GetAttribute("AssemblyId"),
        assemblyName=first:GetAttribute("AssemblyName"),
        freePosition=true,
    }
    self.D.applyState(bolt,state)
    local ignored={[first]=true,[second]=true}
    if self.D.intersectsConstructed(bolt,ignored) then
        bolt:Destroy()
        if #before>0 then self.D.applyState(first,before[1]) end
        return false,"Bolt interferes with another construction"
    end
    bolt.Parent=self.D.folder
    -- Fastener body is a rigid member of the first (bolt-head) side.
    local spec={
        relationId=HttpService:GenerateGUID(false),
        ownerUserId=player.UserId,kind="Bolt",
        sourceId=request.sourceId,targetId=request.targetId,
        componentId=group,boltId=bolt:GetAttribute("InstanceId"),
    }
    local success,err=self:Restore(player,spec)
    if not success then
        bolt:Destroy()
        if #before>0 then self.D.applyState(first,before[1]) end
        return false,err
    end
    local after={self.D.snapshot(bolt)}
    for _,original in ipairs(before) do
        table.insert(after,self.D.snapshot(first))
    end
    self.D.commitAssembly(player,before,after,spec)
    return true,"Physical "..bestId.." placed • bolted rigid connection"
end

-- A prefab-based bolt: fit the dragged bolt THROUGH one or two aligned
-- holes. Make exactly one atomic relationship and weld the physical bolt
-- to each penetrated body. An unfastened editor grouping is not a weld.
function Mechanical:FastenBolt(player,request,newSource)
    local d=self.D
    local bolt=d.findOwned(player,request.boltId)
    local target=d.findOwned(player,request.targetId)
    if not BoltMath.IsBolt(bolt) or not target or bolt==target then
        return false,"Drag a Bolt prefab into a drilled opening"
    end
    if not d.nearPlayer(player,target:GetPivot().Position)
        or not d.nearPlayer(player,bolt:GetPivot().Position) then
        return false,"Bolt is outside your construction range"
    end
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("BoltId")==request.boltId then
            return false,"Remove the existing bolt connection before relocating it"
        end
    end
    local before=if newSource then {} else {d.snapshot(bolt)}
    local old=d.snapshot(bolt)
    -- Bolts added to an already-registered assembly participate in its
    -- simulation scope without changing editable component identities.
    local assemblyId=target:GetAttribute("AssemblyId")
    local assemblyName=target:GetAttribute("AssemblyName")
    if not newSource then
        if typeof(request.position)~="Vector3"
            or typeof(request.orientation)~="CFrame" then
            return false,"Invalid bolt transform"
        end
        local state=table.clone(old)
        state.position=request.position
        state.orientation=request.orientation
        state.freePosition=true
        local entry=d.Registry.Get(state.templateId)
        if not entry then return false,"Bolt prefab template unavailable" end
        local valid,why=d.validState(player,entry,state)
        if not valid then return false,why end
        d.applyState(bolt,state)
    end
    local function rollback(reason)
        if not newSource then d.applyState(bolt,old) end
        return false,reason
    end
    if not BoltMath.Fits(bolt,target) then
        return rollback("Bolt must pass completely through the selected hole")
    end
    local holes={}
    for _,model in ipairs(d.folder:GetChildren()) do
        if model:IsA("Model") and model~=bolt
            and model:GetAttribute("OwnerUserId")==player.UserId then
            local fits,position=BoltMath.Fits(bolt,model)
            if fits then table.insert(holes,{model=model,position=position}) end
        end
    end
    table.sort(holes,function(a,b) return a.position<b.position end)
    if #holes==0 or #holes>2 then
        return rollback("A bolt can fasten one or two pierced holes")
    end
    local selected=false
    local ignored={[bolt]=true}
    for _,item in ipairs(holes) do
        ignored[item.model]=true
        if item.model==target then selected=true end
    end
    if not selected then return rollback("The selected hole is not reached") end
    if d.intersectsConstructed(bolt,ignored) then
        return rollback("Bolt intersects an unrelated solid")
    end
    if assemblyId then
        bolt:SetAttribute("AssemblyId",assemblyId)
        bolt:SetAttribute("AssemblyName",assemblyName)
    end
    local spec={
        relationId=HttpService:GenerateGUID(false),
        ownerUserId=player.UserId,kind="Bolt",
        sourceId=bolt:GetAttribute("InstanceId"),
        targetId=holes[1].model:GetAttribute("InstanceId"),
        secondTargetId=holes[2] and holes[2].model:GetAttribute("InstanceId"),
        boltId=bolt:GetAttribute("InstanceId"),
    }
    local ok,why=self:Restore(player,spec)
    if not ok then
        bolt:SetAttribute("AssemblyId",old.assemblyId)
        bolt:SetAttribute("AssemblyName",old.assemblyName)
        return rollback(why)
    end
    d.commitAssembly(player,before,{d.snapshot(bolt)},spec)
    return true,if holes[2] then "Bolt fastened both drilled bodies"
        else "Bolt fastened one drilled body"
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
    local minOffset,maxOffset=Alignment.OffsetBounds(source,target)
    if not minOffset or offset<minOffset or offset>maxOffset then
        return false,string.format(
            "Insertion must stay between %.1f and %.1f U",
            minOffset or 0,maxOffset or 0
        )
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
    local fits,why=Bore.ShaftFits(source,target)
    if not fits then
        for i,restore in ipairs(members) do d.applyState(restore,before[i]) end
        return false,why or "Shaft must remain inside housing"
    end
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
    if kind=="Slider" or kind=="Cylindrical" then
        local source=self.D.findOwned(player,joint:GetAttribute("SourceId"))
        local target=self.D.findOwned(player,joint:GetAttribute("TargetId"))
        if not source or not target then return false,"Shaft or housing deleted" end
        local min,max=Alignment.OffsetBounds(source,target)
        if not min then return false,max end
        local authored=source:GetAttribute("AlignedOffsetU") or 0
        min-=authored
        max-=authored
        local fittedTravel=joint:GetAttribute("FitTravelU")
        if type(fittedTravel)=="number" then
            min=math.max(min,-fittedTravel)
            max=math.min(max,fittedTravel)
        end
        if lower<min or upper>max then
            return false,string.format(
                "Slide must remain on shaft: %.1f to %.1f U",min,max)
        end
        on=true
    else
        if lower< -180 or upper>180 then
            return false,"Bearing angle limit must be within +/-180°"
        end
    end
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
    if spec.kind=="Spring" then
        relation:SetAttribute("Stiffness",spec.stiffness)
        relation:SetAttribute("Damping",spec.damping)
        relation:SetAttribute("FreeLength",spec.freeLength)
        local spring=relation:FindFirstChildOfClass("SpringConstraint")
        if spring then
            spring.Stiffness=spec.stiffness or 120
            spring.Damping=spec.damping or 14
            spring.FreeLength=spec.freeLength or spring.FreeLength
            spring.MaxLength=math.max(spring.FreeLength*1.8,0.25)
        end
        return true
    end
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
            local source=self.D.findOwned(player,spec.sourceId)
            local target=self.D.findOwned(player,spec.targetId)
            if source and target then
                local lo,hi=Alignment.OffsetBounds(source,target)
                local at=source:GetAttribute("AlignedOffsetU") or 0
                constraint.LimitsEnabled=true
                constraint.LowerLimit=math.max(lo-at,spec.lowerLimit or lo-at)
                    *self.D.Grid.Unit
                constraint.UpperLimit=math.min(hi-at,spec.upperLimit or hi-at)
                    *self.D.Grid.Unit
            end
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
    local spec=self:Snapshot(relation)
    local before={}
    if spec.kind=="Bolt" and type(spec.boltId)=="string" then
        local bolt=self.D.findOwned(player,spec.boltId)
        if bolt then
            table.insert(before,self.D.snapshot(bolt))
            bolt:Destroy()
        end
    end
    self:DestroyRelation(relation)
    self.D.commitAssembly(player,before,{},spec,true)
    return true,if spec.kind=="Bolt"
        then "Bolt and its connection removed" else "Relationship removed"
end

function Mechanical:ApplyHistory(player, record, undo, restoreBatch)
    local function applyEdits(undoEdit)
        for _,edit in ipairs(record.relationEdits or {}) do
            local snapshot=if undoEdit then edit.before else edit.after
            local relation=self:OwnedRelation(player,snapshot.relationId)
            if relation then
                relation:SetAttribute("OffsetUnits",snapshot.offsetUnits)
                relation:SetAttribute("FitPointsJSON",snapshot.fitPointsJSON)
                relation:SetAttribute("FitPointCount",snapshot.fitPointCount)
                relation:SetAttribute("FitTravelU",snapshot.fitTravelU)
                relation:SetAttribute("FitSetId",snapshot.fitSetId)
                relation:SetAttribute("FitSetIndex",snapshot.fitSetIndex)
                relation:SetAttribute("FitSetCount",snapshot.fitSetCount)
            end
        end
    end
    local specs=record.relations or
        (record.relation and {record.relation} or {})
    local removing=if record.removed then not undo else undo

    if removing then
        -- Remove ALL joints belonging to the fit before moving geometry.
        -- Otherwise the surviving three constraints would hold the plate
        -- while undo attempted to remove only one corner relationship.
        for _,spec in ipairs(specs) do
            local relation=self:OwnedRelation(player,spec.relationId)
            if relation then self:DestroyRelation(relation) end
        end
        local ok,why=restoreBatch(player,record,undo)
        if not ok then
            for _,spec in ipairs(specs) do self:Restore(player,spec) end
            return false,why
        end
        applyEdits(undo)
        return true
    end

    local ok,why=restoreBatch(player,record,undo)
    if not ok then return false,why end
    local restored={}
    for _,spec in ipairs(specs) do
        local success,result=self:Restore(player,spec)
        if not success then
            for _,id in ipairs(restored) do
                local relation=self:OwnedRelation(player,id)
                if relation then self:DestroyRelation(relation) end
            end
            restoreBatch(player,record,not undo)
            return false,result
        end
        table.insert(restored,spec.relationId)
    end
    applyEdits(undo)
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
            if source and not spec.fitSetId
                and (spec.kind == "Bearing" or spec.kind == "Slider"
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
                    if spec.kind=="Bolt" and spec.secondTargetId then
                        local other=self.D.findOwned(player,spec.secondTargetId)
                        local second=relation:FindFirstChild("BoltedSecondBody")
                        if other and other.PrimaryPart and second
                            and second:IsA("WeldConstraint") then
                            second.Part0=source.PrimaryPart
                            second.Part1=other.PrimaryPart
                        end
                    end
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
