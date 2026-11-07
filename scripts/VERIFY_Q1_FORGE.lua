--!strict
-- Run in Studio CLIENT command bar after Rojo sync, while game is playing.
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
assert(RunService:IsClient(),"Run this test on Studio client")
local FORGE=require(RS:WaitForChild("FORGE"))
assert(FORGE.Version=="4.4.1","OpenWorks must mount actual FORGE Reforge 4.4.1")
local runtime=FORGE:GetController("OpenWorksRuntime")
assert(runtime and runtime._Started and not runtime._Failed,
 "FORGE OpenWorksRuntime controller failed to start; inspect Output")
local scripts=game.Players.LocalPlayer.PlayerScripts:WaitForChild("Openworks")
local Modes=scripts:WaitForChild("Modes")
local Manager=require(Modes.ModeManager)
local Workspace=require(Modes.EditWorkspace)
local Environment=require(Modes.EditEnvironment)
local m=Manager.new()
local log={}
local function mode(id:string,fail:boolean?)
 return {Enter=function(_self)
  table.insert(log,"+"..id)
  if fail then error("intentional entry failure") end
 end,Exit=function(_self)table.insert(log,"-"..id)end}
end
m:register("A",mode("A"))
m:register("B",mode("B"))
m:register("Broken",mode("Broken",true))
assert(m:switch("A"))
assert(m:switch("B"))
assert(m.currentName=="B")
local ok=m:switch("Broken")
assert(not ok and m.currentName=="B",
 "Failed entry must restore previous active mode")
m:destroy()
local authored=Workspace.new(Vector3.new(14,0,-10),
 Vector3.new(2,1000/280,1),"Test")
assert(authored.center==Environment.Center)
assert((authored:toWorld(authored.editCorner)-authored.worldCorner).Magnitude<1e-5)
assert((authored:toEdit(authored.worldCorner)-authored.editCorner).Magnitude<1e-5)
local env=Environment.new()
env:show()
local root=env.root
assert(root and root.Name=="OPENWORKS_LocalEditChamber")
assert(Environment.Size==Vector3.new(40,20,40))
for _,part in ipairs(root:GetChildren()) do
 assert(part:IsA("BasePart"))
 assert(not part.CastShadow and not part.CanCollide and not part.CanQuery)
end
env:hide()
assert(env.root==nil and root.Parent==nil)
assert(runtime.modeManager.currentName~=nil)
print("OPENWORKS Q1 FORGE PASS: original framework, controller lifecycle, rollback, chamber and coordinate frames")
