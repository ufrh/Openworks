--!strict
-- FORGE Q3: feature-retained mechanical relationships owned by the server.
-- Installation requires an authored, physically placed cylinder through two bores.
local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local FORGE=require(RS:WaitForChild("FORGE"))
local Assembly=RS:WaitForChild("Openworks"):WaitForChild("Assembly")
local FORM=RS.Openworks:WaitForChild("FORM")
local Graph=require(Assembly.RelationshipGraph)
local Matcher=require(Assembly.FeatureMatcher)
local ShaftFit=require(Assembly.ShaftFit)
local Features=require(FORM.Features)
local Service=FORGE.Service("OpenWorksAssembly")
local MAX_JOINTS=128

local function ownDocuments(player:Player)
 local service=FORGE:GetService("OpenWorksDocuments")
 return service and service.documents[player]
end
local function graphFor(self:any,player:Player)
 local graph=self.graphs[player]
 if not graph then graph=Graph.new() self.graphs[player]=graph end
 return graph
end
function Service:Init()
 self.graphs={}
 self:Expose("ListJoints")
 self:Expose("Install")
 self:Expose("Remove")
 self:Expose("SetActuator")
 self:Track(Players.PlayerRemoving:Connect(function(player)
  local documents=FORGE:GetService("OpenWorksDocuments")
  if documents and documents.SaveNow then documents:SaveNow(player,true) end
  task.delay(2,function()self.graphs[player]=nil end)
 end))
end
function Service:ListJoints(player:Player)
 return true,graphFor(self,player):list()
end
function Service:Install(player:Player,kind:any,idA:any,featureA:any,
 idB:any,featureB:any,shaftId:any,relativePose:any,shaftRelative:any)
 if typeof(kind)~="string" or typeof(idA)~="number"
  or typeof(idB)~="number" or idA%1~=0 or idB%1~=0
  or idA==idB or typeof(featureA)~="string"
  or typeof(featureB)~="string" or typeof(shaftId)~="number"
  or shaftId%1~=0 or shaftId==idA or shaftId==idB then
  return false,"Invalid mechanical installation"
 end
 local document=ownDocuments(player)
 if not document then return false,"No manufactured components" end
 local a,b=document.components[idA],document.components[idB]
 local shaft=document.components[shaftId]
 if not a or not b or not shaft then
  return false,"Two bodies and a manufactured shaft must be owned" end
 if shaft.nodes[1].kind~="Cylinder" or #shaft.operations>0 then
  return false,"The connector must be a manufactured uncut cylinder"
 end
 local fa=Features.get(a,featureA)
 local fb=Features.get(b,featureB)
 if not fa or not fb or not Matcher.compatible(fa,fb) then
  return false,"Only compatible drilled features can be mated"
 end
 if not Graph.Types[kind] then return false,"Unknown mechanical relationship" end
 if (kind~="Rigid" and kind~="Revolute") then
  return false,"Only shaft-based rigid and hinge joints are installed here"
 end
 if typeof(relativePose)~="CFrame" or relativePose.Position.Magnitude>16
  or typeof(shaftRelative)~="CFrame"
  or shaftRelative.Position.Magnitude>16 then
  return false,"Install needs a valid relative physical assembly pose"
 end
 for _,frame in ipairs({relativePose,shaftRelative}) do
  for _,value in ipairs({frame:GetComponents()}) do
  if value~=value or value==math.huge or value==-math.huge then
   return false,"Invalid component pose"
  end
  end
 end
 if (kind=="Rigid" or kind=="Revolute") and
  (not fa.through or not fb.through) then
  return false,"Bolt/pin installation currently requires through holes"
 end
 local world=FORGE:GetService("OpenWorksWorld")
 if not world or not world.SourceFrame then
  return false,"Server manufacturing compiler unavailable"
 end
 local frameA=world:SourceFrame(player,idA,a)
 local frameB=world:SourceFrame(player,idB,b)
 local frameS=world:SourceFrame(player,shaftId,shaft)
 if not frameA or not frameB or not frameS then
  return false,"Both installed components must have valid manufactured geometry"
 end
 local fitting,whyFit=ShaftFit.validate(fa,fb,relativePose,
  frameA,frameB,shaft.nodes[1].size,shaftRelative)
 if not fitting then return false,whyFit end
 local graph=graphFor(self,player)
 if #graph:list()>=MAX_JOINTS then
  return false,"Assembly relationship limit reached"
 end
 local joint,why=graph:add(kind,
  {componentId=idA,featureId=featureA},
  {componentId=idB,featureId=featureB},nil,shaftId)
 if not joint then return false,why end
 joint.relativePose=relativePose
 joint.shaftRelative=shaftRelative
 local documents=FORGE:GetService("OpenWorksDocuments")
 if documents and documents.Changed then documents:Changed(player,nil,false) end
 if world and world.RefreshJoints then
  task.defer(function()world:RefreshJoints(player)end)
 end
 return true,joint
end
function Service:Remove(player:Player,id:any)
 if typeof(id)~="number" or id%1~=0 then return false,"Invalid joint ID" end
 local graph=graphFor(self,player)
 if not graph:remove(id) then return false,"Joint not found" end
 local documents=FORGE:GetService("OpenWorksDocuments")
 if documents and documents.Changed then documents:Changed(player,nil,false) end
 local world=FORGE:GetService("OpenWorksWorld")
 if world and world.RefreshJoints then
  task.defer(function()world:RefreshJoints(player)end)
 end
 return true,nil
end
function Service:SetActuator(player:Player,id:any,speed:any,torque:any)
 if typeof(id)~="number" or typeof(speed)~="number"
  or typeof(torque)~="number" or speed~=speed or torque~=torque
  or math.abs(speed)>16 or torque<0 or torque>50000 then
  return false,"Actuator limits: |speed| <= 16 rad/s, torque 0..50000"
 end
 local joint=graphFor(self,player).joints[id]
 if not joint then return false,"Joint not found" end
 if joint.kind~="Revolute" then
  return false,"Q4 motors currently drive revolute joints only"
 end
 joint.actuation={enabled=torque>0 and speed~=0,speed=speed,torque=torque}
 local docs=FORGE:GetService("OpenWorksDocuments")
 if docs and docs.Changed then docs:Changed(player,nil,false) end
 local world=FORGE:GetService("OpenWorksWorld")
 if world and world.ApplyActuation then world:ApplyActuation(player,id) end
 return true,joint.actuation
end
function Service:RemoveComponent(player:Player,id:number)
 local graph=self.graphs[player]
 if graph then graph:removeComponent(id) end
 local world=FORGE:GetService("OpenWorksWorld")
 if world and world.RefreshJoints then
  task.defer(function()world:RefreshJoints(player)end)
 end
end
function Service:Restore(player:Player,joints:any)
 local graph=graphFor(self,player)
 graph:restore(joints)
 -- Sanitize restored feature references against the loaded document.
 local doc=ownDocuments(player)
 for id,joint in pairs(graph.joints) do
  local a=doc and doc.components[joint.a.componentId]
  local b=doc and doc.components[joint.b.componentId]
  local shaft=doc and doc.components[joint.shaftId]
  if not a or not b or not shaft or shaft.nodes[1].kind~="Cylinder"
   or not Matcher.compatible(Features.get(a,joint.a.featureId),
    Features.get(b,joint.b.featureId)) then
   graph.joints[id]=nil
  end
 end
end
function Service:Stop()
 self.graphs={}
end
return Service
