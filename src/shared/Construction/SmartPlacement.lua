--!strict
-- OPENWORKS contextual, drag-first placement. Shared by preview and server.
-- Compatible sockets and gear centers are recognized from physical geometry,
-- not a two-click relationship selection or a compulsory world grid.
local Alignment = require(script.Parent:WaitForChild("AlignmentMath"))
local GearMath = require(script.Parent:WaitForChild("GearMath"))
local Grid = require(script.Parent:WaitForChild("GridMath"))
local MultiFit = require(script.Parent:WaitForChild("MultiFitMath"))
local Smart = {}
Smart.SnapDistance = 2.0 -- studs; generous magnet near a component
Smart.MaxAxialOffsetUnits = 64
Smart.PreviewInterval = 0.08

local function gear(model)
    return model and type(model:GetAttribute("GearTeeth")) == "number"
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
    if radial.Magnitude > pitch + Smart.SnapDistance
        or math.abs(depth)>Smart.SnapDistance then return nil end
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
    return CFrame.new(center)*rotation,math.abs(radial.Magnitude-pitch)+math.abs(depth)
end

-- Gear bores are real open centers, not bearings. Dragging a gear
-- onto a shaft (or a shaft through a gear) mounts the two as one rigid
-- mechanical assembly, without any two-click hub wizard.
function Smart.HubFits(source: Model, target: Model)
    local gearBody=if gear(source) then source else if gear(target) then target else nil
    local shaft=if Alignment.IsShaft(source) then source
        else if Alignment.IsShaft(target) then target else nil
    if not gearBody or not shaft or not shaft.PrimaryPart then
        return false,"Hub requires one gear and one cylindrical shaft"
    end
    local bore=gearBody:GetAttribute("BoreRadiusStuds")
    if type(bore)~="number" or bore<=0 then
        return false,"Gear has no verified center opening"
    end
    local shaftRadius=math.max(shaft.PrimaryPart.Size.Y,shaft.PrimaryPart.Size.Z)*0.5
    if shaftRadius+0.002>bore then
        return false,"Shaft diameter exceeds gear center opening"
    end
    local gcf,scf=gearBody:GetPivot(),shaft:GetPivot()
    if math.abs(gcf.RightVector:Dot(scf.RightVector))<0.999 then
        return false,"Gear and shaft axes must align"
    end
    local radial=gcf.Position-scf.Position
    radial-=scf.RightVector*radial:Dot(scf.RightVector)
    if radial.Magnitude>0.012 then
        return false,"Shaft must pass through gear's center"
    end
    local axial=math.abs((gcf.Position-scf.Position):Dot(scf.RightVector))
    local overlap=(shaft.PrimaryPart.Size.X+gearBody.PrimaryPart.Size.X)*0.5
    if axial>overlap-0.015 then
        return false,"Gear must overlap the shaft length"
    end
    return true
end

function Smart.HubPose(source: Model, target: Model, near: Vector3)
    if not ((gear(source) and Alignment.IsShaft(target))
        or (Alignment.IsShaft(source) and gear(target))) then return nil end
    local shaft=if Alignment.IsShaft(source) then source else target
    local gearBody=if gear(source) then source else target
    local bore=gearBody:GetAttribute("BoreRadiusStuds")
    if type(bore)~="number" then return nil end
    if math.max(shaft.PrimaryPart.Size.Y,shaft.PrimaryPart.Size.Z)*0.5
        +0.002>bore then return nil end
    local fixed=target:GetPivot()
    local axis=fixed.RightVector
    local delta=near-fixed.Position
    local depth=delta:Dot(axis)
    local radial=(delta-axis*depth).Magnitude
    local reach=math.max(0.9,gearBody.PrimaryPart.Size.Magnitude*0.8)
    if radial>reach+Smart.SnapDistance
        or math.abs(depth)>math.max(3,shaft.PrimaryPart.Size.X+1.5)
        then return nil end
    local maxTravel=math.max(0,
        (shaft.PrimaryPart.Size.X+gearBody.PrimaryPart.Size.X)*0.5-0.035)
    local maxUnits=math.min(Smart.MaxAxialOffsetUnits,
        math.floor(maxTravel/(Grid.Unit*0.5))*0.5)
    local offset=math.clamp(math.round(depth/(Grid.Unit*0.5))*0.5,
        -maxUnits,maxUnits)
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
    local axis=if reverse then target:GetPivot().RightVector.Unit
        else (baseDelta*source:GetPivot()).RightVector.Unit
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
    local bestChange=math.huge
    for _,candidate in ipairs(candidates) do
        local plan=if reverse then Alignment.ReversePlan(
            members,source,target,offset,candidate)
            else Alignment.Plan(members,source,target,offset,candidate)
        if plan then
            local nextCF=plan.delta*pivot
            local contacts=MultiFit.Find(members,allTargets,
                nextCF*pivot:Inverse(),ignored)
            if contacts then
                local count=#contacts
                local change=math.abs(candidate-roll)
                if count>bestCount
                    or (count==bestCount and change<bestChange) then
                    bestCF,bestRoll,bestCount=nextCF,candidate,count
                    bestChange=change
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
    allTargets: {Model}?)

    local members=Smart.Members(ghost)
    if #members==0 then return nil end
    local best,bestScore=nil,math.huge
    local matches={}
    for _,source in ipairs(members) do
        local isShaft=Alignment.IsShaft(source)
        local isGear=gear(source)
        local isOpening=Alignment.TargetAxis(source)~=nil
        if not isShaft and not isGear and not isOpening then continue end
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
            if (isGear and Alignment.IsShaft(target))
                or (isShaft and gear(target)) then
                local near=source:GetPivot().Position
                if aimed and (near-target:GetPivot().Position).Magnitude>3.5 then
                    near=target:GetPivot().Position
                end
                local pose,dist,u=Smart.HubPose(source,target,near)
                if pose then
                    kind="Hub"
                    cf=(pose*source:GetPivot():Inverse())*ghost:GetPivot()
                    approach=pose.Position
                    offset=u
                    score=if aimed then rayError+0.07 else dist
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
            elseif isGear and gear(target) then
                approach=source:GetPivot().Position
                if aimed and (approach-target:GetPivot().Position).Magnitude>3.5 then
                    approach=target:GetPivot().Position
                        + target:GetPivot().UpVector
                end
                local pose,dist=Smart.GearPose(source,target,approach)
                if pose then
                    kind="Gear"
                    cf=(pose*source:GetPivot():Inverse())*ghost:GetPivot()
                    approach=pose.Position
                    score=if aimed then rayError+0.14 else dist+0.12
                end
            end
            if cf and kind=="Bore" and #members>1 then
                local chosenTargets=MultiFit.Scope(target,allTargets or targets)
                local initial=MultiFit.Find(members,chosenTargets,
                    cf*ghost:GetPivot():Inverse(),ignored)
                -- Don't run the multi-angle search every frame if the
                -- authored hole pattern already registers two or more fits.
                if not initial or #initial<2 then
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
                    fitted=MultiFit.Find(members,
                        MultiFit.Scope(target,allTargets or targets),
                        delta,ignored)
                    if fitted and #fitted>1 then
                        score-=math.min(12,(#fitted-1)*2.5)
                    end
                end
                local candidate={kind=kind,target=target,source=source,
                    cf=cf,offsetUnits=offset or 0,rollDegrees=roll or 0,
                    relationKind=if kind=="Bore" then "Cylindrical"
                        elseif kind=="Hub" then "Fixed" else "Gear",
                    reverse=kind=="Bore" and isOpening,
                    approach=approach,score=score,
                    fittedCount=fitted and #fitted or 0}
                if target==preferred then score-=1.5 end
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
    reference: Vector3, ignored, aimRay, extraReach)
    local targets={}
    if not folder then return targets end
    for _,model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and model.PrimaryPart
            and model:GetAttribute("OwnerUserId")==playerUserId
            and not (ignored and ignored[model]) then
            local size=model.PrimaryPart.Size.Magnitude
            local range=Smart.SnapDistance+math.min(3,size)
                +math.clamp(extraReach or 0,0,24)
            if (model:GetPivot().Position-reference).Magnitude<=range
                or aimDistance(aimRay,model:GetPivot().Position)
                    <=math.clamp(size*0.38,0.48,1.5) then
                table.insert(targets,model)
            end
        end
    end
    return targets
end

return table.freeze(Smart)
