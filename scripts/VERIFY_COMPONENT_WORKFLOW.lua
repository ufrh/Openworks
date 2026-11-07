--!strict
-- Studio CLIENT Command Bar after Rojo sync. No live scene edits.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize=require(FORM.Quantize)
local Document=require(FORM.Document)
local Fabricator=require(FORM.Fabricator)
local MaterialVolume=require(FORM.MaterialVolume)
local player=Players.LocalPlayer
assert(player,"Run in client Command Bar")
assert(Quantize.MaxComponentVolumeMM3==175616000 and Quantize.Size==1/280,
	"Expected numeric material budget in cubic millimeters")
local doc=Document.new()
local at=Vector3.new(2,0,-3)
local size=Vector3.new(0.25,0.25,0.20)
local ramp,reason=doc:create("RoundedL",at,"Corner Ramp",size)
assert(ramp,"Named placed ramp rejected: "..tostring(reason))
assert(ramp.name=="Corner Ramp")
assert((Document.minCorner(ramp.nodes[1])-at).Magnitude<0.0001,
	"Placed minimum corner must match clicked ground position")
assert(ramp.nodes[1].size==size)
assert(Fabricator.requiresCompile(ramp),"Rounded L must compile into solid mesh")
local over,overReason=doc:create("Block",Vector3.zero,"Too Big",Vector3.new(3,3,3))
assert(over==nil and type(overReason)=="string",
	"Block exceeding 8 cubic studs must be rejected")
local maximum=doc:create("Block",Vector3.zero,"Eight Cubic Studs",
	Vector3.new(2,2,2))
assert(maximum~=nil)
local old=maximum.nodes[1].size
local valid,errorText=doc:editNode(maximum,1,"size","X",2.1)
assert(not valid and type(errorText)=="string" and maximum.nodes[1].size==old,
	"Numeric scaling must respect the component cap")
local transformed,transformError=doc:applyTransform(maximum,1,nil,
	Vector3.new(2,2,2.1),nil,true,false)
assert(not transformed and type(transformError)=="string",
	"Handle resizing must be restricted by component cap")
-- Operations are validated against the manufactured solid, not a box.
-- They are provisionally accepted until Preview compiles and checks CSG.
local accepted=Document.snapshot(maximum)
local add,addError=doc:addOperation(maximum,"SketchExtrude",{
	mode="Add",depth=0.1,
	points={
		Vector2.new(-1,-1),Vector2.new(1,-1),
		Vector2.new(1,1),Vector2.new(-1,1),
	},
})
assert(add,"Adding a feature must not be rejected by a fake envelope cap: "..
	tostring(addError))
assert(doc:restoreSnapshot(maximum,accepted))
assert(#maximum.operations==0,"Reverting an oversize CSG must restore the valid document")
-- Shape volume differs from its bounding box. These fit even though
-- their bounding envelopes exceed the historic 8-stud cuboid.
local slender,err=doc:create("Block",Vector3.zero,"Long Thin",
	Vector3.new(10,0.05,10))
assert(slender,"Long thin stock should fit 5 stud³: "..tostring(err))
local cylinder,cylinderError=doc:create("Cylinder",Vector3.zero,"Round Stock",
	Vector3.new(3,1,3))
assert(cylinder,"Cylinder should fit despite 9-stud³ box: "..tostring(cylinderError))
assert(MaterialVolume.primitive("Cylinder",Vector3.new(3,1,3))<8)
local rounded,roundedError=doc:create("RoundedL",Vector3.zero,"Open L",
	Vector3.new(3,3,1))
assert(rounded,"Hollow L should fit despite 9-stud³ box: "..tostring(roundedError))
assert(MaterialVolume.primitive("RoundedL",rounded.nodes[1].size)<8)
assert(MaterialVolume.toMM3(8)==175616000)
assert(MaterialVolume.display(8)=="175,616,000 mm³")
local measure=require(player.PlayerScripts.Openworks.Tools.Inspection.MeasurementTool)
local dummy=Instance.new("Folder")
dummy.Parent=workspace
local widget=measure.new(player.PlayerGui,dummy)
widget:setActive(true)
assert(widget.active and not widget.line.Visible)
widget:reset()
assert(widget.pointA==nil)
widget:destroy()
dummy:Destroy()
print("FORM creation: numeric mm³ material budget, true primitive volume, CSG rollback and tool passed")
