--!strict
-- Paste into Roblox Studio Command Bar after syncing dev.
-- Regression for the formatting crash that blocked ALL fabrication.
local FORM=game:GetService("ReplicatedStorage"):WaitForChild("Openworks"):WaitForChild("FORM")
local Document=require(FORM.Document)
local Fabricator=require(FORM.Fabricator)
local doc=Document.new()
local component=doc:create("Block",Vector3.zero)
local key=Fabricator.geometryKey(component)
assert(type(key)=="string","Blank material geometry key failed")
local part,summary=Fabricator.compile(component)
assert(part and type(summary)=="string","Blank material compilation failed")
part:Destroy()

-- Geometry keys must not crash for historic or new File operation shapes.
-- The original regression accidentally referred to nil counters when
-- emitting the final status after ANY fabrication operation.
local edge={
	kind="FileMesh",enabled=true,
	a=Vector3.new(-0.5,0.2,-0.5),b=Vector3.new(0.5,0.2,-0.5),
	normalA=Vector3.yAxis,normalB=-Vector3.zAxis,
	width=0.05,segments=4,interior=false,
}
table.insert(component.operations,edge)
assert(type(Fabricator.geometryKey(component))=="string")
edge.segments=nil
assert(type(Fabricator.geometryKey(component))=="string",
	"Legacy File operation missing segment count crashed")
table.remove(component.operations)
-- Compilation must be possible for a standard source part even when
-- feature history contains toggled-off experimental operations.
table.insert(component.operations,{kind="FileMesh",enabled=false,
	interior=true,segments=12,a=Vector3.zero,b=Vector3.xAxis,
	normalA=Vector3.yAxis,normalB=Vector3.zAxis,width=0.05})
part,summary=Fabricator.compile(component)
assert(part and type(summary)=="string","Disabled File must not crash compilation")
part:Destroy()
print("FORM: blank, File keys, old history and disabled operations passed")
