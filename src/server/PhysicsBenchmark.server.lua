--!strict
-- OPENWORKS PHYSICS EXPERIMENT. This script only operates inside Roblox Studio.
-- Separate experiment branch: never merge into the clean game bootstrap.
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:FindFirstChild("OWPhysicsBenchmarkRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "OWPhysicsBenchmarkRemote"
	remote.Parent = ReplicatedStorage
end
local Runtime = require(script.Parent:WaitForChild("Bench"):WaitForChild("Runtime"))
local bench = Runtime.new(remote)
remote.OnServerEvent:Connect(function(player, action, value)
	bench:handle(player, action, value)
end)
print("[OPENWORKS] Physics lab initialized | 17 mechanisms x 5 scales | Studio only")
