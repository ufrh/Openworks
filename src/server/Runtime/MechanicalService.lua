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
local FitFeatures = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("FitFeatureRegistry"))
local BeltMath = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("BeltMath"))
local BeltVisual = require(script.Parent:WaitForChild("BeltVisual"))
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
local VectorJoint=require(script.Parent:WaitForChild("VectorJoint"))
local RopeMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("RopeMath"))

local Mechanical = {}
Mechanical.__index = Mechanical

local function relationValid(kind)
    return kind == "Bearing" or kind == "Slider"
        or kind == "Cylindrical" or kind == "Fixed" or kind == "Gear"
        or kind == "Spring" or kind == "Weld" or kind == "Bolt"
        or kind == "Belt" or kind=="VectorJoint" or kind=="Rope"
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
        beltRestLength = relation:GetAttribute("BeltRestLength"),
        springMode = relation:GetAttribute("SpringMode"),
        stiffness = relation:GetAttribute("Stiffness"),
        damping = relation:GetAttribute("Damping"),
        freeLength = relation:GetAttribute("FreeLength"),
        ropeLength=relation:GetAttribute("RopeLength"),
        ropeMinLength=relation:GetAttribute("RopeMinLength"),
        ropeMaxLength=relation:GetAttribute("RopeMaxLength"),
        ropeSpeedU=relation:GetAttribute("RopeSpeedU"),
        ropeForce=relation:GetAttribute("RopeForce"),
        ropeInKey=relation:GetAttribute("RopeInKey"),
        ropeOutKey=relation:GetAttribute("RopeOutKey"),
        boltId = relation:GetAttribute("BoltId"),
        secondTargetId = relation:GetAttribute("SecondTargetId"),
        fitPointsJSON = relation:GetAttribute("FitPointsJSON"),
        fitPointCount = relation:GetAttribute("FitPointCount"),
        fitTravelU = relation:GetAttribute("FitTravelU"),
        fitSetId = relation:GetAttribute("FitSetId"),
        fitSetIndex = relation:GetAttribute("FitSetIndex"),
        fitSetCount = relation:GetAttribute("FitSetCount"),
        motorEnabled=relation:GetAttribute("MotorEnabled")==true,
        motorRelationship=relation:GetAttribute("MotorRelationship")==true,
        motorSpeed=relation:GetAttribute("MotorSpeed"),
        motorTorque=relation:GetAttribute("MotorTorque"),
        motorAcceleration=relation:GetAttribute("MotorAcceleration"),
        motorKey=relation:GetAttribute("MotorKey"),
        motorDriveType=relation:GetAttribute("MotorDriveType") or "Continuous",
        motorInputMode=relation:GetAttribute("MotorInputMode") or "Hold",
        motorTargetAngle=relation:GetAttribute("MotorTargetAngle") or 90,
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
    local target = self.D.findOwned(player, spec.targetId)
    local source = self.D.findOwned(player, spec.sourceId)
    if not source or not target or source == target then
        return false, "Relationship parts were deleted"
    end
    -- Pre-integration CreateBolt saves linked two holes and stored the
    -- physical bolt only as BoltId. Repair that relationship in-memory
    -- without deleting the original saved bolt or modifying DataStores.
    if spec.kind=="Bolt" and not BoltMath.IsBolt(source)
        and type(spec.boltId)=="string" then
        local physicalBolt=self.D.findOwned(player,spec.boltId)
        if physicalBolt and BoltMath.IsBolt(physicalBolt) then
            spec=table.clone(spec)
            spec.secondTargetId=spec.targetId
            spec.targetId=spec.sourceId
            spec.sourceId=spec.boltId
            source=physicalBolt
            target=self.D.findOwned(player,spec.targetId)
            if not target then
                return false,"Legacy bolt hole is missing"
            end
        end
    end
    -- Upgrade legacy free-spinning gear hubs during plot restore. Every
    -- gear/shaft interface is now a rigid weld, regardless of save version.
    local oldHubMotion=spec.kind=="Bearing" or spec.kind=="Slider"
        or spec.kind=="Cylindrical"
    local oldGearHub=(type(source:GetAttribute("GearTeeth"))=="number"
        and Alignment.IsShaft(target))
        or (type(target:GetAttribute("GearTeeth"))=="number"
            and Alignment.IsShaft(source))
    if oldHubMotion and oldGearHub then
        -- Old saves allowed a gear to spin independently from its shaft.
        -- Both insertion directions now resolve to a rigid shaft weld.
        spec=table.clone(spec)
        spec.kind="Weld"
    end
    -- Saved and freshly authored gear/shaft welds obey the same geometry
    -- preflight. A weld never teleports a gear or accepts an offset bore.
    if spec.kind=="Weld" and
        (type(source:GetAttribute("GearTeeth"))=="number"
            or type(target:GetAttribute("GearTeeth"))=="number"
            or BeltMath.IsPulley(source) or BeltMath.IsPulley(target))
        and (Alignment.IsShaft(source) or Alignment.IsShaft(target)) then
        local fitted,reason=Smart.HubFits(source,target)
        if not fitted then return false,reason or "Gear hub is not fitted" end
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
    folder:SetAttribute("BeltRestLength",spec.beltRestLength)
    folder:SetAttribute("SpringMode",spec.springMode)
    folder:SetAttribute("Stiffness",spec.stiffness)
    folder:SetAttribute("Damping",spec.damping)
    folder:SetAttribute("FreeLength",spec.freeLength)
    if spec.kind=="Rope" then
        local p0,p1=RopeMath.Frames(source,target)
        local settings,why=RopeMath.Settings(spec,(p1-p0).Magnitude)
        if not settings then
            folder:Destroy()
            return false,why
        end
        RopeMath.Write(folder,settings)
    end
    folder:SetAttribute("BoltId",spec.boltId)
    folder:SetAttribute("SecondTargetId",spec.secondTargetId)
    folder:SetAttribute("FitPointsJSON",spec.fitPointsJSON)
    folder:SetAttribute("FitPointCount",spec.fitPointCount)
    folder:SetAttribute("FitTravelU",spec.fitTravelU)
    folder:SetAttribute("FitSetId",spec.fitSetId)
    folder:SetAttribute("FitSetIndex",spec.fitSetIndex)
    folder:SetAttribute("FitSetCount",spec.fitSetCount)
    folder:SetAttribute("MotorEnabled",spec.kind=="Bearing" and spec.motorEnabled==true)
    folder:SetAttribute("MotorRelationship",spec.kind=="Bearing"
        and spec.motorRelationship==true)
    folder:SetAttribute("MotorSpeed",spec.motorSpeed)
    folder:SetAttribute("MotorTorque",spec.motorTorque)
    folder:SetAttribute("MotorAcceleration",spec.motorAcceleration)
    folder:SetAttribute("MotorKey",spec.motorKey)
    folder:SetAttribute("MotorDriveType",spec.motorDriveType or "Continuous")
    folder:SetAttribute("MotorInputMode",spec.motorInputMode or "Hold")
    folder:SetAttribute("MotorTargetAngle",spec.motorTargetAngle or 90)

    local targetPart, sourcePart = target.PrimaryPart, source.PrimaryPart
    if not targetPart or not sourcePart then
        folder:Destroy()
        return false, "Missing relationship geometry"
    end

    if spec.kind=="Rope" then
        RopeMath.Compile(source,target,targetPart,sourcePart,folder,
            RopeMath.Attributes(folder),folder:GetAttribute("RelationId"),true)
    elseif spec.kind=="VectorJoint" then
        local joint,why=VectorJoint.Measure(source,target)
        if not joint then
            folder:Destroy()
            return false,why or "The shaft end faces are not joined"
        end
        -- This aesthetic cover is non-colliding and occupies NO new shaft
        -- length. Dynamic pivot and torque coupling are compiled in Simulate.
        VectorJoint.Hardware(folder,joint,false)
    elseif spec.kind=="Belt" then
        local path,why=BeltMath.Path(source,target)
        if not path then
            folder:Destroy()
            return false,why or "Belt geometry is invalid"
        end
        local length=spec.beltRestLength
        if type(length)~="number" or length~=length or length<=0
            or length>300 or length>path.Length*1.3
            or length<path.Length*0.7 then
            folder:Destroy()
            return false,"Belt length is outside valid tension range"
        end
        local visual=BeltVisual.new(folder)
        visual:Update(path)
    elseif spec.kind == "Gear" then
        if not source:GetAttribute("GearTeeth")
            or not target:GetAttribute("GearTeeth") then
            folder:Destroy()
            return false, "A Gear relationship requires two gear primitives"
        end
        -- Gear-to-gear motion is synchronized in the simulation runtime,
        -- never falsely represented as a native Roblox GearConstraint.
    elseif spec.kind == "Fixed" or spec.kind=="Weld"
        or spec.kind=="Bolt" then
        if spec.kind=="Bolt" and not BoltMath.Fits(source,target) then
            folder:Destroy()
            return false,"Bolt shank does not pass through its first opening"
        end
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
        -- The spring's prismatic guide shares these attachment frames.
        -- Its X axis points between the two saved mounting positions.
        folder:SetAttribute("SpringMode",mode)
        local world0,world1=SpringMath.Frames(source,target,mode)
        local guide0,guide1=SpringMath.AxisFrames(world0,world1,
            targetPart.CFrame.UpVector)
        local att0=Instance.new("Attachment")
        att0.Name="SpringFixedEnd"
        att0.CFrame=targetPart.CFrame:ToObjectSpace(guide0)
        att0.Parent=targetPart
        local att1=Instance.new("Attachment")
        att1.Name="SpringMovingEnd"
        att1.CFrame=sourcePart.CFrame:ToObjectSpace(guide1)
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
        -- The only allowed DOF is compression/extension along the spring
        -- axis. This is one authored Spring relationship, not an extra
        -- player-authored Slider or motor.
        local guide=Instance.new("PrismaticConstraint")
        guide.Name="SpringAxisGuide"
        guide.Attachment0=att0
        guide.Attachment1=att1
        guide.LimitsEnabled=false
        guide.ActuatorType=Enum.ActuatorType.None
        guide.Enabled=true
        guide.Parent=folder
    else
        -- Gear bores are legitimate joint housings, but never accept an
        -- off-center restored hinge or a slider that can leave the hub.
        if type(target:GetAttribute("GearTeeth"))=="number" then
            if spec.kind~="Bearing" then
                folder:Destroy()
                return false,"Gear/shaft mount only allows Rotation or Rigid"
            end
            local fitted,why=Smart.HubFits(source,target)
            if not fitted then
                folder:Destroy()
                return false,why or "Gear and shaft no longer align"
            end
        end
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
        -- Authored-world hinges are passive, including saved Motor
        -- relationships. Only the ACTIVE physical/rack simulation creates
        -- a shaft actuator. An authoring hinge motor can otherwise apply
        -- unintended torque to the housing while the simulation is live.
        constraint.ActuatorType=Enum.ActuatorType.None
        if constraint:IsA("HingeConstraint") then
            constraint.AngularVelocity=0
            constraint.TargetAngle=0
        end
        -- A slider/cylinder ALWAYS has hard mechanical travel stops.
        -- User limits can narrow them but can never permit the shaft
        -- to slide entirely clear of its real opening.
        local linear=constraint:IsA("PrismaticConstraint")
            or constraint:IsA("CylindricalConstraint")
        local low,high
        if linear then
            low,high=Alignment.RelativeTravelBounds(source,target)
            if not low or high-low<0.001 then
                folder:Destroy()
                return false,"Tube and shaft have no usable sliding travel"
            end
            if low>0 or high<0 then
                -- Saved layouts authored before tube-end limits could
                -- legally leave the shaft center beyond the housing.
                -- Restore these joints without changing saved geometry:
                -- park their travel at the CURRENT pose (zero travel)
                -- until the builder realigns the shaft into the tube.
                -- New placement and edits still use strict limits.
                folder:SetAttribute("LegacyOutOfBounds",true)
                low,high=0,0
            end
            if type(spec.fitTravelU)=="number" then
                low=math.max(low,-spec.fitTravelU)
                high=math.min(high,spec.fitTravelU)
            end
            if low>high then
                folder:Destroy()
                return false,"Multiple guides leave no safe linear travel"
            end
            if low==high then
                folder:SetAttribute("LegacyOutOfBounds",true)
            end
        end
        constraint.LimitsEnabled=linear or spec.limitsEnabled==true
        if constraint.LimitsEnabled then
            if constraint:IsA("HingeConstraint") then
                constraint.LowerAngle = spec.lowerLimit or -180
                constraint.UpperAngle = spec.upperLimit or 180
            else
                local authoredLow=spec.lowerLimit
                local authoredHigh=spec.upperLimit
                local lower=math.max(low,if type(authoredLow)=="number"
                    then authoredLow else low)
                local upper=math.min(high,if type(authoredHigh)=="number"
                    then authoredHigh else high)
                if lower>=upper then
                    -- Preserve a legacy out-of-bounds mount as a locked
                    -- visual relationship; normal joints still normalize
                    -- stale authored limits to the new physical stops.
                    lower,upper=low,high
                end
                constraint.LowerLimit=lower*self.D.Grid.Unit
                constraint.UpperLimit=upper*self.D.Grid.Unit
            end
        end
        constraint.Parent = folder
    end
    folder.Parent = self.Folder
    return true, folder
end

local MOTOR_KEYS={
    F=true,R=true,T=true,Y=true,H=true,J=true,K=true,L=true,
    B=true,N=true,M=true,V=true,Z=true,X=true,C=true,
    One=true,Two=true,Three=true,Four=true,
}
-- Optional motor drive mounted on an existing real shaft-in-hole bearing.
-- No authoring endpoint, direction or force can be conjured from empty air.
function Mechanical:TuneBearingMotor(player,request)
    if type(request)~="table" then return false,"Invalid motor request" end
    local joint=self:OwnedRelation(player,request.relationId)
    if not joint or joint:GetAttribute("Kind")~="Bearing" then
        return false,"Select an actual Rotation Only shaft bearing"
    end
    local enabled=request.motorEnabled
    local key,speed,torque,accel=request.motorKey,
        request.motorSpeed,request.motorTorque,request.motorAcceleration
    local driveType=request.motorDriveType or "Continuous"
    local inputMode=request.motorInputMode or "Hold"
    local angle=request.motorTargetAngle
    if angle==nil then angle=90 end
    if type(enabled)~="boolean"
        or (driveType~="Continuous" and driveType~="Servo")
        or (inputMode~="Hold" and inputMode~="Toggle")
        or type(angle)~="number" or angle~=angle or math.abs(angle)>180
        or type(key)~="string" or not MOTOR_KEYS[key]
        or type(speed)~="number" or speed~=speed
        or math.abs(speed)<0.05 or math.abs(speed)>35
        or type(torque)~="number" or torque~=torque
        or torque<1 or torque>100000
        or type(accel)~="number" or accel~=accel
        or accel<0.1 or accel>1000 then
        return false,"Motor requires valid key, speed, torque and acceleration"
    end
    local old=self:Snapshot(joint)
    joint:SetAttribute("MotorEnabled",enabled)
    joint:SetAttribute("MotorKey",key)
    joint:SetAttribute("MotorSpeed",speed)
    joint:SetAttribute("MotorTorque",torque)
    joint:SetAttribute("MotorAcceleration",accel)
    joint:SetAttribute("MotorDriveType",driveType)
    joint:SetAttribute("MotorInputMode",inputMode)
    joint:SetAttribute("MotorTargetAngle",angle)
    local hinge=joint:FindFirstChildOfClass("HingeConstraint")
    if hinge then
        -- Tuning edits metadata only; never power the authored hinge.
        -- The live runtime reads these motor settings for shaft-only drive.
        hinge.ActuatorType=Enum.ActuatorType.None
        hinge.AngularVelocity=0
        hinge.MotorMaxTorque=torque
        hinge.MotorMaxAcceleration=accel
        hinge.TargetAngle=0
        hinge.AngularSpeed=math.abs(speed)
        hinge.ServoMaxTorque=torque
    end
    if self.D.commitJointEdit then
        self.D.commitJointEdit(player,old,self:Snapshot(joint))
    end
    return true,if enabled then "Physical bearing motor bound to "..key
        else "Bearing motor disabled"
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
    if #members==0 then
        return false,"Invalid source component"
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
    if mode=="Hub" and request.relationKind~="Weld"
        and request.relationKind~="Rigid" then
        return false,"Gear and pulley hubs always weld to shafts"
    end
    if mode=="Surface" then
        return false,"Touching parts are never welded automatically. Use Weld."
    end
    if mode~="Bore" and mode~="Gear" and mode~="Rack"
        and mode~="Guide" and mode~="Hub" and mode~="Surface" then
        return false,"Unsupported attachment"
    end
    if (mode=="Bore" or mode=="Hub" or mode=="Gear")
        and FitFeatures.Pair(source,target)~=mode then
        return false,"These parts do not expose compatible fitting features"
    end
    local reverse=mode=="Bore" and request.reverse==true
    local shaft=if mode=="Hub" then
        (if Alignment.IsShaft(source) then source else target)
        else (if reverse then target else source)
    local opening=if mode=="Hub" then
        (if source:GetAttribute("GearTeeth") or BeltMath.IsPulley(source)
            then source else target)
        else (if reverse then source else target)
    local motorRequested=mode=="Bore" and request.relationKind=="Motor"
    local typeName=if motorRequested then "Bearing"
        elseif mode=="Bore" then (request.relationKind or "Cylindrical")
        elseif mode=="Gear" or mode=="Rack"
            or mode=="Guide" then mode
        elseif mode=="Hub" then "Weld"
        else "Fixed"
    -- Powered Motor is a rotation-only bearing fitted into a real
    -- drilled/hole block. The server validates both insertion directions.
    if motorRequested then
        local name=string.lower(tostring(opening:GetAttribute("TemplateId")
            or opening.Name)):gsub("[%s_%-]","")
        if not (name:find("drilledblock",1,true)
            or name:find("holeblock",1,true))
            or not Alignment.IsShaft(shaft)
            or not Alignment.TargetAxis(opening) then
            return false,"Powered Motor requires a Cylinder shaft and drilled hole block"
        end
    end
    -- Gear/shaft mounts ALWAYS create explicit WeldConstraints.
    -- Shaft/housing bearings alone determine rotational freedom.
    if mode=="Bore" and typeName~="Bearing"
        and typeName~="Slider" and typeName~="Cylindrical"
        and typeName~="FreeFit" then
        return false,"Choose Rotate + Slide, Slide, Rotate or Fit Only"
    end
    local transient=nil
    if request.selectedIds~=nil then
        if newSource or type(request.selectedIds)~="table"
            or #request.selectedIds<2 then
            return false,"Invalid temporary multi-fit selection"
        end
        local seen={}
        transient={}
        local includesSource=false
        for _,id in ipairs(request.selectedIds) do
            if type(id)~="string" or seen[id] then
                return false,"Duplicate or invalid multi-fit ID"
            end
            seen[id]=true
            local model=d.findOwned(player,id)
            if not model or model:GetAttribute("ComponentId") or model==target
                or not d.nearPlayer(player,model:GetPivot().Position) then
                return false,"Multi-fit must contain owned independent moving primitives"
            end
            if model==source then includesSource=true end
            table.insert(transient,model)
        end
        if not includesSource then
            return false,"Multi-fit selection must include the chosen shaft/hole"
        end
    end
    local movingComponent=source:GetAttribute("ComponentId")
    local targetComponent=target:GetAttribute("ComponentId")
    if movingComponent and movingComponent==targetComponent then
        -- ComponentId is ONLY an editor selection group, not a rigid joint.
        -- A gear already concentric with a shaft in the same component
        -- must still be able to author its mechanical Hub Weld in place.
        -- Do not try to move an entire group onto one of its own members.
        if mode~="Hub" then
            return false,"Choose an independent moving part to align inside this component"
        end
        local valid,why=Smart.HubFits(source,target)
        if not valid then return false,why or "Hub must already fit the shaft" end
        local shaftId=shaft:GetAttribute("InstanceId")
        local gearId=opening:GetAttribute("InstanceId")
        for _,relation in ipairs(self.Folder:GetChildren()) do
            if relation:GetAttribute("OwnerUserId")==player.UserId then
                local a,b=relation:GetAttribute("SourceId"),relation:GetAttribute("TargetId")
                if (a==shaftId and b==gearId) or (a==gearId and b==shaftId) then
                    if relation:GetAttribute("Kind")=="Weld" then
                        return true,"Gear is already rigidly mounted to this shaft"
                    end
                    return false,"Remove the old free-spinning joint before welding this gear"
                end
            end
        end
        local spec={
            relationId=HttpService:GenerateGUID(false),
            ownerUserId=player.UserId,kind="Weld",
            sourceId=shaftId,targetId=gearId,
            componentId=movingComponent,
        }
        local ok,reason=self:Restore(player,spec)
        if not ok then return false,reason end
        d.commitAssembly(player,{},{},spec)
        return true,"Gear rigidly welded onto the shaft (in-place Hub)"
    end
    local members=if transient then transient
        elseif movingComponent then d.components:Members(player,movingComponent)
        else {source}
    if #members==0 then
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
            if (movingComponent or transient)
                and typeof(request.groupPivot)=="CFrame" then
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
        local requestedSnug=request.shaftDiameter
        local allowedSnug=nil
        if requestedSnug~=nil then
            if newSource or reverse
                or typeof(requestedSnug)~="number" then
                return false,"Invalid shaft resize in this fit"
            end
            allowedSnug=Bore.SnugDiameter(shaft,opening)
            if not allowedSnug or math.abs(allowedSnug-requestedSnug)>0.0002 then
                return false,"Shaft cannot be automatically resized for that bore"
            end
        end
        for _,item in ipairs(plan.items) do
            local old=d.snapshot(item.model)
            local state=table.clone(old)
            state.position=item.position
            state.steps=item.steps
            state.orientation=item.orientation
            state.assemblyPrecision=true
            state.freePosition=true
            if allowedSnug and item.model==shaft then
                state.size=Vector3.new(state.size.X,allowedSnug,allowedSnug)
                state.fitPrecision=true
                state.resizePrecision=true
                local entry=d.Registry.Get(state.templateId)
                local valid,why=entry and d.validState(player,entry,state)
                if not valid then return false,why or "Invalid fine-fit shaft diameter" end
            end
            if item.model==shaft then
                state.alignedOpeningId=opening:GetAttribute("InstanceId")
                state.alignedOffsetU=offset
                state.shaftRollDegrees=roll
            end
            table.insert(planned,state)
        end
    elseif mode=="Gear" or mode=="Rack" or mode=="Guide"
        or mode=="Hub" then
        if typeof(request.approach)~="Vector3"
            or not d.Grid.ValidPosition(request.approach) then
            return false,"Move closer to the compatible gear/shaft"
        end
        local pose,why
        if mode=="Gear" then
            pose,why=Smart.GearPose(source,target,request.approach)
        elseif mode=="Rack" then
            pose,why=Smart.RackPose(source,target,request.approach)
        elseif mode=="Guide" then
            pose,why=Smart.GuidePose(source,target,request.approach)
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
        if request.shaftDiameter~=nil then
            local valid,why=self:ValidateResize(player,shaft:GetAttribute("InstanceId"))
            if not valid then restoreMoving() return false,why end
        end
        local fits,why=Bore.ShaftFits(shaft,opening)
        if not fits then restoreMoving() return false,why end
    elseif mode=="Gear" or mode=="Rack" or mode=="Guide" then
        local fits,why=GearMath.AutoMeshStatus(source,target)
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
    local hubGears=nil
    if mode=="Hub" or mode=="Bore" then
        -- A hole is the primary alignment target; afterwards collect ALL
        -- genuinely engaged gears on the shaft and rigidly weld them in the
        -- very same transaction. A gear is NOT a shaft bearing.
        -- The existing Hub-first workflow shares this verified scan.
        -- Do not stop at the first valid hub, but only attach a gear if its
        -- actual bore overlaps the finite shaft and passes full clearance.
        hubGears=if mode=="Hub" then {opening} else {}
        if Alignment.IsShaft(shaft) then
            local shaftCF=shaft:GetPivot()
            local axis=shaftCF.RightVector.Unit
            local seen=if mode=="Hub" then {[opening]=true} else {}
            local shaftHalf=shaft.PrimaryPart.Size.X*0.5
            for _,candidate in ipairs(d.folder:GetChildren()) do
                if candidate:IsA("Model") and candidate~=shaft
                    and candidate.PrimaryPart
                    and candidate:GetAttribute("OwnerUserId")==player.UserId
                    and (type(candidate:GetAttribute("GearTeeth"))=="number"
                        or BeltMath.IsPulley(candidate))
                    and not seen[candidate] then
                    local delta=candidate:GetPivot().Position-shaftCF.Position
                    local axial=math.abs(delta:Dot(axis))
                    local radial=(delta-axis*delta:Dot(axis)).Magnitude
                    local reach=shaftHalf+candidate.PrimaryPart.Size.X*0.5
                    if axial<reach-0.002 and radial<0.035 then
                        local fits,why=Smart.HubFits(shaft,candidate)
                        if fits then
                            seen[candidate]=true
                            table.insert(hubGears,candidate)
                        elseif mode=="Hub" then
                            restoreMoving()
                            return false,why or "Another hub cannot fit this shaft"
                        end
                    end
                end
            end
        end
        fitMap=if mode=="Hub" then {[shaft]={}} else nil
        for _,gear in ipairs(hubGears) do
            if not fitMap then fitMap={[shaft]={}} end
            fitMap[shaft][gear]=true
            -- The moving object may be the gear rather than the shaft.
            -- Collision authorization must work in BOTH mount directions.
            fitMap[gear]=fitMap[gear] or {}
            fitMap[gear][shaft]=true
        end
    end
    if mode=="Bore" then
        local all={}
        for _,candidate in ipairs(d.folder:GetChildren()) do
            if candidate:IsA("Model")
                and candidate:GetAttribute("OwnerUserId")==player.UserId then
                table.insert(all,candidate)
            end
        end
        local reason
        local stationary=MultiFit.StationarySet(members,target,
            all,nil,excluded)
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
        -- A blocked-end hole may only permit PARTIAL insertion. This
        -- is still a physically valid slider/cylinder if its shaft has
        -- nonzero genuine overlap. RelativeTravelBounds safely includes
        -- the starting position but never extends beyond engagement.
        if typeName=="Slider" or typeName=="Cylindrical" then
            for _,pair in ipairs(fitPairs) do
                local low,high=Alignment.InsertionBounds(pair.shaft,pair.hole)
                if not low or pair.depthU<low-0.006
                    or pair.depthU>high+0.006 then
                    restoreMoving()
                    return false,"Shaft must genuinely engage every opening"
                end
            end
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
        if request.fitMovingIds~=nil then
            if type(request.fitMovingIds)~="table"
                or #request.fitMovingIds>MultiFit.MaxPairs then
                restoreMoving()
                return false,"Invalid moving guide selection"
            end
            local confirmed={}
            for _,pair in ipairs(fitPairs) do
                confirmed[pair.movingId]=true
            end
            for _,id in ipairs(request.fitMovingIds) do
                if type(id)~="string" or #id>64 or not confirmed[id] then
                    restoreMoving()
                    return false,"Every moving hole must still fit the shaft"
                end
            end
        end
        fitMap=MultiFit.AllowMap(fitPairs)
    end
    if mode=="Bore" and typeName~="FreeFit"
        and hubGears and #hubGears>0 then
        -- Never close a rigid loop around a moving bearing. In particular,
        -- a gear previously welded to its hole housing cannot ALSO be
        -- welded onto the rotating shaft without locking the mechanism.
        -- ComponentId alone is not a weld, so un-welded components pass.
        local neighbors={}
        local function link(a,b)
            if type(a)~="string" or type(b)~="string" then return end
            neighbors[a]=neighbors[a] or {}
            neighbors[b]=neighbors[b] or {}
            table.insert(neighbors[a],b)
            table.insert(neighbors[b],a)
        end
        for _,rel in ipairs(self.Folder:GetChildren()) do
            if rel:GetAttribute("OwnerUserId")~=player.UserId then continue end
            local kind=rel:GetAttribute("Kind")
            if kind=="Weld" or kind=="Fixed" or kind=="Bolt" then
                local a=rel:GetAttribute("SourceId")
                local b=rel:GetAttribute("TargetId")
                link(a,b)
                if kind=="Bolt" then
                    link(a,rel:GetAttribute("SecondTargetId"))
                end
            end
        end
        local function rigidPath(startId,finishId)
            local queue={startId}
            local seen={[startId]=true}
            local index=1
            while index<=#queue do
                local id=queue[index]
                index+=1
                if id==finishId then return true end
                for _,nextId in ipairs(neighbors[id] or {}) do
                    if not seen[nextId] then
                        seen[nextId]=true
                        table.insert(queue,nextId)
                    end
                end
            end
            return false
        end
        for _,gear in ipairs(hubGears) do
            for _,pair in ipairs(fitPairs) do
                if rigidPath(gear:GetAttribute("InstanceId"),
                    pair.hole:GetAttribute("InstanceId")) then
                    restoreMoving()
                    return false,"Gear is rigidly welded to its hole housing. "
                        .."Release that weld so the gear can rotate with the shaft"
                end
            end
        end
    end
    -- Verify every gear against the FINAL fitted shaft, then allow only
    -- that precise shaft/hub cavity through the collision broadphase.
    -- Unrelated gears, plates and obstructions remain solid blockers.
    if hubGears and #hubGears>0 then
        fitMap=fitMap or {}
        fitMap[shaft]=fitMap[shaft] or {}
        for _,gear in ipairs(hubGears) do
            fitMap[shaft][gear]=true
            fitMap[gear]=fitMap[gear] or {}
            fitMap[gear][shaft]=true
        end
    end

    for _,member in ipairs(members) do
        if d.intersectsConstructed(member,excluded,
            if mode=="Hub" or mode=="Gear"
                or mode=="Rack" or mode=="Guide" then target
                elseif mode=="Bore" and not reverse then opening else nil,
            if mode=="Hub" then source:GetAttribute("InstanceId")
                elseif mode=="Bore" and not reverse
                    then shaft:GetAttribute("InstanceId") else nil,
            fitMap) then
            restoreMoving()
            return false,"Attachment intersects another solid"
        end
    end

    if mode=="Gear" or mode=="Rack" or mode=="Guide" then
        -- Tooth contact and rack guides are placement operations, never
        -- permanent input/output relationships.
        local after={}
        for _,member in ipairs(members) do
            table.insert(after,d.snapshot(member))
        end
        d.commitAssembly(player,before,after,nil,false)
        return true,if mode=="Rack" then
            "Rack and pinion engaged • automatic transmission in simulation"
            elseif mode=="Guide" then
            "Rack positioned in guide • ground guide housing for support"
            else "Gear positioned at pitch geometry • automatic shaft mesh in simulation"
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
    -- Multiple separated guide holes may permit rotation but ZERO
    -- axial motion. That is a valid fitted configuration: native linear
    -- limits collapse to zero instead of rejecting the entire relation
    -- selection and bouncing the user back into the fit picker.
    if (typeName=="Slider" or typeName=="Cylindrical")
        and fittedTravel and fittedTravel<0.25 then
        fittedTravel=0
    end
    if typeName=="FreeFit" and (not hubGears or #hubGears==0) then
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
    if mode=="Bore" and typeName~="FreeFit" then
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
                -- Only the explicitly selected primary hole becomes
                -- powered in a multipoint fit; other coaxial holes stay
                -- ordinary passive bearings.
                motorRelationship=motorRequested
                    and pair.shaft:GetAttribute("InstanceId")
                        ==shaft:GetAttribute("InstanceId")
                    and pair.hole:GetAttribute("InstanceId")
                        ==opening:GetAttribute("InstanceId"),
                motorEnabled=motorRequested
                    and pair.shaft:GetAttribute("InstanceId")
                        ==shaft:GetAttribute("InstanceId")
                    and pair.hole:GetAttribute("InstanceId")
                        ==opening:GetAttribute("InstanceId"),
                motorKey=if motorRequested then "F" else nil,
                motorSpeed=if motorRequested then 3 else nil,
                motorTorque=if motorRequested then 3000 else nil,
                motorAcceleration=if motorRequested then 40 else nil,
                motorDriveType="Continuous",
                motorInputMode="Hold",
                motorTargetAngle=90,
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
    elseif mode~="Bore" and mode~="Hub" then
        table.insert(desiredSpecs,{
            relationId=HttpService:GenerateGUID(false),
            ownerUserId=player.UserId,
            kind=typeName,
            sourceId=request.sourceId,
            targetId=request.targetId,
            componentId=movingComponent,
            offsetUnits=offset,
            rollDegrees=roll,
        })
    end

    -- The bore's physical joint and every coaxial gear rigid mount are
    -- authored together; either ALL commit, or NONE do.
    for _,gear in ipairs(hubGears or {}) do
        table.insert(desiredSpecs,{
            relationId=HttpService:GenerateGUID(false),
            ownerUserId=player.UserId,
            kind="Weld",
            sourceId=shaft:GetAttribute("InstanceId"),
            targetId=gear:GetAttribute("InstanceId"),
            componentId=shaft:GetAttribute("ComponentId"),
            offsetUnits=(gear:GetPivot().Position-shaft:GetPivot().Position)
                :Dot(shaft:GetPivot().RightVector)/d.Grid.Unit,
            rollDegrees=0,
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
            if prior:GetAttribute("Kind")~=candidate.kind then
                if reverse then d.applyState(shaft,fixedShaftBefore) end
                restoreMoving()
                return false,"An existing relationship has a different motion type"
            end
            if mode=="Bore" and candidate.kind=="Bearing"
                and (prior:GetAttribute("MotorRelationship")==true)
                    ~= (candidate.motorRelationship==true) then
                if reverse then d.applyState(shaft,fixedShaftBefore) end
                restoreMoving()
                return false,"A bearing or motor already exists for this pair. "
                    .."Remove it before choosing a different drive type"
            end
            table.insert(reused,{relation=prior,spec=candidate})
        else
            table.insert(need,candidate)
        end
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
        d.commitBatch(player,before,after,true)
        return true,string.format("%d existing %s connections repositioned",
            #desiredSpecs,typeName)
    end
    -- One authored operation, one undo/redo entry, all joints or none.
    d.commitAssembly(player,before,after,createdSpecs,false,relationEdits)
    return true,if mode=="Bore" then
        string.format("%d shaft/hole %s fit(s) • %d gear/pulley weld(s)",
            #fitPairs,typeName,#hubGears)
        elseif mode=="Hub" then
            string.format("%d pulley/gear hub(s) rigidly welded to shaft",#hubGears)
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

-- Author a complete friction belt as one saved relationship.
-- Neither motor power nor shaft mounting is generated by this action.
function Mechanical:CreateBelt(player,request)
    if type(request)~="table" or type(request.sourceId)~="string"
        or type(request.targetId)~="string" then
        return false,"Click two belt pulleys"
    end
    local source=self.D.findOwned(player,request.sourceId)
    local target=self.D.findOwned(player,request.targetId)
    if not source or not target or source==target
        or not self.D.nearPlayer(player,source:GetPivot().Position)
        or not self.D.nearPlayer(player,target:GetPivot().Position) then
        return false,"Select two different pulleys within your plot"
    end
    local path,reason=BeltMath.Path(source,target)
    if not path then return false,reason end
    local function mounted(pulley)
        local pid=pulley:GetAttribute("InstanceId")
        for _,relation in ipairs(self.Folder:GetChildren()) do
            if relation:GetAttribute("OwnerUserId")==player.UserId
                and (relation:GetAttribute("Kind")=="Weld"
                    or relation:GetAttribute("Kind")=="Fixed") then
                local otherId=if relation:GetAttribute("SourceId")==pid
                    then relation:GetAttribute("TargetId")
                    elseif relation:GetAttribute("TargetId")==pid
                    then relation:GetAttribute("SourceId") else nil
                local other=otherId and self.D.findOwned(player,otherId)
                if other and Alignment.IsShaft(other)
                    and Smart.HubFits(pulley,other) then
                    return otherId
                end
            end
        end
        return nil
    end
    local mountA,mountB=mounted(source),mounted(target)
    if not mountA or not mountB then
        return false,"Fit and weld each pulley onto a real shaft first"
    end
    if mountA==mountB then
        return false,"A belt must connect two independent shafts"
    end
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("Kind")=="Belt"
            and relation:GetAttribute("OwnerUserId")==player.UserId then
            local a,b=relation:GetAttribute("SourceId"),relation:GetAttribute("TargetId")
            if (a==request.sourceId and b==request.targetId)
                or (a==request.targetId and b==request.sourceId) then
                return false,"These pulleys already share a belt"
            end
        end
    end
    -- Preload is explicit, never inferred from a client-sent world length.
    -- A zero-preload loop is slack and cannot transmit torque until stretched.
    local preload=if request.preloadPercent==nil then 1.5
        else request.preloadPercent
    if type(preload)~="number" or preload~=preload or preload<0
        or preload>8 or math.abs(preload*2-math.round(preload*2))>0.0001 then
        return false,"Belt preload must be 0–8% in 0.5% steps"
    end
    local spec={
        relationId=HttpService:GenerateGUID(false),kind="Belt",
        ownerUserId=player.UserId,sourceId=request.sourceId,
        targetId=request.targetId,beltRestLength=path.Length*(1-preload*0.01),
    }
    local ok,why=self:Restore(player,spec)
    if not ok then return false,why end
    self.D.commitAssembly(player,{},{},spec)
    return true,string.format(
        "Belt fitted • %.2f U circumference • %.1f%% preload",
        path.Length/self.D.Grid.Unit,preload)
end

-- Explicit pair removal prevents Shift+Delete from accidentally removing
-- the pulley-to-shaft Weld instead of the desired belt.
function Mechanical:RemoveBelt(player,request)
    if type(request)~="table"
        or type(request.sourceId)~="string"
        or type(request.targetId)~="string" then
        return false,"Select two belt pulleys"
    end
    if not self.D.findOwned(player,request.sourceId)
        or not self.D.findOwned(player,request.targetId) then
        return false,"Both pulleys must belong to your plot"
    end
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId
            and relation:GetAttribute("Kind")=="Belt" then
            local a,b=relation:GetAttribute("SourceId"),
                relation:GetAttribute("TargetId")
            if (a==request.sourceId and b==request.targetId)
                or (a==request.targetId and b==request.sourceId) then
                return self:Remove(player,{relationId=relation:GetAttribute("RelationId")})
            end
        end
    end
    return false,"These pulleys have no belt to remove"
end

-- Construct a genuine zero-span articulation at two adjacent shaft ends.
-- The relationship is named, saved and undoable; it creates no axle stock.
function Mechanical:CreateVectorJoint(player,request)
    if type(request)~="table" or type(request.sourceId)~="string"
        or type(request.targetId)~="string" then
        return false,"Select two shaft end faces"
    end
    local a=self.D.findOwned(player,request.sourceId)
    local b=self.D.findOwned(player,request.targetId)
    if not a or not b or a==b then
        return false,"Choose two different shafts you own"
    end
    if not self.D.nearPlayer(player,a:GetPivot().Position)
        or not self.D.nearPlayer(player,b:GetPivot().Position) then
        return false,"Vector Joint is outside your build range"
    end
    local pivot,why=VectorJoint.Measure(a,b)
    if not pivot then return false,why end
    for _,existing in ipairs(self.Folder:GetChildren()) do
        if existing:GetAttribute("OwnerUserId")==player.UserId then
            local kind=existing:GetAttribute("Kind")
            local id0=existing:GetAttribute("SourceId")
            local id1=existing:GetAttribute("TargetId")
            if (id0==request.sourceId and id1==request.targetId)
                or (id1==request.sourceId and id0==request.targetId) then
                if kind=="VectorJoint" or kind=="Weld"
                    or kind=="Fixed" or kind=="Bearing"
                    or kind=="Slider" or kind=="Cylindrical" then
                    return false,"Remove the existing joint between these shafts first"
                end
            end
        end
    end
    local spec={relationId=HttpService:GenerateGUID(false),
        ownerUserId=player.UserId,kind="VectorJoint",
        sourceId=request.sourceId,targetId=request.targetId}
    local created,detail=self:Restore(player,spec)
    if not created then return false,detail end
    self.D.commitAssembly(player,{}, {},spec)
    return true,"Vector Joint: shaft ends coupled at one pivot • 1:1 reversible drive"
end

-- Create a physical tension-only rope with individually keyed winch
-- directions. Unlike spring or prismatic constraints this does not resist
-- either endpoint moving closer than the paid-out rope length.
function Mechanical:CreateRope(player,request)
    if type(request)~="table" then return false,"Invalid rope request" end
    request.kind="Rope"
    local source,target,reason=validEndpoints(self,player,request)
    if not source then return false,reason end
    local p0,p1=RopeMath.Frames(source,target)
    local settings,why=RopeMath.Settings(request,(p1-p0).Magnitude)
    if not settings then return false,why end
    local spec={
        relationId=HttpService:GenerateGUID(false),
        ownerUserId=player.UserId,kind="Rope",
        sourceId=request.sourceId,targetId=request.targetId,
        componentId=source:GetAttribute("ComponentId"),
    }
    for name,value in pairs(settings) do spec[name]=value end
    local ok,message=self:Restore(player,spec)
    if not ok then return false,message end
    self.D.commitAssembly(player,{}, {},spec)
    return true,"Rope connected • Z retract / X pay out (rebind in Properties)"
end

function Mechanical:TuneRope(player,request)
    local relation=self:OwnedRelation(player,request.relationId)
    if not relation or relation:GetAttribute("Kind")~="Rope" then
        return false,"Choose a rope relationship"
    end
    local source=self.D.findOwned(player,relation:GetAttribute("SourceId"))
    local target=self.D.findOwned(player,relation:GetAttribute("TargetId"))
    if not source or not target then return false,"Rope endpoints are missing" end
    local p0,p1=RopeMath.Frames(source,target)
    local current=RopeMath.Attributes(relation)
    for name in pairs(current) do
        if request[name]~=nil then current[name]=request[name] end
    end
    local settings,why=RopeMath.Settings(current,(p1-p0).Magnitude)
    if not settings then return false,why end
    local before=self:Snapshot(relation)
    RopeMath.Write(relation,settings)
    local rope=relation:FindFirstChildOfClass("RopeConstraint")
    if rope then
        rope.Length=settings.ropeLength
        rope.WinchTarget=settings.ropeLength
        rope.WinchSpeed=settings.ropeSpeedU*self.D.Grid.Unit
        rope.WinchForce=settings.ropeForce
    end
    self.D.commitJointEdit(player,before,self:Snapshot(relation))
    return true,"Rope length "..string.format("%.2f U",settings.ropeLength/self.D.Grid.Unit)
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
    return true,"Spring connected • single-axis compression and extension"
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

-- Find crank-to-shaft couplings without relying on editor components.
-- A shaft may have more than one real output coupling (either end).
function Mechanical:CoupledCranks(player,shaft)
    local found={}
    local seen={}
    if not HandCrankMath.IsOutputShaft(shaft) then return found end
    local shaftId=shaft:GetAttribute("InstanceId")
    for _,relation in ipairs(self.Folder:GetChildren()) do
        local kind=relation:GetAttribute("Kind")
        if relation:GetAttribute("OwnerUserId")==player.UserId
            and (kind=="Weld" or kind=="Fixed") then
            local sourceId=relation:GetAttribute("SourceId")
            local targetId=relation:GetAttribute("TargetId")
            local otherId=if sourceId==shaftId then targetId
                elseif targetId==shaftId then sourceId else nil
            if otherId and not seen[otherId] then
                local crank=self.D.findOwned(player,otherId)
                if HandCrankMath.IsCrank(crank) then
                    seen[otherId]=true
                    table.insert(found,crank)
                end
            end
        end
    end
    return found
end

-- Refit ALL cranks atomically when an already-coupled shaft's diameter is
-- edited. Caller commits a single combined undo record with the shaft.
-- Returns two history arrays, or nil and a reason; no partial resizing.
function Mechanical:ResizeCoupledCranks(player,shaft)
    local d=self.D
    local plans={}
    for _,crank in ipairs(self:CoupledCranks(player,shaft)) do
        local desired,why=HandCrankMath.ShaftSize(crank,shaft)
        if not desired then return nil,nil,why end
        local old=d.snapshot(crank)
        if (old.size-desired).Magnitude>0.0001 then
            local state=table.clone(old)
            state.size=desired
            local entry=d.Registry.Get(old.templateId)
            if not entry then return nil,nil,"Hand crank template missing" end
            local valid,reason=d.validState(player,entry,state)
            if not valid then return nil,nil,reason end
            table.insert(plans,{model=crank,before=old,after=state})
        end
    end
    local function rollback()
        for _,plan in ipairs(plans) do
            d.applyState(plan.model,plan.before)
        end
    end
    for _,plan in ipairs(plans) do
        d.applyState(plan.model,plan.after)
    end
    for _,plan in ipairs(plans) do
        if d.intersectsConstructed(plan.model,{[plan.model]=true}) then
            rollback()
            return nil,nil,"Resized hand crank intersects another construction"
        end
    end
    local before,after={},{}
    for _,plan in ipairs(plans) do
        table.insert(before,plan.before)
        table.insert(after,d.snapshot(plan.model))
    end
    return before,after
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
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId
            and (relation:GetAttribute("Kind")=="Weld"
                or relation:GetAttribute("Kind")=="Fixed")
            and (relation:GetAttribute("SourceId")==request.sourceId
                or relation:GetAttribute("TargetId")==request.sourceId) then
            local otherId=if relation:GetAttribute("SourceId")==request.sourceId
                then relation:GetAttribute("TargetId")
                else relation:GetAttribute("SourceId")
            local other=d.findOwned(player,otherId)
            if HandCrankMath.IsOutputShaft(other) then
                return false,"Hand crank output is already attached to a shaft"
            end
        end
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

    local desiredSize,sizeReason=HandCrankMath.ShaftSize(source,target)
    if not desiredSize then return false,sizeReason end

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

    -- Change the complete crank's radial geometry to match the output
    -- shaft, preserving its fixed axial output length and coaxial snap.
    local beforeSize=d.snapshot(source)
    if not newSource and not changed then
        table.insert(before,beforeSize)
    end
    local fittedState=table.clone(beforeSize)
    fittedState.size=desiredSize
    local entry=d.Registry.Get(fittedState.templateId)
    local sizingValid,sizingWhy=false,"Missing crank template"
    if entry then
        sizingValid,sizingWhy=d.validState(player,entry,fittedState)
    end
    if not sizingValid then
        if changed then
            for index,member in ipairs(members) do
                d.applyState(member,before[index])
            end
        end
        return false,sizingWhy or "Hand crank cannot fit the target shaft"
    end
    d.applyState(source,fittedState)
    if d.intersectsConstructed(source,{[source]=true}) then
        if changed then
            for index,member in ipairs(members) do
                d.applyState(member,before[index])
            end
        elseif not newSource then
            d.applyState(source,beforeSize)
        end
        return false,"Resized hand crank intersects another construction"
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
            for index,member in ipairs(members) do
                d.applyState(member,before[index])
            end
        elseif not newSource then
            d.applyState(source,beforeSize)
        end
        return false,reason
    end
    if newSource then
        d.commitAssembly(player,{}, {d.snapshot(source)},spec)
    else
        for _,member in ipairs(members) do
            table.insert(after,d.snapshot(member))
        end
        d.commitAssembly(player,before,after,spec)
    end
    return true,"Hand crank sized to shaft and rigidly coupled"
end

-- Conservative two-way oriented solid-bounds proximity check.
-- The physics overlap query can miss exactly flush CSG or cylinder ends.
-- Use this same test for authored welds and joint detachment, with a
-- slightly wider tolerance during manual fabrication.
local function stillTouching(a,b,tolerance)
    if not a or not b or not a.PrimaryPart or not b.PrimaryPart then
        return false
    end
    local function nearOnAxes(first,second)
        local cf=first.CFrame
        local delta=cf:PointToObjectSpace(second.Position)
        local x,y,z=cf.RightVector,cf.UpVector,cf.LookVector
        local bx,by,bz=second.CFrame.RightVector,
            second.CFrame.UpVector,second.CFrame.LookVector
        local h=second.Size*0.5
        local epsilon=tolerance or 0.012
        local function fits(offset,half,axis)
            local reach=math.abs(axis:Dot(bx))*h.X
                +math.abs(axis:Dot(by))*h.Y
                +math.abs(axis:Dot(bz))*h.Z
            return math.abs(offset)<=half+reach+epsilon
        end
        return fits(delta.X,first.Size.X*0.5,x)
            and fits(delta.Y,first.Size.Y*0.5,y)
            and fits(delta.Z,first.Size.Z*0.5,z)
    end
    for _,left in ipairs(a:GetDescendants()) do
        if not left:IsA("BasePart") or not left.CanCollide
            or left:GetAttribute("GearPivotOnly")==true then continue end
        for _,right in ipairs(b:GetDescendants()) do
            if right:IsA("BasePart") and right.CanCollide
                and right:GetAttribute("GearPivotOnly")~=true
                and nearOnAxes(left,right) and nearOnAxes(right,left) then
                return true
            end
        end
    end
    return false
end


-- Single and multi-weld use the same server-authoritative proximity,
-- clearance and competing-relationship checks. Never weld at a distance.
local function weldPairValid(self,player,source,target)
    if HandCrankMath.IsCrank(source) or HandCrankMath.IsCrank(target) then
        return false,"Use the HandCrank output coupling to attach a crank to its shaft"
    end
    -- The parts must be in REAL contact; being nearby is insufficient.
    local close=false
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Include
    overlap.FilterDescendantsInstances={target}
    for _,part in ipairs(source:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            local probe=part:Clone()
            probe.Size=part.Size+Vector3.one*0.016
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
    -- A manually selected RIGID weld may attach an ordinary shaft or
    -- cylinder to the exterior of a drilled-hole housing. The shaft need
    -- not be coaxial with or inserted into the hole. A flush face should
    -- not be rejected because the narrow collision query missed it.
    -- An explicit weld still requires closely adjoining solid bounds:
    -- distant objects cannot be connected through this action.
    if not close then close=stillTouching(source,target,0.03) end
    if not close then
        return false,"Rigid weld requires adjoining surfaces; shaft-to-hole fitting is only for motion joints"
    end
    -- A rigid weld must not sit alongside an already-authored motion joint
    -- between the same bodies; remove the old relationship deliberately.
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId then
            local a=relation:GetAttribute("SourceId")
            local b=relation:GetAttribute("TargetId")
            if (a==source:GetAttribute("InstanceId") and b==target:GetAttribute("InstanceId"))
                or (a==target:GetAttribute("InstanceId") and b==source:GetAttribute("InstanceId")) then
                return false,"Remove the existing relationship before rigid welding"
            end
        end
    end
    return true
end

function Mechanical:CreateWeld(player,request)
    request.kind="Weld"
    local source,target,reason=validEndpoints(self,player,request)
    if not source then return false,reason end
    local valid,why=weldPairValid(self,player,source,target)
    if not valid then return false,why end
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

-- Batch rigid fabrication for Edit's Shift-selected geometry. Build a
-- connected spanning tree: only genuine touching / inserted neighbors
-- become welds. Validate the whole plan before creating any relationship.
-- A disconnected selection is rejected rather than silently half-welded.
function Mechanical:CreateMultiWeld(player,request)
    local ids=request and request.ids
    if type(ids)~="table" or #ids<2 or #ids>32 then
        return false,"Select 2–32 primitives to multi-weld"
    end
    local models,seen={},{}
    for _,id in ipairs(ids) do
        if type(id)~="string" or #id==0 or #id>64 or seen[id] then
            return false,"Multi-weld needs distinct owned primitives"
        end
        seen[id]=true
        local model=self.D.findOwned(player,id)
        if not model or not model.PrimaryPart
            or not self.D.nearPlayer(player,model:GetPivot().Position) then
            return false,"Multi-weld selection has an unavailable part"
        end
        if HandCrankMath.IsCrank(model) then
            return false,"Use the dedicated hand-crank coupling for crank parts"
        end
        table.insert(models,model)
    end
    local linked={[1]=true}
    local count=1
    local planned={}
    local function existingWeld(a,b)
        local aid=a:GetAttribute("InstanceId")
        local bid=b:GetAttribute("InstanceId")
        for _,rel in ipairs(self.Folder:GetChildren()) do
            if rel:GetAttribute("OwnerUserId")==player.UserId
                and (rel:GetAttribute("Kind")=="Weld"
                    or rel:GetAttribute("Kind")=="Fixed") then
                local x=rel:GetAttribute("SourceId")
                local y=rel:GetAttribute("TargetId")
                if (x==aid and y==bid) or (x==bid and y==aid) then
                    return true
                end
            end
        end
        return false
    end
    while count<#models do
        local found=false
        for i=1,#models do
            if not linked[i] then continue end
            for j=1,#models do
                if linked[j] then continue end
                local a,b=models[i],models[j]
                local already=existingWeld(a,b)
                local valid=already
                if not valid then valid=weldPairValid(self,player,a,b) end
                if valid then
                    linked[j]=true
                    count+=1
                    if not already then
                        table.insert(planned,{
                            relationId=HttpService:GenerateGUID(false),
                            ownerUserId=player.UserId,kind="Weld",
                            sourceId=a:GetAttribute("InstanceId"),
                            targetId=b:GetAttribute("InstanceId"),
                            componentId=a:GetAttribute("ComponentId"),
                        })
                    end
                    found=true
                    break
                end
            end
            if found then break end
        end
        if not found then
            return false,"Selected parts are disconnected; place each solid against a selected neighbor"
        end
    end
    if #planned==0 then return false,"These parts are already rigidly welded" end
    local completed={}
    for _,spec in ipairs(planned) do
        local ok,reason=self:Restore(player,spec)
        if not ok then
            for _,id in ipairs(completed) do
                self:DestroyRelation(self:OwnedRelation(player,id))
            end
            return false,reason or "Multi-weld validation failed"
        end
        table.insert(completed,spec.relationId)
    end
    self.D.commitAssembly(player,{}, {},planned)
    return true,string.format("Multi-welded %d parts with %d rigid connections",
        #models,#planned)
end

-- A REGISTERED component is an explicit group of primitives, not a
-- physical weld. This Mechanics command makes the entire group one rigid
-- body with a minimum spanning tree of real WeldConstraints. Unlike Edit's
-- Shift+K multi-weld, it intentionally permits separated component members:
-- the user registered them into ONE component and explicitly requested it.
-- Existing internal rigid paths are reused, never duplicated.
function Mechanical:WeldComponent(player,request)
    local cid=request and request.componentId
    if type(cid)~="string" or #cid==0 or #cid>64 then
        return false,"Select a registered component to weld"
    end
    local members,why=self.D.components:RequireMembers(player,cid)
    if not members then return false,why end
    local parent={}
    local byId={}
    for i,model in ipairs(members) do
        if not model.PrimaryPart or not self.D.nearPlayer(player,
            model:GetPivot().Position) then
            return false,"A component member is unavailable or outside build range"
        end
        if HandCrankMath.IsCrank(model) then
            return false,"Hand cranks require their dedicated shaft coupling"
        end
        parent[i]=i
        byId[model:GetAttribute("InstanceId")]=i
    end
    local function root(i)
        while parent[i]~=i do
            parent[i]=parent[parent[i]]
            i=parent[i]
        end
        return i
    end
    local function join(a,b)
        local ra,rb=root(a),root(b)
        if ra==rb then return false end
        parent[rb]=ra
        return true
    end
    for _,rel in ipairs(self.Folder:GetChildren()) do
        if rel:GetAttribute("OwnerUserId")~=player.UserId then continue end
        local a=byId[rel:GetAttribute("SourceId")]
        local b=byId[rel:GetAttribute("TargetId")]
        local kind=rel:GetAttribute("Kind")
        if a and b then
            if kind=="Weld" or kind=="Fixed" or kind=="Bolt" then
                join(a,b)
            else
                return false,"Component contains an internal "..tostring(kind)
                    .." joint; remove it before rigid welding"
            end
        end
        if kind=="Bolt" and a then
            local third=byId[rel:GetAttribute("SecondTargetId")]
            if third then join(a,third) end
        end
    end
    local planned={}
    while true do
        local bestA,bestB,bestDistance=nil,nil,math.huge
        for i,a in ipairs(members) do
            for j,b in ipairs(members) do
                if i==j or root(i)==root(j) then continue end
                local shaft=if Alignment.IsShaft(a) then a
                    elseif Alignment.IsShaft(b) then b else nil
                local hub=if shaft==a then b else a
                local hubKind=type(hub:GetAttribute("GearTeeth"))=="number"
                    or BeltMath.IsPulley(hub)
                local valid=not (shaft and hubKind)
                    or Smart.HubFits(shaft,hub)
                if valid then
                    local dist=(a:GetPivot().Position-b:GetPivot().Position).Magnitude
                    if dist<bestDistance then
                        bestA,bestB,bestDistance=i,j,dist
                    end
                end
            end
        end
        if not bestA then break end
        table.insert(planned,{
            relationId=HttpService:GenerateGUID(false),
            ownerUserId=player.UserId,
            kind="Weld",
            sourceId=members[bestA]:GetAttribute("InstanceId"),
            targetId=members[bestB]:GetAttribute("InstanceId"),
            componentId=cid,
        })
        join(bestA,bestB)
    end
    local initial=root(1)
    for i=2,#members do
        if root(i)~=initial then
            return false,"Cannot safely weld this component: gear/shaft geometry conflicts"
        end
    end
    if #planned==0 then
        return true,"All "..#members.." component primitives are already rigidly connected"
    end
    local created={}
    for _,spec in ipairs(planned) do
        local ok,detail=self:Restore(player,spec)
        if not ok then
            for _,id in ipairs(created) do
                local relation=self:OwnedRelation(player,id)
                if relation then self:DestroyRelation(relation) end
            end
            return false,"Component weld aborted: "..tostring(detail)
        end
        table.insert(created,spec.relationId)
    end
    -- One history record for ALL welds; undo restores the original free parts.
    self.D.commitAssembly(player,{},{},planned)
    return true,string.format("Smart welded %d component primitives (%d new welds)",
        #members,#planned)
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
    -- Select from ALL registered fasteners, preferring the five new precision
    -- bolts but retaining legacy IDs for old saves and disabled Mesh APIs.
    local thickness0=math.abs(axis0.X)*first.PrimaryPart.Size.X
        +math.abs(axis0.Y)*first.PrimaryPart.Size.Y
        +math.abs(axis0.Z)*first.PrimaryPart.Size.Z
    local thickness1=math.abs(axis1.X)*second.PrimaryPart.Size.X
        +math.abs(axis1.Y)*second.PrimaryPart.Size.Y
        +math.abs(axis1.Z)*second.PrimaryPart.Size.Z
    local minimumReach=math.abs(distance)
        +thickness0*0.5+thickness1*0.5+self.D.Grid.Unit*0.1
    local bestId,bestDiameter,bestLen,bestNew=nil,nil,nil,false
    for _,entry in ipairs(self.D.Registry.List()) do
        local model=entry.Model
        if model:GetAttribute("PrimitiveFamily")=="Bolt" then
            local diameterU=model:GetAttribute("BoltDiameterU")
            local lengthU=model:GetAttribute("BoltLengthU")
            if type(diameterU)=="number" and type(lengthU)=="number"
                and diameterU>0 and lengthU>0 then
                local diameter=diameterU*self.D.Grid.Unit
                local length=lengthU*self.D.Grid.Unit
                local precision=model:GetAttribute("StaticDataModelMesh")==true
                if diameter<=math.min(hole0,hole1)-0.002
                    and length>=minimumReach
                    and (bestDiameter==nil
                        or (precision and not bestNew)
                        or (precision==bestNew and diameter>bestDiameter)) then
                    bestId=entry.Id
                    bestDiameter=diameter
                    bestLen=length
                    bestNew=precision
                end
            end
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
    -- Put the head OUTSIDE the entry face, rather than at the midpoint
    -- between two holes (which previously buried it inside solid metal).
    local origin=cf0.Position-direction*(thickness0*0.5+0.005)
        +direction*(bestLen*0.5)
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
    if not BoltMath.Fits(bolt,first) or not BoltMath.Fits(bolt,second) then
        bolt:Destroy()
        if #before>0 then self.D.applyState(first,before[1]) end
        return false,"Bolt does not fully pass through both openings"
    end
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
        -- The bolt is the source of BOTH welds: fastening two plates to
        -- each other without the physical bolt was a dangling-body bug.
        sourceId=bolt:GetAttribute("InstanceId"),
        targetId=first:GetAttribute("InstanceId"),
        secondTargetId=second:GetAttribute("InstanceId"),
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
    local compatible,reason=GearMath.AutoMeshStatus(first,second)
    if not compatible then
        return false,reason or "Gear teeth are not in a valid mesh"
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
    local linear=relation and (relation:GetAttribute("Kind")=="Slider"
        or relation:GetAttribute("Kind")=="Cylindrical")
    local minOffset,maxOffset=if linear
        then Alignment.OffsetBounds(source,target)
        else Alignment.InsertionBounds(source,target)
    if not minOffset or offset<minOffset or offset>maxOffset then
        return false,string.format(
            "Insertion must stay between %.1f and %.1f U",
            minOffset or 0,maxOffset or 0)
    end
    -- Physical hinges may include several separately built bores.
    -- Collect every authored contact so moving the pin cannot silently
    -- pull it out of another connected hinge lug.
    local authoredOpenings={}
    for _,edge in ipairs(self.Folder:GetChildren()) do
        if edge:GetAttribute("OwnerUserId")==player.UserId
            and edge:GetAttribute("SourceId")==request.sourceId
            and (edge:GetAttribute("Kind")=="Bearing"
                or edge:GetAttribute("Kind")=="Slider"
                or edge:GetAttribute("Kind")=="Cylindrical") then
            local hole=d.findOwned(player,edge:GetAttribute("TargetId"))
            if hole then table.insert(authoredOpenings,hole) end
        end
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
    for _,hole in ipairs(authoredOpenings) do
        if not MultiFit.Check(source,hole) then
            for i,restore in ipairs(members) do d.applyState(restore,before[i]) end
            return false,"Insertion would pull the pin out of another connected hole"
        end
    end
    local all={}
    for _,candidate in ipairs(d.folder:GetChildren()) do
        if candidate:IsA("Model")
            and candidate:GetAttribute("OwnerUserId")==player.UserId
            and not ignored[candidate] then table.insert(all,candidate) end
    end
    local stations=MultiFit.StationarySet({source},target,all)
    local candidates=MultiFit.Find({source},stations)
    local verified=candidates and MultiFit.Unique(candidates,
        request.sourceId,request.targetId) or {}
    local fitMap=MultiFit.AllowMap(verified)
    for _,member in ipairs(members) do
        if d.intersectsConstructed(member,ignored,target,
            request.sourceId,fitMap) then
            for i,restore in ipairs(members) do d.applyState(restore,before[i]) end
            return false,"Pose interferes with a hinge lug or another solid"
        end
    end
    if relation then
        relation:SetAttribute("OffsetUnits", offset)
        relation:SetAttribute("RollDegrees", roll)
    end
    d.commitBatch(player,before,planned,true)
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
        local min,max=Alignment.RelativeTravelBounds(source,target)
        if not min then return false,max end
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
    if spec.kind=="Rope" then
        local source=self.D.findOwned(player,spec.sourceId)
        local target=self.D.findOwned(player,spec.targetId)
        if not source or not target then return false,"Rope endpoints are missing" end
        local p0,p1=RopeMath.Frames(source,target)
        local settings,why=RopeMath.Settings(spec,(p1-p0).Magnitude)
        if not settings then return false,why end
        RopeMath.Write(relation,settings)
        local rope=relation:FindFirstChildOfClass("RopeConstraint")
        if rope then
            rope.Length=settings.ropeLength
            rope.WinchTarget=settings.ropeLength
            rope.WinchSpeed=settings.ropeSpeedU*self.D.Grid.Unit
            rope.WinchForce=settings.ropeForce
        end
        return true
    end
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
    if spec.kind=="Bearing" then
        relation:SetAttribute("MotorEnabled",spec.motorEnabled==true)
        relation:SetAttribute("MotorKey",spec.motorKey)
        relation:SetAttribute("MotorSpeed",spec.motorSpeed)
        relation:SetAttribute("MotorTorque",spec.motorTorque)
        relation:SetAttribute("MotorAcceleration",spec.motorAcceleration)
        relation:SetAttribute("MotorDriveType",spec.motorDriveType or "Continuous")
        relation:SetAttribute("MotorInputMode",spec.motorInputMode or "Hold")
        relation:SetAttribute("MotorTargetAngle",spec.motorTargetAngle or 90)
    end
    local constraint = relation:FindFirstChildWhichIsA("Constraint")
    if constraint then
        constraint.LimitsEnabled = spec.limitsEnabled == true
        if spec.kind == "Bearing" then
            constraint.LowerAngle = spec.lowerLimit or -180
            constraint.UpperAngle = spec.upperLimit or 180
            -- Undo/redo must not reactivate the obsolete housing-side
            -- authored hinge actuator. The runtime motor is shaft-only.
            constraint.ActuatorType=Enum.ActuatorType.None
            constraint.AngularVelocity=0
            constraint.TargetAngle=0
            constraint.AngularSpeed=math.abs(spec.motorSpeed or 3)
            constraint.ServoMaxTorque=math.clamp(spec.motorTorque or 3000,1,100000)
            constraint.MotorMaxTorque=math.clamp(spec.motorTorque or 3000,1,100000)
            constraint.MotorMaxAcceleration=math.clamp(
                spec.motorAcceleration or 40,0.1,1000)
        elseif spec.kind == "Slider" or spec.kind == "Cylindrical" then
            local source=self.D.findOwned(player,spec.sourceId)
            local target=self.D.findOwned(player,spec.targetId)
            if source and target then
                local lo,hi=Alignment.RelativeTravelBounds(source,target)
                if lo and hi then
                    local authoredLow=spec.lowerLimit
                    local authoredHigh=spec.upperLimit
                    local lower=math.max(lo,if type(authoredLow)=="number"
                        then authoredLow else lo)
                    local upper=math.min(hi,if type(authoredHigh)=="number"
                        then authoredHigh else hi)
                    if lower<upper then
                        constraint.LimitsEnabled=true
                        constraint.LowerLimit=lower*self.D.Grid.Unit
                        constraint.UpperLimit=upper*self.D.Grid.Unit
                    end
                end
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

    -- A fitted pin must respect the SMALLEST of all its through-bores,
    -- not only the hole chosen when opening the micro-fit controls.
    local all={}
    for _,candidate in ipairs(d.folder:GetChildren()) do
        if candidate:IsA("Model")
            and candidate:GetAttribute("OwnerUserId")==player.UserId
            and candidate~=source then table.insert(all,candidate) end
    end
    local stations=MultiFit.StationarySet({source},target,all)
    local matched,why=MultiFit.Find({source},stations)
    local contacts=matched and MultiFit.Unique(matched,
        request.sourceId,request.targetId) or {}
    if not MultiFit.Contains(contacts,request.sourceId,request.targetId) then
        return false,why or "Primary shaft/hole fit has come apart"
    end
    local maxDiameter=math.huge
    for _,pair in ipairs(contacts) do
        local cap,reason=Bore.MaxShaftDiameter(source,pair.hole)
        if not cap then return false,reason end
        maxDiameter=math.min(maxDiameter,cap)
    end

    local current = source.PrimaryPart.Size
    local stepU = d.Grid.FitDiameterStepU
    local oldDiameterU = current.Y / d.Grid.Unit
    -- Diameter is uniform in Y/Z; X is never altered by fitting.
    local nextTicks = math.round(oldDiameterU / stepU) + request.step
    local nextDiameter = nextTicks * stepU * d.Grid.Unit
    if nextDiameter < d.Grid.MinSizeStepU*d.Grid.Unit-1e-6 then
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
    local fits,fitReason=Bore.ShaftFits(source,target)
    local stillEngaged=true
    local approved={}
    for _,pair in ipairs(contacts) do
        local verified=MultiFit.Check(source,pair.hole)
        if not verified then
            stillEngaged=false
            break
        end
        table.insert(approved,verified)
    end
    local fitMap=MultiFit.AllowMap(approved)
    if not fits or not stillEngaged or d.intersectsConstructed(
        source,source,target,request.sourceId,fitMap
    ) then
        d.applyState(source,before)
        return false,fitReason or "Shaft must fit every connected opening"
    end

    local crankBefore,crankAfter,crankReason=
        self:ResizeCoupledCranks(player,source)
    if not crankBefore then
        d.applyState(source,before)
        return false,crankReason or "Coupled hand crank could not be resized"
    end

    local after = d.snapshot(source)
    if #crankBefore>0 then
        local previous={before}
        local nextStates={after}
        for index,old in ipairs(crankBefore) do
            table.insert(previous,old)
            table.insert(nextStates,crankAfter[index])
        end
        d.commitBatch(player,previous,nextStates,true)
    else
        d.commitRecord(player, before, after,true)
    end
    return true,string.format(
        "Shaft %.2f U diameter • %.2f U clearance • %d fitted hole(s)",
        nextDiameter/d.Grid.Unit,
        math.max(0,(maxDiameter-nextDiameter)/d.Grid.Unit),
        #contacts)
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


-- Resizing must never silently create an impossible mechanical joint.
-- Preserve the relation and geometry on failure; a move may disconnect it
-- according to the independent geometric contact rule below.
function Mechanical:ValidateResize(player,changedId)
    if type(changedId)~="string" then return false,"Invalid resized primitive" end
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if relation:IsA("Folder")
            and relation:GetAttribute("OwnerUserId")==player.UserId
            and (relation:GetAttribute("SourceId")==changedId
                or relation:GetAttribute("TargetId")==changedId) then
            local kind=relation:GetAttribute("Kind")
            if kind=="Bearing" or kind=="Slider" or kind=="Cylindrical"
                or kind=="VectorJoint" then
                local source=self.D.findOwned(player,relation:GetAttribute("SourceId"))
                local target=self.D.findOwned(player,relation:GetAttribute("TargetId"))
                local valid=false
                if source and target then
                    if kind=="VectorJoint" then
                        valid=VectorJoint.Measure(source,target)~=nil
                    else
                        valid=MultiFit.Check(source,target)~=nil
                    end
                end
                if not valid then
                    return false,"Resize would invalidate "..kind
                        .." connection; adjust the part or fitting first"
                end
            end
        end
    end
    return true
end

-- Conservative geometry overlap used ONLY to decide whether an already
-- authenticated relationship remains physically adjacent after editing.
-- It never creates a new relationship. A world-space SAT-lite test in both
-- local frames detects face-touch while tolerating tiny CSG seam gaps.

-- A normal construction transform must not keep invisible joints spanning
-- independently moved geometry. Springs and ropes are exempt: stretching
-- a spring is an ordinary operation, not an authoring error.
-- Both endpoints may move together ONLY under the same rigid world delta.
-- Collect snapshots before removing constraints so undo restores every joint.
function Mechanical:DisconnectMoved(player,beforeStates,afterStates,exemptRelations)
    local beforeById,afterById={},{}
    for _,state in ipairs(beforeStates) do
        if state then beforeById[state.instanceId]=state end
    end
    for _,state in ipairs(afterStates) do
        if state then afterById[state.instanceId]=state end
    end
    local function pose(state)
        local rotation=if typeof(state.orientation)=="CFrame"
            then state.orientation.Rotation else self.D.Grid.Rotation(state.steps)
        return CFrame.new(state.position)*rotation
    end
    local function matching(a,b)
        return (a.Position-b.Position).Magnitude<0.001
            and a.RightVector:Dot(b.RightVector)>0.99999
            and a.UpVector:Dot(b.UpVector)>0.99999
    end
    local moved={}
    for id,old in pairs(beforeById) do
        local nextState=afterById[id]
        if nextState then
            local a,b=pose(old),pose(nextState)
            local resized=(old.size-nextState.size).Magnitude>0.0001
            local pureResize=resized
                and a.RightVector:Dot(b.RightVector)>0.99999
                and a.UpVector:Dot(b.UpVector)>0.99999
                and (a.Position-b.Position).Magnitude
                    <=(old.size-nextState.size).Magnitude*0.51+0.003
            -- A scale-grip resize is not a joint-breaking movement. The
            -- opposite face can stay put while the center shifts by half
            -- the dimension change, so testing center equality is wrong.
            if not pureResize and not matching(a,b) then
                moved[id]={delta=b*a:Inverse(),resized=false}
            end
        end
    end
    if next(moved)==nil then return {} end

    local disconnected={}
    for _,relation in ipairs(self.Folder:GetChildren()) do
        if not relation:IsA("Folder")
            or relation:GetAttribute("OwnerUserId")~=player.UserId
            or relation:GetAttribute("Kind")=="Spring"
            or relation:GetAttribute("Kind")=="Rope"
            or (exemptRelations and exemptRelations[relation:GetAttribute("RelationId")])
            then continue end
        local ids={}
        local used={}
        for _,key in ipairs({"SourceId","TargetId","BoltId","SecondTargetId"}) do
            local id=relation:GetAttribute(key)
            if type(id)=="string" and id~="" and not used[id] then
                used[id]=true
                table.insert(ids,id)
            end
        end
        -- A belt may change its tension as a pulley moves; unlike a rigid
        -- joint, a valid re-routed belt must survive independent movement.
        if relation:GetAttribute("Kind")=="Belt" then
            local a=self.D.findOwned(player,relation:GetAttribute("SourceId"))
            local b=self.D.findOwned(player,relation:GetAttribute("TargetId"))
            if a and b and BeltMath.Path(a,b) then continue end
        end
        local changed=false
        local common=nil
        local keep=true
        for _,id in ipairs(ids) do
            local motion=moved[id]
            if motion then
                changed=true
                if common and not matching(common,motion.delta) then
                    keep=false
                end
                common=common or motion.delta
            else
                keep=false
            end
        end
        if changed and not keep then
            -- A one-sided edit only disconnects once the geometry is no
            -- longer physically engaged. Sliding a shaft inside its bore,
            -- or sliding a joined panel along a touching face, is allowed.
            local source=self.D.findOwned(player,
                relation:GetAttribute("SourceId"))
            local target=self.D.findOwned(player,
                relation:GetAttribute("TargetId"))
            local kind=relation:GetAttribute("Kind")
            local engaged=false
            if source and target then
                if kind=="VectorJoint" then
                    engaged=VectorJoint.Measure(source,target)~=nil
                elseif kind=="Bearing" or kind=="Slider"
                    or kind=="Cylindrical" then
                    engaged=MultiFit.Check(source,target)~=nil
                elseif kind=="Fixed" or kind=="Weld" or kind=="Bolt" then
                    engaged=stillTouching(source,target)
                        or (Alignment.IsShaft(source) and
                            Bore.ShaftFits(source,target)==true)
                        or (Alignment.IsShaft(target) and
                            Bore.ShaftFits(target,source)==true)
                    local secondId=relation:GetAttribute("SecondTargetId")
                    if kind=="Bolt" and type(secondId)=="string" then
                        local other=self.D.findOwned(player,secondId)
                        engaged=engaged and other~=nil
                            and stillTouching(source,other)
                    end
                end
            end
            if engaged then continue end
            local spec=self:Snapshot(relation)
            table.insert(disconnected,spec)
            self:DestroyRelation(relation)
            -- Dropping a bearing/slider also removes its old insertion
            -- metadata. Otherwise the next ordinary shaft move can remain
            -- trapped by an opening it is no longer mechanically joined to.
            if spec.kind=="Bearing" or spec.kind=="Slider"
                or spec.kind=="Cylindrical" then
                local source=self.D.findOwned(player,spec.sourceId)
                if source and source:GetAttribute("AlignedOpeningId")==spec.targetId then
                    if not beforeById[spec.sourceId] then
                        local old=self.D.snapshot(source)
                        table.insert(beforeStates,old)
                        beforeById[spec.sourceId]=old
                    end
                    source:SetAttribute("AlignedOpeningId",nil)
                    source:SetAttribute("AlignedOffsetU",0)
                    source:SetAttribute("ShaftRollDegrees",0)
                    local state=afterById[spec.sourceId]
                    if state then
                        state.alignedOpeningId=nil
                        state.alignedOffsetU=0
                        state.shaftRollDegrees=0
                    else
                        local updated=self.D.snapshot(source)
                        table.insert(afterStates,updated)
                        afterById[spec.sourceId]=updated
                    end
                end
            end
        end
    end
    -- Belt endpoints can remain perfectly coplanar even after a moved shaft
    -- DISCONNECTS from its pulley. Validate again AFTER all rigid joints
    -- have been detached. Otherwise a visually intact but unpowered belt
    -- could poison a saved mechanism or make simulation compilation fail.
    local function mountedShaft(pulley)
        if not pulley then return nil end
        local pulleyId=pulley:GetAttribute("InstanceId")
        for _,rel in ipairs(self.Folder:GetChildren()) do
            if rel:GetAttribute("OwnerUserId")==player.UserId
                and (rel:GetAttribute("Kind")=="Weld"
                    or rel:GetAttribute("Kind")=="Fixed") then
                local a,b=rel:GetAttribute("SourceId"),rel:GetAttribute("TargetId")
                local otherId=if a==pulleyId then b
                    elseif b==pulleyId then a else nil
                local shaft=otherId and self.D.findOwned(player,otherId)
                if shaft and Alignment.IsShaft(shaft)
                    and Smart.HubFits(pulley,shaft) then
                    return otherId
                end
            end
        end
        return nil
    end
    for _,rel in ipairs(self.Folder:GetChildren()) do
        if rel:IsA("Folder") and rel:GetAttribute("Kind")=="Belt"
            and rel:GetAttribute("OwnerUserId")==player.UserId
            and not (exemptRelations and exemptRelations[rel:GetAttribute("RelationId")]) then
            local a=self.D.findOwned(player,rel:GetAttribute("SourceId"))
            local b=self.D.findOwned(player,rel:GetAttribute("TargetId"))
            local path=a and b and BeltMath.Path(a,b)
            local rest=rel:GetAttribute("BeltRestLength")
            local ma=mountedShaft(a)
            local mb=mountedShaft(b)
            local valid=path and type(rest)=="number" and rest>0
                and rest<=300 and rest<=path.Length*1.3
                and rest>=path.Length*0.7
                and ma~=nil and mb~=nil and ma~=mb
            if not valid then
                table.insert(disconnected,self:Snapshot(rel))
                self:DestroyRelation(rel)
            end
        end
    end
    return disconnected
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
    local detached=record.disconnected or {}
    if #detached>0 and not record.removed then
        -- Smart-mate can relocate an existing body while creating a NEW
        -- relationship. Track both sets in one reversible transaction:
        -- undo removes the new joint and restores the detached old ones.
        local remove=if undo then specs else detached
        local restore=if undo then detached else specs
        for _,spec in ipairs(remove) do
            local relation=self:OwnedRelation(player,spec.relationId)
            if relation then self:DestroyRelation(relation) end
        end
        local moved,why=restoreBatch(player,record,undo)
        if not moved then
            for _,spec in ipairs(remove) do self:Restore(player,spec) end
            return false,why
        end
        local completed={}
        for _,spec in ipairs(restore) do
            local ok,reason=self:Restore(player,spec)
            if not ok then
                for _,id in ipairs(completed) do
                    local restored=self:OwnedRelation(player,id)
                    if restored then self:DestroyRelation(restored) end
                end
                restoreBatch(player,record,not undo)
                for _,prior in ipairs(remove) do self:Restore(player,prior) end
                return false,reason
            end
            table.insert(completed,spec.relationId)
        end
        applyEdits(undo)
        return true
    end
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
                elseif spec.kind=="VectorJoint" then
                    VectorJoint.RefreshHardware(relation,source,target)
                elseif spec.kind=="Belt" then
                    BeltVisual.Refresh(relation,BeltMath.Path(source,target))
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
