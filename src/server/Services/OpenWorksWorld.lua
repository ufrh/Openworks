--!strict
-- Q4 replicated physics bodies compiled from server-owned FORM histories.
local RS=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local FORGE=require(RS:WaitForChild("FORGE"))
local FORM=RS:WaitForChild("Openworks"):WaitForChild("FORM")
local Assembly=RS.Openworks:WaitForChild("Assembly")
local Fabricator=require(FORM.Fabricator)
local Compiler=require(FORM.Compiler)
local Document=require(FORM.Document)
local Features=require(FORM.Features)
local JointCompiler=require(Assembly.ConstraintCompiler)
local Service=FORGE.Service("OpenWorksWorld")
local function sceneRoot()
 local root=workspace:FindFirstChild("OPENWORKS_Published")
 if not root then
  root=Instance.new("Folder") root.Name="OPENWORKS_Published"
  root.Parent=workspace
 end
 return root
end
function Service:Init()
 self.records={} self.folders={} self.pending={} self.workers={}
 self.enabled={} self.jointInstances={} self.errors={}
 self.restored={}
 self:Expose("PublishAll")
 self:Expose("GetStats")
 self:Track(Players.PlayerRemoving:Connect(function(p)self:RemovePlayer(p)end))
end
function Service:Start()sceneRoot()end
function Service:bucket(player:Player):Folder
 if self.folders[player] then return self.folders[player] end
 local folder=Instance.new("Folder")
 folder.Name=tostring(player.UserId) folder.Parent=sceneRoot()
 self.folders[player]=folder
 return folder
end
function Service:GetStats(player:Player)
 local count,joints=0,0
 for _ in pairs(self.records[player] or {}) do count+=1 end
 for _ in pairs(self.jointInstances[player] or {}) do joints+=1 end
 return true,{published=count,joints=joints,
  busy=self.workers[player]==true,error=self.errors[player] or ""}
end
function Service:_compile(player:Player,id:number)
 local documents=FORGE:GetService("OpenWorksDocuments")
 local doc=documents and documents.documents[player]
 local current=doc and doc.components[id]
 if not current then
  self:RemoveComponent(player,id)
  return
 end
 local snapshot=Document.snapshot(current)
 local ok,part,summary=pcall(function()
  if Fabricator.requiresCompile(snapshot) then return Fabricator.compile(snapshot) end
  return Compiler.nativePart(snapshot.nodes[1]),"native"
 end)
 if not ok or not part or not part:IsA("BasePart") then
  self.errors[player]="Server CSG failed for "..id..": "..tostring(part)
  warn("[OPENWORKS] "..self.errors[player])
  FORGE.Metric("OpenWorks.World.CSGFailures"):Add(1)
  return
 end
 if not doc.components[id] or doc.components[id].revision~=snapshot.revision then
  part:Destroy()
  if doc.components[id] then self:QueuePublish(player,id) end
  return
 end
 local frame=part.CFrame
 local origin=snapshot.worldOrigin or snapshot.workspaceOrigin or Vector3.zero
 local edit=snapshot.workspaceOrigin or Vector3.zero
 local base=CFrame.new(origin-edit)*Compiler.pose(snapshot.nodes[1])*frame
 local records=self.records[player]
 local previous=records and records[id]
 local delta=CFrame.identity
 local linear,angular=Vector3.zero,Vector3.zero
 if previous and previous.part and previous.part.Parent then
  delta=previous.part.CFrame*previous.base:Inverse()
  linear=previous.part.AssemblyLinearVelocity
  angular=previous.part.AssemblyAngularVelocity
 end
 local restored=self.restored[player]
 if restored and typeof(restored[id])=="CFrame" and not previous then
  delta=restored[id]*base:Inverse()
 end
 part.Name="Component_"..id
 part:SetAttribute("OWComponentId",id)
 part:SetAttribute("OWOwner",player.UserId)
 part:SetAttribute("OWRevision",snapshot.revision)
 part:SetAttribute("OWSourceLocalFrame",frame)
 part.Material=Enum.Material.Metal
 part.Color=Color3.fromRGB(170,190,199)
 part.CanCollide=true part.CanTouch=true part.CanQuery=true
 part.Anchored=true part.CastShadow=true
 if part:IsA("MeshPart") or part:IsA("PartOperation") then
  pcall(function()part.CollisionFidelity=Enum.CollisionFidelity.PreciseConvexDecomposition end)
 end
 part.CFrame=delta*base
 local drag=Instance.new("DragDetector")
 drag.Name="OW_ServerPhysicalDrag"
 drag.ResponseStyle=Enum.DragDetectorResponseStyle.Physical
 drag.DragStyle=Enum.DragDetectorDragStyle.TranslatePlaneOrLine
 drag.RunLocally=false drag.Responsiveness=11
 drag.MaxForce=math.clamp(part:GetMass()*1600,500,85000)
 drag.MaxTorque=math.clamp(part:GetMass()*1000,200,50000)
 drag:SetPermissionPolicyFunction(function(who:Player)return who==player end)
 drag.Parent=part
 part.Parent=self:bucket(player)
 records[id]={part=part,base=base,revision=snapshot.revision}
 if previous and previous.part then previous.part:Destroy() end
 part.Anchored=false
 part.AssemblyLinearVelocity=linear part.AssemblyAngularVelocity=angular
 pcall(function()part:SetNetworkOwner(nil)end)
 FORGE.Metric("OpenWorks.World.Published"):Add(1)
 FORGE.Pulse("OpenWorks","World","Published",{Id=id,Revision=snapshot.revision})
end
function Service:QueuePublish(player:Player,id:number)
 if not self.enabled[player] or not player.Parent then return end
 local queue=self.pending[player] or {}
 self.pending[player]=queue
 queue[id]=true
 if self.workers[player] then return end
 self.workers[player]=true
 task.spawn(function()
  while self.enabled[player] and player.Parent do
   local nextId=nil
   for key in pairs(queue) do nextId=key break end
   if not nextId then break end
   queue[nextId]=nil
   local ok,err=xpcall(function()self:_compile(player,nextId)end,debug.traceback)
   if not ok then self.errors[player]=tostring(err)
    warn("[OPENWORKS] World compiler: "..tostring(err)) end
   task.wait()
  end
  self.workers[player]=nil
  if self.enabled[player] and player.Parent then self:RefreshJoints(player) end
 end)
end
function Service:PublishAll(player:Player)
 local docs=FORGE:GetService("OpenWorksDocuments")
 local doc=docs and docs.documents[player]
 if not doc then return true,"No document yet" end
 if #doc.order>96 then return false,"Physical component budget exceeded" end
 self.enabled[player]=true
 self.records[player]=self.records[player] or {}
 for _,id in ipairs(doc.order) do
  local existing=self.records[player][id]
  if not existing or existing.revision~=doc.components[id].revision then
   self:QueuePublish(player,id)
  end
 end
 return true,"Queued server manufacturing"
end
function Service:RemoveComponent(player:Player,id:number)
 local entries=self.records[player]
 local prior=entries and entries[id]
 if prior then
  if prior.part then prior.part:Destroy() end
  entries[id]=nil
 end
 local pending=self.pending[player]
 if pending then pending[id]=nil end
 self:RefreshJoints(player)
end
function Service:RefreshJoints(player:Player)
 for _,objects in pairs(self.jointInstances[player] or {}) do
  JointCompiler.destroy(objects)
 end
 self.jointInstances[player]={}
 local assembly=FORGE:GetService("OpenWorksAssembly")
 local graph=assembly and assembly.graphs[player]
 local docs=FORGE:GetService("OpenWorksDocuments")
 local document=docs and docs.documents[player]
 local records=self.records[player]
 if not graph or not document or not records then return end
 local parts,features={},{}
 for id,item in pairs(records) do
  parts[id]=item.part
  local component=document.components[id]
  if component then
   local lookup={}
   for _,feature in ipairs(Features.list(component)) do
    lookup[feature.id]=feature
   end
   features[id]=lookup
  end
 end
 local out=self.jointInstances[player]
 for _,joint in ipairs(graph:list()) do
  local a,b=parts[joint.a.componentId],parts[joint.b.componentId]
  if not a or not b then continue end
  if typeof(joint.relativePose)=="CFrame" then
   b.Anchored=true b.CFrame=a.CFrame*joint.relativePose
   b.Anchored=false
   pcall(function()b:SetNetworkOwner(nil)end)
  end
  local objects,reason=JointCompiler.compile(joint,parts,
   document.components,features,self:bucket(player))
  if objects then
   out[joint.id]=objects
   self:ApplyActuation(player,joint.id)
  else
   warn("[OPENWORKS] Cannot compile joint "..joint.id..": "..tostring(reason))
  end
 end
end
function Service:ApplyActuation(player:Player,id:number)
 local assembly=FORGE:GetService("OpenWorksAssembly")
 local graph=assembly and assembly.graphs[player]
 local joint=graph and graph.joints[id]
 local objects=self.jointInstances[player] and self.jointInstances[player][id]
 if not joint or not objects then return end
 for _,obj in ipairs(objects) do
  if obj:IsA("HingeConstraint") then
   local motor=joint.actuation or {}
   obj.ActuatorType=if motor.enabled then Enum.ActuatorType.Motor
    else Enum.ActuatorType.None
   obj.AngularVelocity=math.clamp(motor.speed or 0,-16,16)
   obj.MotorMaxTorque=math.clamp(motor.torque or 0,0,50000)
   obj.MotorMaxAcceleration=50
  end
 end
end
function Service:PoseSnapshot(player:Player):any
 local positions={}
 for id,item in pairs(self.records[player] or {}) do
  if item.part and item.part.Parent then positions[tostring(id)]=item.part.CFrame end
 end
 return positions
end
function Service:RestorePoses(player:Player,poses:any)
 self.restored[player]=if type(poses)=="table" then poses else {}
end
function Service:RemovePlayer(player:Player)
 self.enabled[player]=nil self.pending[player]=nil
 for _,objects in pairs(self.jointInstances[player] or {}) do JointCompiler.destroy(objects) end
 self.jointInstances[player]=nil
 for _,item in pairs(self.records[player] or {}) do
  if item.part then item.part:Destroy() end
 end
 self.records[player]=nil
 if self.folders[player] then self.folders[player]:Destroy() end
 self.folders[player]=nil self.errors[player]=nil self.restored[player]=nil
end
function Service:Stop()
 for player in pairs(self.records) do self:RemovePlayer(player) end
end
return Service
