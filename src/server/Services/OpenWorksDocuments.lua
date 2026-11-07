--!strict
-- FORGE server authority for Q2 manufacturing source documents.
-- Workspaces, sketches and operation histories are data, not client-owned
-- MeshParts. Generated CSG meshes remain local previews until acceptance.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local FORGE=require(ReplicatedStorage:WaitForChild("FORGE"))
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Document=require(FORM.Document)
local Quantize=require(FORM.Quantize)
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
 if not current then
  current=Document.new()
  self.documents[player]=current
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
 self:Expose("CreateSketchBody")
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
 self:Track(Players.PlayerRemoving:Connect(function(player)
  self.documents[player]=nil
  self.history[player]=nil
 end))
end

function Service:CreateSketchBody(player:Player,name:any,worldOrigin:any,
 editOrigin:any,size:any,points:any,depth:any)
 if typeof(name)~="string" or #name<1 or #name>64
  or not name:match("%S") or not finiteVector(worldOrigin)
  or not finiteVector(editOrigin) or not finiteSize(size)
  or math.max(math.abs(worldOrigin.X),math.abs(worldOrigin.Y),
   math.abs(worldOrigin.Z))>Quantize.MaxPosition
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
 return true,Document.snapshot(component)
end

function Service:ApplyOperation(player:Player,id:any,revision:any,kind:any,data:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 if typeof(kind)~="string" or typeof(data)~="table"
  or #component.operations>=MAX_OPERATIONS then
  return false,"Invalid fabrication operation or operation limit reached"
 end
 remember(self,player,component)
 local ok,valid,reason=pcall(function()
  return doc:addOperation(component,kind,data)
 end)
 if not ok then return false,tostring(valid) end
 if not valid then return false,reason end
 return true,Document.snapshot(component)
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
 return true,Document.snapshot(component)
end

function Service:RemoveOperation(player:Player,id:any,revision:any,operationId:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 if typeof(operationId)~="number" then return false,"Invalid feature ID" end
 remember(self,player,component)
 local ok,reason=doc:removeOperation(component,operationId)
 if not ok then return false,reason end
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
  and snap>=.01 and snap<=2 then snap else Quantize.Grid
 remember(self,player,component)
 local ok,valid,reason=pcall(function()
  return doc:applyTransform(component,nodeId,position,size,rotation,
   faceAnchor==true,rotatePrecision==true,step)
 end)
 if not ok then return false,tostring(valid) end
 if not valid then return false,reason end
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
 return true,Document.snapshot(component)
end

function Service:UndoOperation(player:Player,id:any,revision:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 remember(self,player,component)
 local ok,reason=doc:undoOperation(component)
 if not ok then return false,reason end
 return true,Document.snapshot(component)
end

function Service:DeleteComponent(player:Player,id:any,revision:any)
 local doc,component,err=selected(self,player,id,revision)
 if not doc then return false,err end
 doc:removeComponent(component.id)
 local byPlayer=self.history[player]
 if byPlayer then byPlayer[id]=nil end
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
 return true,Document.snapshot(component)
end

function Service:GetSnapshot(player:Player,id:any)
 local doc=getDocument(self,player)
 if typeof(id)~="number" then return false,"Invalid component" end
 local component=doc.components[id]
 if not component then return false,"Component not found" end
 return true,Document.snapshot(component)
end

function Service:ListSnapshots(player:Player)
 local doc=getDocument(self,player)
 local result={}
 for _,id in ipairs(doc.order) do
  local component=doc.components[id]
  if component then table.insert(result,Document.snapshot(component)) end
 end
 return true,result
end

function Service:Stop()
 self.documents={}
 self.history={}
end
return Service
