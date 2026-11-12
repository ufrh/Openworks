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
local FitOrigin = require(script.Parent:WaitForChild("FitOrigin"))
local FitSolver = require(script.Parent:WaitForChild("FitSolver"))
local Smart = {}
Smart.SnapDistance = 2.0 -- unchanged for general hole/gear-to-gear snapping
Smart.HubSnapRadius = 0.34 -- studs from the REAL bore/shaft axis, not gear bounds
Smart.HubAimRadius = 0.24 -- small crosshair tolerance through an empty bore
Smart.HubAxialReach = 0.65 -- axial approach tolerance, excluding shaft overlap
Smart.GearPitchCapture = 0.7 -- radial proximity to the true mesh pitch circle
Smart.GearFaceCapture = 0.55 -- transient cursor distance from axial gear plane
Smart.BevelCapture = 0.85 -- near a matching 45°/90° pitch-cone apex
Smart.MaxAxialOffsetUnits = 64
Smart.PreviewInterval = 0.08

local function gear(model)
    return model and type(model:GetAttribute("GearTeeth")) == "number"
end

local function hub(model)
    return gear(model) or (model and model:GetAttribute("PrimitiveFamily")=="Pulley")
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
    local aKind,bKind=GearMath.Kind(source),GearMath.Kind(target)
    if aKind=="Bevel45" or aKind=="Bevel90"
        or bKind=="Bevel45" or bKind=="Bevel90" then
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

-- Place an equal-tooth bevel where its physical 45° or 90° pitch
-- cones intersect. The direction
-- around the fixed shaft is selected by approaching with the cursor;
-- the cone apex position and exact shaft angle are never guessed.
function Smart.BevelPose(source:Model,target:Model,near:Vector3)
    local kind=GearMath.Kind(source)
    if (kind~="Bevel45" and kind~="Bevel90")
        or GearMath.Kind(target)~=kind then return nil end
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
    local angle=math.rad(source:GetAttribute("BevelShaftAngleDeg") or 45)
    local cone=math.rad(source:GetAttribute("BevelConeDeg") or 22.5)
    local newAxis=xaxis*math.cos(angle)+side*math.sin(angle)
    local radius=GearMath.PitchRadius(source)
    local center=apex+newAxis*radius/math.tan(cone)
    if (center-near).Magnitude>Smart.BevelCapture
        +radius*0.75 then return nil end
    local up=side-newAxis*side:Dot(newAxis)
    if up.Magnitude<0.001 then up=fixed.UpVector end
    up=up.Unit
    local pose=CFrame.fromMatrix(center,newAxis,up,newAxis:Cross(up))
    return pose,(center-near).Magnitude
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

-- Gear bores are real open centers. Gear/shaft fits ALWAYS produce
-- rigid physical welds; shaft bearings remain the sole rotation joints.
function Smart.HubFits(source: Model, target: Model)
    local gearBody=if hub(source) then source else if hub(target) then target else nil
    local shaft=if Alignment.IsShaft(source) then source
        else if Alignment.IsShaft(target) then target else nil
    if not gearBody or not shaft or not shaft.PrimaryPart then
        return false,"Hub requires a gear/pulley and a cylindrical shaft"
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
        return false,"Pulley/gear hub must be centered on the shaft axis"
    end
    -- One authoritative clearance predicate for gears, tubes and holes.
    -- Also checks shaft diameter, coaxial orientation and engagement.
    return Bore.ShaftFits(shaft,gearBody)
end

function Smart.HubPose(source: Model, target: Model, near: Vector3)
    if not ((hub(source) and Alignment.IsShaft(target))
        or (Alignment.IsShaft(source) and hub(target))) then return nil end
    local shaft=if Alignment.IsShaft(source) then source else target
    local gearBody=if hub(source) then source else target
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
    -- A Cylinder can be used as a wheel, roller, or solid construction
    -- piece. It is a shaft candidate ONLY when its real diameter is
    -- smaller than the target's verifiable opening, with sufficient
    -- insertion length. Never magnetize oversized wheel geometry.
    if not Bore.CanInsert(shaft,target) then return nil end
    local axis=Alignment.TargetAxis(target)
    if not axis then return nil end
    local targetCF=target:GetPivot()
    local worldAxis=targetCF:VectorToWorldSpace(axis)
    local delta=shaft:GetPivot().Position-targetCF.Position
    local depth=delta:Dot(worldAxis)
    local radial=(delta-worldAxis*depth).Magnitude
    local reach=math.max(0.65,
        math.min(1.6,target.PrimaryPart.Size.Magnitude*0.58))
    -- A 10 U pin can be 5 U beyond a housing midpoint and still touch
    -- the bore. Capture should scale with the shaft's ACTUAL axial reach.
    local axialReach=math.max(2.5,
        target.PrimaryPart.Size.Magnitude+1.5,
        shaft.PrimaryPart.Size.X*0.5
            +target.PrimaryPart.Size.Magnitude*0.5+0.65)
    if (radial>reach+0.65 or math.abs(depth)>axialReach)
        and not forcedByAim then return nil end
    -- A ray passing through an empty drilled hole can hit something far
    -- behind it. Aim recognition still centers the shaft in THAT hole.
    if forcedByAim and (radial>reach+0.65
        or math.abs(depth)>axialReach) then
        depth=0
    end
    local low,high=Alignment.InsertionBounds(shaft,target)
    if not low then return nil end
    local snapped=math.round(depth/(Grid.Unit*0.5))*0.5
    -- Authored offsets must stay on the half-U lattice. The physical
    -- face-bound stops are continuous; clamping to them directly could
    -- create illegal fractional offsets for the alignment planner.
    local loSnap=math.ceil(low*2-1e-6)*0.5
    local hiSnap=math.floor(high*2+1e-6)*0.5
    if loSnap>hiSnap then return nil end
    local units=math.clamp(snapped,loSnap,hiSnap)
    local roll=shaft:GetAttribute("ShaftRollDegrees") or 0
    local plan=Alignment.Plan(members,shaft,target,units,roll)
    if not plan then return nil end
    return plan,units,roll,radial+math.abs(depth)*0.12
end

-- Finds the closest approach of the center camera ray to the FINITE
-- physical shaft segment. Returns an axial coordinate from the shaft's
-- midpoint, not the cursor's distance from the shaft's central pivot.
-- The ray can hit the cylindrical SIDE, a shaft END or an empty space
-- between neighbouring hinge leaves; all use the same projection.
local function shaftCursorDepth(ray,shaft)
    if not ray or not shaft or not shaft.PrimaryPart then
        return nil,math.huge
    end
    local shaftCF=shaft:GetPivot()
    local center=shaftCF.Position
    local axis=shaftCF.RightVector.Unit
    local halfLength=shaft.PrimaryPart.Size.X*0.5
    local direction=ray.Direction.Unit
    local relative=ray.Origin-center
    local parallel=direction:Dot(axis)
    local rayProjection=relative:Dot(direction)
    local shaftProjection=relative:Dot(axis)
    local denominator=1-parallel*parallel
    local depth,rayT
    if denominator>0.0001 then
        rayT=(parallel*shaftProjection-rayProjection)/denominator
        depth=shaftProjection+parallel*math.max(0,rayT)
    else
        -- Looking directly down the shaft axis is ambiguous: choose the
        -- VISIBLE near end rather than springing back to the midpoint.
        depth=if parallel>=0 then -halfLength else halfLength
    end
    depth=math.clamp(depth,-halfLength,halfLength)
    local nearest=center+axis*depth
    rayT=(nearest-ray.Origin):Dot(direction)
    if rayT<=0 or rayT>Grid.MaxDistance then
        return nil,math.huge
    end
    local error=(ray.Origin+direction*rayT-nearest).Magnitude
    return depth,error
end

local function reverseSocketPlan(members, opening, shaft, forcedByAim,
    mouseDepth,mouseError)
    if not Bore.CanInsert(shaft,opening) then return nil end
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
    local axialReach=math.max(2.5,
        opening.PrimaryPart.Size.Magnitude+1.5,
        shaft.PrimaryPart.Size.X*0.5
            +opening.PrimaryPart.Size.Magnitude*0.5+0.65)
    if (radial>reach+0.65 or math.abs(axial)>axialReach)
        and not forcedByAim then return nil end
    if forcedByAim and (radial>reach+0.65
        or math.abs(axial)>axialReach) then
        axial=0
    end
    -- For a MOVING drilled hole onto a FIXED shaft, use the actual
    -- crosshair position ALONG that shaft. The old behavior projected
    -- the moving ghost's center and repeatedly jumped to the midpoint.
    -- Never follow a ray pointing past the shaft or far outside its
    -- radius: only a genuine shaft aim overrides ordinary drag proximity.
    local cursorTolerance=math.clamp(
        math.max(shaft.PrimaryPart.Size.Y,shaft.PrimaryPart.Size.Z)*0.5+0.14,
        0.20,0.60)
    local cursorOnShaft=type(mouseDepth)=="number"
        and type(mouseError)=="number"
        and mouseError<=cursorTolerance
    if cursorOnShaft then
        axial=mouseDepth*shaftAxis:Dot(axis)
    end
    local low,high=Alignment.InsertionBounds(shaft,opening)
    if not low then return nil end
    local snapped=math.round((-axial)/(Grid.Unit*0.5))*0.5
    local loSnap=math.ceil(low*2-1e-6)*0.5
    local hiSnap=math.floor(high*2+1e-6)*0.5
    if loSnap>hiSnap then return nil end
    local units=math.clamp(snapped,loSnap,hiSnap)
    local roll=shaft:GetAttribute("ShaftRollDegrees") or 0
    local plan=Alignment.ReversePlan(members,opening,shaft,units,roll)
    if not plan then return nil end
    return plan,units,roll,
        if cursorOnShaft then mouseError+0.03
            else radial+math.abs(axial)*0.12
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
    -- Analytic closest ray/segment point, not 9 uneven sample points.
    -- The exact same cursor depth feeds reverse drilled-hole insertion.
    local _,distance=shaftCursorDepth(ray,target)
    return distance
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
    local pivotAnchor=FitOrigin.ComponentAnchor(members)
    for _,source in ipairs(members) do
        local isShaft=Alignment.IsShaft(source)
        local isGear=gear(source)
        local isHub=hub(source)
        local isOpening=Alignment.TargetAxis(source)~=nil
        -- A custom origin is a first-class fit feature on ANY primitive,
        -- even on solid blocks, plates and custom CSG geometry.
        local pivotSource=source==pivotAnchor
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
            local shaftMouseDepth,shaftMouseError
            if isOpening and Alignment.IsShaft(target) then
                shaftMouseDepth,shaftMouseError=shaftCursorDepth(aimRay,target)
                if shaftMouseDepth then rayError=shaftMouseError end
            end
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
            elseif (isHub and Alignment.IsShaft(target))
                or (isShaft and hub(target)) then
                -- A broad aim on the rim or tooth must never magnetize
                -- into the hub. Only a tight ray near the actual gear bore
                -- (or a visibly aimed shaft segment) can override proximity.
                local boreAim=hubAimDistance(aimRay,target)
                local hubAimed=boreAim<=Smart.HubAimRadius
                local near=source:GetPivot().Position
                if hubAimed then
                    local stationary=target:GetPivot()
                    if isHub and Alignment.IsShaft(target) then
                        -- Gears also have real bores: while dragging a
                        -- gear onto a long fixed shaft, preserve the
                        -- crosshair's axial location, not shaft midpoint.
                        local cursorDepth=shaftCursorDepth(aimRay,target)
                        if cursorDepth then
                            near=stationary.Position
                                +stationary.RightVector*cursorDepth
                        end
                    else
                        local delta=near-stationary.Position
                        local axial=delta:Dot(stationary.RightVector)
                        local radial=(delta-stationary.RightVector*axial).Magnitude
                        if radial>Smart.HubSnapRadius then
                            -- Shaft into an empty NON-COLLIDING gear bore.
                            near=stationary.Position
                                +stationary.RightVector*math.clamp(axial,
                                    -Smart.HubAxialReach,Smart.HubAxialReach)
                        end
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
                    members,source,target,aimed,
                    shaftMouseDepth,shaftMouseError
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
            elseif isGear and gear(target) then
                local directAim=aimedModel==target
                approach=source:GetPivot().Position
                local bevelKind=GearMath.Kind(source)
                if directAim and (bevelKind=="Bevel45"
                    or bevelKind=="Bevel90")
                    and GearMath.Kind(target)==bevelKind then
                    -- Aim anywhere on the actual target bevel teeth.
                    -- The cursor chooses the azimuth around its axle;
                    -- the correct 45° or 90° shaft angle and pitch-cone
                    -- apex are enforced automatically.
                    local fixed=target:GetPivot()
                    local axis=fixed.RightVector.Unit
                    local apex=GearMath.BevelApex(target)
                    local delta=approach-apex
                    local lateral=delta-axis*delta:Dot(axis)
                    local side=if lateral.Magnitude>0.001 then
                        lateral.Unit else fixed.UpVector
                    local theta=math.rad(
                        source:GetAttribute("BevelShaftAngleDeg") or 45)
                    local cone=math.rad(
                        source:GetAttribute("BevelConeDeg") or 22.5)
                    local outputAxis=axis*math.cos(theta)
                        +side*math.sin(theta)
                    approach=apex+outputAxis*GearMath.PitchRadius(source)
                        /math.tan(cone)
                elseif directAim and GearMath.Kind(source)=="Spur"
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
            if not cf and pivotSource then
                local pivot=FitSolver.PivotCandidate(
                    ghost,target,aimRay,aimedModel,allTargets or targets)
                if pivot then
                    kind="Pivot"
                    cf=pivot.cf
                    approach=pivot.approach
                    score=pivot.score
                end
            end
            if cf and kind=="Bore" and #members>1 then
                local delta=cf*ghost:GetPivot():Inverse()
                local chosenTargets=MultiFit.StationarySet(
                    members,target,allTargets or targets,delta,ignored)
                local initial=MultiFit.Find(members,chosenTargets,
                    delta,ignored)
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
                    local stations=MultiFit.StationarySet(
                        members,target,allTargets or targets,delta,ignored)
                    local raw=MultiFit.Find(members,
                        stations,delta,ignored)
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
                            local refinedDelta=candidateCF*ghost:GetPivot():Inverse()
                            local refinedStations=MultiFit.StationarySet(
                                members,target,allTargets or targets,
                                refinedDelta,ignored)
                            local checked=MultiFit.Find(members,
                                refinedStations,refinedDelta,ignored)
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
                        elseif kind=="Hub" then "Weld"
                        elseif kind=="Pivot" then "FitOnly"
                        else "Gear",
                    reverse=kind=="Bore" and isOpening,
                    approach=approach,score=score,
                    fittedCount=fitted and #fitted or 0}
                if target==preferred then
                    score-=if kind=="Gear" then 0.08 else 1.5
                end
                if kind=="Bore" and isOpening and aimedModel==target
                    and shaftMouseDepth~=nil then
                    -- Aim at this particular shaft outranks a sticky
                    -- previously hovered shaft across crowded builds.
                    score=-3+shaftMouseError*0.05
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
    -- Moving-component traits do not depend on the stationary candidate.
    -- Resolve them once, rather than walking every moving member for every
    -- object in the plot on every snap scan.
    local movingGearMembers={}
    if moving then
        for _,member in ipairs(Smart.Members(moving)) do
            if gear(member) then table.insert(movingGearMembers,member) end
        end
    end
    local hasMovingGear=#movingGearMembers>0
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
            local movingGear=hasMovingGear
            if isGear and movingGear then
                local moduleB=model:GetAttribute("GearModuleStuds")
                local targetCF=model:GetPivot()
                local axis=targetCF.RightVector
                local delta=reference-targetCF.Position
                local axial=math.abs(delta:Dot(axis))
                local radial=(delta-axis*delta:Dot(axis)).Magnitude
                for _,member in ipairs(movingGearMembers) do
                    local moduleA=member:GetAttribute("GearModuleStuds")
                    if type(moduleA)=="number" and type(moduleB)=="number"
                        and math.abs(moduleA-moduleB)<0.0001 then
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
            -- Directly hitting a solid gear tooth is a valid explicit
            -- target, even when the center pivot is non-queryable.
            local hitGear=isGear and movingGear
                and aimedPart and aimedPart:IsDescendantOf(model)
            if gearPlacement or hitGear
                or (model:GetPivot().Position-reference).Magnitude<=range
                or hubRay<=aimThreshold then
                table.insert(targets,model)
            end
        end
    end
    return targets
end

return table.freeze(Smart)
