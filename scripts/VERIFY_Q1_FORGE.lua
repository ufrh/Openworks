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
assert(runtime.tools.mode==runtime.modeManager.currentName,
 "Mode permissions must update synchronously with the active mode")
assert(RS:WaitForChild("Openworks"):FindFirstChild("FORGE")==nil,
 "Duplicate FORGE replication under Openworks")
local scripts=game.Players.LocalPlayer.PlayerScripts:WaitForChild("Openworks")
local Modes=scripts:WaitForChild("Modes")
local Manager=require(Modes.ModeManager)
local Workspace=require(Modes.EditWorkspace)
local Environment=require(Modes.EditEnvironment)
local Preview=require(scripts.Systems.Components.Preview)
local WorldProjection=require(Modes.WorldProjection)
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
local visualNames={}
for _,part in ipairs(root:GetChildren()) do
 assert(part:IsA("BasePart"))
 assert(not part.CastShadow and not part.CanCollide and not part.CanQuery)
 visualNames[part.Name]=true
end
assert(visualNames.BlueWallX and visualNames.BlueWallZ and visualNames.BlueCeiling
  and visualNames.SkyBackdrop_X and visualNames.SkyBackdrop_Z,
 "Blue Edit environment must surround the room, not only paint the floor")
env:hide()
assert(env.root==nil and root.Parent==nil)
assert(runtime.modeManager.currentName~=nil)
if runtime.modeManager.currentName=="Free" then
 local player=game.Players.LocalPlayer
 assert(math.abs(player.CameraMinZoomDistance-player.CameraMaxZoomDistance)<1e-5,
  "Free Mode must lock character camera zoom")
elseif runtime.modeManager.currentName=="Edit" then
 local bridge=runtime.bridge
 bridge.setPreviewEnabled(true)
 assert(bridge.isPreviewEnabled(),"Edit preview mode failed to activate")
 local gui=game.Players.LocalPlayer.PlayerGui
 assert(not gui.FORM_DebugUI.Enabled and not gui.OPENWORKS_Modes.Enabled,
  "Model preview must hide both editing panels and the FORGE mode bar")
 bridge.setPreviewEnabled(false)
 assert(not bridge.isPreviewEnabled(),"Edit preview failed to restore")
end
-- Verify source models are NOT simultaneously shown at the same CAD origin.
local preview=Preview.new(function() end,function() end)
local first={id=1,name="Plate A",revision=1,
 workspaceOrigin=authored.editCorner,worldOrigin=authored.worldCorner}
local second={id=2,name="Plate B",revision=1,
 workspaceOrigin=authored.editCorner,worldOrigin=authored.worldCorner+Vector3.new(6,0,0)}
local one=preview:ensure(first)
local two=preview:ensure(second)
preview:showOnly(1)
assert(one.Parent==preview.root and two.Parent==nil,
 "Edit Mode must isolate only the active component")
preview:showOnly(-1)
assert(one.Parent==nil and two.Parent==nil,
 "Initial sketch must hide all previously manufactured solids")
preview:showOnly(2)
assert(two.Parent==preview.root and one.Parent==nil)
-- Projections must preserve world placement and cache identity on mode return.
local source=Instance.new("Part")
source.Name="Solid"
source.Size=Vector3.new(1,.1,1)
source.CFrame=CFrame.new(authored.editCorner+Vector3.new(.5,.1,.5))
source.Parent=one
preview.states[1]={part=source,key="q1-check"}
local projection=WorldProjection.new()
projection:show(preview,{components={[1]=first}},authored)
local worldModel=projection.cache[1] and projection.cache[1].model
assert(worldModel,"World model projection was not created")
local cloned=worldModel:FindFirstChild("Solid")
assert(cloned and cloned:IsA("BasePart"))
local expected=authored:toWorld(source.Position)
assert((cloned.Position-expected).Magnitude<1e-4,
 "World projection must restore original component coordinates")
assert(cloned.CanCollide and cloned.CanQuery and not cloned.Anchored,
 "Free Mode components must have physics and support DragDetector selection")
local drag=worldModel:FindFirstChild("OpenWorks_PhysicalDrag",true)
assert(drag and drag:IsA("DragDetector") and drag.Enabled,
 "Free Mode components must be physically draggable")
projection:clear()
assert(projection.root.Parent==nil)
projection:show(preview,{components={[1]=first}},authored)
assert(projection.cache[1].model==worldModel,
 "Mode switching must reuse unchanged projection rather than recloning")
projection:Destroy()
preview:destroy()
local tests=FORGE.Tests:Run("OpenWorks.Q1")
assert(tests.Total>=1 and tests.Failed==0,"FORGE Q1 registered tests failed")
print("OPENWORKS Q1 FORGE PASS: framework, lifecycle, isolation, coordinate mapping, cache and test registry")
