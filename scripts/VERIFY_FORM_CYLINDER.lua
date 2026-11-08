--!strict
-- Studio Client Command Bar. Native cylinder stock, FORGE-compatible source.
local RS=game:GetService("ReplicatedStorage")
local FORM=RS:WaitForChild("Openworks"):WaitForChild("FORM")
local Document=require(FORM.Document)
local Compiler=require(FORM.Compiler)
local Fabricator=require(FORM.Fabricator)
local doc=Document.new()
local diameter=28/280
local length=140/280
local component,reason=doc:create("Cylinder",Vector3.zero,
 "Manufactured Shaft",Vector3.new(diameter,length,diameter))
assert(component,reason)
assert(not Fabricator.requiresCompile(component),
 "Native cylinder should never require unnecessary CSG")
local part=Compiler.nativePart(component.nodes[1])
assert(part.Shape==Enum.PartType.Cylinder)
assert(math.abs(part.Size.X-length)<1e-5)
assert(math.abs(part.Size.Y-diameter)<1e-5)
assert(math.abs(part.CFrame.XVector:Dot(Vector3.yAxis))>.99,
 "Shaft long axis must be aligned to authoring Y")
part:Destroy()
print("FORM CYLINDER PASS: dimensions, native stock, shaft axis")
