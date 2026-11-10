--!strict
-- Phase 11: fit many independently authored holes to many shafts using
-- one rigid EDITOR transform. Fit geometry is NOT a weld or a constraint.
-- Shared client/server predicate; all geometry is checked again server-side.
local Alignment=require(script.Parent:WaitForChild("AlignmentMath"))
local Bore=require(script.Parent:WaitForChild("BoreClearance"))
local Grid=require(script.Parent:WaitForChild("GridMath"))
local Fit={}
Fit.MaxPairs=32
Fit.RadialTolerance=Grid.Unit*0.12
Fit.AxisTolerance=0.9998

local function key(model)
    return tostring(model:GetAttribute("InstanceId") or model.Name)
end

-- delta is the transform applied to all moving models, never the stationary
-- rods; a paired source is the MOVING primitive (shaft OR opening).
function Fit.Check(moving,stationary,delta)
    if not moving or not stationary or not moving.PrimaryPart
        or not stationary.PrimaryPart or moving==stationary then return nil end
    local reverse=Alignment.TargetAxis(moving)~=nil
        and Alignment.IsShaft(stationary)
    local forward=Alignment.IsShaft(moving)
        and Alignment.TargetAxis(stationary)~=nil
    if not reverse and not forward then return nil end
    local shaft=if reverse then stationary else moving
    local hole=if reverse then moving else stationary
    local shaftCF=if reverse then shaft:GetPivot()
        else (delta or CFrame.identity)*shaft:GetPivot()
    local holeCF=if reverse then
        (delta or CFrame.identity)*hole:GetPivot() else hole:GetPivot()
    local localAxis=Alignment.TargetAxis(hole)
    local axis=holeCF:VectorToWorldSpace(localAxis).Unit
    local shaftAxis=shaftCF.RightVector.Unit
    local angular=math.abs(axis:Dot(shaftAxis))
    if angular<Fit.AxisTolerance then return nil end
    local diameter=Bore.OpeningDiameter(hole)
    if not diameter then return nil end
    local shaftDiameter=math.max(shaft.PrimaryPart.Size.Y,
        shaft.PrimaryPart.Size.Z)
    if shaftDiameter>diameter-0.002 then return nil end
    local distance=shaftCF.Position-holeCF.Position
    local depth=distance:Dot(axis)
    local radial=(distance-axis*depth).Magnitude
    if radial>Fit.RadialTolerance then return nil end
    local holeSize=hole.PrimaryPart.Size
    local thickness=math.abs(localAxis.X)*holeSize.X
        +math.abs(localAxis.Y)*holeSize.Y
        +math.abs(localAxis.Z)*holeSize.Z
    local skew=thickness*0.5*math.sqrt(math.max(0,1-angular*angular))
        /angular
    -- Inset shaft must fit at BOTH faces, not only along its centerline.
    -- Without this clearance check a nearly-aligned rod could be falsely
    -- whitelisted as noninterfering despite clipping the bore wall.
    if shaftDiameter+2*(radial+skew)>diameter-0.002 then return nil end
    local lo,hi=Alignment.OffsetBounds(shaft,hole)
    if not lo or depth/Grid.Unit<lo-0.006
        or depth/Grid.Unit>hi+0.006 then return nil end
    return {
        moving=moving, stationary=stationary, shaft=shaft, hole=hole,
        movingId=key(moving),stationaryId=key(stationary),
        reverse=reverse,depthU=depth/Grid.Unit,radial=radial,
        axis=axis,offsetMin=lo,offsetMax=hi,
    }
end

-- All stationary members of the SELECTED editor component are part of the
-- mechanical fitting operation, not merely the primitive the camera hit.
-- Separate nearby components must not become accidental guide contacts.
function Fit.Scope(target,all)
    if not target then return {} end
    local id=target:GetAttribute("ComponentId")
    if type(id)~="string" or id=="" then return {target} end
    local owner=target:GetAttribute("OwnerUserId")
    local result={}
    for _,model in ipairs(all or {}) do
        if model:IsA("Model") and model.PrimaryPart
            and model:GetAttribute("ComponentId")==id
            and model:GetAttribute("OwnerUserId")==owner then
            table.insert(result,model)
        end
    end
    if #result==0 then return {target} end
    return result
end

-- If both sides contain the same number of guide sockets (e.g. four
-- holes and four rods), require ALL of them to fit uniquely. This stops a
-- red/misaligned fourth rod from being overlooked just because one good
-- pair could still create a slider.
function Fit.Completeness(movingMembers,stationaryModels,pairs,reverse)
    local movingCount,stationaryCount=0,0
    for _,model in ipairs(movingMembers) do
        if (reverse and Alignment.TargetAxis(model)~=nil)
            or (not reverse and Alignment.IsShaft(model)) then
            movingCount+=1
        end
    end
    for _,model in ipairs(stationaryModels) do
        if (reverse and Alignment.IsShaft(model))
            or (not reverse and Alignment.TargetAxis(model)~=nil) then
            stationaryCount+=1
        end
    end
    if movingCount<=1 or movingCount~=stationaryCount then return true end
    local movingUnique,stationaryUnique={},{}
    local fitCount=0
    for _,pair in ipairs(pairs or {}) do
        if pair.reverse==reverse
            and not movingUnique[pair.movingId]
            and not stationaryUnique[pair.stationaryId] then
            movingUnique[pair.movingId]=true
            stationaryUnique[pair.stationaryId]=true
            fitCount+=1
        end
    end
    if fitCount<movingCount then
        return false,string.format(
            "Only %d/%d holes fitted. Check every rod, diameter, angle and spacing",
            fitCount,movingCount)
    end
    return true
end

function Fit.Find(movingMembers,stationaryModels,delta,ignore)
    local list={}
    for _,moving in ipairs(movingMembers) do
        for _,stationary in ipairs(stationaryModels) do
            if not (ignore and ignore[stationary]) then
                local match=Fit.Check(moving,stationary,delta)
                if match then
                    table.insert(list,match)
                    if #list>Fit.MaxPairs then
                        return nil,"Too many fitted shaft/hole contacts (max 32)"
                    end
                end
            end
        end
    end
    table.sort(list,function(a,b)
        local akey=a.movingId..":"..a.stationaryId
        local bkey=b.movingId..":"..b.stationaryId
        return akey<bkey
    end)
    return list
end

function Fit.AllowMap(matches)
    local result={}
    for _,pair in ipairs(matches or {}) do
        local member=result[pair.moving]
        if not member then member={} result[pair.moving]=member end
        member[pair.stationary]=true
    end
    return result
end

function Fit.Contains(matches,movingId,stationaryId)
    for _,pair in ipairs(matches or {}) do
        if pair.movingId==movingId
            and pair.stationaryId==stationaryId then return true end
    end
    return false
end

-- A kinematic slider on one master pair is sufficient; other physically
-- aligned holes are clearance checks, NOT redundant PrismaticConstraints.
-- Calculate conservative symmetric physical travel from ALL guide pairs
-- so the shortest engaged rod can't be exited by a long master rod.
function Fit.SymmetricTravel(matches)
    local travel=math.huge
    for _,pair in ipairs(matches) do
        travel=math.min(travel,
            pair.depthU-pair.offsetMin,pair.offsetMax-pair.depthU)
    end
    if travel==math.huge then return nil end
    return math.max(0,travel)
end

return table.freeze(Fit)
