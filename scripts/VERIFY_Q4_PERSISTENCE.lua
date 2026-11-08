--!strict

-- SERVER Studio Command Bar. Codec is exercised without touching DataStore.
local server = game:GetService("ServerScriptService"):WaitForChild("Openworks")
local Codec = require(server.Persistence.DocumentCodec)
local Store = require(server.Persistence.DocumentStore)

local original = {
	version = 1,
	sessionId = "local-check",
	sequence = 4,
	components = {
		{
			id = 2,
			name = "Test",
			nodes = {
				{
					position = Vector3.new(1, 2, 3),
					size = Vector3.one,
					profilePoints = {Vector2.new(0.1, 0.2)},
				},
			},
			operations = {},
		},
	},
	joints = {
		{
			id = 7,
			kind = "Revolute",
			relativePose = CFrame.new(4, 5, 6) * CFrame.Angles(0, 0.5, 0),
		},
	},
	poses = {["2"] = CFrame.new(7, 8, 9)},
	assembly = {
		version = 2,
		revision = 3,
		poses = {["2"] = CFrame.new(120, 205, 0)},
		grounded = {["2"] = true},
		supports = {},
		quarantined = {{kind = "Revolute", id = 7}},
	},
}

local json = Codec.encode(original)
assert(#json <= Codec.MaxBytes)

local roundtrip = Codec.decode(json)
assert(roundtrip.components[1].nodes[1].position == Vector3.new(1, 2, 3))
assert(roundtrip.components[1].nodes[1].profilePoints[1] == Vector2.new(0.1, 0.2))
assert(
	(roundtrip.joints[1].relativePose.Position - Vector3.new(4, 5, 6)).Magnitude < 1e-5
)
assert(roundtrip.poses["2"].Position == Vector3.new(7, 8, 9))
assert(roundtrip.assembly.poses["2"].Position == Vector3.new(120, 205, 0))
assert(roundtrip.assembly.grounded["2"] and #roundtrip.assembly.supports == 0)
assert(roundtrip.assembly.quarantined[1].kind == "Revolute")

local store = Store.new()
if game:GetService("RunService"):IsStudio()
	and game:GetAttribute("OpenworksEnableStudioDataStore") ~= true then
	assert(store.disabled == true, "Studio saves should be opt-in")
end

print("Q4 PERSISTENCE CODEC PASS: nested FORM snapshots, CFrames and opt-in Studio policy")
