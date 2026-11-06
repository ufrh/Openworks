--!strict
-- Run on the CLIENT Command Bar during Studio Play after Rojo sync.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local FORM=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Volume=require(FORM.MaterialVolume)
local Quantize=require(FORM.Quantize)
local Document=require(FORM.Document)

assert(Quantize.MaxComponentVolumeMM3==175616000)
assert(Volume.toMM3(8)==175616000)
assert(Volume.display(8)=="175,616,000 mm³")
assert(math.abs(Volume.primitive("Block",Vector3.new(2,2,2))-8)<1e-5)
local round=Volume.primitive("Cylinder",Vector3.new(3,1,3))
assert(round<8 and round>7 and not Volume.within(9),
	"Cylinder must be counted by its circular material, not its 9-stud box")
local l=Volume.primitive("RoundedL",Vector3.new(3,3,1))
assert(l<8 and l>0,"Rounded L hollow portion must not count as solid material")
local doc=Document.new()
local shape=doc:create("RoundedL",Vector3.zero,"Open Corner",Vector3.new(3,3,1))
assert(shape,"A 9-stud enclosing box must be allowed when actual material fits")
local before=Document.snapshot(shape)
assert(before.materialVolume and before.materialVolume<8)
-- Native mass with density 1 is exactly volume. For manufactured meshes,
-- fallback physical decompositions are estimates, not guaranteed render
-- mesh volume; Studio needs to exercise those CSG paths separately.
local cube=Instance.new("Part")
cube.Size=Vector3.new(2,2,2)
cube.Anchored=true
cube.Parent=workspace
local measured=Volume.fromPart(cube)
assert(math.abs(measured-8)<1e-3,
	"Roblox physical mass / density must equal material cube volume")
cube:Destroy()
print("FORM material budget: mm³, cylinder, hollow L and mass conversion verified")
