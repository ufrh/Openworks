--!strict
-- OPENWORKS contextual, drag-first placement. Shared by preview and server.
-- Compatible sockets and gear centers are recognized from physical geometry,
-- not a two-click relationship selection or a compulsory world grid.
local Alignment = require(script.Parent:WaitForChild("AlignmentMath"))
local GearMath = require(script.Parent:WaitForChild("GearMath"))
local Bore = require(script.Parent:WaitForChild("BoreClearance"))
local HandCrankMath = require(script.Parent:WaitForChild("HandCrankMath"))
local Grid = require(script.Parent:WaitForChild("GridMath"))
local MultiFit = require(script.Parent:WaitForChild("MultiFitMath"))
local Smart = {}
Smart.SnapDistance = 2.0 -- unchanged for general hole/gear-to-gear snapping
Smart.HubSnapRadius = 0.34 -- studs from the REAL bore/shaft axis, not gear bounds
Smart.HubAimRadius = 0.24 -- small crosshair tolerance through an empty bore
Smart.HubAxialReach = 0.65 -- axial approach tolerance, excluding shaft overlap
Smart.GearPitchCapture = 0.7 -- radial proximity to the true mesh pitch circle
Smart.GearFaceCapture = 0.55 -- transient cursor distance from axial gear plane
Smart.BevelCapture = 0.85 -- near the proper 45-degree pitch-cone apex
Smart.RackCapture = 0.65 -- near actual straight toothed pitch line
Smart.MaxAxialOffsetUnits = 64
Smart.PreviewInterval = 0.08

local function gear(model)
    return model and type(model:GetAttribute("GearTeeth")) == "number"
end
local function rack(model)
    return GearMath.Kind(model)=="Rack"
end
local function guide(model)
    return GearMath.Kind(model)=="RackGuide"
end

function Smart.Members(ghost: Model)
    local members = {}
    if ghost.PrimaryPart then
        table.insert(members, ghost)
    else
        for _, child in ipairs(ghost:GetChildren()) do
            if child:IsA("Model") and child.PrimaryPart then
                table.insert(members, child)
            end
        end
    end
    return members
end

function Smart.GearPose(source: Model, target: Model, near: Vector3)
    if not gear(source) or not gear(target) then return nil end
    if GearMath.Kind(source)=="Bevel45"
        or GearMath.Kind(target)=="Bevel45" then
        return Smart.BevelPose(source,target,near)
    end
    local moduleA, moduleB = source:GetAttribute("GearModuleStuds"),
        target:GetAttribute("GearModuleStuds")
    if type(moduleA) ~= "number" or type(moduleB) ~= "number"
        or math.abs(moduleA-moduleB) > 0.0001 then return nil end
    local targetCF=target:GetPivot()
    local normal=targetCF.RightVector
    local diff=near-targetCF.Position
    local depth=diff:Dot(normal)
    local radial=diff-normal*depth
    local pitch=(source:GetAttribute("GearTeeth")
        +target:GetAttribute("GearTeeth"))*moduleA/(2*math.pi)
    -- Never attract a gear simply because the ghost is within a huge
    -- radius of another gear. Capture around the TRUE mesh circumference,
    -- NOT the gear's bore and NOT a 2-stud sphere around its center.
    local overlap=(source.PrimaryPart.Size.X+target.PrimaryPart.Size.X)*0.5
    if math.abs(radial.Magnitude-pitch)>Smart.GearPitchCapture
        or math.abs(depth)>overlap+Smart.GearFaceCapture then
        return nil
    end
    local direction=if radial.Magnitude>0.001
        then radial.Unit else targetCF.UpVector
    local center=targetCF.Position+direction*pitch
    -- Phase the teeth so an approaching tooth faces its partner's gap.
    -- With equal tooth pitch, the contact phases sum to half a tooth.
    -- This is a visual/geometric mating approximation, not an involute
    -- profile solver or passive torque transmission guarantee.
    local tangentZ=targetCF:VectorToWorldSpace(Vector3.zAxis)
    local angle=math.atan2(direction:Dot(tangentZ),direction:Dot(targetCF.UpVector))
    local targetPitch=2*math.pi/target:GetAttribute("GearTeeth")
    local sourcePitch=2*math.pi/source:GetAttribute("GearTeeth")
    local targetPhase=(angle/targetPitch)%1
    local sourcePhase=(0.5-targetPhase)%1
    local desiredPhase=(angle+math.pi)-sourcePhase*sourcePitch
    local phase=((desiredPhase+sourcePitch*0.5)%sourcePitch)-sourcePitch*0.5
    local rotation=CFrame.fromAxisAngle(normal,phase)*targetCF.Rotation
    -- Match face planes by default. A valid pitch-circle placement is
    -- always physically meshed when the player confirms it.
    return CFrame.new(center)*rotation,
        math.abs(radial.Magnitude-pitch)+math.abs(depth)
end

-- Place an equal-tooth bevel at the intersection of two pitch
-- cones, where the shaft directions meet at 45 degrees. The direction
-- around the fixed shaft is selected by approaching with the cursor;
-- the cone apex position and exact shaft angle are never guessed.
function Smart.BevelPose(source:Model,target:Model,near:Vector3)
    if GearMath.Kind(source)~="Bevel45"
        or GearMath.Kind(target)~="Bevel45" then return nil end
    if source:GetAttribute("GearTeeth")~=target:GetAttribute("GearTeeth")
        or math.abs((source:GetAttribute("GearModuleStuds") or -1)
            -(target:GetAttribute("GearModuleStuds") or -2))>0.0001 then
        return nil
    end
    local fixed=target:GetPivot()
    local xaxis=fixed.RightVector.Unit
    local apex=GearMath.BevelApex(target)
    local diff=near-apex
    local lateral=diff-xaxis*diff:Dot(xaxis)
    local side=if lateral.Magnitude>0.001
        then lateral.Unit else fixed.UpVector
    local angle=math.rad(45)
    local newAxis=xaxis*math.cos(angle)+side*math.sin(angle)
    local radius=GearMath.PitchRadius(source)
    local center=apex+newAxis*radius/math.tan(math.rad(22.5))
    if (center-near).Magnitude>Smart.BevelCapture
        +radius*0.75 then return nil end
    local up=side-newAxis*side:Dot(newAxis)
    if up.Magnitude<0.001 then up=fixed.UpVector end
    up=up.Unit
    local pose=CFrame.fromMatrix(center,newAxis,up,newAxis:Cross(up))
    return pose,(center-near).Magnitude
end

-- A rack slides along its own long axis. For Rack->Pinion we keep the
-- rack's pitch surface facing the pinion; for Pinion->Rack we place the
-- pinion over the rack's actual pitch line. Both are reversible in the
-- simulation solver once physically positioned.
function Smart.RackPose(source:Model,target:Model,near:Vector3)
    local kindSource,kindTarget=GearMath.Kind(source),GearMath.Kind(target)
    if not ((kindSource=="Rack" and kindTarget=="Spur")
        or (kindSource=="Spur" and kindTarget=="Rack")) then
        return nil
    end
    local rackBody=if kindSource=="Rack" then source else target
    local pinion=if kindSource=="Spur" then source else target
    if math.abs((rackBody:GetAttribute("RackPitchStuds") or -1)
        -(pinion:GetAttribute("GearModuleStuds") or -2))>0.0001 then
        return nil
    end
    local radius=GearMath.PitchRadius(pinion)
    local offset=rackBody:GetAttribute("RackPitchOffsetStuds")
    local length=rackBody:GetAttribute("RackLengthStuds")
    if type(offset)~="number" or type(length)~="number" then return nil end
    local pose
    if kindTarget=="Rack" then
        local cf=target:GetPivot()
        local along=(near-cf.Position):Dot(cf.LookVector)
        local maxAlong=math.max(0,length*0.5
            -(rackBody:GetAttribute("RackPitchStuds") or 0)*2)
        along=math.clamp(along,-maxAlong,maxAlong)
        local center=cf.Position+cf.UpVector*(radius+offset)
            +cf.LookVector*along
        pose=CFrame.fromMatrix(center,cf.RightVector,cf.UpVector,
            cf.RightVector:Cross(cf.UpVector))
    else
        local cf=target:GetPivot()
        local axis=cf.RightVector.Unit
        local direction=cf.Position-near
        direction-=axis*direction:Dot(axis)
        local up=if direction.Magnitude>0.001
            then direction.Unit else cf.UpVector
        local back=axis:Cross(up)
        local center=cf.Position-up*(radius+offset)
        pose=CFrame.fromMatrix(center,axis,up,back)
    end
    if (pose.Position-near).Magnitude>
        math.max(Smart.RackCapture,radius*0.65+Smart.RackCapture) then
        return nil
    end
    return pose,(pose.Position-near).Magnitude
end

-- The guide is an independent grounded part. Snapping to the
-- rack aligns its construction geometry without creating an implicit
-- weld or fake PrismaticConstraint.
function Smart.GuidePose(source:Model,target:Model,near:Vector3)
    local sourceKind=GearMath.Kind(source)
    local targetKind=GearMath.Kind(target)
    if not ((sourceKind=="Rack" and targetKind=="RackGuide")
        or (sourceKind=="RackGuide" and targetKind=="Rack")) then
        return nil
    end
    local rackBody=if sourceKind=="Rack" then source else target
    local guideBody=if sourceKind=="RackGuide" then source else target
    local rackLength=rackBody:GetAttribute("RackLengthStuds")
    local guideLength=guideBody:GetAttribute("RackGuideLengthStuds")
    if type(rackLength)~="number" or type(guideLength)~="number"
        or rackLength>guideLength-0.25 then return nil end
    local cf=target:GetPivot()
    local pose
    if sourceKind=="Rack" then
        local maxTravel=(guideLength-rackLength)*0.5
        local travel=(near-cf.Position):Dot(cf.LookVector)
        pose=CFrame.new(cf.Position
            +cf.LookVector*math.clamp(travel,-maxTravel,maxTravel))
            *cf.Rotation
    else
        -- Guide origin centers on the exact rack lane; it is bigger
        -- than the rack and permits future translation in either way.
        pose=cf
    end
    if (pose.Position-near).Magnitude>1.4 then return nil end
    return pose,(pose.Position-near).Magnitude
end

-- Solve the intersection of TWO pitch circles when the moving gear
-- can simultaneously engage two stationary gears. This is an ordinary
-- geometry problem, not a hardcoded 3-gear relationship. Repeated gear
-- placements can build arbitrary branched graphs and reversible chains.
function Smart.MultiGearPose(source:Model,target:Model,near:Vector3,
    options:{Model}?):(CFrame?,number?,number)
    local base,baseError=Smart.GearPose(source,target,near)
    if not base then return nil,nil,0 end
    if GearMath.Kind(source)~="Spur"
        or GearMath.Kind(target)~="Spur" then
        return base,baseError,1
    end
    if not options or not source.PrimaryPart then return base,baseError,1 end
    local first=target:GetPivot()
    local axis=first.RightVector.Unit
    local sourceTeeth=source:GetAttribute("GearTeeth")
    local module=source:GetAttribute("GearModuleStuds")
    local r1=(sourceTeeth+target:GetAttribute("GearTeeth"))
        *module/(2*math.pi)
    local bestPose,bestError,bestCount=base,baseError,1
    local bestDistance=math.huge
    for _,other in ipairs(options) do
        if other==target or other==source or not gear(other)
            or not other.PrimaryPart or not other.Parent then continue end
        local otherModule=other:GetAttribute("GearModuleStuds")
        if type(otherModule)~="number"
            or math.abs(otherModule-module)>0.0001 then continue end
        local cf=other:GetPivot()
        if math.abs(axis:Dot(cf.RightVector))<0.999 then continue end
        local axial=math.abs((cf.Position-first.Position):Dot(axis))
        local thickness=(source.PrimaryPart.Size.X+other.PrimaryPart.Size.X)*0.5
            -math.max(0.012,math.min(source.PrimaryPart.Size.X,
                other.PrimaryPart.Size.X)*0.07)
        if axial>=thickness then continue end
        local r2=(sourceTeeth+other:GetAttribute("GearTeeth"))
            *module/(2*math.pi)
        local vector=cf.Position-first.Position
        local planar=vector-axis*vector:Dot(axis)
        local distance=planar.Magnitude
        if distance<0.0001 or distance>r1+r2+0.0001
            or distance<math.abs(r1-r2)-0.0001 then continue end
        local direction=planar/distance
        local along=(r1*r1-r2*r2+distance*distance)/(2*distance)
        local height2=r1*r1-along*along
        if height2< -0.0001 then continue end
        local perp=axis:Cross(direction).Unit
        local height=math.sqrt(math.max(0,height2))
        for _,sign in ipairs({-1,1}) do
            local candidate=first.Position+direction*along
                +perp*(height*sign)
            local capture=(candidate-near).Magnitude
            if capture>Smart.GearPitchCapture*1.65 then continue end
            local posed,err=Smart.GearPose(source,target,candidate)
            if posed then
                local delta=posed.Position-cf.Position
                local side=(delta-axis*delta:Dot(axis)).Magnitude
                if math.abs(side-r2)<=0.04
                    and capture<bestDistance then
                    bestDistance=capture
                    bestPose=posed
                    bestError=err
                    bestCount=2
                end
            end
        end
    end
    return bestPose,bestError,bestCount
end

-- Gear bores are real open centers. Dragging a gear onto a shaft (or
-- vice versa) aligns the hub; the user must explicitly choose a free
-- rotational hinge or a rigid weld before the mount is committed.
function Smart.HubFits(source: Model, target: Model)
    local gearBody=if gear(source) then source else if gear(target) then target else nil
    local shaft=if Alignment.IsShaft(source) then source
        else if Alignment.IsShaft(target) then target else nil
    if not gearBody or not shaft or not shaft.PrimaryPart then
        return false,"Hub requires one gear and one cylindrical shaft"
    end
    -- A gear hub is truly concentric, not merely somewhere within
    -- its clearance cavity. Keep a precise centered mount (including
    -- both polarities of shaft insertion) so the simulated hinge axis
    -- cannot be offset from the actual rotating gear center.
    local gcf,scf=gearBody:GetPivot(),shaft:GetPivot()
    local direction=scf.RightVector.Unit
    local separation=gcf.Position-scf.Position
    local eccentricity=(separation-direction*separation:Dot(direction)).Magnitude
    if eccentricity>0.012 then
        return false,"Gear hub must be centered on the shaft axis"
    end
    -- One authoritative clearance predicate for gears, tubes and holes.
    -- Also checks shaft diameter, coaxial orientation and engagement.
    return Bore.ShaftFits(shaft,gearBody)
end

function Smart.HubPose(source: Model, target: Model, near: Vector3)
    if not ((gear(source) and Alignment.IsShaft(target))
        or (Alignment.IsShaft(source) and gear(target))) then return nil end
    local shaft=if Alignment.IsShaft(source) then source else target
    local gearBody=if gear(source) then source else target
    local bore=gearBody:GetAttribute("BoreRadiusStuds")
    if type(bore)~="number" or bore<=0 then return nil end
    local diameter=math.max(shaft.PrimaryPart.Size.Y,shaft.PrimaryPart.Size.Z)
    if diameter+0.004>bore*2 then return nil end

    -- Snap to the ACTUAL axial center of the stationary target. With
    -- moving gear, the target is a shaft and can be long; with moving
    -- shaft, the target is a gear's non-colliding bore pivot. Neither
    -- case should use the outer gear radius as a magnetic hitbox.
    local fixed=target:GetPivot()
    local axis=fixed.RightVector.Unit
    local delta=near-fixed.Position
    local depth=delta:Dot(axis)
    local radial=(delta-axis*depth).Magnitude
    local thickness=gearBody.PrimaryPart.Size.X
    local length=shaft.PrimaryPart.Size.X
    local maxTravel=math.max(0,(length+thickness)*0.5-0.035)
    if radial>Smart.HubSnapRadius or
        math.abs(depth)>maxTravel+Smart.HubAxialReach then
        return nil
    end
    local maxUnits=math.min(Smart.MaxAxialOffsetUnits,
        math.floor(maxTravel/(Grid.Unit*0.5))*0.5)
    local offset=math.clamp(math.round(depth/(Grid.Unit*0.5))*0.5,
        -maxUnits,maxUnits)
    -- Actual final center is always on the stationary axis. This is
    -- valid in both directions and preserves the chosen insertion depth.
    local center=fixed.Position+axis*offset*Grid.Unit
    return CFrame.new(center)*fixed.Rotation,
        radial+math.abs(depth)*0.12,offset
end

local function socketPlan(members, shaft, target, forcedByAim)
    local axis=Alignment.TargetAxis(target)
    if not axis then return nil end
    local targetCF=target:GetPivot()
    local worldAxis=targetCF:VectorToWorldSpace(axis)
    local delta=shaft:GetPivot().Position-targetCF.Position
    local depth=delta:Dot(worldAxis)
    local radial=(delta-worldAxis*depth).Magnitude
    local reach=math.max(0.65,
        math.min(1.6,target.PrimaryPart.Size.Magnitude*0.58))
    if (radial>reach+0.65 or math.abs(depth)>math.max(2.5,
        target.PrimaryPart.Size.Magnitude+1.5)) and not forcedByAim then
        return nil
    end
    -- A ray passing through an empty drilled hole can hit something far
    -- behind it. Aim recognition still centers the shaft in THAT hole.
    if forcedByAim and (radial>reach+0.65
        or math.abs(depth)>math.max(2.5,
            target.PrimaryPart.Size.Magnitude+1.5)) then
        depth=0
    end
    local low,high=Alignment.OffsetBounds(shaft,target)
    if not low then return nil end
    local units=math.clamp(math.round(depth/(Grid.Unit*0.5))*0.5,
        low,high)
    local roll=shaft:GetAttribute("ShaftRollDegrees") or 0
    local plan=Alignment.Plan(members,shaft,target,units,roll)
    if not plan then return nil end
    return plan,units,roll,radial+math.abs(depth)*0.12
end

local function reverseSocketPlan(members, opening, shaft, forcedByAim)
    local shaftCF=shaft:GetPivot()
    local holeCF=opening:GetPivot()
    local shaftAxis=shaftCF.RightVector
    local holeAxis=holeCF:VectorToWorldSpace(
        Alignment.TargetAxis(opening)
    )
    local axis=if holeAxis:Dot(shaftAxis)>=0 then shaftAxis
        else -shaftAxis
    local delta=holeCF.Position-shaftCF.Position
    local axial=delta:Dot(axis)
    local radial=(delta-axis*axial).Magnitude
    local reach=math.max(0.65,math.min(1.6,
        opening.PrimaryPart.Size.Magnitude*0.58))
    if (radial>reach+0.65 or math.abs(axial)>math.max(
        2.5,opening.PrimaryPart.Size.Magnitude+1.5)) and not forcedByAim then
        return nil
    end
    if forcedByAim and (radial>reach+0.65 or
        math.abs(axial)>math.max(2.5,
            opening.PrimaryPart.Size.Magnitude+1.5)) then
        axial=0
    end
    local low,high=Alignment.OffsetBounds(shaft,opening)
    if not low then return nil end
    local units=math.clamp(math.round((-axial)/(Grid.Unit*0.5))*0.5,
        low,high)
    local roll=shaft:GetAttribute("ShaftRollDegrees") or 0
    local plan=Alignment.ReversePlan(members,opening,shaft,units,roll)
    if not plan then return nil end
    return plan,units,roll,radial+math.abs(axial)*0.12
end

local function aimDistance(ray, worldPosition)
    if not ray then return math.huge end
    local direction=ray.Direction.Unit
    local delta=worldPosition-ray.Origin
    local along=delta:Dot(direction)
    if along<=0 or along>Grid.MaxDistance then return math.huge end
    return (delta-direction*along).Magnitude
end

-- Aim at the middle of the physical gear bore, not its tooth/rim bounds.
-- For an already placed long shaft, aim anywhere along its actual axis.
local function hubAimDistance(ray,target)
    if not ray or not target.PrimaryPart then return math.huge end
    if gear(target) then return aimDistance(ray,target:GetPivot().Position) end
    if not Alignment.IsShaft(target) then return math.huge end
    local cf=target:GetPivot()
    local half=target.PrimaryPart.Size.X*0.5
    local best=math.huge
    -- Minimize distance from the camera ray to the FINITE shaft segment.
    -- A tiny sample set is enough to find the visible insertion location;
    -- this is selection assistance only, never the final fit predicate.
    for i=0,8 do
        local position=cf.Position+cf.RightVector*((i/8*2-1)*half)
        best=math.min(best,aimDistance(ray,position))
    end
    return best
end

-- A single coaxial fit leaves free rotation about its axis. For a plate
-- with several holes, solve that remaining roll geometrically using the
-- spacing between OTHER compatible shafts and holes. No prefab patterns:
-- this works with arbitrary player-built groups and arbitrary orientations.
local function bestBoreRoll(ghost,members,source,target,reverse,
    offset,roll,baseCF,allTargets,ignored)
    if #members<2 or #allTargets<2 then return baseCF,roll end
    local pivot=ghost:GetPivot()
    local baseDelta=baseCF*pivot:Inverse()
    local primary=(baseDelta*source:GetPivot()).Position
    local fixed=target:GetPivot().Position
    -- A reversed housing may face opposite the fixed shaft. Rotate in
    -- the MOVING opening's aligned axial direction, exactly as
    -- Alignment.ReversePlan does, or the inferred roll sign flips.
    local alignedSource=baseDelta*source:GetPivot()
    local axis=if reverse then alignedSource:VectorToWorldSpace(
        Alignment.TargetAxis(source)).Unit
        else alignedSource.RightVector.Unit
    local candidates={roll}
    local used={}
    local function addAngle(theta)
        local suggestion=roll+math.deg(theta)
        if suggestion < -360 or suggestion > 360 then return end
        local key=math.round(suggestion*10)
        if not used[key] and #candidates<25 then
            used[key]=true
            table.insert(candidates,suggestion)
        end
    end
    for _,member in ipairs(members) do
        if member==source then continue end
        local validMoving=if reverse
            then Alignment.TargetAxis(member)~=nil
            else Alignment.IsShaft(member)
        if not validMoving then continue end
        local radial=(baseDelta*member:GetPivot()).Position-primary
        radial-=axis*radial:Dot(axis)
        if radial.Magnitude<Grid.Unit*0.5 then continue end
        for _,stationary in ipairs(allTargets) do
            if stationary==target or (ignored and ignored[stationary])
                then continue end
            local validTarget=if reverse
                then Alignment.IsShaft(stationary)
                else Alignment.TargetAxis(stationary)~=nil
            if not validTarget then continue end
            local direction=if reverse then stationary:GetPivot().RightVector
                else stationary:GetPivot():VectorToWorldSpace(
                    Alignment.TargetAxis(stationary))
            if math.abs(direction:Dot(axis))<0.997 then continue end
            local destination=stationary:GetPivot().Position-fixed
            destination-=axis*destination:Dot(axis)
            if destination.Magnitude<Grid.Unit*0.5
                or math.abs(destination.Magnitude-radial.Magnitude)
                    >Grid.Unit*0.25 then continue end
            addAngle(math.atan2(
                axis:Dot(radial:Cross(destination)),
                radial:Dot(destination)))
        end
    end
    local bestCF,bestRoll,bestCount=baseCF,roll,0
    local bestError,bestChange=math.huge,math.huge
    for _,candidate in ipairs(candidates) do
        local plan=if reverse then Alignment.ReversePlan(
            members,source,target,offset,candidate)
            else Alignment.Plan(members,source,target,offset,candidate)
        if plan then
            local nextCF=plan.delta*pivot
            local contacts=MultiFit.Find(members,allTargets,
                nextCF*pivot:Inverse(),ignored)
            if contacts then
                local unique=MultiFit.Unique(contacts,
                    source:GetAttribute("InstanceId"),
                    target:GetAttribute("InstanceId"))
                local count=#unique
                local error=0
                for _,pair in ipairs(unique) do
                    error+=pair.radial*pair.radial
                        +math.max(0,1-(pair.angular or 1))*0.04
                end
                local change=math.abs(candidate-roll)
                if count>bestCount
                    or (count==bestCount and
                        (error<bestError-0.0000001
                            or (math.abs(error-bestError)<0.0000001
                                and change<bestChange))) then
                    bestCF,bestRoll,bestCount=nextCF,candidate,count
                    bestError,bestChange=error,change
                end
            end
        end
    end
    return bestCF,bestRoll
end

-- caller has positioned ghost at unsnapped world pose. Targets must be
-- the caller's owned construction. Aim ray is optional and allows
-- recognition THROUGH empty holes and behind other nested geometry.
function Smart.Find(ghost: Model, targets: {Model}, ignored, preferred: Model?, aimRay,
    allTargets: {Model}?, aimedModel: Model?)

    local members=Smart.Members(ghost)
    if #members==0 then return nil end
    -- Cache welded/editor-group scope per scan to avoid redundant network
    -- traversals for every one of four holes and four fixed shafts.
    local scopedCache={}
    local function scoped(target)
        if scopedCache[target] then return scopedCache[target] end
        local group=MultiFit.Scope(target,allTargets or targets)
        for _,member in ipairs(group) do scopedCache[member]=group end
        return group
    end
    local best,bestScore=nil,math.huge
    local matches={}
    for _,source in ipairs(members) do
        local isShaft=Alignment.IsShaft(source)
        local isGear=gear(source)
        local isRack=rack(source)
        local isGuide=guide(source)
        local isOpening=Alignment.TargetAxis(source)~=nil
        if not isShaft and not isGear and not isRack
            and not isGuide and not isOpening then continue end
        for _,target in ipairs(targets) do
            if not target or not target.Parent or not target.PrimaryPart
                or (ignored and ignored[target]) then continue end
            if source:GetAttribute("InstanceId") ~= nil
                and source:GetAttribute("InstanceId")==target:GetAttribute("InstanceId")
                then continue end
            local sourceComponent=source:GetAttribute("ComponentId")
            if type(sourceComponent)=="string" and sourceComponent~=""
                and sourceComponent==target:GetAttribute("ComponentId") then
                -- Interior editing must never magnetize a member onto
                -- another member of its OWN already-rigid component.
                continue
            end
            local rayError=aimDistance(aimRay,target:GetPivot().Position)
            local aimReach=math.clamp(target.PrimaryPart.Size.Magnitude*0.38,0.48,1.5)
            local aimed=rayError<=aimReach
            local kind,cf,offset,roll,score,approach
            if HandCrankMath.IsCrank(source)
                and HandCrankMath.IsOutputShaft(target) then
                local pose,dist=HandCrankMath.Snap(source,target)
                if pose and (dist<Smart.SnapDistance+1.0 or aimed) then
                    kind="CrankCoupling"
                    cf=(pose*source:GetPivot():Inverse())*ghost:GetPivot()
                    score=if aimed then rayError+0.04 else dist
                end
            elseif (isGear and Alignment.IsShaft(target))
                or (isShaft and gear(target)) then
                -- A broad aim on the rim or tooth must never magnetize
                -- into the hub. Only a tight ray near the actual gear bore
                -- (or a visibly aimed shaft segment) can override proximity.
                local boreAim=hubAimDistance(aimRay,target)
                local hubAimed=boreAim<=Smart.HubAimRadius
                local near=source:GetPivot().Position
                if hubAimed then
                    local stationary=target:GetPivot()
                    local delta=near-stationary.Position
                    local axial=delta:Dot(stationary.RightVector)
                    local radial=(delta-stationary.RightVector*axial).Magnitude
                    if radial>Smart.HubSnapRadius then
                        -- An intentional center aim lets a shaft reach a
                        -- NON-COLLIDING gear opening even if the world's
                        -- surface hit snapped the ghost against its rim.
                        near=stationary.Position
                            +stationary.RightVector*math.clamp(axial,
                                -Smart.HubAxialReach,Smart.HubAxialReach)
                    end
                end
                local pose,dist,u=Smart.HubPose(source,target,near)
                if pose then
                    kind="Hub"
                    cf=(pose*source:GetPivot():Inverse())*ghost:GetPivot()
                    approach=pose.Position
                    offset=u
                    score=if hubAimed then boreAim*0.25+0.015
                        else dist+0.2
                end
            elseif isOpening and Alignment.IsShaft(target) then
                local plan,u,r,dist=reverseSocketPlan(
                    members,source,target,aimed
                )
                if plan then
                    kind="Bore"
                    cf=plan.delta*ghost:GetPivot()
                    offset=u
                    roll=r
                    score=if aimed then math.min(dist,rayError+0.12) else dist
                    approach=source:GetPivot().Position
                end
            elseif isShaft and Alignment.TargetAxis(target) then
                local plan,u,r,dist=socketPlan(members,source,target,aimed)
                if plan then
                    kind="Bore"
                    cf=plan.delta*ghost:GetPivot()
                    offset=u
                    roll=r
                    score=if aimed then math.min(dist,rayError+0.12) else dist
                end
            elseif (isRack and guide(target))
                or (isGuide and rack(target)) then
                approach=source:GetPivot().Position
                local pose,dist=Smart.GuidePose(source,target,approach)
                if pose then
                    kind="Guide"
                    cf=(pose*source:GetPivot():Inverse())*ghost:GetPivot()
                    approach=pose.Position
                    score=if aimedModel==target then -0.2 else dist+0.1
                end
            elseif (isRack and GearMath.Kind(target)=="Spur")
                or (isGear and GearMath.Kind(source)=="Spur"
                    and rack(target)) then
                local directAim=aimedModel==target
                approach=source:GetPivot().Position
                local pose,dist=Smart.RackPose(source,target,approach)
                if pose then
                    kind="Rack"
                    cf=(pose*source:GetPivot():Inverse())*ghost:GetPivot()
                    approach=pose.Position
                    score=if directAim then -0.15 else dist+0.12
                end
            elseif isGear and gear(target) then
                local directAim=aimedModel==target
                approach=source:GetPivot().Position
                if directAim and GearMath.Kind(source)=="Spur"
                    and GearMath.Kind(target)=="Spur" then
                    -- The ray often strikes a TOOTH, not the transparent
                    -- center pivot. Surface-placement may therefore push
                    -- the moving gear away from its ideal pitch ring.
                    -- A deliberate tooth hit still chooses the direction;
                    -- it never snaps through the hub/center hitbox.
                    local fixed=target:GetPivot()
                    local delta=approach-fixed.Position
                    local axial=delta:Dot(fixed.RightVector)
                    local radial=delta-fixed.RightVector*axial
                    if radial.Magnitude<0.01 then
                        radial=fixed.UpVector
                    end
                    local pitch=(source:GetAttribute("GearTeeth")
                        +target:GetAttribute("GearTeeth"))
                        *source:GetAttribute("GearModuleStuds")/(2*math.pi)
                    approach=fixed.Position+radial.Unit*pitch
                end
                local pose,dist,meshes=Smart.MultiGearPose(
                    source,target,approach,allTargets or targets)
                if pose then
                    kind="Gear"
                    cf=(pose*source:GetPivot():Inverse())*ghost:GetPivot()
                    approach=pose.Position
                    -- An exact two-mesh pitch-circle intersection gets
                    -- preference without requiring the player to create
                    -- two separate permanent gear connections.
                    score=(if directAim then -0.15 else dist+0.2)
                        -math.max(0,meshes-1)*0.5
                end
            end
            if cf and kind=="Bore" and #members>1 then
                local chosenTargets=scoped(target)
                local initial=MultiFit.Find(members,chosenTargets,
                    cf*ghost:GetPivot():Inverse(),ignored)
                -- Solve the full pattern even if a partial 2/4 snap
                -- looks valid around the first guide. A two-point result
                -- is not sufficient when there are four expected holes.
                local eligible=0
                for _,member in ipairs(members) do
                    if (isOpening and Alignment.TargetAxis(member))
                        or (not isOpening and Alignment.IsShaft(member)) then
                        eligible+=1
                    end
                end
                local currentFits=initial and MultiFit.Unique(initial,
                    source:GetAttribute("InstanceId"),
                    target:GetAttribute("InstanceId")) or {}
                local completed=MultiFit.Completeness(
                    members,chosenTargets,currentFits,isOpening)
                if #currentFits<eligible or not completed then
                    cf,roll=bestBoreRoll(ghost,members,source,target,
                        isOpening,offset,roll,cf,chosenTargets,ignored)
                end
            end
            if cf then
                -- Evaluate the WHOLE moving component under the proposed pose:
                -- a 4-hole plate should score four valid fits, not one click.
                local fitted=nil
                if kind=="Bore" then
                    local delta=cf*ghost:GetPivot():Inverse()
                    local raw=MultiFit.Find(members,
                        scoped(target),
                        delta,ignored)
                    fitted=raw and MultiFit.Unique(raw,
                        source:GetAttribute("InstanceId"),
                        target:GetAttribute("InstanceId"))
                    if fitted and #fitted>1 then
                        -- Center the COMPLETE moving pattern on the complete
                        -- fixed pattern. Correct average lateral drift after
                        -- choosing the best rotation, not just corner #1.
                        local error=Vector3.zero
                        for _,pair in ipairs(fitted) do
                            local current=delta*pair.moving:GetPivot()
                            local gap=pair.stationary:GetPivot().Position
                                -current.Position
                            local axis=pair.axis
                            error+=gap-axis*gap:Dot(axis)
                        end
                        error/= #fitted
                        if error.Magnitude>0.00005 then
                            local candidateCF=CFrame.new(error)*cf
                            local checked=MultiFit.Find(members,
                                scoped(target),
                                candidateCF*ghost:GetPivot():Inverse(),ignored)
                            local refined=checked and MultiFit.Unique(checked,
                                source:GetAttribute("InstanceId"),
                                target:GetAttribute("InstanceId"))
                            if refined and #refined==#fitted then
                                cf=candidateCF
                                fitted=refined
                            end
                        end
                        score-=math.min(12,(#fitted-1)*2.5)
                    end
                end
                local candidate={kind=kind,target=target,source=source,
                    cf=cf,offsetUnits=offset or 0,rollDegrees=roll or 0,
                    relationKind=if kind=="Bore" then "Cylindrical"
                        elseif kind=="CrankCoupling" then "Weld"
                        elseif kind=="Hub" then "Rotation"
                        elseif kind=="Rack" then "Rack"
                        elseif kind=="Guide" then "Guide" else "Gear",
                    reverse=kind=="Bore" and isOpening,
                    approach=approach,score=score,
                    fittedCount=fitted and #fitted or 0}
                if target==preferred then
                    score-=if kind=="Gear" or kind=="Rack"
                        or kind=="Guide" then 0.08 else 1.5
                end
                candidate.score=score
                table.insert(matches,candidate)
                if score<bestScore then
                    bestScore=score
                    best=candidate
                end
            end
        end
    end
    table.sort(matches,function(a,b)
        return a.score<b.score
    end)
    return best,matches
end

function Smart.NearbyTargets(folder: Folder?, playerUserId: number,
    reference: Vector3, ignored, aimRay, extraReach,
    moving: Model?, aimedPart: Instance?)
    local targets={}
    if not folder then return targets end
    for _,model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and model.PrimaryPart
            and model:GetAttribute("OwnerUserId")==playerUserId
            and not (ignored and ignored[model]) then
            local size=model.PrimaryPart.Size.Magnitude
            local isGear=gear(model)
            local hubRay=hubAimDistance(aimRay,model)
            -- Do not use the large tooth bounds to pick a gear. Gears
            -- remain discoverable within a small central radius, even
            -- though their actual empty bores have no raycast hitbox.
            local range=if isGear then Smart.HubSnapRadius
                else Smart.SnapDistance+math.min(3,size)
                    +math.clamp(extraReach or 0,0,24)
            local aimThreshold=if isGear then Smart.HubAimRadius
                else math.clamp(size*0.38,0.48,1.5)
            local gearPlacement=false
            local movingGear=false
            local movingRack=false
            if moving then
                for _,member in ipairs(Smart.Members(moving)) do
                    if rack(member) then movingRack=true end
                    if isGear and gear(member) then
                        movingGear=true
                        local moduleA=member:GetAttribute("GearModuleStuds")
                        local moduleB=model:GetAttribute("GearModuleStuds")
                        if type(moduleA)=="number" and type(moduleB)=="number"
                            and math.abs(moduleA-moduleB)<0.0001 then
                            local axis=model:GetPivot().RightVector
                            local delta=reference-model:GetPivot().Position
                            local axial=math.abs(delta:Dot(axis))
                            local radial=(delta-axis*delta:Dot(axis)).Magnitude
                            local pitch=(member:GetAttribute("GearTeeth")
                                +model:GetAttribute("GearTeeth"))
                                *moduleA/(2*math.pi)
                            local face=(member.PrimaryPart.Size.X
                                +model.PrimaryPart.Size.X)*0.5
                            gearPlacement=gearPlacement
                                or (math.abs(radial-pitch)
                                    <=Smart.GearPitchCapture
                                    and axial<=face+Smart.GearFaceCapture)
                        end
                    end
                end
            end
            -- Directly hitting a solid gear tooth is a valid explicit
            -- target, even when the center pivot is non-queryable.
            local hitGear=isGear and (movingGear or movingRack)
                and aimedPart and aimedPart:IsDescendantOf(model)
            local hitRack=rack(model) and movingGear
                and aimedPart and aimedPart:IsDescendantOf(model)
            if gearPlacement or hitGear or hitRack
                or (model:GetPivot().Position-reference).Magnitude<=range
                or hubRay<=aimThreshold then
                table.insert(targets,model)
            end
        end
    end
    return targets
end

return table.freeze(Smart)
