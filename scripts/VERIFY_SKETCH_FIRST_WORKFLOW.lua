--!strict
-- Run during Studio Play on the CLIENT Command Bar after Rojo sync.
-- Validates character-first creation data, local grid and first sketch stock.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
assert(player,"Run from client Command Bar")
local client=player:WaitForChild("PlayerScripts"):WaitForChild("Openworks")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local GridOverlay=require(client.Experience.Visuals.GridOverlay)
local CharacterMode=require(client.Modes.Free.CharacterMode)
local Document=require(FORM.Document)
local MaterialVolume=require(FORM.MaterialVolume)
local Compiler=require(FORM.Compiler)
local Fabricator=require(FORM.Fabricator)
local HistoryTopology=require(client.Systems.Selection.HistoryTopology)
local SketchBodyProfile=require(FORM.SketchBodyProfile)
local SketchEditor=require(client.Tools.Sketch.SketchEditor)
local ComponentPlacement=require(client.Experience.Placement.ComponentPlacement)
local GeometryCutter=require(FORM.GeometryCutter)
assert(ComponentPlacement.WORKSPACE_HEIGHT_MM==1000,
	"Component placement must set an automatic 1000mm workspace height")
assert(SketchEditor.DEFAULT_FIRST_EXTRUSION_MM==56,
	"First sketch extrusion must not inherit workspace height")


local playerMode=CharacterMode.new(player)
assert(not playerMode.editing,"Character controls should be default mode")

local grid=GridOverlay.new(player.PlayerGui)
assert(#grid.lines==0,"Global 6x6 grid must NOT exist on startup")
local corner=Vector3.new(3.25,0,-5.25)
local dimensions=Vector3.new(1,.3,.6)
grid:update(corner,dimensions)
grid:setVisible(true)
assert(grid.corner==corner)
assert(grid.size==Vector2.new(1,.6))
assert(grid.lineCount>0 and grid.lineCount<70)
for i=1,grid.lineCount do
	assert(grid.lines[i].Visible,"Selected local grid must actually render")
end
local moved=Vector3.new(-2,0,2.5)
grid:update(moved,Vector3.new(.5,.3,.3))
assert(grid.corner==moved and grid.size==Vector2.new(.5,.3),
	"Placement grid must relocate AND resize")
grid:setVisible(false)
for _,line in ipairs(grid.lines) do
	assert(not line.Visible,"No old large grid lines may remain visible")
end
grid:destroy()

local doc=Document.new()
assert(#doc.order==0,"Entering creation mode must not spawn a solid")
local points={
	Vector2.new(-.4,-.2),Vector2.new(.4,-.2),
	Vector2.new(.4,.05),Vector2.new(.1,.05),
	Vector2.new(.1,.2),Vector2.new(-.4,.2),
}
local solid,reason=doc:createSketchBody("My First Sketch",corner,
	Vector3.new(1,.3,.6),points,.3)
assert(solid,"First sketch rejected: "..tostring(reason))
local node=solid.nodes[1]
assert(node.kind=="SketchBody" and node.profilePoints
	and #node.profilePoints==6,"A drawn outline, not a primitive, must source stock")
assert(solid.name=="My First Sketch")
assert((Document.minCorner(node)-corner).Magnitude<1e-5)
assert(solid.materialVolume>0 and
	solid.materialVolume<dimensions.X*dimensions.Z*.3)
assert(MaterialVolume.node(node)==solid.materialVolume)
assert(Fabricator.requiresCompile(solid),"First sketch must compile into mesh")
local allowed=pcall(function()return Compiler.nativePart(node)end)
assert(not allowed,"A sketch must NEVER have a hidden primitive placeholder")
local ring,travel=SketchBodyProfile.profile(node)
assert(#ring==6 and math.abs(travel.Y-.3)<1e-6)

-- Verify manufacturing-face selection follows the drawn polygon instead
-- of a rectangular envelope, even with an inward concave corner.
local part=Instance.new("Part")
part.Size=node.size
part.CFrame=Compiler.pose(node)
part.Anchored=true
local topology,problem=HistoryTopology.build(part,solid)
assert(topology,"Sketch history surface indexing failed: "..tostring(problem))
local top
for _,face in ipairs(topology.faces) do
	if face.tag=="sketch_top" then top=face break end
end
assert(top and #top.polygon==6,"Selection must follow six drawn edges, not a box")
part:Destroy()
-- This is the IMPORTANT runtime assertion: a finished manufactured
-- BasePart, not just sketch adornments. Works with EditableMesh or the
-- native CSG wedge fallback if mesh APIs are restricted in Studio.
local compiled,actual,summary=pcall(Fabricator.compile,solid)
assert(compiled,"First sketch solid failed to compile: "..tostring(actual))
assert(typeof(actual)=="Instance" and actual:IsA("BasePart")
	and actual.Size.Magnitude>0 and actual.Transparency<1,
	"First sketch returned no visible manufactured solid")
print("FORM first sketch compiled as "..actual.ClassName..
	" ("..tostring(summary)..")")
actual:Destroy()
local profile,travel=SketchBodyProfile.profile(node)
local nativeOK,nativeOrError=pcall(GeometryCutter.prismNative,profile,travel)
assert(nativeOK and nativeOrError and nativeOrError:IsA("BasePart"),
	"Native no-EditableMesh wedge fallback failed: "..tostring(nativeOrError))
nativeOrError.Parent=workspace
nativeOrError.CanQuery=true
local cast=RaycastParams.new()
cast.FilterType=Enum.RaycastFilterType.Include
cast.FilterDescendantsInstances={nativeOrError}
local hit=workspace:Raycast(Vector3.new(-0.25,1,-0.05),
	Vector3.new(0,-2,0),cast)
assert(hit and hit.Instance==nativeOrError,
	"Native solid must occupy a point inside the authored sketch, not just its bounding box")
nativeOrError:Destroy()
print("FORM sketch-first: default 1000mm workspace / 56mm extrude, 3D CSG solid, native fallback and topology verified")
