--!strict
-- Physical Q3 assembly. Holes are selection references, NOT magnetic
-- snap points. A user-manufactured cylinder must already occupy both
-- bores before any rigid or revolute joint can be installed.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local FORM=RS:WaitForChild("Openworks"):WaitForChild("FORM")
local Assembly=RS.Openworks:WaitForChild("Assembly")
local Features=require(FORM.Features)
local Fit=require(Assembly.ShaftFit)
local Compiler=require(Assembly.ConstraintCompiler)
local Manipulator=require(script.Parent.PrecisionManipulator)
local Controller={}
Controller.__index=Controller

local function button(parent:Instance,caption:string,y:number,action:()->())
 local b=Instance.new("TextButton")
 b.Name=caption:gsub("%W","")
 b.Position=UDim2.fromOffset(10,y)
 b.Size=UDim2.new(1,-20,0,30)
 b.BackgroundColor3=Color3.fromRGB(39,63,74)
 b.BorderSizePixel=0
 b.Text=caption b.TextColor3=Color3.fromRGB(229,241,246)
 b.TextSize=12 b.Font=Enum.Font.GothamMedium
 b.Parent=parent
 b.Activated:Connect(action)
 local corner=Instance.new("UICorner")
 corner.CornerRadius=UDim.new(0,5) corner.Parent=b
 return b
end
local function label(parent:Instance,value:string,y:number,height:number):TextLabel
 local l=Instance.new("TextLabel")
 l.Position=UDim2.fromOffset(10,y)
 l.Size=UDim2.new(1,-20,0,height)
 l.TextWrapped=true l.Text=value
 l.TextColor3=Color3.fromRGB(197,222,232)
 l.TextSize=12 l.Font=Enum.Font.Gotham
 l.BackgroundTransparency=1 l.TextXAlignment=Enum.TextXAlignment.Left
 l.Parent=parent
 return l
end
local function solid(entry:any):BasePart?
 local model=entry and entry.model
 local part=model and model:FindFirstChild("Solid",true)
 return if part and part:IsA("BasePart") then part else nil
end
local function sourceFrame(part:BasePart):CFrame
 local f=part:GetAttribute("OWSourceLocalFrame")
 return if typeof(f)=="CFrame" then f else CFrame.identity
end
local function holeWorld(part:BasePart,feature:any):Vector3
 return (part.CFrame*sourceFrame(part):Inverse()):PointToWorldSpace(
  feature.componentLocalCenter)
end

function Controller.new(bridge:any,remote:any,documents:any,world:any)
 local gui=Instance.new("ScreenGui")
 gui.Name="OPENWORKS_AssemblyControls"
 gui.ResetOnSpawn=false gui.Enabled=false gui.DisplayOrder=82
 gui.Parent=Players.LocalPlayer:WaitForChild("PlayerGui")
 local panel=Instance.new("Frame")
 panel.Name="AssemblyPanel"
 panel.AnchorPoint=Vector2.new(1,0)
 panel.Position=UDim2.new(1,-14,0,70)
 panel.Size=UDim2.fromOffset(310,525)
 panel.BorderSizePixel=0
 panel.BackgroundColor3=Color3.fromRGB(22,35,44)
 panel.Parent=gui
 local corner=Instance.new("UICorner")
 corner.CornerRadius=UDim.new(0,8) corner.Parent=panel
 local header=label(panel,"ASSEMBLY  /  PHYSICAL FIT",11,26)
 header.TextColor3=Color3.fromRGB(102,226,245)
 local choices=label(panel,"Pick two bores + designate a manufactured shaft.",43,54)
 local status=label(panel,"No automatic align. Move solids without penetrating their walls.",103,50)
 local self=setmetatable({
  bridge=bridge,remote=remote,documents=documents,world=world,
  gui=gui,choices=choices,status=status,active=false,step=0,
  a=nil,b=nil,shaftId=nil,selectedId=nil,
  markers={},markerRoot=nil,fixtures={},lastJoint=nil,
  manipulator=Manipulator.new(),
 },Controller)
 button(panel,"Move handles  ·  1 mm steps",161,function()
  self.manipulator:setMode("Move")
  self:_report("Drag axis arrows to move with collision-aware physics forces.")
 end)
 button(panel,"Rotate handles  ·  5° steps",195,function()
  self.manipulator:setMode("Rotate")
  self:_report("Drag rotation rings. Bodies rotate through physics, not teleportation.")
 end)
 button(panel,"Use selected cylinder as shaft",229,function()self:selectShaft()end)
 button(panel,"Install shaft  ·  Rigid",263,function()self:install("Rigid")end)
 button(panel,"Install shaft  ·  Revolute",297,function()self:install("Revolute")end)
 button(panel,"Start hinge motor",331,function()self:motor(true)end)
 button(panel,"Stop hinge motor",365,function()self:motor(false)end)
 button(panel,"Remove last joint",399,function()self:removeLast()end)
 button(panel,"Save Workshop",433,function()self:save()end)
 button(panel,"World / Physics Status",467,function()self:stats()end)
 return self
end
function Controller:_report(msg:string)
 self.status.Text=msg
end
function Controller:_state():any?
 if not self.active then return nil end
 return self.bridge.getAssemblyState()
end
function Controller:_choiceText()
 self.choices.Text="Hole A: "..tostring(self.a and self.a.id or "—")..
  "   Hole B: "..tostring(self.b and self.b.id or "—")..
  "\nShaft: "..tostring(self.shaftId or "—")..
  "   Moving: "..tostring(self.selectedId or "—")
end
function Controller:select(id:number)
 local state=self:_state()
 if not state then return end
 self.selectedId=id
 self.manipulator:select(solid(state.projection.cache[id]))
 self:_choiceText()
 self:_report("Workpiece selected. Move or rotate with handles; drag body to position it.")
end
function Controller:selectShaft()
 local state=self:_state()
 if not state or not self.selectedId then
  self:_report("Click or drag your manufactured cylinder first.")
  return
 end
 local component=state.document.components[self.selectedId]
 if not component or component.nodes[1].kind~="Cylinder"
  or #component.operations>0 then
  self:_report("Shaft must be a separate, uncut manufactured cylinder.")
  return
 end
 if (self.a and self.a.id==self.selectedId)
  or (self.b and self.b.id==self.selectedId) then
  self:_report("The shaft must be a third component, not a drilled body.")
  return
 end
 self.shaftId=self.selectedId
 self:_choiceText()
 self:_report("Shaft selected. Physically insert it through both bores.")
end
function Controller:_clearMarkers()
 if self.markerRoot then self.markerRoot:Destroy() end
 self.markerRoot=nil
 table.clear(self.markers)
end
function Controller:_refreshMarkers()
 local state=self:_state()
 if not state then return end
 if not self.markerRoot then
  self.markerRoot=Instance.new("Folder")
  self.markerRoot.Name="OPENWORKS_AssemblyHoleSelectors"
  self.markerRoot.Parent=workspace
 end
 local live={}
 for id,component in pairs(state.document.components) do
  local part=solid(state.projection.cache[id])
  if not part then continue end
  for _,feature in ipairs(Features.list(component)) do
   local key=tostring(id)..":"..feature.id
   live[key]=true
   local marker=self.markers[key]
   if not marker then
    marker=Instance.new("Part")
    marker.Name="OW_Bore_"..key
    marker.Shape=Enum.PartType.Ball
    marker.Anchored=true
    marker.CanCollide=false marker.CanTouch=false
    marker.CanQuery=true
    marker.Material=Enum.Material.Neon
    marker.Transparency=.2
    marker.Parent=self.markerRoot
    self.markers[key]=marker
   end
   marker.Size=Vector3.one*math.clamp(feature.diameter*1.25,.13,.23)
   marker.Position=holeWorld(part,feature)
   local chosen=(self.a and self.a.id==id and self.a.featureId==feature.id)
    or (self.b and self.b.id==id and self.b.featureId==feature.id)
   marker.Color=if chosen then Color3.fromRGB(255,190,90)
    else Color3.fromRGB(90,225,255)
  end
 end
 for key,marker in pairs(self.markers) do
  if not live[key] then marker:Destroy() self.markers[key]=nil end
 end
end
function Controller:_pickRay(ray:Ray):boolean
 if not self.active or not self.markerRoot then return false end
 local params=RaycastParams.new()
 params.FilterType=Enum.RaycastFilterType.Include
 params.FilterDescendantsInstances={self.markerRoot}
 local hit=workspace:Raycast(ray.Origin,ray.Direction*5000,params)
 if not hit then return false end
 for key,marker in pairs(self.markers) do
  if marker==hit.Instance then
   local colon=string.find(key,":",1,true)
   if colon then
    local id=tonumber(string.sub(key,1,colon-1))
    local featureId=string.sub(key,colon+1)
    if id then self:pickHole(id,featureId) end
   end
   return true
  end
 end
 return false
end
function Controller:pickHole(id:number,featureId:string)
 local state=self:_state()
 if not state then return end
 local component=state.document.components[id]
 if not component or not Features.get(component,featureId) then return end
 if self.shaftId==id then
  self:_report("A shaft cannot also be one of the drilled bodies.")
  return
 end
 if not self.a or self.b then
  self.a={id=id,featureId=featureId}
  self.b=nil
  self:_report("Bore A selected. Click a hole on another manufactured body.")
 elseif self.a.id==id then
  self.a={id=id,featureId=featureId}
  self:_report("Bore A changed. Select B on a different body.")
 else
  self.b={id=id,featureId=featureId}
  self:_report("Both bores selected. Insert your separate shaft manually, then install.")
 end
 self:_choiceText()
 self:_refreshMarkers()
end
function Controller:Enter()
 self.active=true self.step=0
 self.a=nil self.b=nil self.shaftId=nil self.selectedId=nil
 self.gui.Enabled=true
 self.bridge.enterAssembly()
 self:_choiceText()
 self:_report("Select and position the solids. No automatic hole snapping.")
 local state=self:_state()
 if state then
  state.projection.holePicker=function(ray:Ray):boolean return self:_pickRay(ray) end
 end
 self:_refreshMarkers()
 -- Recreate only actual hardware-backed saved relationships.
 if self.remote and state then
  local success,ok,joints=pcall(function()return self.remote:ListJoints()end)
  if success and ok and type(joints)=="table" then
   for _,joint in ipairs(joints) do
    if not joint.shaftId or typeof(joint.relativePose)~="CFrame"
     or typeof(joint.shaftRelative)~="CFrame" then continue end
    local ca=state.document.components[joint.a.componentId]
    local cb=state.document.components[joint.b.componentId]
    local cs=state.document.components[joint.shaftId]
    local pa=solid(state.projection.cache[joint.a.componentId])
    local pb=solid(state.projection.cache[joint.b.componentId])
    local ps=solid(state.projection.cache[joint.shaftId])
    if not ca or not cb or not cs or not pa or not pb or not ps then continue end
    pb.Anchored=true ps.Anchored=true
    pb.CFrame=pa.CFrame*joint.relativePose
    ps.CFrame=pa.CFrame*joint.shaftRelative
    pb.Anchored=false ps.Anchored=false
    local fa=Features.get(ca,joint.a.featureId)
    local fb=Features.get(cb,joint.b.featureId)
    if not fa or not fb then continue end
    local objects=Compiler.compile(joint,
     {[ca.id]=pa,[cb.id]=pb,[cs.id]=ps},
     {[ca.id]=ca,[cb.id]=cb,[cs.id]=cs},
     {[ca.id]={[fa.id]=fa},[cb.id]={[fb.id]=fb}},pa.Parent)
    if objects then self.fixtures[joint.id]=objects end
    self.lastJoint=joint.id
   end
  end
 end
end
function Controller:Exit()
 self.active=false
 self.gui.Enabled=false
 local state=self.bridge.getAssemblyState()
 if state then state.projection.holePicker=nil end
 self.manipulator:select(nil)
 self:_clearMarkers()
 for _,objects in pairs(self.fixtures) do Compiler.destroy(objects) end
 table.clear(self.fixtures)
 self.bridge.leaveAssembly()
end
function Controller:Update(dt:number)
 if not self.active then return end
 self.step+=dt
 if self.step<.08 then return end
 self.step=0
 self:_refreshMarkers()
 if self.selectedId then
  local state=self:_state()
  local part=state and solid(state.projection.cache[self.selectedId])
  if part~=self.manipulator.part then self.manipulator:select(part) end
 end
end
function Controller:install(kind:string)
 local state=self:_state()
 if not state or not self.a or not self.b or not self.shaftId then
  return self:_report("Choose two bores AND an independently made cylinder shaft.")
 end
 local ca=state.document.components[self.a.id]
 local cb=state.document.components[self.b.id]
 local cs=state.document.components[self.shaftId]
 local pa=solid(state.projection.cache[self.a.id])
 local pb=solid(state.projection.cache[self.b.id])
 local ps=solid(state.projection.cache[self.shaftId])
 if not ca or not cb or not cs or not pa or not pb or not ps then
  return self:_report("A selected workpiece has no valid manufactured solid.")
 end
 local fa=Features.get(ca,self.a.featureId)
 local fb=Features.get(cb,self.b.featureId)
 if not fa or not fb then return self:_report("A selected hole no longer exists.") end
 if cs.nodes[1].kind~="Cylinder" or #cs.operations>0 then
  return self:_report("Connector must be an uncut manufactured cylinder.")
 end
 local relativeB=pa.CFrame:ToObjectSpace(pb.CFrame)
 local relativeS=pa.CFrame:ToObjectSpace(ps.CFrame)
 local fitting,reason=Fit.validate(fa,fb,relativeB,
  sourceFrame(pa),sourceFrame(pb),cs.nodes[1].size,relativeS)
 if not fitting then return self:_report("Cannot install: "..tostring(reason)) end
 if not self.remote then return self:_report("FORGE Assembly service unavailable.") end
 local ok,accepted,record=pcall(function()
  return self.remote:Install(kind,self.a.id,fa.id,self.b.id,fb.id,
   self.shaftId,relativeB,relativeS)
 end)
 if not ok or not accepted then
  return self:_report("Installation rejected: "..tostring(if ok then record else accepted))
 end
 local objects,problem=Compiler.compile(record,
  {[ca.id]=pa,[cb.id]=pb,[cs.id]=ps},
  {[ca.id]=ca,[cb.id]=cb,[cs.id]=cs},
  {[ca.id]={[fa.id]=fa},[cb.id]={[fb.id]=fb}},pa.Parent)
 if objects then self.fixtures[record.id]=objects end
 self.lastJoint=record.id
 self.a=nil self.b=nil self.shaftId=nil
 self:_choiceText()
 self:_report(if objects then
  "Installed actual "..kind.." shaft #"..record.id else
  "Joint accepted; stage compile: "..tostring(problem))
end
function Controller:motor(on:boolean)
 if not self.lastJoint or not self.remote then
  return self:_report("Install a revolute shaft joint first.")
 end
 local success,ok,response=pcall(function()
  return self.remote:SetActuator(self.lastJoint,
   if on then 2 else 0,if on then 220 else 0)
 end)
 self:_report(if success and ok then
  (if on then "Hinge motor enabled" else "Hinge motor disabled")
  else "Motor rejected: "..tostring(if success then response else ok))
end
function Controller:removeLast()
 if not self.lastJoint or not self.remote then
  return self:_report("No joint to remove")
 end
 local id=self.lastJoint
 local success,ok,response=pcall(function()return self.remote:Remove(id)end)
 if success and ok then
  Compiler.destroy(self.fixtures[id])
  self.fixtures[id]=nil self.lastJoint=nil
  self:_report("Removed physical connection #"..id)
 else
  self:_report("Removal rejected: "..tostring(if success then response else ok))
 end
end
function Controller:save()
 if not self.documents then return self:_report("Save service unavailable") end
 local success,ok,response=pcall(function()return self.documents:SaveNow(true)end)
 self:_report(if success and ok then "Workshop saved" else
  "Save rejected: "..tostring(if success then response else ok))
end
function Controller:stats()
 if not self.world then return self:_report("Physics service unavailable") end
 local success,ok,data=pcall(function()return self.world:GetStats()end)
 if not success or not ok or type(data)~="table" then
  return self:_report("Cannot read physics diagnostics")
 end
 self:_report(string.format("%d published bodies · %d hardware joints · %s",
  data.published or 0,data.joints or 0,
  if data.busy then "Manufacturing" else data.error or "Idle"))
end
function Controller:Destroy()
 self:Exit()
 self.manipulator:Destroy()
 self.gui:Destroy()
end
return Controller
