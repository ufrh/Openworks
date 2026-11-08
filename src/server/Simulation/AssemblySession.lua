--!strict
local RS=game:GetService('ReplicatedStorage')
local Shared=RS:WaitForChild('Openworks')
local Fabricator=require(Shared.FORM.Fabricator)
local Compiler=require(Shared.FORM.Compiler)
local Document=require(Shared.FORM.Document)
local Interference=require(Shared.Assembly.Interference)
local Resolver=require(Shared.Assembly.MechanicalResolver)
local Constraints=require(Shared.Assembly.ConstraintCompiler)
local Session={}
function Session.compile(document:any,poses:any):(any?,string?)
 local parts={}
 local function cleanup() for _,part in pairs(parts) do part:Destroy() end end
 for _,id in ipairs(document.order) do
  local component=Document.snapshot(document.components[id])
  local ok,part=pcall(function()
   if Fabricator.requiresCompile(component) then return Fabricator.compile(component) end
   return Compiler.nativePart(component.nodes[1])
  end)
  if not ok or not part then cleanup() return nil,'Manufacturing failed for component '..id end
  if not poses[tostring(id)] then part:Destroy() cleanup() return nil,'Missing component pose' end
  parts[id]=part
  local source=part.CFrame
  part:SetAttribute('OWSourceLocalFrame',source)
  part:SetAttribute('OWComponentId',id)
  part.CFrame=poses[tostring(id)]*source
  part.Anchored=true part.CanCollide=true part.CanQuery=true part.CanTouch=true
 end
 return parts,nil
end
function Session.validate(parts:any,changedId:number?):(boolean,string?,any?)
 local ids={}
 for id in pairs(parts) do table.insert(ids,id) end
 table.sort(ids)
 local floor=Instance.new('Part')
 floor.Size=Vector3.new(1000,.1,1000)
 floor.CFrame=CFrame.new(120,199.92,0)
 floor.Anchored=true
 for _,id in ipairs(ids) do
  if changedId and changedId~=id then continue end
  local clear,reason=Interference.pair(parts[id],floor)
  if not clear then floor:Destroy() return false,id..' / stage: '..tostring(reason),{id} end
 end
 floor:Destroy()
 for i=1,#ids do for j=i+1,#ids do
  if changedId and ids[i]~=changedId and ids[j]~=changedId then continue end
  local ok,reason=Interference.pair(parts[ids[i]],parts[ids[j]])
  if not ok then return false,ids[i]..' / '..ids[j]..': '..tostring(reason),{ids[i],ids[j]} end
 end end
 return true,nil,nil
end
function Session.destroy(session:any)
 if not session then return end
 if session.player and session.player.Parent and session.focus and session.player.ReplicationFocus==session.focus then
  session.player.ReplicationFocus=session.previousFocus
 end
 if session.root then session.root:Destroy()
 elseif session.parts then for _,p in pairs(session.parts) do p:Destroy() end end
end
function Session.start(player:Player,document:any,layout:any,parts:any,slot:number):(any?,string?)
 local shift=Vector3.new(slot*1200,0,0)
 local poses={}
 for key,pose in pairs(layout.poses) do poses[key]=pose+shift end
 local session={player=player,previousFocus=player.ReplicationFocus,parts=parts,relations={},source=document.components,center=Vector3.new(120,200,0)+shift}
 local root=Instance.new('Folder')
 root.Name='OPENWORKS_Simulation_'..player.UserId
 session.root=root
 for _,part in pairs(parts) do part.CFrame+=shift part.Parent=root end
 local success,problem=xpcall(function()
 local floor=Instance.new('Part')
 floor.Name='SimulationFloor' floor.Size=Vector3.new(1000,.1,1000)
 floor.Position=Vector3.new(120,199.92,0)+shift
 floor.Anchored=true floor.CanCollide=true floor.CanQuery=false
 floor.Color=Color3.fromRGB(51,88,130) floor.Material=Enum.Material.SmoothPlastic
 floor.Parent=root
 for _,record in ipairs(layout.supports) do
  local relation,reason=Resolver.resolve(record,document.components,poses)
  if not relation then error(reason) end
  local objects,problem=Constraints.compileResolved(relation,parts,root)
  if not objects then error(problem) end
  table.insert(session.relations,{record=record,objects=objects})
 end
 root.Parent=workspace
 session.focus=parts[document.order[1]]
 player.ReplicationFocus=session.focus
 for id,part in pairs(parts) do
  part.Anchored=layout.grounded[tostring(id)]==true
  if not part.Anchored then part:SetNetworkOwner(nil) end
 end
 end,debug.traceback)
 if not success then Session.destroy(session) return nil,tostring(problem) end
 return session,nil
end
function Session.update(session:any)
 local poses={}
 for id,part in pairs(session.parts) do
  poses[tostring(id)]=part.CFrame*part:GetAttribute('OWSourceLocalFrame'):Inverse()
 end
 for i=#session.relations,1,-1 do
  local item=session.relations[i]
  if not Resolver.resolve(item.record,session.source,poses) then
   Constraints.destroy(item.objects)
   table.remove(session.relations,i)
  end
 end
end
return Session
