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
        angular=angular,axis=axis,offsetMin=lo,offsetMax=hi,
    }
end

-- All stationary members of the SELECTED editor component are part of the
-- mechanical fitting operation, not merely the primitive the camera hit.
-- Separate nearby components must not become accidental guide contacts.
function Fit.Scope(target,all)
    if not target then return {} end
    -- Rigid membership has TWO legitimate sources:
    -- (1) the EDITOR ComponentId group and
    -- (2) manually authored Weld/Fixed/Bolt relationships.
    -- The latter was previously omitted, so welding four rods to one
    -- lower plate still left the snap search looking at ONE rod.
    local modelsById={}
    local byComponent={}
    local owner=target:GetAttribute("OwnerUserId")
    local function record(model)
        if not model:IsA("Model") or not model.PrimaryPart
            or model:GetAttribute("OwnerUserId")~=owner then return end
        local id=model:GetAttribute("InstanceId")
        if type(id)~="string" then return end
        modelsById[id]=model
        local component=model:GetAttribute("ComponentId")
        if type(component)=="string" and component~="" then
            byComponent[component]=byComponent[component] or {}
            table.insert(byComponent[component],id)
        end
    end
    for _,model in ipairs(all or {}) do record(model) end
    record(target)

    local neighbours={}
    local function connect(a,b)
        if type(a)~="string" or type(b)~="string"
            or not modelsById[a] or not modelsById[b] then return end
        neighbours[a]=neighbours[a] or {}
        neighbours[b]=neighbours[b] or {}
        table.insert(neighbours[a],b)
        table.insert(neighbours[b],a)
    end
    local relations=workspace:FindFirstChild("OPENWORKS_Relationships")
    if relations then
        for _,relation in ipairs(relations:GetChildren()) do
            if relation:GetAttribute("OwnerUserId")~=owner then continue end
            local kind=relation:GetAttribute("Kind")
            if kind=="Weld" or kind=="Fixed" or kind=="Bolt" then
                local shaft=relation:GetAttribute("SourceId")
                local body=relation:GetAttribute("TargetId")
                connect(shaft,body)
                if kind=="Bolt" then
                    connect(shaft,relation:GetAttribute("SecondTargetId"))
                end
            end
        end
    end

    local seen={}
    local queue={}
    local start=target:GetAttribute("InstanceId")
    if type(start)~="string" then return {target} end
    seen[start]=true
    table.insert(queue,start)
    local result={}
    local cursor=1
    while cursor<=#queue do
        local id=queue[cursor]
        cursor+=1
        local member=modelsById[id]
        if member then
            table.insert(result,member)
            local group=member:GetAttribute("ComponentId")
            local candidates={}
            if type(group)=="string" and group~="" then
                for _,peer in ipairs(byComponent[group] or {}) do
                    table.insert(candidates,peer)
                end
            end
            for _,peer in ipairs(neighbours[id] or {}) do
                table.insert(candidates,peer)
            end
            for _,peer in ipairs(candidates) do
                if not seen[peer] then
                    seen[peer]=true
                    table.insert(queue,peer)
                end
            end
        end
        if #queue>128 then break end
    end
    table.sort(result,function(a,b)
        return tostring(a:GetAttribute("InstanceId"))
            <tostring(b:GetAttribute("InstanceId"))
    end)
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
    local expected=math.min(movingCount,stationaryCount)
    if expected<=1 then return true end
    -- A 4-hole plate can fit four rods even if its supporting structure
    -- also has unrelated fifth/sixth shafts. The expected count is the
    -- smaller compatible side, NOT only when both counts are identical.
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
    if fitCount<expected then
        return false,string.format(
            "Only %d/%d shaft-hole pairs fitted. Check all angles and spacing",
            fitCount,expected)
    end
    -- Multiple genuine constraints require their axes to be exceptionally
    -- close. Do not silently use just one accepted guide.
    for _,pair in ipairs(pairs or {}) do
        if pair.radial>Grid.Unit*0.04 or (pair.angular or 0)<0.999995 then
            return false,"Guide pattern is slightly offset; re-align the whole component"
        end
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

-- Assign one and only one stationary shaft/hole to each moving socket.
-- A loose hole can geometrically fit multiple nearby shafts; counting each
-- candidate as a separate attachment causes duplicate joints and bad poses.
-- The selected primary pair remains locked while augmenting the other matches.
function Fit.Unique(matches,primaryMovingId,primaryStationaryId)
    local byMoving,ids={},{}
    local chosenPrimary=nil
    for _,pair in ipairs(matches or {}) do
        if not byMoving[pair.movingId] then
            byMoving[pair.movingId]={}
            table.insert(ids,pair.movingId)
        end
        table.insert(byMoving[pair.movingId],pair)
        if pair.movingId==primaryMovingId
            and pair.stationaryId==primaryStationaryId then
            chosenPrimary=pair
        end
    end
    table.sort(ids)
    for _,list in pairs(byMoving) do
        table.sort(list,function(a,b)
            if math.abs(a.radial-b.radial)>1e-6 then
                return a.radial<b.radial
            end
            return a.stationaryId<b.stationaryId
        end)
    end
    if primaryMovingId and not chosenPrimary then return {} end
    local selected={}
    local assigned={}
    if chosenPrimary then
        selected[primaryMovingId]=chosenPrimary
        assigned[primaryStationaryId]=primaryMovingId
    end
    local function augment(id,visited)
        for _,pair in ipairs(byMoving[id] or {}) do
            local destination=pair.stationaryId
            if visited[destination] then continue end
            visited[destination]=true
            local previous=assigned[destination]
            if not previous or (previous~=primaryMovingId
                and augment(previous,visited)) then
                assigned[destination]=id
                selected[id]=pair
                return true
            end
        end
        return false
    end
    for _,id in ipairs(ids) do
        if not selected[id] then augment(id,{}) end
    end
    local result={}
    for _,id in ipairs(ids) do
        if selected[id] then table.insert(result,selected[id]) end
    end
    return result
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

-- Each verified guide now receives its own passive joint.
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
