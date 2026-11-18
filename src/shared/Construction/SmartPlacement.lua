--!strict
-- OPENWORKS contextual, drag-first placement. Shared by preview and server.
-- Compatible sockets and gear centers are recognized from physical geometry,
-- not a two-click relationship selection or a compulsory world grid.
local Alignment = require(script.Parent:WaitForChild("AlignmentMath"))
local GearMath = require(script.Parent:WaitForChild("GearMath"))
local BeltMath = require(script.Parent:WaitForChild("BeltMath"))
local FitOrigin = require(script.Parent:WaitForChild("FitOrigin"))
local FitSolver = require(script.Parent:WaitForChild("FitSolver"))
local Bore = require(script.Parent:WaitForChild("BoreClearance"))
local HandCrankMath = require(script.Parent:WaitForChild("HandCrankMath"))
local Grid = require(script.Parent:WaitForChild("GridMath"))
local MultiFit = require(script.Parent:WaitForChild("MultiFitMath"))
local QuartzFit = require(script.Parent:WaitForChild("QuartzPortFit"))
local BoreInsertion=require(script.Parent:WaitForChild("BoreInsertion"))
local Smart = {}
Smart.SnapDistance = 0.55 -- deliberately small general socket capture
Smart.HubSnapRadius = 0.14 -- studs from the REAL bore/shaft axis, not gear bounds
Smart.HubAimRadius = 0.10 -- small crosshair tolerance through an empty bore
Smart.HubAxialReach = 0.22 -- axial approach tolerance, excluding shaft overlap
Smart.GearPitchCapture = 0.24 -- radial proximity to the true mesh pitch circle
Smart.SpurSlots = 8 -- every 45 degrees about target gear axle
Smart.Bevel90AimRadius = 0.72 -- analytic target capture even through transparent hub
Smart.GearFaceCapture = 0.20 -- transient cursor distance from axial gear plane
Smart.BevelCapture = 0.32 -- free-position 45-degree bevel approach
Smart.Bevel90Slots = 8 -- fixed positions at 45-degree intervals around target axle
Smart.Bevel90Capture = 0.55 -- additional tolerance for discrete 90-degree slots
Smart.RackCapture = 0.24 -- near actual straight toothed pitch line
Smart.MaxAxialOffsetUnits = 64
Smart.PreviewInterval = 0.08

local function gear(model)
    return model and type(model:GetAttribute("GearTeeth")) == "number"
end
local function hub(model)
    return gear(model) or BeltMath.IsPulley(model)
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
    -- Ordinary spur gears use the same eight discrete local-Y/Z slots
    -- as 90-degree bevels. Dragging chooses the nearest of the cardinal
    -- and diagonal positions, not an arbitrary pitch-circle angle.
    local around=if radial.Magnitude>0.001 then radial else targetCF.UpVector
    local localZ=targetCF:VectorToWorldSpace(Vector3.zAxis)
    local azimuth=math.atan2(around:Dot(localZ),around:Dot(targetCF.UpVector))
    local slot=math.floor(azimuth/(2*math.pi/Smart.SpurSlots)+0.5)
        %Smart.SpurSlots
    local direction=(targetCF.UpVector*math.cos(slot*2*math.pi/Smart.SpurSlots)
        +localZ*math.sin(slot*2*math.pi/Smart.SpurSlots)).Unit
    local center=targetCF.Position+direction*pitch
    -- Phase the teeth so an approaching tooth faces its partner's gap.
    -- With equal tooth pitch, the contact phases sum to half a tooth.
    -- This is a visual/geometric mating approximation, not an involute
    -- profile solver or passive torque transmission guarantee.
    local tangentZ=targetCF:VectorToWorldSpace(Vector3.zAxis)
    local angle=math.atan2(direction:Dot(tangentZ),direction:Dot(targetCF.UpVector))
    local targetPitch=2*math.pi/target:GetAttribute("GearTeeth")
    local sourcePitch=2*math.pi/source:GetAttribute("GearTeeth")
    -- Both old (tooth on cardinal) and new (gap on cardinal) published
    -- profiles can coexist until the permanent mesh IDs are updated.
    -- Offset phase in *tooth pitches*, rather than deleting any teeth.
    local sourceShift=source:GetAttribute("GearToothPhaseFraction") or 0
    local targetShift=target:GetAttribute("GearToothPhaseFraction") or 0
    local targetPhase=(angle/targetPitch-targetShift)%1
    local sourcePhase=(0.5-targetPhase)%1
    local desiredPhase=(angle+math.pi)
        -(sourcePhase+sourceShift)*sourcePitch
    local phase=((desiredPhase+sourcePitch*0.5)%sourcePitch)-sourcePitch*0.5
    local rotation=CFrame.fromAxisAngle(normal,phase)*targetCF.Rotation
    -- Match face planes by default. A valid pitch-circle placement is
    -- always physically meshed when the player confirms it.
    return CFrame.new(center)*rotation,
        math.abs(radial.Magnitude-pitch)+math.abs(depth)
end

-- 90-degree bevel gears have exactly EIGHT allowable mating positions.
-- Quantize the cursor direction in the TARGET gear's LOCAL Y/Z plane:
-- cardinal and diagonal offsets, 45 degrees apart. This rotates naturally
-- with the target instead of relying on global world axes.
function Smart.Bevel90Side(target:Model,near:Vector3):Vector3
    local fixed=target:GetPivot()
    local axis=fixed.RightVector.Unit
    local offset=near-GearMath.BevelApex(target)
    local radial=offset-axis*offset:Dot(axis)
    local up=fixed.UpVector.Unit
    local z=fixed:VectorToWorldSpace(Vector3.zAxis).Unit
    local azimuth=if radial.Magnitude>0.0001
        then math.atan2(radial:Dot(z),radial:Dot(up)) else 0
    local slot=math.floor(azimuth/(2*math.pi/Smart.Bevel90Slots)+0.5)
        %Smart.Bevel90Slots
    local theta=slot*2*math.pi/Smart.Bevel90Slots
    return (up*math.cos(theta)+z*math.sin(theta)).Unit
end

-- Bevel45 remains continuously positionable. Bevel90 may only use one
-- of the eight discrete local slots. Both use exactly shared apexes and
-- tooth phase correction; client ghost and server validation use this
-- same pose function so confirmation cannot drift to a free angle.
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
    local is90=kind=="Bevel90"
    local side=if is90 then Smart.Bevel90Side(target,near)
        elseif lateral.Magnitude>0.001 then lateral.Unit
        else fixed.UpVector
    local angle=math.rad(source:GetAttribute("BevelShaftAngleDeg") or 45)
    local cone=math.rad(source:GetAttribute("BevelConeDeg") or 22.5)
    local newAxis=if is90 then side
        else xaxis*math.cos(angle)+side*math.sin(angle)
    local radius=GearMath.PitchRadius(source)
    local center=apex+newAxis*radius/math.tan(cone)
    local capture=if is90 then Smart.Bevel90Capture+radius
        else Smart.BevelCapture+radius*0.75
    if (center-near).Magnitude>capture then return nil end
    -- For 90 degrees, side and shaft axis are the SAME vector. The old
    -- continuous solver projected side onto its own axis, yielding zero,
    -- then sometimes used a NON-perpendicular up vector (bad CFrame).
    -- Fixed X is exactly orthogonal to all eight slots.
    local up=if is90 then xaxis
        else side-newAxis*side:Dot(newAxis)
    if up.Magnitude<0.001 then up=xaxis end
    up=up.Unit
    local pose=CFrame.fromMatrix(center,newAxis,up,newAxis:Cross(up))
    -- Seat the moving bevel's tooth tips between the fixed teeth at
    -- placement. Runtime phase-lock maintains this half-tooth offset as
    -- the two shafts spin; no part rotation is scripted during simulation.
    local phaseError=GearMath.ToothPhaseError(source,target,pose)
    if phaseError then
        local teeth=source:GetAttribute("GearTeeth")
        local phase=phaseError*2*math.pi/teeth
        local corrected=CFrame.fromAxisAngle(newAxis,phase)*pose.Rotation
        pose=CFrame.new(center)*corrected
    end
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

-- Gear and pulley bores are real open centers. Dragging either hub onto
-- a shaft (or vice versa) aligns the geometry. Hubs always weld rigidly
-- to the shaft; the shaft's bearing determines rotational freedom.
function Smart.HubFits(source: Model, target: Model)
    local gearBody=if hub(source) then source else if hub(target) then target else nil
    local shaft=if Alignment.IsShaft(source) then source
        else if Alignment.IsShaft(target) then target else nil
    if not gearBody or not shaft or not shaft.PrimaryPart then
        return false,"Hub requires one gear/pulley and one cylindrical shaft"
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
        return false,"Gear/pulley hub must be centered on the shaft axis"
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
    -- A solid default 1U Cylinder is slightly wider than the standard
    -- 0.98U drilled opening. Detect geometry first and, only when the
    -- player aims near a compatible hole, offer an automatic fine fit.
    -- This also works for a single existing independent cylinder in Edit;
    -- the server separately validates and persists its diameter change.
    local axis=Alignment.TargetAxis(target)
    if not axis then return nil end
    local targetCF=target:GetPivot()
    local worldAxis=targetCF:VectorToWorldSpace(axis)
    local delta=shaft:GetPivot().Position-targetCF.Position
    local depth=delta:Dot(worldAxis)
    local radial=(delta-worldAxis*depth).Magnitude
    local reach=math.clamp(target.PrimaryPart.Size.Magnitude*0.18,0.12,0.5)
    -- A 10 U pin can be 5 U beyond a housing midpoint and still touch
    -- the bore. Capture should scale with the shaft's ACTUAL axial reach.
    local axialReach=math.max(0.2,
        shaft.PrimaryPart.Size.X*0.5
            +target.PrimaryPart.Size.Magnitude*0.5+0.18)
    if (radial>reach+0.10 or math.abs(depth)>axialReach)
        and not forcedByAim then return nil end
    -- A ray passing through an empty drilled hole can hit something far
    -- behind it. Aim recognition still centers the shaft in THAT hole.
    if forcedByAim and (radial>reach+0.10
        or math.abs(depth)>axialReach) then
        depth=0
    end
    local snugDiameter=nil
    if not Bore.CanInsert(shaft,target) then
        -- A shaft stays fit-capable when its parent component is moved.
        -- Change only this member's diameter in the preview; the server
        -- validates the resulting clearance and every existing joint.
        snugDiameter=Bore.SnugDiameter(shaft,target)
        if not snugDiameter then return nil end
        local original=shaft.PrimaryPart.Size
        shaft.PrimaryPart.Size=Vector3.new(original.X,snugDiameter,snugDiameter)
        shaft:SetAttribute("OPENWORKS_AutoSnugDiameter",snugDiameter)
        if not Bore.CanInsert(shaft,target) then
            shaft.PrimaryPart.Size=original
            shaft:SetAttribute("OPENWORKS_AutoSnugDiameter",nil)
            return nil
        end
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
    local reach=math.clamp(opening.PrimaryPart.Size.Magnitude*0.18,0.12,0.5)
    local axialReach=math.max(0.2,
        shaft.PrimaryPart.Size.X*0.5
            +opening.PrimaryPart.Size.Magnitude*0.5+0.18)
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
-- Analytic distance from the camera ray to the ACTUAL finite opening axis.
-- The hole itself contains no raycastable metal: aiming THROUGH it may
-- otherwise select a wall meters behind, leaving an unsnapped red shaft.
local function boreAimDistance(ray,target)
    if not ray or not target or not target.PrimaryPart then return math.huge end
    local localAxis=Alignment.TargetAxis(target)
    if not localAxis or Alignment.IsShaft(target) then return math.huge end
    local cf=target:GetPivot()
    local axis=cf:VectorToWorldSpace(localAxis).Unit
    local size=target.PrimaryPart.Size
    local half=(math.abs(localAxis.X)*size.X
        +math.abs(localAxis.Y)*size.Y
        +math.abs(localAxis.Z)*size.Z)*0.5
    local direction=ray.Direction.Unit
    local offset=ray.Origin-cf.Position
    local parallel=direction:Dot(axis)
    local denom=1-parallel*parallel
    local depth,along
    if denom>0.0001 then
        along=(parallel*offset:Dot(axis)-offset:Dot(direction))/denom
        depth=offset:Dot(axis)+parallel*math.max(0,along)
    else
        depth=if parallel>=0 then -half else half
    end
    depth=math.clamp(depth,-half,half)
    local nearest=cf.Position+axis*depth
    along=(nearest-ray.Origin):Dot(direction)
    if along<=0 or along>Grid.MaxDistance then return math.huge end
    return (ray.Origin+direction*along-nearest).Magnitude
end

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

    -- Try universal physical sockets before mechanical-only fit solvers.
    local quartzMatch=QuartzFit.Find(ghost,targets,ignored,preferred)
    if quartzMatch then return quartzMatch,{quartzMatch} end
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
    local pivotAnchor=FitOrigin.ComponentAnchor(members)
    local _,movingHasOrigin=FitOrigin.PreviewLocal(ghost)
    local matches={}
    for _,source in ipairs(members) do
        local isShaft=Alignment.IsShaft(source)
        local isGear=gear(source)
        local isHub=hub(source)
        local isRack=rack(source)
        local isGuide=guide(source)
        local isOpening=Alignment.TargetAxis(source)~=nil
        if not isShaft and not isHub and not isRack
            and not isGuide and not isOpening
            and not (movingHasOrigin and source==pivotAnchor) then continue end
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
            elseif isShaft and Alignment.TargetAxis(target) then
                rayError=math.min(rayError,boreAimDistance(aimRay,target))
            end
            local aimReach=math.clamp(target.PrimaryPart.Size.Magnitude*0.20,0.10,0.55)
            if isShaft and Alignment.TargetAxis(target) then
                -- Every point INSIDE the visible aperture counts as a
                -- deliberate hole aim; its centerline is not the only
                -- clickable point. This matches NearbyTargets capture.
                local aperture=Bore.OpeningDiameter(target)
                if aperture then
                    aimReach=math.max(aimReach,
                        math.clamp(aperture*0.5+0.07,0.10,0.40))
                end
            end
            local aimed=rayError<=aimReach
            local kind,cf,offset,roll,score,approach
            local pivot=if movingHasOrigin and source==pivotAnchor
                then FitSolver.PivotCandidate(ghost,target,aimRay,
                    aimedModel,allTargets or targets) else nil
            if pivot then
                kind="Pivot"
                cf=pivot.cf
                approach=pivot.approach
                score=pivot.score
            elseif HandCrankMath.IsCrank(source)
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
                        -- Gears and pulleys also have real bores: while dragging a
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
                local bevelKind=GearMath.Kind(source)
                local rayToTarget=aimDistance(aimRay,target:GetPivot().Position)
                local directAim=aimedModel==target or
                    (bevelKind=="Bevel90" and GearMath.Kind(target)==bevelKind
                        and rayToTarget<=Smart.Bevel90AimRadius)
                approach=source:GetPivot().Position
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
                    -- Bevel90 hit-testing uses the ray's projected point
                    -- near the gear's center: don't use the moved ghost's
                    -- position to guess which 45-degree side the user aims at.
                    if bevelKind=="Bevel90" and aimRay then
                        local direction=aimRay.Direction.Unit
                        local distance=math.max(0,
                            (apex-aimRay.Origin):Dot(direction))
                        local rayPoint=aimRay.Origin+direction*distance
                        local raySide=rayPoint-apex
                        raySide-=axis*raySide:Dot(axis)
                        if raySide.Magnitude>0.03 then
                            approach=apex+raySide.Unit*
                                (GearMath.PitchRadius(source)/
                                    math.tan(math.rad(45)))
                        end
                    end
                    local delta=approach-apex
                    local lateral=delta-axis*delta:Dot(axis)
                    local side=if bevelKind=="Bevel90" then
                        Smart.Bevel90Side(target,approach)
                        elseif lateral.Magnitude>0.001 then lateral.Unit
                        else fixed.UpVector
                    local theta=math.rad(
                        source:GetAttribute("BevelShaftAngleDeg") or 45)
                    local cone=math.rad(
                        source:GetAttribute("BevelConeDeg") or 22.5)
                    local outputAxis=if bevelKind=="Bevel90" then side
                        else axis*math.cos(theta)+side*math.sin(theta)
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
                    local side=radial.Unit
                    -- Align the target side to a discrete slot before
                    -- requesting the regular gear's common shared solver.
                    local azimuth=math.atan2(side:Dot(
                        fixed:VectorToWorldSpace(Vector3.zAxis)),
                        side:Dot(fixed.UpVector))
                    local slot=math.floor(azimuth/(2*math.pi/Smart.SpurSlots)+0.5)
                        %Smart.SpurSlots
                    side=fixed.UpVector*math.cos(slot*2*math.pi/Smart.SpurSlots)
                        +fixed:VectorToWorldSpace(Vector3.zAxis)
                            *math.sin(slot*2*math.pi/Smart.SpurSlots)
                    approach=fixed.Position+side*pitch
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
            local centeredHoles=nil
            local centeredMovingHoles=nil
            if cf and kind=="Bore" and isOpening and #members>1 then
                local centered,count,holes=MultiFit.CenteredReverseOffset(
                    members,source,target)
                if centered and count and count>1 then
                    local plan=Alignment.ReversePlan(
                        members,source,target,centered,roll or 0)
                    if plan then
                        cf=plan.delta*ghost:GetPivot()
                        offset=centered
                        centeredMovingHoles=holes
                    end
                end
            end
            if cf and kind=="Bore" and isShaft then
                -- The first hovered hole chooses the AXIS, not the final
                -- shaft midpoint. For multiple coaxial guide holes use
                -- the middle of their extreme centers, irrespective of
                -- which lug was aimed at. Handles grouped/welded guides
                -- and nearby independent lugs that one shaft can bridge.
                local centered,count,holes=MultiFit.CenteredShaftOffset(
                    source,target,allTargets or targets)
                if centered and count and count>1 then
                    local plan=Alignment.Plan(
                        members,source,target,centered,roll or 0)
                    if plan then
                        cf=plan.delta*ghost:GetPivot()
                        offset=centered
                        centeredHoles=holes
                    end
                end
            end
            if cf and kind=="Bore" then
                -- A through-hole can have a solid backstop. Instead of
                -- centering the shaft into that obstruction (red forever),
                -- search valid insertion depth on the same 0.5U lattice.
                -- Probe EVERY moving member; never clip a hidden flange.
                local resolved,newDepth=BoreInsertion.Resolve(ghost,
                    source,target,isShaft,cf,offset or 0,ignored,
                    centeredHoles,centeredMovingHoles)
                if resolved then
                    cf=resolved
                    offset=newDepth
                else
                    -- Never keep a red invalid snapped pose just because
                    -- an initial center alignment was geometrically close.
                    -- Other holes may still be valid candidates.
                    cf=nil
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
                local available=0
                for _,fixed in ipairs(chosenTargets) do
                    if (isOpening and Alignment.IsShaft(fixed))
                        or (not isOpening and Alignment.TargetAxis(fixed)) then
                        available+=1
                    end
                end
                if #currentFits<math.min(eligible,available)
                    or not completed then
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
                        elseif kind=="Rack" then "Rack"
                        elseif kind=="Guide" then "Guide" else "Gear",
                    reverse=kind=="Bore" and isOpening,
                    approach=approach,score=score,
                    fittedCount=fitted and #fitted or 0,
                    centeredGuideCount=if centeredHoles then #centeredHoles
                        elseif centeredMovingHoles then #centeredMovingHoles else 0,
                    requiredFitTargets=if centeredHoles then (function()
                        local ids={}
                        for _,hole in ipairs(centeredHoles) do
                            table.insert(ids,hole:GetAttribute("InstanceId"))
                        end
                        return ids
                    end)() else nil,
                    requiredMovingFitIds=if centeredMovingHoles then (function()
                        local ids={}
                        for _,hole in ipairs(centeredMovingHoles) do
                            table.insert(ids,hole:GetAttribute("InstanceId"))
                        end
                        return ids
                    end)() else nil,
                    snugDiameter=if kind=="Bore" and isShaft
                        then source:GetAttribute("OPENWORKS_AutoSnugDiameter")
                        else nil}
                if kind=="Bore" and isShaft and not hub(target) then
                    -- A shaft through a coaxial gear + drilled opening
                    -- must choose the HOLE as the primary mate, then the
                    -- server mounts any engaged gears onto that shaft.
                    -- A standalone gear remains a Hub mate as before.
                    score-=3.0
                end
                if target==preferred then
                    score-=if kind=="Gear" or kind=="Rack"
                        or kind=="Guide" then 0.08 else 1.5
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
    local hasMovingRack=false
    if moving then
        for _,member in ipairs(Smart.Members(moving)) do
            if rack(member) then hasMovingRack=true end
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
            local isHub=hub(model)
            local hubRay=hubAimDistance(aimRay,model)
            local boreRay=boreAimDistance(aimRay,model)
            local boreDiameter=Bore.OpeningDiameter(model)
            local boreAimed=type(boreDiameter)=="number"
                and boreRay<=math.clamp(boreDiameter*0.5+0.07,0.10,0.40)
            -- Do not use the large tooth bounds to pick a gear. Gears
            -- remain discoverable within a small central radius, even
            -- though their actual empty bores have no raycast hitbox.
            local range=if isHub then Smart.HubSnapRadius
                else Smart.SnapDistance+math.min(1.0,size*0.45)
                    +math.clamp(extraReach or 0,0,24)
            local aimThreshold=if isHub then Smart.HubAimRadius
                else math.clamp(size*0.20,0.10,0.55)
            local gearPlacement=false
            local movingGear=hasMovingGear
            local movingRack=hasMovingRack
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
                        if GearMath.Kind(member)=="Bevel90"
                            and GearMath.Kind(model)=="Bevel90" then
                            -- Spur pitch-radius searches miss right-angle
                            -- gears (their axle centers differ in X too).
                            -- Detect the same discrete slots used by the
                            -- shared preview/server solver instead.
                            local pose=Smart.BevelPose(member,model,reference)
                            gearPlacement=gearPlacement or pose~=nil
                        else
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
            -- Transparent bore pivots and compact 90-degree bevel teeth
            -- are hard to hit with the mouse. A center-ray capture radius
            -- lets the player aim through the opening or between teeth,
            -- without creating an oversized physical hitbox.
            local bevelAim=isGear and movingGear and aimRay
                and GearMath.Kind(model)=="Bevel90"
                and hubRay<=Smart.Bevel90AimRadius
            local hitRack=rack(model) and movingGear
                and aimedPart and aimedPart:IsDescendantOf(model)
            if gearPlacement or hitGear or bevelAim or hitRack or boreAimed
                or (model:GetPivot().Position-reference).Magnitude<=range
                or hubRay<=aimThreshold then
                table.insert(targets,model)
            end
        end
    end
    -- Tiny quartz endpoints need a much tighter, port-aware search
    -- than a body's bounding-box center.
    if moving and QuartzFit.HasPorts(moving) then
        local movingPorts=QuartzFit.Ports(moving)
        local known={}
        for _,item in ipairs(targets) do known[item]=true end
        for _,candidate in ipairs(folder:GetChildren()) do
            if candidate:IsA("Model") and candidate.PrimaryPart
                and candidate:GetAttribute("OwnerUserId")==playerUserId
                and not known[candidate]
                and not (ignored and ignored[candidate])
                and QuartzFit.HasPorts(candidate) then
                local close=false
                for _,a in ipairs(movingPorts) do
                    for _,b in ipairs(QuartzFit.Ports(candidate)) do
                        if (a.WorldPosition-b.WorldPosition).Magnitude
                            <= QuartzFit.CaptureDistance+0.08 then
                            close=true
                            break
                        end
                    end
                    if close then break end
                end
                if close then
                    table.insert(targets,candidate)
                    known[candidate]=true
                end
            end
        end
    end
    return targets
end

return table.freeze(Smart)
