--!strict
-- FORGE Layer-2 controller is the single owner of client game-mode state.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local FORGE=require(ReplicatedStorage:WaitForChild("FORGE"))
local Client=script.Parent.Parent
local Modes=Client:WaitForChild("Modes")
local Experience=Client:WaitForChild("Experience")
local Editor=require(Client.Modes.Edit.LegacyFabricationAdapter)
local ModeManager=require(Modes.ModeManager)
local FreeMode=require(Modes.FreeMode)
local EditMode=require(Modes.EditMode)
local AssemblyMode=require(Modes.AssemblyMode)
local EditEnvironment=require(Modes.EditEnvironment)
local ModeBar=require(Experience.ModeBar)
local ToolRegistry=require(Client.Tools.ToolRegistry)
local ToolController=require(Client.Tools.ToolController)
local Controller=FORGE.Controller("OpenWorksRuntime")
function Controller:Init()
 self.modeManager=ModeManager.new()
 self.environment=EditEnvironment.new()
 self.tools=ToolController.new(ToolRegistry.standard())
end
function Controller:Start()
 local manager=self.modeManager
 local function switch(name:string,context:any?)
  if name=="Edit" and not context then
   context={workspace=self.bridge.getWorkspace()}
   if not context.workspace then
    warn("[OPENWORKS] Create a component before opening Edit Mode")
    return
   end
  end
  local startedAt=os.clock()
  local ok,reason=manager:switch(name,context)
  local elapsed=(os.clock()-startedAt)*1000
  FORGE.Metric("OpenWorks.Mode.TransitionMs"):Observe(elapsed)
  if not ok then
   FORGE.Metric("OpenWorks.Mode.Failures"):Add(1)
   warn("[OPENWORKS] Cannot enter "..name..": "..tostring(reason))
  else
   -- FORGE.Signal dispatches listeners asynchronously. Update the
   -- authoritative mode UI/tool permissions synchronously, in order.
   self.modeBar:setActive(name)
   self.tools:setMode(name)
   FORGE.Pulse("OpenWorks","Mode","Enter",{Name=name,DurationMs=elapsed})
  end
 end
 self.bridge=Editor.start({
  onEditRequested=function(workspaceData)
   switch("Edit",{workspace=workspaceData})
  end,
  onFreeRequested=function()switch("Free")end,
  onToolChanged=function(kind)
   if not kind then self.tools:clear() return end
   local ok,reason=self.tools:activate(kind)
   if not ok then warn("[OPENWORKS] "..tostring(reason)) end
  end,
 })
 manager:register("Free",FreeMode.new(self.bridge))
 manager:register("Edit",EditMode.new(self.bridge,self.environment))
 manager:register("Assembly",AssemblyMode.new(self.bridge))
 self.modeBar=ModeBar.new(Players.LocalPlayer:WaitForChild("PlayerGui"),switch)
 -- External observers may subscribe to manager.changed, but internal
 -- correctness must never depend on asynchronous notification ordering.
 FORGE.Test("OpenWorks.Q1.ModeRegistration",function()
  assert(manager.modes.Free and manager.modes.Edit and manager.modes.Assembly)
  assert(self.tools.registry:available("Drill","Edit"))
  assert(not self.tools.registry:available("Drill","Free"))
  assert(self.environment.Size==Vector3.new(40,20,40))
 end)
 self:Track(RunService.Heartbeat:Connect(function(dt)
  manager:update(dt)
 end))
 local ok,reason=manager:switch("Free")
 assert(ok,"OpenWorks mode startup failed: "..tostring(reason))
 self.modeBar:setActive("Free")
 self.tools:setMode("Free")
end
function Controller:Stop()
 if self.modeManager then self.modeManager:destroy() end
 if self.environment then self.environment:Destroy() end
 if self.modeBar then self.modeBar:destroy() end
 if self.tools then self.tools:destroy() end
end
return Controller
