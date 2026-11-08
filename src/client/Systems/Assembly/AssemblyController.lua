--!strict
-- Q3 Assembly: deliberately pick two visible drilled holes to align.
-- Body dragging remains independent; nothing auto-fastens.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Features=require(RS:WaitForChild("Openworks"):WaitForChild("FORM").Features)
local Matcher=require(RS.Openworks.Assembly.FeatureMatcher)
local MAX_PAIR_DISTANCE=.75 -- studs (210 mm), measured between bore centers
local Compiler=require(RS.Openworks.Assembly.ConstraintCompiler)
local Controller={}
Controller.__index=Controller
local function button(parent:Instance,caption:string,y:number,action:()->())
 local b=Instance.new("TextButton")
 b.Name=caption:gsub("%W","")
 b.Position=UDim2.fromOffset(10,y)
 b.Size=UDim2.new(1,-20,0,29)
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
local function label(parent:Instance,value:string,y:number):TextLabel
 local l=Instance.new("TextLabel")
 l.Position=UDim2.fromOffset(10,y)
 l.Size=UDim2.new(1,-20,0,42)
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
function Controller.new(bridge:any,remote:any,documents:any,world:any)
 local gui=Instance.new("ScreenGui")
 gui.Name="OPENWORKS_AssemblyControls"
 gui.ResetOnSpawn=false gui.Enabled=false gui.DisplayOrder=82
 gui.Parent=Players.LocalPlayer:WaitForChild("PlayerGui")
 local panel=Instance.new("Frame")
 panel.Name="AssemblyPanel"
 panel.AnchorPoint=Vector2.new(1,0)
 panel.Position=UDim2.new(1,-14,0,70)
 panel.Size=UDim2.fromOffset(290,425)
 panel.BorderSizePixel=0
 panel.BackgroundColor3=Color3.fromRGB(22,35,44)
 panel.Parent=gui
 local round=Instance.new("UICorner")
 round.CornerRadius=UDim.new(0,8) round.Parent=panel
 local heading=label(panel,"ASSEMBLY  /  FEATURE FIT",12)
 heading.TextColor3=Color3.fromRGB(102,226,245)
 local choices=label(panel,"Click a hole on A, then a hole on B.",52)
 local status=label(panel,"Hole markers align on second click; bolt or pin is explicit.",98)
 status.Size=UDim2.new(1,-20,0,44)
 local self=setmetatable({bridge=bridge,remote=remote,
  gui=gui,choices=choices,status=status,
  documents=documents,world=world,
  a=nil,b=nil,active=false,step=0,lastMatch=nil,lastJoint=nil,
  pickedHole=nil,markers={},markerRoot=nil,fixtures={}},Controller)
 button(panel,"Install Bolt  ·  Rigid",154,function()self:install("Rigid")end)
 button(panel,"Install Pin  ·  Revolute",189,function()self:install("Revolute")end)
 button(panel,"Start hinge motor",224,function()self:motor(true)end)
 button(panel,"Stop hinge motor",259,function()self:motor(false)end)
 button(panel,"Remove last joint",294,function()self:removeLast()end)
 button(panel,"Save Workshop",329,function()self:save()end)
 button(panel,"World / Physics Status",364,function()self:stats()end)
 return self
end
function Controller:_report(msg:string)
 self.status.Text=msg
end
-- A drag moves a body; only a deliberate hole marker click selects a fit.
function Controller:select(_id:number)
 if self.active and not self.pickedHole then
  self:_report("Click a highlighted hole to select the mating pair.")
 end
end

local function sourceFrame(part:BasePart):CFrame
 local frame=part:GetAttribute("OWSourceLocalFrame")
 return if typeof(frame)=="CFrame" then frame else CFrame.identity
end
local function componentPose(part:BasePart):CFrame
 return part.CFrame*sourceFrame(part):Inverse()
end
local function holeWorld(part:BasePart,feature:any):Vector3
 return componentPose(part):PointToWorldSpace(feature.componentLocalCenter)
end
local function rotateAxis(from:Vector3,to:Vector3):CFrame
 local dot=math.clamp(from.Unit:Dot(to.Unit),-1,1)
 if dot>.99999 then return CFrame.identity end
 local cross=from:Cross(to)
 if cross.Magnitude<.00001 then
  local perpendicular=from:Cross(Vector3.yAxis)
  if perpendicular.Magnitude<.01 then perpendicular=from:Cross(Vector3.xAxis) end
  return CFrame.fromAxisAngle(perpendicular.Unit,math.pi)
 end
 return CFrame.fromAxisAngle(cross.Unit,math.acos(dot))
end

function Controller:_clearMarkers()
 if self.markerRoot then self.markerRoot:Destroy() end
 self.markerRoot=nil
 table.clear(self.markers)
end

function Controller:_refreshMarkers()
 if not self.active then return end
 local state=self.bridge.getAssemblyState()
 if not state then return end
 if not self.markerRoot then
  local root=Instance.new("Folder")
  root.Name="OPENWORKS_AssemblyHoleMarkers"
  root.Parent=workspace
  self.markerRoot=root
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
    marker.Name="Hole_"..key
    marker.Shape=Enum.PartType.Ball
    marker.Anchored=true
    marker.CanCollide=false
    marker.CanTouch=false
    marker.CanQuery=true
    marker.CastShadow=false
    marker.Material=Enum.Material.Neon
    marker.Transparency=.15
    marker.Parent=self.markerRoot
    self.markers[key]=marker
   end
   marker.Size=Vector3.one*math.clamp(feature.diameter*1.35,.16,.28)
   marker.Position=holeWorld(part,feature)
   marker.Color=if self.pickedHole and self.pickedHole.id==id
    and self.pickedHole.featureId==feature.id
    then Color3.fromRGB(255,198,83) else Color3.fromRGB(90,225,255)
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
 if not self.active then return end
 local state=self.bridge.getAssemblyState()
 if not state then return end
 local component=state.document.components[id]
 local feature=component and Features.get(component,featureId)
 local part=solid(state.projection.cache[id])
 if not feature or not part then return end
 if not self.pickedHole then
  self.pickedHole={id=id,featureId=featureId}
  self.a=id self.b=nil self.lastMatch=nil
  self.choices.Text="A: "..tostring(id).." / "..featureId.."   B: —"
  self:_report("First hole selected. Click a hole on a DIFFERENT component.")
  self:_refreshMarkers()
  return
 end
 local first=self.pickedHole
 if first.id==id then
  self.pickedHole={id=id,featureId=featureId}
  self:_report("First hole updated. Choose a hole on another component.")
  self:_refreshMarkers()
  return
 end
 local ca=state.document.components[first.id]
 local fa=ca and Features.get(ca,first.featureId)
 local pa=solid(state.projection.cache[first.id])
 if not fa or not pa then
  self.pickedHole=nil self.lastMatch=nil
  self:_report("First hole is no longer available. Select it again.")
  return
 end
 local distance=(holeWorld(pa,fa)-holeWorld(part,feature)).Magnitude
 if distance>MAX_PAIR_DISTANCE then
  self:_report(string.format("Holes are %.0f mm apart; bring within %.0f mm.",
   distance*280,MAX_PAIR_DISTANCE*280))
  return
 end
 if not Matcher.compatible(fa,feature) then
  self:_report("These hole diameters are incompatible. Choose another hole.")
  return
 end
 -- Snap only on the SECOND explicit click. No continuous attraction,
 -- AlignPosition, or AlignOrientation constraints are created.
 local poseA=componentPose(pa)
 local poseB=componentPose(part)
 local axisA=poseA:VectorToWorldSpace(fa.componentLocalAxis).Unit
 local axisB=poseB:VectorToWorldSpace(feature.componentLocalAxis).Unit
 local rotation=rotateAxis(axisB,axisA)
 local centerA=poseA:PointToWorldSpace(fa.componentLocalCenter)
 local centerB=poseB:PointToWorldSpace(feature.componentLocalCenter)
 local targetPose=CFrame.new(centerA)*rotation*CFrame.new(-centerB)*poseB
 part.AssemblyLinearVelocity=Vector3.zero
 part.AssemblyAngularVelocity=Vector3.zero
 part.CFrame=targetPose*sourceFrame(part)
 self.a=first.id self.b=id
 self.lastMatch={pairs={{a=fa,b=feature,distance=0}},targetPose=targetPose}
 self.pickedHole=nil
 self.choices.Text="A: "..tostring(self.a).." / "..fa.id..
  "   B: "..tostring(self.b).." / "..feature.id
 self:_report("Holes aligned. Install Bolt (rigid) or Pin (hinge) to connect.")
 self:_refreshMarkers()
end

function Controller:Enter()
 self.active=true self.step=0 self.a=nil self.b=nil
 self.pickedHole=nil self.lastMatch=nil self.gui.Enabled=true
 self.bridge.enterAssembly()
 self.choices.Text="Click a hole on A, then a hole on B."
 self:_report("Drag bodies freely, then click two blue hole markers to align.")
 local state=self.bridge.getAssemblyState()
 if state then
  state.projection.holePicker=function(ray:Ray):boolean return self:_pickRay(ray) end
 end
 self:_refreshMarkers()
 -- Restore explicit joint graph into the local stage on each re-entry.
 if self.remote then
  local success,ok,records=pcall(function()return self.remote:ListJoints()end)
  if success and ok and type(records)=="table" then
   local state=self.bridge.getAssemblyState()
   for _,joint in ipairs(records) do
    local ca=state.document.components[joint.a.componentId]
    local cb=state.document.components[joint.b.componentId]
    local entryA=state.projection.cache[joint.a.componentId]
    local entryB=state.projection.cache[joint.b.componentId]
    local partA,partB=solid(entryA),solid(entryB)
    if not ca or not cb or not partA or not partB then continue end
    if typeof(joint.relativePose)=="CFrame" then
     partB.Anchored=true
     partB.CFrame=partA.CFrame*joint.relativePose
     partB.Anchored=false
    end
    local featureA=Features.get(ca,joint.a.featureId)
    local featureB=Features.get(cb,joint.b.featureId)
    if not featureA or not featureB then continue end
    local instances=Compiler.compile(joint,
     {[ca.id]=partA,[cb.id]=partB},
     {[ca.id]=ca,[cb.id]=cb},
     {[ca.id]={[featureA.id]=featureA},
      [cb.id]={[featureB.id]=featureB}},partA.Parent)
    if instances then self.fixtures[joint.id]=instances end
    self.lastJoint=joint.id
   end
  end
 end
end
function Controller:Exit()
 self.active=false self.gui.Enabled=false
 local state=self.bridge.getAssemblyState()
 if state then state.projection.holePicker=nil end
 self:_clearMarkers()
 self.pickedHole=nil self.lastMatch=nil
 for _,objects in pairs(self.fixtures) do Compiler.destroy(objects) end
 table.clear(self.fixtures)
 self.bridge.leaveAssembly()
end
function Controller:_context():any?
 if not self.active or not self.a or not self.b then return nil end
 local state=self.bridge.getAssemblyState()
 if not state then return nil end
 local aa=state.document.components[self.a]
 local bb=state.document.components[self.b]
 local ea=state.projection.cache[self.a]
 local eb=state.projection.cache[self.b]
 local pa,pb=solid(ea),solid(eb)
 if not aa or not bb or not pa or not pb then return nil end
 return {a=aa,b=bb,pa=pa,pb=pb,
  holesA=Features.list(aa),holesB=Features.list(bb),projection=state.projection}
end
function Controller:Update(dt:number)
 if not self.active then return end
 self.step+=dt
 if self.step<.05 then return end
 self.step=0
 self:_refreshMarkers()
end
function Controller:install(kind:string)
 local c=self:_context()
 if not c then return self:_report("Click one hole on each component to align first.") end
 local result=self.lastMatch
 if not result then
  return self:_report("Pick two nearby compatible hole markers first.")
 end
 local fa,fb=result.pairs[1].a,result.pairs[1].b
 local dist=(holeWorld(c.pa,fa)-holeWorld(c.pb,fb)).Magnitude
 if dist>.12 then
  self.lastMatch=nil
  return self:_report("Holes moved apart. Click both holes to realign.")
 end
 if not self.remote then return self:_report("FORGE Assembly service unavailable") end
 local pair=result.pairs[1]
 local ok,accepted,record=pcall(function()
  return self.remote:Install(kind,self.a,pair.a.id,self.b,pair.b.id,
   c.pa.CFrame:ToObjectSpace(c.pb.CFrame))
 end)
 if not ok or not accepted then
  return self:_report("Installation rejected: "..tostring(if ok then record else accepted))
 end
 self.lastJoint=record.id
 self.lastMatch=nil
 -- The stage receives the same physical relation as the published world.
 local features={
  [self.a]={[pair.a.id]=pair.a},
  [self.b]={[pair.b.id]=pair.b},
 }
 local components={[self.a]=c.a,[self.b]=c.b}
 local parts={[self.a]=c.pa,[self.b]=c.pb}
 local objects,reason=Compiler.compile(record,parts,components,features,
  c.pa.Parent)
 if objects then self.fixtures[record.id]=objects end
 self:_report(if objects then
  "Installed "..kind.." relationship #"..record.id else
  "Server joint stored; local preview: "..tostring(reason))
end
function Controller:motor(on:boolean)
 if not self.lastJoint then return self:_report("Install a hinge first.") end
 if not self.remote then return self:_report("Assembly service unavailable") end
 local success,ok,result=pcall(function()
  return self.remote:SetActuator(self.lastJoint,
   if on then 2.0 else 0,if on then 220 else 0)
 end)
 if success and ok then
  self:_report(if on then "Hinge motor on · 2 rad/s" else "Hinge motor off")
 else self:_report("Actuation rejected: "..tostring(if success then result else ok)) end
end
function Controller:removeLast()
 if not self.lastJoint or not self.remote then
  return self:_report("No installed joint selected")
 end
 local id=self.lastJoint
 local success,ok,result=pcall(function()return self.remote:Remove(id)end)
 if success and ok then
  Compiler.destroy(self.fixtures[id])
  self.fixtures[id]=nil self.lastJoint=nil
  self:_report("Removed relationship #"..id)
 else self:_report("Removal rejected: "..tostring(if success then result else ok)) end
end
function Controller:save()
 if not self.documents then return self:_report("Document service unavailable") end
 local success,ok,msg=pcall(function()return self.documents:SaveNow(true)end)
 self:_report(if success and ok then "Workshop saved" else
  "Save unavailable: "..tostring(if success then msg else ok))
end
function Controller:stats()
 if not self.world then return self:_report("World service unavailable") end
 local success,ok,data=pcall(function()return self.world:GetStats()end)
 if not success or not ok or type(data)~="table" then
  return self:_report("Cannot read world diagnostics")
 end
 self:_report(string.format("%d published parts, %d joints. %s",
  data.published or 0,data.joints or 0,
  if data.busy then "Manufacturing..." else data.error or "Idle"))
end
function Controller:Destroy()
 self:Exit() self.gui:Destroy()
end
return Controller
