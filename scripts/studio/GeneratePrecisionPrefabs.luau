-- OPENWORKS Studio Edit-mode Command Bar. Sync `dev` into Studio first.
-- Generates 45 static-session prefabs, builds the Workspace gallery and
-- focuses the camera on it. On failure, prints the precise failed stage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local openworks = ReplicatedStorage:FindFirstChild("Openworks")
assert(openworks, "Openworks missing from ReplicatedStorage: sync GitHub dev into Studio")
local construction = openworks:FindFirstChild("Construction")
assert(construction, "Openworks.Construction missing: sync the current Rojo project")
local module = construction:FindFirstChild("ProceduralPrefabLibrary")
assert(module and module:IsA("ModuleScript"),
    "ProceduralPrefabLibrary missing: sync latest dev into Roblox Studio")
local prefabs = require(module)
local ok, result = pcall(function()
    return prefabs.BuildGallery(true)
end)
local status = prefabs.GetStatus()
print(string.format("[OPENWORKS][PREFABS] Ready=%s, Count=%d, Gallery=%s, Stage=%s",
    tostring(status.Ready), status.Count, tostring(status.Gallery), status.Progress))
if not ok then
    error("OPENWORKS prefab gallery failed at " .. status.Progress .. ": " .. tostring(result))
end
assert(status.Ready and status.Count == 45 and status.Gallery,
    "OPENWORKS prefab gallery did not install all 45 items")
print("[OPENWORKS][PREFABS] Gallery generated successfully. Inspect Workspace."
    .. result.Name)
