--!strict
-- Run in Studio Play, CLIENT Command Bar, after Rojo sync.
-- A centered drawn sketch must create a centered Boolean cutter and
-- successfully remove material from the compiled sketched stock.
local RS=game:GetService("ReplicatedStorage")
local FORM=RS:WaitForChild("Openworks"):WaitForChild("FORM")
local Document=require(FORM.Document)
local Extrusion=require(FORM.Extrusion)
local Fabricator=require(FORM.Fabricator)
local doc=Document.new()
local base={
 Vector2.new(-1,-1),Vector2.new(1,-1),
 Vector2.new(1,1),Vector2.new(-1,1),
}
local body,reason=doc:createSketchBody(
 "Centered Cut Regression",Vector3.zero,Vector3.new(2,.6,2),base,.6)
assert(body,"Unable to create test body: "..tostring(reason))
local operation={
 points={
  Vector2.new(-.35,-.35),Vector2.new(.35,-.35),
  Vector2.new(.35,.35),Vector2.new(-.35,.35),
 },
 mode="Remove",through=false,depth=.25,
}
local cutter,dispose=Extrusion.create(body.nodes[1],operation)
local position=cutter.CFrame.Position
assert(math.abs(position.X)<1e-4 and math.abs(position.Z)<1e-4,
 "Sketch cut shifted away from its drawn center: "..tostring(position))
assert(math.abs(position.Y-(.6/2-.25/2+.04/2))<1e-4,
 "Sketch cut height did not match removal depth")
dispose()
local before,firstStatus=Fabricator.compile(body)
assert(before and before:IsA("BasePart"),
 "Initial SketchBody failed: "..tostring(firstStatus))
before:Destroy()
local ok,why=doc:addOperation(body,"SketchExtrude",operation)
assert(ok,"Unable to add sketch removal: "..tostring(why))
local finished,summary=Fabricator.compile(body)
assert(finished and finished:IsA("BasePart"),
 "Subtractive SketchExtrude failed: "..tostring(summary))
assert(finished.Size.Magnitude>0,"Cut produced empty or invalid solid")
finished:Destroy()
print("FORM SKETCH REMOVAL PASS: center alignment, blind-cut depth, and CSG compilation")
