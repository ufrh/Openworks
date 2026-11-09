--!strict
local RS = game:GetService("ReplicatedStorage")
local modules = RS:WaitForChild("Openworks"):WaitForChild("Assembly")
local Alignment = require(modules.Alignment)
local References = require(modules.GeometryReferences)
local Resolver = require(modules.MechanicalResolver)
local Interference = require(modules.Interference)
local Compiler = require(modules.ConstraintCompiler)
local body = {
	id = 1,
	nodes = { { kind = "Block", size = Vector3.one } },
	operations = {
		{
			id = 1,
			kind = "DrillFace",
			origin = Vector3.new(0, 0.5, 0),
			normal = Vector3.yAxis,
			diameter = 0.11,
			depth = 1,
			through = true,
		},
	},
}
local shaft =
	{ id = 2, nodes = { { kind = "Cylinder", size = Vector3.new(0.1, 2, 0.1) } }, operations = {} }
local poses = { ["1"] = CFrame.identity, ["2"] = CFrame.identity }
local record = { model = "BoreSupportV1", bodyId = 1, shaftId = 2, featureId = "hole:1" }
local resolved, why = Resolver.resolve(record, { [1] = body, [2] = shaft }, poses)
assert(resolved, why)
assert(resolved.translation == 1 and resolved.rotation == 1 and not resolved.retained)
local a = Instance.new("Part")
local b = Instance.new("Part")
a.Size = Vector3.one
b.Size = Vector3.one
a.Anchored = true
b.Anchored = true
local root = Instance.new("Folder")
a.Parent = root
b.Parent = root
local ok, problem = xpcall(function()
	a.CFrame = CFrame.identity
	b.CFrame = CFrame.new(1, 0, 0)
	assert(Interference.pair(a, b), "Touching boxes must be valid")
	b.CFrame = CFrame.new(0.9, 0, 0)
	assert(not Interference.pair(a, b), "Penetrating boxes must fail")
	local objects, err = Compiler.compileResolved(resolved, { [1] = a, [2] = b }, root)
	assert(objects, err)
	local cylindrical = objects[1]
	assert(cylindrical:IsA("CylindricalConstraint"))
	assert(cylindrical.InclinationAngle == 0, "Rotation must use the sliding bore axis")
	assert(not cylindrical.LimitsEnabled and not cylindrical.AngularLimitsEnabled)
	for _, obj in ipairs(objects) do
		assert(not obj:IsA("WeldConstraint") and not obj:IsA("BasePart"))
	end
	Compiler.destroy(objects)
	local refA = References.world(References.get(shaft, "shaft"), CFrame.new(3, 4, 5))
	local refB = References.world(References.get(body, "hole:1"), CFrame.identity)
	local aligned = Alignment.solve("Concentric", CFrame.new(3, 4, 5), refA, refB)
	assert(aligned and math.abs(aligned.Position.Y - 4) < 1e-6)
end, debug.traceback)
root:Destroy()
assert(ok, problem)
print(
	"CAD DOMAIN PASS: touching / penetration, cylindrical DOFs, no manufactured hardware, concentric depth"
)
