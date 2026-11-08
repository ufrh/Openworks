--!strict
-- Q3 Assembly interaction: drag any manufactured component to select it,
-- then another. Temporary forces guide nearby matching holes. A joint
-- exists only after explicit installation through the FORGE service.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local Features=require(RS:WaitForChild("Openworks"):WaitForChild("FORM").Features)
local Matcher=require(RS.Openworks.Assembly.FeatureMatcher)
local Assist=require(script.Parent.AlignmentAssist)
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
 local choices=label(panel,"Drag first component (A), then second (B).",52)
 local status=label(panel,"Nearby drilled holes assist alignment; they do not fasten.",98)
 status.Size=UDim2.new(1,-20,0,44)
 local self=setmetatable({bridge=bridge,remote=remote,
  gui=gui,choices=choices,status=status,assist=Assist.new(),
  documents=documents,world=world,
  a=nil,b=nil,active=false,step=0,lastMatch=nil,lastJoint=nil,
  fixtures={}},Controller)
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
function Controller:select(id:number)
 if not self.active then return end
 if self.a==nil or (self.a and self.b) then
  self.a=id self.b=nil
 elseif self.a==id then
  return
 else
  self.b=id
 end
 self.assist:release()
 self.choices.Text="A: "..tostring(self.a or "—")..
  "   B: "..tostring(self.b or "—")
 self:_report(if self.b then "Move the selected bodies together." else
  "Drag a second component to select B.")
end
function Controller:Enter()
 self.active=true self.step=0 self.a=nil self.b=nil
 self.assist:release()
 self.gui.Enabled=true
 self.bridge.enterAssembly()
 self.choices.Text="Drag first component (A), then second (B)."
 self:_report("Bring matching drilled holes close; install hardware explicitly.")
end
function Controller:Exit()
 self.active=false self.gui.Enabled=false
 self.assist:release()
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
 if self.step<.15 then return end
 self.step=0
 local c=self:_context()
 if not c then self.assist:release() return end
 local result,why=self.assist:guide(c.pa,c.pb,
  c.a,c.b,c.holesA,c.holesB)
 self.lastMatch=result
 if result then
  self:_report(string.format("%d matching hole pair(s) · %.1f mm offset. Install bolt or pin to retain.",
   #result.pairs,result.pairs[1].distance*280))
 else self:_report(why or "No nearby compatible holes") end
end
function Controller:install(kind:string)
 local c=self:_context()
 if not c then return self:_report("Select and drag two manufactured components.") end
 local result=self.lastMatch
 if not result or result.pairs[1].distance>.18 then
  return self:_report("Bring matching bores within 50 mm before installing.")
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
 self.assist:release()
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
 self:Exit() self.assist:Destroy() self.gui:Destroy()
end
return Controller
