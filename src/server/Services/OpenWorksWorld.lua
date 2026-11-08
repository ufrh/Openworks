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
local MaterialVolume=require(FORM.MaterialVolume)
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
 self.appliedJoints={}
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
 local volume,exact=MaterialVolume.fromPartAsync(part)
 if not MaterialVolume.within(volume) then
  part:Destroy()
  self.errors[player]="Manufactured solid exceeds material budget: "..id
  FORGE.Metric("OpenWorks.World.VolumeRejects"):Add(1)
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
 if restored and typeof(restored[tostring(id)])=="CFrame" and not previous then
  delta=restored[tostring(id)]*base:Inverse()
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
-- Obtain the real manufactured part's source-local frame. This is
-- required for validating offset CSG cutters and hole centerlines.
function Service:SourceFrame(player:Player,id:number,component:any):CFrame?
 local current=self.records[player] and self.records[player][id]
 if current and current.revision==component.revision and current.part then
  local frame=current.part:GetAttribute("OWSourceLocalFrame")
  if typeof(frame)=="CFrame" then return frame end
 end
 local doc=Document.snapshot(component)
 local ok,part=pcall(function()
  if Fabricator.requiresCompile(doc) then return Fabricator.compile(doc) end
  return Compiler.nativePart(doc.nodes[1])
 end)
 if not ok or not part then return nil end
 local frame=part.CFrame
 part:Destroy()
 return frame
end

-- Verify physical collision geometry on SERVER-owned source solids.
-- Deliberately fail closed: an overlapping fastener installation cannot
-- turn intersecting parts into a persistent joint. Roblox CSG hull
-- approximation may reject some visually clear fits; report this.
function Service:ValidateAssemblyClearance(player:Player,idA:number,
 idB:number,shaftId:number,relativeB:CFrame,relativeS:CFrame):(boolean,string?)
 local docs=FORGE:GetService("OpenWorksDocuments")
 local document=docs and docs.documents[player]
 if not document then return false,"Document unavailable" end
 local ids={idA,idB,shaftId}
 local parts={}
 local function cleanup()
  for _,part in ipairs(parts) do part:Destroy() end
 end
 for _,id in ipairs(ids) do
  local component=document.components[id]
  if not component then cleanup() return false,"Missing manufactured component" end
  local record=self.records[player] and self.records[player][id]
  local part:BasePart?
  if record and record.revision==component.revision and record.part then
   part=record.part:Clone()
   part:ClearAllChildren()
  else
   local snapshot=Document.snapshot(component)
   local success,result=pcall(function()
    if Fabricator.requiresCompile(snapshot) then return Fabricator.compile(snapshot) end
    return Compiler.nativePart(snapshot.nodes[1])
   end)
   if not success or not result or not result:IsA("BasePart") then
    cleanup() return false,"Cannot compile collision geometry for installation"
   end
   part=result
  end
  part.Anchored=true
  part.CanCollide=true
  part.CanTouch=false
  part.CanQuery=true
  if part:IsA("MeshPart") or part:IsA("PartOperation") then
   pcall(function()
    part.CollisionFidelity=Enum.CollisionFidelity.PreciseConvexDecomposition
   end)
  end
  table.insert(parts,part)
  part.Parent=workspace
 end
 -- Keep validation bodies away from live workshop physics.
 local origin=CFrame.new(0,2000,0)
 parts[1].CFrame=origin
 parts[2].CFrame=origin*relativeB
 parts[3].CFrame=origin*relativeS
 local overlapped=false
 local valid=true
 for i=1,2 do
  for j=i+1,3 do
   local params=OverlapParams.new()
   params.FilterType=Enum.RaycastFilterType.Include
   params.FilterDescendantsInstances={parts[j]}
   params.MaxParts=1
   local ok,results=pcall(function()
    return workspace:GetPartsInPart(parts[i],params)
   end)
   if not ok then valid=false break end
   if #results>0 then overlapped=true break end
  end
  if overlapped or not valid then break end
 end
 cleanup()
 if not valid then return false,"Physical collision audit unavailable" end
 if overlapped then
  return false,"Solid penetration detected. Adjust the geometry/shaft clearance"
 end
 return true,nil
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
  if not existing or not existing.part or not existing.part.Parent
   or existing.revision~=doc.components[id].revision then
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
 for _,objects in pairs(self.jointInstances[player] or {}) do JointCompiler.destroy(objects) end
 self.jointInstances[player]={}
 self.appliedJoints[player]={}
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
 self.appliedJoints[player]=nil
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

