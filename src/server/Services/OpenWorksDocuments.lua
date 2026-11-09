--!strict
-- FORGE server authority for Q2 manufacturing source documents.
-- Workspaces, sketches and operation histories are data, not client-owned
-- MeshParts. Generated CSG meshes remain local previews until acceptance.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local FORGE=require(ReplicatedStorage:WaitForChild("FORGE"))
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Document=require(FORM.Document)
local Fabricator = require(FORM.Fabricator)
local Quantize=require(FORM.Quantize)
local Store=require(script.Parent.Parent.Persistence.DocumentStore)
local HttpService=game:GetService("HttpService")
local Service=FORGE.Service("OpenWorksDocuments")

local MAX_COMPONENTS=96
local MAX_OPERATIONS=256
local function finiteVector(value:any):boolean
 return typeof(value)=="Vector3" and
  Quantize.isFinite(value.X) and Quantize.isFinite(value.Y)
  and Quantize.isFinite(value.Z)
end
local function finiteSize(value:any):boolean
 return finiteVector(value) and value.X>=Quantize.MinSize
  and value.Z>=Quantize.MinSize and value.Y>=Quantize.MinSize
  and value.X<=Quantize.MaxSize and value.Y<=Quantize.MaxSize
  and value.Z<=Quantize.MaxSize
end
local function getDocument(self:any,player:Player):any
 local current=self.documents[player]
 if current then return current end
 -- Only one load for each player; simultaneous first RPCs wait for it.
 while self.loading[player] do
  task.wait()
  current=self.documents[player]
  if current then return current end
 end
 self.loading[player]=true
 current=Document.new()
 local payload,err=self.store:load(player.UserId)
 if err then warn("[OPENWORKS] Load failed for "..player.UserId..": "..err) end
 if payload and type(payload.components)=="table" then
  for i,snapshot in ipairs(payload.components) do
   if i>96 then break end
   local ok,why=pcall(function()
    if type(snapshot)=="table" and type(snapshot.operations)=="table"
     and #snapshot.operations<=256 then
     current:adoptSnapshot(snapshot)
    end
   end)
   if not ok then warn("[OPENWORKS] Skipped saved component: "..tostring(why)) end
  end
 end
 self.documents[player]=current
 self.loading[player]=nil
 if payload then
  local assembly=FORGE:GetService("OpenWorksAssembly")
  if assembly and assembly.Restore then
   assembly:Restore(player,payload.joints,payload.assembly)
  end
  local world=FORGE:GetService("OpenWorksWorld")
  if world and world.RestorePoses then world:RestorePoses(player,payload.poses) end
 end
 return current
end
local function remember(self:any,player:Player,component:any)
 local byPlayer=self.history[player]
 if not byPlayer then byPlayer={} self.history[player]=byPlayer end
 local byComponent=byPlayer[component.id]
 if not byComponent then byComponent={} byPlayer[component.id]=byComponent end
 byComponent[component.revision]=Document.snapshot(component)
 local revisions={}
 for revision in pairs(byComponent) do table.insert(revisions,revision) end
 table.sort(revisions)
 while #revisions>20 do
  byComponent[table.remove(revisions,1)]=nil
 end
end

local function selected(self:any,player:Player,id:any,revision:any)
 local assembly = FORGE:GetService("OpenWorksAssembly")
 if assembly and assembly:IsBusy(player) then
  return nil, nil, "Stop simulation or wait for assembly validation"
 end
 if typeof(id)~="number" or id~=math.floor(id) then
  return nil,nil,"Invalid component ID"
 end
 local doc=getDocument(self,player)
 local component=doc.components[id]
 if not component then return nil,nil,"Component not owned by player" end
 if typeof(revision)~="number" or revision~=component.revision then
  return nil,nil,"Stale component revision"
 end
 return doc,component,nil
end

function Service:Init()
 self.documents={}
 self.history={}
 self.mutating={}
 self.loading={}
 self.dirty={}
 self.sequence={}
 self.savedAt={}
 self.saveErrors={}
 self.store=Store.new()
 self.sessionId=HttpService:GenerateGUID(false)
 self.running=false
 self:Expose("CreateSketchBody")
 self:Expose("CreateBlock")
 self:Expose("CreateCylinder")
 self:Expose("GetSnapshot")
 self:Expose("ListSnapshots")
 self:Expose("ApplyOperation")
 self:Expose("SetOperationEnabled")
 self:Expose("RemoveOperation")
 self:Expose("ApplyTransform")
 self:Expose("EditNode")
 self:Expose("SetNotes")
 self:Expose("UndoOperation")
 self:Expose("DeleteComponent")
 self:Expose("RestoreRevision")
 self:Expose("SaveNow")
 self:Expose("GetSaveStatus")
 self:Track(Players.PlayerRemoving:Connect(function(player)
  self:SaveNow(player)
  self.documents[player]=nil
  self.history[player]=nil
  self.loading[player]=nil
  self.dirty[player]=nil
  self.sequence[player]=nil
  self.savedAt[player]=nil
  self.saveErrors[player]=nil
 end))
end
function Service:Start()
 self.running=true
 task.spawn(function()
  while self.running do
   task.wait(120)
   if not self.running then break end
   for player in pairs(self.documents) do
    if player.Parent then
     -- Persist world physics even if no source-document property changed.
     self:SaveNow(player,true)
    end
   end
  end
 end)
end
function Service:Changed(player:Player,id:number?,geometry:boolean?)
 self.dirty[player]=true
 self.sequence[player]=(self.sequence[player] or 0)+1
 if geometry and id then
  local world=FORGE:GetService("OpenWorksWorld")
  if world and world.QueuePublish then world:QueuePublish(player,id) end
 end
end
function Service:SaveNow(player:Player,force:any?)
 if not force and self.dirty[player]==false and self.savedAt[player] then
  return true,"No unsaved changes"
 end
 local doc=self.documents[player]
 if not doc then return true,"Nothing to save" end
 local components={}
 for _,id in ipairs(doc.order) do
  local component=doc.components[id]
  if component then table.insert(components,Document.snapshot(component)) end
 end
 local assembly=FORGE:GetService("OpenWorksAssembly")
 local graph=assembly and assembly.graphs[player]
 local world=FORGE:GetService("OpenWorksWorld")
 local poses=world and world:PoseSnapshot(player) or {}
 local payload = {
  version = 1, sessionId = self.sessionId,
  sequence = self.sequence[player] or 0, components = components,
  joints = {}, poses = poses,
  assembly = assembly and assembly:Snapshot(player) or nil,
 }
 local ok,reason=self.store:save(player.UserId,payload)
 if ok then
  self.savedAt[player]=os.time()
  self.dirty[player]=false
  self.saveErrors[player]=nil
  FORGE.Metric("OpenWorks.Save.Success"):Add(1)
 else
  self.saveErrors[player]=tostring(reason)
  FORGE.Metric("OpenWorks.Save.Failures"):Add(1)
 end
 return ok,if ok then "Saved" else reason
end
function Service:GetSaveStatus(player:Player)
 return true,{dirty=self.dirty[player]==true,
  lastSaved=self.savedAt[player] or 0,
  error=self.saveErrors[player] or "",
  studioDisabled=self.store.disabled==true}
end

function Service:CreateSketchBody(player:Player,name:any,worldOrigin:any,
 editOrigin:any,size:any,points:any,depth:any)
 local assembly = FORGE:GetService("OpenWorksAssembly")
 if assembly and assembly:IsBusy(player) then
  return false, "Assembly is busy"
 end
 if typeof(name)~="string" or #name<1 or #name>64
  or not name:match("%S") or not finiteVector(worldOrigin)
  or not finiteVector(editOrigin) or not finiteSize(size)
  or math.max(math.abs(worldOrigin.X),math.abs(worldOrigin.Y),
   math.abs(worldOrigin.Z))>Quantize.MaxPosition
  or math.max(math.abs(editOrigin.X),math.abs(editOrigin.Y),
   math.abs(editOrigin.Z))>Quantize.MaxPosition
  or typeof(points)~="table" or #points<3 or #points>64
  or typeof(depth)~="number" or not Quantize.isFinite(depth) then
  return false,"Invalid component specification"
 end
 local doc=getDocument(self,player)
 if #doc.order>=MAX_COMPONENTS then
  return false,"Maximum number of components reached"
 end
 local ok,component,reason=pcall(function()
  return doc:createSketchBody(name,editOrigin,size,points,depth)
 end)
 if not ok then return false,tostring(component) end
 if not component then return false,reason end
 component.worldOrigin=worldOrigin
 remember(self,player,component)
 self:Changed(player,component.id,true)
 return true,Document.snapshot(component)
end

-- Start directly from a dimensioned solid block. Sketching stays optional.
function Service:CreateBlock(player: Player, name: any, worldOrigin: any,
 editOrigin: any, workspaceSize: any, materialSize: any)
 local assembly = FORGE:GetService("OpenWorksAssembly")
 if assembly and assembly:IsBusy(player) then
  return false, "Assembly is busy"
 end
 if typeof(name) ~= "string" or #name < 1 or #name > 64
  or not name:match("%S") or not finiteVector(worldOrigin)
  or not finiteVector(editOrigin) or not finiteSize(workspaceSize)
  or not finiteSize(materialSize)
  or math.max(math.abs(worldOrigin.X), math.abs(worldOrigin.Y),
   math.abs(worldOrigin.Z)) > Quantize.MaxPosition
  or math.max(math.abs(editOrigin.X), math.abs(editOrigin.Y),
   math.abs(editOrigin.Z)) > Quantize.MaxPosition
  or materialSize.X > workspaceSize.X
  or materialSize.Z > workspaceSize.Z
  or materialSize.Y > workspaceSize.Y then
  return false, "Invalid block dimensions or construction workspace"
 end
 local doc = getDocument(self, player)
 if #doc.order >= MAX_COMPONENTS then return false, "Component limit reached" end
 local corner = editOrigin + Vector3.new(
  (workspaceSize.X - materialSize.X) * 0.5,
  0,
  (workspaceSize.Z - materialSize.Z) * 0.5
 )
 local component, reason = doc:create("Block", corner, name, materialSize)
 if not component then return false, reason end
 component.worldOrigin = worldOrigin
 component.workspaceOrigin = editOrigin
 component.workspaceSize = workspaceSize
 remember(self, player, component)
 self:Changed(player, component.id, true)
 return true, Document.snapshot(component)
end

-- Native manufactured cylinder: authored hardware, never generated by assembly.
function Service:CreateCylinder(player:Player,name:any,worldOrigin:any,
 editOrigin:any,workspaceSize:any,diameter:any,length:any)
 local assembly = FORGE:GetService("OpenWorksAssembly")
 if assembly and assembly:IsBusy(player) then
  return false, "Assembly is busy"
 end
 if typeof(name)~="string" or #name<1 or #name>64
  or not name:match("%S") or not finiteVector(worldOrigin)
  or not finiteVector(editOrigin) or not finiteSize(workspaceSize)
  or typeof(diameter)~="number" or typeof(length)~="number"
  or not Quantize.isFinite(diameter) or not Quantize.isFinite(length)
  or diameter<Quantize.MinSize or length<Quantize.MinSize
  or diameter>workspaceSize.X or diameter>workspaceSize.Z
  or length>Quantize.MaxSize then
  return false,"Invalid cylinder dimensions or workspace"
 end
 local doc=getDocument(self,player)
 if #doc.order>=MAX_COMPONENTS then return false,"Component limit reached" end
 local materialSize=Vector3.new(diameter,length,diameter)
 local corner=editOrigin+Vector3.new(
  (workspaceSize.X-diameter)*.5,0,(workspaceSize.Z-diameter)*.5)
 local component,reason=doc:create("Cylinder",corner,name,materialSize)
 if not component then return false,reason end
 component.worldOrigin=worldOrigin
 component.workspaceOrigin=editOrigin
 component.workspaceSize=workspaceSize
 remember(self,player,component)
 self:Changed(player,component.id,true)
 return true,Document.snapshot(component)
end

function Service:ApplyOperation(player: Player, id: any, revision: any,
 kind: any, data: any)
 if self.mutating[player] then
  return false, "Manufacturing operation is already being validated"
 end
 local doc, component, err = selected(self, player, id, revision)
 if not doc then return false, err end
 if typeof(kind) ~= "string" or typeof(data) ~= "table"
  or #component.operations >= MAX_OPERATIONS then
  return false, "Invalid fabrication operation or operation limit reached"
 end
 local mustRemainConnected = kind == "AddPrimitive"
  or (kind == "SketchExtrude" and data.mode == "Add")
 if mustRemainConnected then
  -- Evaluate the new operation on a detached snapshot. Invalid unions
  -- never change the authoritative manufacturing document or revision.
  self.mutating[player] = true
  local trial = Document.snapshot(component)
  local accepted, ok, reason = pcall(function()
   return doc:addOperation(trial, kind, data)
  end)
  if not accepted or not ok then
   self.mutating[player] = nil
   return false, tostring(if accepted then reason else ok)
  end
  local compiled, result = pcall(Fabricator.compile, trial)
  if compiled and result then result:Destroy() end
  self.mutating[player] = nil
  if not compiled then
   return false, "Added material must form one connected solid: " .. tostring(result)
  end
  remember(self, player, component)
  component.operations = trial.operations
  component.revision = trial.revision
 else
  remember(self, player, component)
  local accepted, ok, reason = pcall(function()
   return doc:addOperation(component, kind, data)
  end)
  if not accepted then return false, tostring(ok) end
  if not ok then return false, reason end
 end
 self:Changed(player, component.id, true)
 return true, Document.snapshot(component)
end

function Service:SetOperationEnabled(player:Player,id:any,revision:any,
 operationId:any,enabled:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 if typeof(operationId)~="number" or typeof(enabled)~="boolean" then
  return false,"Invalid feature operation"
 end
 remember(self,player,component)
 local ok,reason=doc:setOperationEnabled(component,operationId,enabled)
 if not ok then return false,reason end
 self:Changed(player,component.id,true)
 return true,Document.snapshot(component)
end

function Service:RemoveOperation(player:Player,id:any,revision:any,operationId:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 if typeof(operationId)~="number" then return false,"Invalid feature ID" end
 remember(self,player,component)
 local ok,reason=doc:removeOperation(component,operationId)
 if not ok then return false,reason end
 self:Changed(player,component.id,true)
 return true,Document.snapshot(component)
end

function Service:ApplyTransform(player:Player,id:any,revision:any,
 nodeId:any,position:any,size:any,rotation:any,faceAnchor:any,rotatePrecision:any,snap:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 if typeof(nodeId)~="number"
  or (position~=nil and not finiteVector(position))
  or (size~=nil and not finiteSize(size))
  or (rotation~=nil and not finiteVector(rotation)) then
  return false,"Invalid transformation"
 end
 local step=if typeof(snap)=="number" and Quantize.isFinite(snap)
  and snap>=Quantize.Size and snap<=2 then snap else Quantize.Grid
 remember(self,player,component)
 local ok,valid,reason=pcall(function()
  return doc:applyTransform(component,nodeId,position,size,rotation,
   faceAnchor==true,rotatePrecision==true,step)
 end)
 if not ok then return false,tostring(valid) end
 if not valid then return false,reason end
 self:Changed(player,component.id,true)
 return true,Document.snapshot(component)
end

function Service:EditNode(player:Player,id:any,revision:any,index:any,
 field:any,axis:any,value:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 if typeof(index)~="number" or typeof(field)~="string"
  or typeof(axis)~="string" or typeof(value)~="number" then
  return false,"Invalid node edit"
 end
 remember(self,player,component)
 local ok,valid,reason=pcall(function()
  return doc:editNode(component,index,field,axis,value)
 end)
 if not ok then return false,tostring(valid) end
 if not valid then return false,reason end
 self:Changed(player,component.id,true)
 return true,Document.snapshot(component)
end

function Service:SetNotes(player:Player,id:any,revision:any,notes:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 if typeof(notes)~="string" or #notes>4096 then
  return false,"Component notes exceed the maximum length"
 end
 remember(self,player,component)
 local ok,reason=doc:setNotes(component,notes)
 if not ok then return false,reason end
 self:Changed(player,component.id,false)
 return true,Document.snapshot(component)
end

function Service:UndoOperation(player:Player,id:any,revision:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 remember(self,player,component)
 local ok,reason=doc:undoOperation(component)
 if not ok then return false,reason end
 self:Changed(player,component.id,true)
 return true,Document.snapshot(component)
end

function Service:DeleteComponent(player:Player,id:any,revision:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 doc:removeComponent(component.id)
 local world=FORGE:GetService("OpenWorksWorld")
 if world and world.RemoveComponent then world:RemoveComponent(player,id) end
 local assembly=FORGE:GetService("OpenWorksAssembly")
 if assembly and assembly.RemoveComponent then assembly:RemoveComponent(player,id) end
 local byPlayer=self.history[player]
 if byPlayer then byPlayer[id]=nil end
 self:Changed(player,id,false)
 return true,nil
end

-- A client may roll back only to a state *previously issued by this server*.
-- This repairs failed local CSG compilations without accepting arbitrary
-- client-authored snapshots as authoritative data.
function Service:RestoreRevision(player:Player,id:any,revision:any,
 targetRevision:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 local history=self.history[player]
 local byComponent=history and history[id]
 local accepted=byComponent and byComponent[targetRevision]
 if not accepted or targetRevision>component.revision then
  return false,"Rollback revision is not in server history"
 end
 remember(self,player,component)
 if not doc:restoreSnapshot(component,accepted) then
  return false,"Unable to restore saved component"
 end
 self:Changed(player,component.id,true)
 return true,Document.snapshot(component)
end

function Service:GetSnapshot(player:Player,id:any)
 local doc=getDocument(self,player)
 if typeof(id)~="number" then return false,"Invalid component" end
 local component=doc.components[id]
 if not component then return false,"Component not found" end
 return true,Document.snapshot(component)
end

function Service:ListSnapshots(player:Player,afterIndex:any)
 local doc=getDocument(self,player)
 local start=if typeof(afterIndex)=="number" and afterIndex%1==0
  then math.clamp(afterIndex,0,#doc.order) else 0
 local result={}
 local last=start
 for index=start+1,math.min(start+4,#doc.order) do
  local component=doc.components[doc.order[index]]
  if component then table.insert(result,Document.snapshot(component)) end
  last=index
 end
 return true,{items=result,nextAfter=if last<#doc.order then last else nil}
end

function Service:SaveAll()
 if self.savedDuringShutdown then return end
 self.savedDuringShutdown=true
 for player in pairs(self.documents) do
  self:SaveNow(player,true)
 end
end
function Service:Stop()
 self.running=false
 self:SaveAll()
 self.documents={}
 self.history={}
end
return Service

