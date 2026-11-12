--!strict
-- Versioned player plot persistence. Autosave only successful edits from a
-- loaded plot, with manual Save/Load and safe final flush on leave/shutdown.
-- Existing manual saves remain readable under the same DataStore key.
local DataStoreService=game:GetService("DataStoreService")
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local shared=game:GetService("ReplicatedStorage")
    :WaitForChild("Openworks"):WaitForChild("Construction")
local HandCrankMath=require(shared:WaitForChild("HandCrankMath"))
local PaintCatalog=require(shared:WaitForChild("PaintCatalog"))
local Config=require(shared:WaitForChild("BuildConfig"))

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
        LastWriteAt={},
        LastWrittenDocument={},
        KnownCloudRevision={},
        Dirty={},
        DirtySince={},
        LastAttemptAt={},
        AutoSaveActive=false,
    },Persistence)
end

function Persistence:Key(player)
    return "player_"..tostring(player.UserId)
end

function Persistence:Status(player,status,message)
    player:SetAttribute("OPENWORKS_SaveState",status)
    player:SetAttribute("OPENWORKS_SaveMessage",message or "")
end

function Persistence:MarkDirty(player)
    -- The first successful mutation starts a pending autosave window.
    -- Ongoing edits must not postpone periodic saves indefinitely.
    if not self.Dirty[player] then
        self.DirtySince[player]=os.clock()
    end
    self.Dirty[player]=true
    player:SetAttribute("OPENWORKS_AutoSavePending",true)
end

function Persistence:MarkSaved(player,document,mode)
    self.Dirty[player]=false
    self.DirtySince[player]=nil
    self.LastWriteAt[player]=os.clock()
    self.LastWrittenDocument[player]=document
    self.KnownCloudRevision[player]={
        id=document.writeId,
        savedAt=document.savedAt,
    }
    player:SetAttribute("OPENWORKS_AutoSavePending",false)
    player:SetAttribute("OPENWORKS_LastSavedAt",document.savedAt or 0)
    player:SetAttribute("OPENWORKS_LastSaveMode",mode)
end

function Persistence:ShouldAutoSave(player)
    if not Config.AutoSaveEnabled or not self.Ready[player]
        or not self.Dirty[player] or self.Busy[player]
        or not self.D.plots:Get(player) then return false end
    local now=os.clock()
    return now-(self.LastWriteAt[player] or now)>=Config.AutoSaveIntervalSeconds
        and now-(self.DirtySince[player] or now)>=Config.AutoSaveDebounceSeconds
        and now-(self.LastAttemptAt[player] or 0)>=Config.AutoSaveRetrySeconds
end

function Persistence:StartAutoSave()
    if self.AutoSaveActive then return end
    self.AutoSaveActive=true
    task.spawn(function()
        while self.AutoSaveActive do
            task.wait(Config.AutoSaveCheckSeconds)
            if not self.AutoSaveActive then break end
            for _,player in ipairs(Players:GetPlayers()) do
                if self:ShouldAutoSave(player) then
                    task.spawn(function()
                        local ok,why=self:Save(player,"Auto")
                        if not ok then
                            warn("[OPENWORKS] Autosave for "..player.Name
                                .." failed: "..tostring(why))
                        end
                    end)
                end
            end
        end
    end)
end

function Persistence:StopAutoSave()
    self.AutoSaveActive=false
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
                material=snap.materialId,
                paintFinish=snap.paintFinish,
                paintHex=snap.paintColorHex,
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
            or not short(record.alignedOpening,64)
            or not PaintCatalog.IsValidFinish(
                record.paintFinish or "Factory")
            or (record.paintHex~=nil and
                PaintCatalog.NormalizeHex(record.paintHex)==nil) then
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
            or not (if HandCrankMath.IsCrank(entry.Model)
                then HandCrankMath.ValidSize(entry.Model.PrimaryPart.Size,size)
                else d.grid.ValidSize(entry.Model.PrimaryPart.Size,size,
                    entry.ResizeMode,record.fitPrecision==true,
                    record.numericPrecision==true))
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
            materialId=record.material or "Steel",
            paintFinish=record.paintFinish or "Factory",
            paintColorHex=PaintCatalog.NormalizeHex(record.paintHex),
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
    -- Retired arbitrary-joint types can appear in older manual saves.
    -- Keep physical construction and valid relationships loadable instead
    -- of failing the entire plot on a deleted imaginary joint.
    local supported={}
    local skipped=0
    for _,spec in ipairs(document.joints) do
        if spec.kind=="AxisHinge" or spec.kind=="AxisBall"
            or spec.kind=="AxisUniversal" or spec.kind=="PoweredHinge" then
            skipped+=1
        else
            table.insert(supported,spec)
        end
    end
    if skipped>0 then
        warn("[OPENWORKS] Skipped "..skipped..
            " retired arbitrary-axis joint(s) during plot load")
    end
    return parsed,supported
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
    -- Named assemblies are now explicitly authored; their IDs and names
    -- already live on each restored primitive. The retired NextNumber
    -- counter no longer exists and must not be touched during plot load.
    return true,string.format("Loaded %d parts and %d relationships",
        #states,#specs)
end

-- Read-only load. Never write back failed, malformed or missing data.
function Persistence:Load(player)
    if self.Busy[player] then return false,"Plot storage is busy" end
    if not self.D.plots:Get(player) then return false,"Plot not assigned" end
    self.Busy[player]=true
    self:Status(player,"Loading","Loading latest saved plot")
    -- Recently acknowledged writes take precedence over GetAsync cache.
    local recent=self.LastWrittenDocument[player]
    local useRecent=recent and self.LastWriteAt[player]
        and os.clock()-self.LastWriteAt[player]<30
    local ok,document
    if useRecent then
        ok,document=true,recent
    else
        ok,document=pcall(function()
            return self.Store:GetAsync(self:Key(player))
        end)
    end
    if not ok then
        self.Busy[player]=nil
        self.Ready[player]=false
        self:Status(player,"Error","Storage unavailable • autosave disabled")
        warn("[OPENWORKS] Plot load failed: "..tostring(document))
        return false,"Could not access plot storage; prior cloud save intact"
    end
    if not player.Parent then
        self.Busy[player]=nil
        return false,"Player left"
    end
    local target=if document==nil
        then {version=SCHEMA_VERSION,parts={},joints={}}
        else document
    local completed,result,message=pcall(self.Apply,self,player,target)
    self.Busy[player]=nil
    if not completed then
        warn("[OPENWORKS] Plot apply failed: "..tostring(result))
        message="Plot load failed unexpectedly; check Output"
        result=false
    end
    self.Ready[player]=result==true
    if result then
        -- Empty means no save ONLY when GetAsync itself succeeded.
        self.KnownCloudRevision[player]=if document==nil then false else {
            id=document.writeId,
            savedAt=document.savedAt,
        }
        self.LastWriteAt[player]=os.clock()
        self.LastWrittenDocument[player]=document
        self.Dirty[player]=false
        self.DirtySince[player]=nil
        self.LastAttemptAt[player]=nil
        player:SetAttribute("OPENWORKS_AutoSavePending",false)
        local at=document and document.savedAt or 0
        player:SetAttribute("OPENWORKS_LastSavedAt",
            if finite(at) then at else 0)
        player:SetAttribute("OPENWORKS_LastSaveMode",if document
            then (document.saveMode or "Previous") else "None")
        if document==nil then
            message="Empty plot loaded • autosave enabled"
        end
        self:Status(player,"Ready",message)
    else
        self:Status(player,"Error",message)
    end
    return result,message
end

-- A newer writer must never be silently overwritten. New saves carry a
-- writeId; legacy manual saves compare their savedAt timestamp on migration.
local function sameCloudRevision(cloud,expected,attempt)
    if type(cloud)=="table" and cloud.writeId==attempt.writeId then
        -- Idempotent on UpdateAsync internal retries.
        return true
    end
    if expected==false then return cloud==nil end
    if type(expected)~="table" or type(cloud)~="table" then return false end
    if expected.id then return cloud.writeId==expected.id end
    return cloud.writeId==nil and cloud.savedAt==expected.savedAt
end

-- All four save modes use the SAME version-protected write path.
function Persistence:Save(player,mode)
    mode=mode or "Manual"
    if self.Busy[player] or not self.Ready[player] then
        return false,"Plot not fully loaded; saving disabled to protect cloud data"
    end
    if mode~="Manual" and not self.Dirty[player] then
        return true,"No unsaved changes"
    end
    if mode=="Manual" and self.LastManualSave[player]
        and os.clock()-self.LastManualSave[player]<4 then
        return false,"Save was just requested; try again shortly"
    end
    self.Busy[player]=true
    self.LastAttemptAt[player]=os.clock()
    local completed,document,problem=pcall(self.Encode,self,player)
    if not completed or not document then
        self.Busy[player]=nil
        if not completed then
            warn("[OPENWORKS] Plot encode failed: "..tostring(document))
        end
        self:Status(player,"Ready","Save blocked • previous cloud save intact")
        return false,if completed then tostring(problem)
            else "Plot encode error (see Studio Output)"
    end
    document.writeId=HttpService:GenerateGUID(false)
    document.saveMode=mode
    local expected=self.KnownCloudRevision[player]
    self:Status(player,"Saving",if mode=="Auto"
        then "Autosaving construction" else "Saving construction")
    local conflict=false
    local ok,saved=pcall(function()
        return self.Store:UpdateAsync(self:Key(player),function(cloud)
            if not sameCloudRevision(cloud,expected,document) then
                conflict=true
                return nil
            end
            return document
        end)
    end)
    self.Busy[player]=nil
    if not ok then
        warn("[OPENWORKS] "..mode.." save failed: "..tostring(saved))
        self:Status(player,"Ready","Save failed • unsaved changes kept")
        return false,"DataStore write failed; unsaved work is still in this server"
    end
    if conflict or saved==nil then
        self.Ready[player]=false
        self:Status(player,"Error","Cloud plot changed elsewhere • reload required")
        return false,"Cloud plot was updated elsewhere; local edits not overwritten"
    end
    if mode=="Manual" then self.LastManualSave[player]=os.clock() end
    self:MarkSaved(player,document,mode)
    self:Status(player,"Ready",if mode=="Auto" then
        "Autosaved successfully" elseif mode=="Exit" then
        "Saved on exit" elseif mode=="Shutdown" then
        "Saved on shutdown" else "Saved manually")
    return true,string.format("Saved %d parts and %d relationships",
        #document.parts,#document.joints)
end

function Persistence:Flush(player,mode)
    local started=os.clock()
    while self.Busy[player] and os.clock()-started<18 do
        task.wait(0.1)
    end
    if self.Busy[player] then
        return false,"Previous save is still running"
    end
    if not self.Ready[player] then
        return false,"Cloud plot not loaded; refusing unsafe exit save"
    end
    return self:Save(player,mode or "Exit")
end

function Persistence:Clear(player)
    self.Ready[player]=nil
    self.Busy[player]=nil
    self.LastManualSave[player]=nil
    self.LastWriteAt[player]=nil
    self.LastWrittenDocument[player]=nil
    self.KnownCloudRevision[player]=nil
    self.Dirty[player]=nil
    self.DirtySince[player]=nil
    self.LastAttemptAt[player]=nil
end

return Persistence
