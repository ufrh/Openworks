--!strict
-- Studio CLIENT Command Bar after Rojo sync. No live scene edits.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize=require(FORM.Quantize)
local Document=require(FORM.Document)
local Fabricator=require(FORM.Fabricator)
local player=Players.LocalPlayer
assert(player,"Run in client Command Bar")
assert(Quantize.MaxComponentVolume==8 and Quantize.Size==1/280,
	"Expected 8 stud^3 cap and millimeter sizing")
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
local add,addError=doc:addOperation(maximum,"SketchExtrude",{
	mode="Add",depth=0.1,
	points={
		Vector2.new(-1,-1),Vector2.new(1,-1),
		Vector2.new(1,1),Vector2.new(-1,1),
	},
})
assert(not add and type(addError)=="string",
	"Additive material must not exceed the component envelope")
local measure=require(player.PlayerScripts.Openworks.MeasurementTool)
local dummy=Instance.new("Folder")
dummy.Parent=workspace
local widget=measure.new(player.PlayerGui,dummy)
widget:setActive(true)
assert(widget.active and not widget.line.Visible)
widget:reset()
assert(widget.pointA==nil)
widget:destroy()
dummy:Destroy()
print("FORM creation: named ground placement, 1 mm sizes, volume limits and two-point tool passed")
