--!strict
-- Per-player, persistent, self-contained component blueprints. Placement
-- reconstructs primitives and INTERNAL relationships, never references the
-- original source component or its assembly membership.
local DataStoreService=game:GetService("DataStoreService")
local HttpService=game:GetService("HttpService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local shared=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Codec=require(shared:WaitForChild("ComponentBankCodec"))
local FitOrigin=require(shared:WaitForChild("FitOrigin"))
local Bank={}
Bank.__index=Bank
local MAX_BANK=16
local MAX_PARTS=64
local MAX_BYTES=500000
local MAX_NAME=48
local function blank()
    return {version=1,entries={}}
end
local function clean(doc)
    if doc==nil then return blank() end
    if type(doc)~="table" or doc.version~=1
        or type(doc.entries)~="table" or #doc.entries>MAX_BANK then
        return nil,"Unsupported or corrupt component bank"
    end
    for _,entry in ipairs(doc.entries) do
        if type(entry)~="table" or type(entry.id)~="string"
            or type(entry.name)~="string" or #entry.name>MAX_NAME
            or type(entry.anchorId)~="string"
            or type(entry.parts)~="table" or #entry.parts<2
            or #entry.parts>MAX_PARTS or type(entry.joints)~="table"
            then return nil,"Component bank contains an invalid blueprint" end
        local ids={}
        for _,part in ipairs(entry.parts) do
            if not Codec.PartValid(part) or ids[part.id] then
                return nil,"Component bank contains invalid primitive metadata"
            end
            ids[part.id]=true
        end
        if not ids[entry.anchorId] then
            return nil,"Component bank has a missing anchor"
        end
        for _,joint in ipairs(entry.joints) do
            if type(joint)~="table" or not ids[joint.sourceId]
                or not ids[joint.targetId]
                or (joint.boltId and not ids[joint.boltId])
                or (joint.secondTargetId and not ids[joint.secondTargetId])
                then return nil,"Component bank contains an external relationship" end
        end
    end
    return doc
end
local function nameValid(value)
    return type(value)=="string" and #value>=1 and #value<=MAX_NAME
        and not value:find("[%c]")
        and value:match("%S")~=nil
end
local function documentSize(doc)
    local ok,result=pcall(HttpService.JSONEncode,HttpService,doc)
    return if ok then #result else math.huge
end
local function relationInternal(spec,ids)
    if not ids[spec.sourceId] or not ids[spec.targetId]
        or (spec.boltId and not ids[spec.boltId])
        or (spec.secondTargetId and not ids[spec.secondTargetId]) then
        return false
    end
    if type(spec.fitPointsJSON)=="string" and spec.fitPointsJSON~="" then
        local ok,points=pcall(HttpService.JSONDecode,HttpService,spec.fitPointsJSON)
        if not ok or type(points)~="table" then return false end
        for _,point in ipairs(points) do
            if type(point)~="table" or not ids[point.movingId]
                or not ids[point.stationaryId] then return false end
        end
    end
    return true
end
function Bank.new(deps)
    return setmetatable({
        D=deps,
        Store=DataStoreService:GetDataStore("OPENWORKS_ComponentBank_v1"),
        Cache={},
    },Bank)
end
function Bank:Load(player)
    if self.Cache[player] then return self.Cache[player] end
    local ok,raw=pcall(function()
        return self.Store:GetAsync("player_"..tostring(player.UserId))
    end)
    if not ok then return nil,"Component bank unavailable: DataStore read failed" end
    local doc,why=clean(raw)
    if not doc then return nil,why end
    self.Cache[player]=doc
    return doc
end
function Bank:List(player)
    local doc,why=self:Load(player)
    if not doc then return false,why end
    local entries={}
    for _,entry in ipairs(doc.entries) do
        table.insert(entries,{
            id=entry.id,name=entry.name,
            parts=#entry.parts,relationships=#entry.joints
        })
    end
    table.sort(entries,function(a,b) return a.name:lower()<b.name:lower() end)
    return true,"Component bank loaded",{entries=entries}
end
function Bank:Get(player,payload)
    local doc,why=self:Load(player)
    if not doc then return false,why end
    for _,entry in ipairs(doc.entries) do
        if entry.id==payload.bankId then
            -- Only layout metadata is returned to the placement client.
            -- Server retains and authorizes every relationship on placement.
            return true,"Blueprint ready",{
                id=entry.id,name=entry.name,anchorId=entry.anchorId,
                parts=entry.parts,relationships=#entry.joints,
            }
        end
    end
    return false,"Saved component not found"
end
function Bank:Persist(player,mutator)
    -- Save synchronously with UpdateAsync, not in an untracked background
    -- task. Atomic mutation preserves other server writes to the same bank.
    local result,reason
    local ok,updated=pcall(function()
        return self.Store:UpdateAsync(
            "player_"..tostring(player.UserId),function(current)
                local doc,why=clean(current)
                if not doc then reason=why return nil end
                local nextDoc,err=mutator(doc)
                if not nextDoc then reason=err return nil end
                if documentSize(nextDoc)>MAX_BYTES then
                    reason="Component bank storage limit reached"
                    return nil
                end
                return nextDoc
            end)
    end)
    if not ok then return false,"Component bank could not be saved" end
    if not updated then return false,reason or "Bank update was cancelled" end
    self.Cache[player]=updated
    return true
end
function Bank:Register(player,payload)
    if not nameValid(payload.name) then
        return false,"Choose a name between 1 and 48 characters"
    end
    local componentId=payload.componentId
    local d=self.D
    local members,why=d.components:RequireMembers(player,componentId)
    if not members then return false,why end
    if #members>MAX_PARTS then
        return false,"Bank supports up to 64 primitives per component"
    end
    local anchor=FitOrigin.ComponentAnchor(members)
    if not anchor then return false,"Component has no valid anchor" end
    local anchorId=anchor:GetAttribute("InstanceId")
    local baseCF=anchor:GetPivot()
    local entry={
        id=HttpService:GenerateGUID(false),
        name=payload.name:match("^%s*(.-)%s*$"),
        anchorId=anchorId,parts={},joints={},
        savedAt=os.time(),
    }
    local ids={}
    for _,model in ipairs(members) do
        local snap=d.snapshot(model)
        if not d.nearPlayer(player,snap.position) then
            return false,"Move closer to the component to save it"
        end
        ids[snap.instanceId]=true
        table.insert(entry.parts,{
            id=snap.instanceId,template=snap.templateId,
            relative=Codec.Pose(baseCF:ToObjectSpace(model:GetPivot())),
            size=Codec.Vec(snap.size),steps=snap.steps,
            fitPivot=if FitOrigin.Valid(snap.fitPivotLocal)
                then Codec.Vec(snap.fitPivotLocal) else nil,
            componentPivot=if snap.instanceId==anchorId
                and FitOrigin.Valid(snap.componentFitPivotLocal)
                then Codec.Vec(snap.componentFitPivotLocal) else nil,
            fitPrecision=snap.fitPrecision,resizePrecision=snap.resizePrecision,
            numericPrecision=snap.numericPrecision,
            alignedOpening=snap.alignedOpeningId,
            alignedOffsetU=snap.alignedOffsetU,shaftRollDegrees=snap.shaftRollDegrees,
            material=snap.materialId,paintFinish=snap.paintFinish,
            paintHex=snap.paintColorHex,
        })
    end
    table.sort(entry.parts,function(a,b) return a.id<b.id end)
    local excluded=0
    for _,relation in ipairs(d.mechanical.Folder:GetChildren()) do
        if relation:IsA("Folder") and
            relation:GetAttribute("OwnerUserId")==player.UserId then
            local spec=d.mechanical:Snapshot(relation)
            if ids[spec.sourceId] or ids[spec.targetId] then
                if relationInternal(spec,ids) then
                    table.insert(entry.joints,spec)
                else
                    excluded+=1
                end
            end
        end
    end
    local saved,reason=self:Persist(player,function(doc)
        local nextDoc=table.clone(doc)
        nextDoc.entries=table.clone(doc.entries)
        if #nextDoc.entries>=MAX_BANK then
            return nil,"Component bank is full (16 blueprints)"
        end
        for _,existing in ipairs(nextDoc.entries) do
            if existing.name:lower()==entry.name:lower() then
                return nil,"A bank component already uses this name"
            end
        end
        table.insert(nextDoc.entries,entry)
        return nextDoc
    end)
    if not saved then return false,reason end
    return true,"Saved "..entry.name.." ("..#entry.parts.." parts, "
        ..#entry.joints.." internal relationships"
        ..(if excluded>0 then ", "..excluded.." external excluded)" else ")"),
        {id=entry.id}
end
function Bank:Remove(player,payload)
    if type(payload.bankId)~="string" then return false,"Select a bank entry" end
    local removed
    local ok,why=self:Persist(player,function(doc)
        local entries={}
        for _,entry in ipairs(doc.entries) do
            if entry.id==payload.bankId then removed=entry.name
            else table.insert(entries,entry) end
        end
        if not removed then return nil,"Component bank entry not found" end
        return {version=1,entries=entries}
    end)
    if not ok then return false,why end
    return true,"Removed "..removed.." from the component bank"
end
local function remapFit(spec,idMap,fitSets)
    local result=table.clone(spec)
    result.relationId=HttpService:GenerateGUID(false)
    result.sourceId=idMap[spec.sourceId]
    result.targetId=idMap[spec.targetId]
    result.boltId=if spec.boltId then idMap[spec.boltId] else nil
    result.secondTargetId=if spec.secondTargetId
        then idMap[spec.secondTargetId] else nil
    if not result.sourceId or not result.targetId
        or (spec.boltId and not result.boltId)
        or (spec.secondTargetId and not result.secondTargetId) then
        return nil,"Blueprint refers to an external part"
    end
    if type(spec.fitPointsJSON)=="string" and spec.fitPointsJSON~="" then
        local ok,points=pcall(HttpService.JSONDecode,HttpService,spec.fitPointsJSON)
        if not ok or type(points)~="table" then return nil,"Corrupt fit set" end
        local mapped={}
        for _,point in ipairs(points) do
            if type(point)~="table" or not idMap[point.movingId]
                or not idMap[point.stationaryId] then
                return nil,"Fit set reaches outside the saved component"
            end
            local item=table.clone(point)
            item.movingId=idMap[point.movingId]
            item.stationaryId=idMap[point.stationaryId]
            table.insert(mapped,item)
        end
        result.fitPointsJSON=HttpService:JSONEncode(mapped)
    end
    if type(spec.fitSetId)=="string" then
        fitSets[spec.fitSetId]=fitSets[spec.fitSetId]
            or HttpService:GenerateGUID(false)
        result.fitSetId=fitSets[spec.fitSetId]
    end
    return result
end
function Bank:Place(player,payload)
    local doc,why=self:Load(player)
    if not doc then return false,why end
    local entry
    for _,item in ipairs(doc.entries) do
        if item.id==payload.bankId then entry=item break end
    end
    if not entry then return false,"Bank component no longer exists" end
    local targetCF=payload.origin
    if typeof(targetCF)~="CFrame"
        or not self.D.Grid.ValidPosition(targetCF.Position)
        or not Codec.ReadPose(Codec.Pose(targetCF)) then
        return false,"Aim at a valid build surface"
    end
    if self.D.ownedCount(player)+#entry.parts>self.D.Config.MaxPartsPerPlayer then
        return false,"Construction part limit reached"
    end
    if self.D.mechanical:Count(player)+#entry.joints>128 then
        return false,"Mechanical relationship limit reached"
    end
    local d=self.D
    local groupId=HttpService:GenerateGUID(false)
    local idMap,staged,states,fitSets={},{},{},{}
    for _,part in ipairs(entry.parts) do
        idMap[part.id]=HttpService:GenerateGUID(false)
    end
    local function discard()
        for _,model in ipairs(staged) do model:Destroy() end
    end
    for _,part in ipairs(entry.parts) do
        local relative=Codec.ReadPose(part.relative)
        local size=Codec.ReadVec(part.size)
        if not relative or not size then
            discard()
            return false,"Saved component geometry is corrupt"
        end
        local cf=targetCF*relative
        local state={
            instanceId=idMap[part.id],templateId=part.template,
            position=cf.Position,orientation=cf.Rotation,
            steps=part.steps,size=size,
            componentId=groupId,componentAnchorId=idMap[entry.anchorId],
            fitPivotLocal=if part.fitPivot then Codec.ReadVec(part.fitPivot) else nil,
            componentFitPivotLocal=if part.id==entry.anchorId and part.componentPivot
                then Codec.ReadVec(part.componentPivot) else nil,
            alignedOpeningId=if part.alignedOpening
                then idMap[part.alignedOpening] else nil,
            fitPrecision=part.fitPrecision==true,
            resizePrecision=part.resizePrecision==true,
            numericPrecision=part.numericPrecision==true,
            freePosition=true,grounded=false,
            alignedOffsetU=if part.alignedOpening
                and idMap[part.alignedOpening] then part.alignedOffsetU or 0
                else 0,
            shaftRollDegrees=if part.alignedOpening
                and idMap[part.alignedOpening] then part.shaftRollDegrees or 0
                else 0,
            materialId=part.material or "Steel",
            paintFinish=part.paintFinish or "Factory",
            paintColorHex=part.paintHex,
        }
        local primitive=d.Registry.Get(state.templateId)
        if not primitive then discard()
            return false,"Saved primitive template is no longer available" end
        local valid,message=d.validState(player,primitive,state)
        if not valid then discard() return false,message end
        local model,reason=d.createFromTemplate(player,state.templateId,
            state.instanceId,true)
        if not model then discard() return false,reason end
        d.applyState(model,state)
        table.insert(staged,model)
        table.insert(states,state)
    end
    -- Validate against existing world BEFORE parenting or authoring joints.
    -- Overlap among the blueprint's own authored parts remains permissible.
    for _,model in ipairs(staged) do
        if d.intersectsConstructed(model) then
            discard()
            return false,"Component bank placement intersects existing geometry"
        end
    end
    local joints={}
    for _,spec in ipairs(entry.joints) do
        local mapped,why=remapFit(spec,idMap,fitSets)
        if not mapped then discard() return false,why end
        mapped.componentId=groupId
        mapped.ownerUserId=player.UserId
        table.insert(joints,mapped)
    end
    for _,model in ipairs(staged) do model.Parent=d.folder end
    local created={}
    for _,spec in ipairs(joints) do
        local called,ok,reason=pcall(function()
            return d.mechanical:Restore(player,spec)
        end)
        if not called or not ok then
            -- A thrown native constraint error must be as atomic as a
            -- returned validation failure; nothing leaks into the plot.
            local partial=d.mechanical:OwnedRelation(player,spec.relationId)
            if partial then d.mechanical:DestroyRelation(partial) end
            for _,id in ipairs(created) do
                local relation=d.mechanical:OwnedRelation(player,id)
                if relation then d.mechanical:DestroyRelation(relation) end
            end
            discard()
            return false,"Could not restore blueprint relationship: "
                ..tostring(if called then reason else ok)
        end
        table.insert(created,spec.relationId)
    end
    if #joints>0 then
        d.commitAssembly(player,{},states,joints,false)
    else
        d.commitBatch(player,{},states)
    end
    return true,"Placed "..entry.name.." with "..#joints.." internal relationships",
        {componentId=groupId}
end
function Bank:Handle(player,action,payload)
    if action=="ListComponentBank" then return self:List(player) end
    if action=="GetComponentBank" then return self:Get(player,payload) end
    if action=="RegisterComponentBank" then return self:Register(player,payload) end
    if action=="RemoveComponentBank" then return self:Remove(player,payload) end
    if action=="PlaceComponentBank" then return self:Place(player,payload) end
    return false,"Unknown component bank operation"
end
return Bank
