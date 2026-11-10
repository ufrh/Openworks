--!strict
-- OPENWORKS contextual, drag-first placement. Shared by preview and server.
-- Compatible sockets and gear centers are recognized from physical geometry,
-- not a two-click relationship selection or a compulsory world grid.
local Alignment = require(script.Parent:WaitForChild("AlignmentMath"))
local GearMath = require(script.Parent:WaitForChild("GearMath"))
local Grid = require(script.Parent:WaitForChild("GridMath"))
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
    local units=math.clamp(math.round(depth/(Grid.Unit*0.5))*0.5,
        -Smart.MaxAxialOffsetUnits,Smart.MaxAxialOffsetUnits)
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
    local units=math.clamp(math.round((-axial)/(Grid.Unit*0.5))*0.5,
        -Smart.MaxAxialOffsetUnits,Smart.MaxAxialOffsetUnits)
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

-- caller has positioned ghost at unsnapped world pose. Targets must be
-- the caller's owned construction. Aim ray is optional and allows
-- recognition THROUGH empty holes and behind other nested geometry.
function Smart.Find(ghost: Model, targets: {Model}, ignored, preferred: Model?, aimRay)

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
            if cf then
                local candidate={kind=kind,target=target,source=source,
                    cf=cf,offsetUnits=offset or 0,rollDegrees=roll or 0,
                    relationKind=if kind=="Bore" then "Rigid"
                        elseif kind=="Hub" then "Fixed" else "Gear",
                    reverse=kind=="Bore" and isOpening,
                    approach=approach,score=score}
                table.insert(matches,candidate)
                if target==preferred then score-=1.5 end
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
    reference: Vector3, ignored, aimRay)
    local targets={}
    if not folder then return targets end
    for _,model in ipairs(folder:GetChildren()) do
        if model:IsA("Model") and model.PrimaryPart
            and model:GetAttribute("OwnerUserId")==playerUserId
            and not (ignored and ignored[model]) then
            local size=model.PrimaryPart.Size.Magnitude
            local range=Smart.SnapDistance+math.min(3,size)
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
