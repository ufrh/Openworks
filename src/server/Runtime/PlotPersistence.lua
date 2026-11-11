--!strict
-- Versioned manual-only player plot persistence.
-- NEVER call Save from PlayerRemoving, BindToClose or a timer.
local DataStoreService=game:GetService("DataStoreService")
local HttpService=game:GetService("HttpService")

local Persistence={}
Persistence.__index=Persistence
local STORE_NAME="OPENWORKS_ManualPlots_v1"
local SCHEMA_VERSION=1
local MAX_JOINTS=128
local MAX_BYTES=3200000

local function finite(n)
    return type(n)=="number" and n==n
        and n~=math.huge and n~=-math.huge
end

local function vec3(v)
    return {v.X,v.Y,v.Z}
end

local function readVec3(value)
    if type(value)~="table" or #value~=3 then return nil end
    for _,v in ipairs(value) do if not finite(v) then return nil end end
    return Vector3.new(value[1],value[2],value[3])
end

local function rotation(cf)
    if typeof(cf)~="CFrame" then return nil end
    local x,y,z,a,b,c,d,e,f,g,h,i=cf:GetComponents()
    return {a,b,c,d,e,f,g,h,i}
end

local function readRotation(value)
    if value==nil then return nil end
    if type(value)~="table" or #value~=9 then return nil end
    for _,n in ipairs(value) do if not finite(n) or math.abs(n)>2 then return nil end end
    local cf=CFrame.new(0,0,0,
        value[1],value[2],value[3],
        value[4],value[5],value[6],
        value[7],value[8],value[9])
    if math.abs(cf.RightVector.Magnitude-1)>0.015
        or math.abs(cf.UpVector.Magnitude-1)>0.015
        or math.abs(cf.RightVector:Dot(cf.UpVector))>0.015 then
        return nil
    end
    return cf.Rotation
end

local function short(value,max)
    return value==nil
        or (type(value)=="string" and #value<=max)
end

function Persistence.new(deps)
    return setmetatable({
        D=deps,
        Store=DataStoreService:GetDataStore(STORE_NAME),
        Ready={},
        Busy={},
        LastManualSave={},
    },Persistence)
end

function Persistence:Key(player)
    return "player_"..tostring(player.UserId)
end

function Persistence:Status(player,status,message)
    player:SetAttribute("OPENWORKS_SaveState",status)
    player:SetAttribute("OPENWORKS_SaveMessage",message or "")
end

function Persistence:Encode(player)
    local d=self.D
    local plot=d.plots:Get(player)
    if not plot then return nil,"Plot unavailable" end
    local parts,ids={},{}
    for _,model in ipairs(d.folder:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("OwnerUserId")==player.UserId then
            local snap=d.snapshot(model)
            if not d.plots:Contains(player,snap.position,snap.size) then
                return nil,"Move every construction inside your plot before saving"
            end
            local pos=snap.position-plot.origin
            local record={
                id=snap.instanceId,
                template=snap.templateId,
                pos=vec3(pos),
                size=vec3(snap.size),
                steps=snap.steps,
                rotation=rotation(snap.orientation),
                component=snap.componentId,
                anchor=snap.componentAnchorId,
                assemblyPrecision=snap.assemblyPrecision,
                resizePrecision=snap.resizePrecision,
                freePosition=snap.freePosition,
                fitPrecision=snap.fitPrecision,
                numericPrecision=snap.numericPrecision,
                alignedOpening=snap.alignedOpeningId,
                grounded=snap.grounded,
                assembly=snap.assemblyId,
                assemblyName=snap.assemblyName,
                roll=snap.shaftRollDegrees,
                offset=snap.alignedOffsetU,
            }
            if type(record.id)~="string" or ids[record.id] then
                return nil,"Duplicate construction ID; cannot save safely"
            end
            ids[record.id]=true
            table.insert(parts,record)
        end
    end
    table.sort(parts,function(a,b) return a.id<b.id end)
    local joints={}
    for _,relation in ipairs(d.mechanical.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId then
            local spec=d.mechanical:Snapshot(relation)
            if not ids[spec.sourceId] or not ids[spec.targetId]
                or (spec.secondTargetId and not ids[spec.secondTargetId]) then
                return nil,"A mechanical relationship has a missing part"
            end
            table.insert(joints,spec)
        end
    end
    table.sort(joints,function(a,b) return a.relationId<b.relationId end)
    local document={
        version=SCHEMA_VERSION,
        savedAt=os.time(),
        parts=parts,
        joints=joints,
    }
    local ok,encoded=pcall(function() return HttpService:JSONEncode(document) end)
    if not ok or #encoded>MAX_BYTES then
        return nil,"Plot save exceeds the storage limit"
    end
    return document,#encoded
end

function Persistence:Decode(player,document)
    local d=self.D
    local plot=d.plots:Get(player)
    if not plot then return nil,"Plot unavailable" end
    if type(document)~="table" or document.version~=SCHEMA_VERSION
        or type(document.parts)~="table"
        or type(document.joints)~="table" then
        return nil,"Save format is unsupported"
    end
    if #document.parts>d.config.MaxPartsPerPlayer
        or #document.joints>MAX_JOINTS then
        return nil,"Save exceeds construction or relationship limits"
    end
    local parsed,ids={},{}
    for _,record in ipairs(document.parts) do
        if type(record)~="table"
            or type(record.id)~="string" or #record.id>64
            or ids[record.id] or type(record.template)~="string"
            or not short(record.component,64)
            or not short(record.anchor,64)
            or not short(record.assembly,64)
            or not short(record.assemblyName,80)
            or not short(record.alignedOpening,64) then
            return nil,"Corrupt construction metadata in plot save"
        end
        local entry=d.registry.Get(record.template)
        local pos=readVec3(record.pos)
        local size=readVec3(record.size)
        local cf=readRotation(record.rotation)
        if not entry or not pos or not size
            or (record.rotation~=nil and not cf)
            or not d.grid.ValidSteps(record.steps) then
            return nil,"Invalid saved template, size, position or orientation"
        end
        pos+=plot.origin
        if not d.grid.ValidPosition(pos)
            or not d.grid.ValidSize(entry.Model.PrimaryPart.Size,size,
                entry.ResizeMode,record.fitPrecision==true,
                record.numericPrecision==true)
            or not d.plots:Contains(player,pos,size) then
            return nil,"Saved construction is outside plot or has invalid geometry"
        end
        if not finite(record.roll or 0) or not finite(record.offset or 0) then
            return nil,"Invalid saved alignment"
        end
        ids[record.id]=true
        table.insert(parsed,{
            instanceId=record.id,templateId=record.template,
            position=pos,size=size,steps=record.steps,orientation=cf,
            componentId=record.component,componentAnchorId=record.anchor,
            assemblyPrecision=record.assemblyPrecision==true,
            resizePrecision=record.resizePrecision==true,
            freePosition=record.freePosition==true,
            fitPrecision=record.fitPrecision==true,
            numericPrecision=record.numericPrecision==true,
            alignedOpeningId=record.alignedOpening,
            grounded=record.grounded==true,
            assemblyId=record.assembly,assemblyName=record.assemblyName,
            shaftRollDegrees=record.roll or 0,
            alignedOffsetU=record.offset or 0,
        })
    end
    local seen={}
    for _,spec in ipairs(document.joints) do
        if type(spec)~="table"
            or type(spec.relationId)~="string" or #spec.relationId>64
            or seen[spec.relationId] or not ids[spec.sourceId]
            or not ids[spec.targetId]
            or (spec.secondTargetId and not ids[spec.secondTargetId]) then
            return nil,"Corrupt saved mechanical relationship"
        end
        seen[spec.relationId]=true
    end
    return parsed,document.joints
end

function Persistence:Apply(player,document)
    local d=self.D
    local states,specs=self:Decode(player,document)
    if not states then return false,specs end
    local staged={}
    for _,state in ipairs(states) do
        local model,reason=d.createFromTemplate(player,state.templateId,
            state.instanceId,true)
        if not model then
            for _,item in ipairs(staged) do item:Destroy() end
            return false,reason
        end
        d.applyState(model,state)
        table.insert(staged,model)
    end
    local oldParts,oldSpecs={},{}
    for _,model in ipairs(d.folder:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("OwnerUserId")==player.UserId then
            table.insert(oldParts,model)
        end
    end
    for _,relation in ipairs(d.mechanical.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId then
            table.insert(oldSpecs,d.mechanical:Snapshot(relation))
        end
    end
    for _,relation in ipairs(d.mechanical.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId then
            d.mechanical:DestroyRelation(relation)
        end
    end
    for _,model in ipairs(oldParts) do model.Parent=nil end
    for _,model in ipairs(staged) do model.Parent=d.folder end
    local restored={}
    local success,err=pcall(function()
        for _,spec in ipairs(specs) do
            local ok,message=d.mechanical:Restore(player,spec)
            if not ok then error(message) end
            table.insert(restored,spec.relationId)
        end
    end)
    if not success then
        for _,id in ipairs(restored) do
            local relation=d.mechanical:OwnedRelation(player,id)
            if relation then d.mechanical:DestroyRelation(relation) end
        end
        for _,model in ipairs(staged) do model:Destroy() end
        for _,model in ipairs(oldParts) do model.Parent=d.folder end
        for _,spec in ipairs(oldSpecs) do
            local ok,why=d.mechanical:Restore(player,spec)
            if not ok then
                warn("[OPENWORKS] Plot rollback relationship failed: "..tostring(why))
            end
        end
        return false,"Could not restore the saved mechanism: "..tostring(err)
    end
    for _,model in ipairs(oldParts) do model:Destroy() end
    local history=d.histories[player]
    if history then table.clear(history.undo) table.clear(history.redo) end
    -- Assembly labels continue after the highest restored display number.
    local maximum=0
    for _,state in ipairs(states) do
        local num=type(state.assemblyName)=="string"
            and tonumber(string.match(state.assemblyName,"^Assembly (%d+)$"))
        if num then maximum=math.max(maximum,num) end
    end
    d.assemblies.NextNumber[player]=maximum
    return true,string.format("Loaded %d parts and %d relationships",
        #states,#specs)
end

function Persistence:Load(player)
    if self.Busy[player] then return false,"Plot storage is busy" end
    if not self.D.plots:Get(player) then return false,"Plot not assigned" end
    self.Busy[player]=true
    self:Status(player,"Loading","Loading your last manual save")
    local ok,document=pcall(function() return self.Store:GetAsync(self:Key(player)) end)
    if not ok then
        self.Busy[player]=nil
        self.Ready[player]=false
        self:Status(player,"Error","Storage unavailable. Enable Studio API access")
        warn("[OPENWORKS] Plot load failed: "..tostring(document))
        return false,"Could not access plot storage; your existing construction was not erased"
    end
    if not player.Parent then self.Busy[player]=nil return false,"Player left" end
    local result,message=true,"New empty plot"
    if document~=nil then
        result,message=self:Apply(player,document)
    end
    self.Busy[player]=nil
    self.Ready[player]=result
    if result then
        local savedAt=document and document.savedAt or 0
        player:SetAttribute("OPENWORKS_LastSavedAt",
            if finite(savedAt) then savedAt else 0)
        self:Status(player,"Ready",message)
    else
        self:Status(player,"Error",message)
    end
    return result,message
end

function Persistence:Save(player)
    if self.Busy[player] or not self.Ready[player] then
        return false,"Plot not loaded; saving is disabled to protect your data"
    end
    if self.LastManualSave[player]
        and os.clock()-self.LastManualSave[player]<4 then
        return false,"Save was just requested; try again shortly"
    end
    self.Busy[player]=true
    local document,problem=self:Encode(player)
    if not document then
        self.Busy[player]=nil
        return false,problem
    end
    self:Status(player,"Saving","Writing your manual save")
    -- This is the ONLY DataStore WRITE anywhere in OPENWORKS. No autosave.
    local ok,err=pcall(function()
        self.Store:SetAsync(self:Key(player),document)
    end)
    self.Busy[player]=nil
    if not ok then
        warn("[OPENWORKS] Manual save failed: "..tostring(err))
        self:Status(player,"Ready","Save FAILED; your previous save is intact")
        return false,"Save failed; previous save was not intentionally overwritten"
    end
    self.LastManualSave[player]=os.clock()
    player:SetAttribute("OPENWORKS_LastSavedAt",document.savedAt)
    self:Status(player,"Ready","Saved manually")
    return true,string.format("Saved %d parts and %d relationships",
        #document.parts,#document.joints)
end

function Persistence:Clear(player)
    -- Intentionally no save on player leave or server shutdown.
    self.Ready[player]=nil
    self.Busy[player]=nil
    self.LastManualSave[player]=nil
end

return Persistence
