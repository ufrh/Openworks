-- OPENWORKS | MANUAL V4 MOTOR MESH REGISTRATION (NO PLUGIN)
-- FIRST: Upload all six V4 OBJ meshes through Studio's 3D Importer.
-- NEXT: Replace each zero below with the corresponding Mesh asset ID.
-- THEN: Paste this complete script into Studio's EDIT-MODE Command Bar.
-- This script DOES NOT upload meshes. It installs verified IDs in the place.
local IDS = {
    RearCan = 0,
    Armature = 0,
    Housing = 0,
    Endbell = 0,
    Bearing = 0,
    Bushing = 0,
}
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerScriptService")
local AS = game:GetService("AssetService")
local geometry = require(RS.Openworks.Construction.MotorMeshGeometry)
local motor = require(SS.Openworks.Runtime.MotorLibrary)
assert(geometry.Version == 4,"Sync OpenWorks V4 source before registering meshes")

-- IMPORTANT: Never apply a partial set of asset IDs. Validation must succeed
-- for all six before touching the currently active mesh manifest.
local verified = {}
for _,key in ipairs(geometry.Keys) do
    local id=IDS[key]
    assert(type(id)=="number" and id>0 and id%1==0,
        "Set the numeric mesh asset ID for "..key)
    local ok,result=pcall(function()
        return AS:CreateMeshPartAsync(Content.fromAssetId(id),{
            CollisionFidelity=Enum.CollisionFidelity.Box,
            RenderFidelity=Enum.RenderFidelity.Precise,
        })
    end)
    assert(ok and result,"Cannot load "..key.." asset "..tostring(id)..
        ": "..tostring(result)..". Check moderation and creator permissions.")
    verified[key]=result
end

-- Optional geometry sanity check: check relative model dimensions using
-- the first six imports. Export meshes with zeroed CFrame (see export stage).
for _,key in ipairs(geometry.Keys) do
    local part=verified[key]
    assert(part.Size.X>0 and part.Size.Y>0 and part.Size.Z>0,
        "Invalid imported mesh bounds for "..key)
    print("[OW MOTOR][MANUAL] "..key..": asset "..IDS[key].." | "..tostring(part.Size))
    part:Destroy()
end

local manifest=RS:FindFirstChild("OPENWORKS_PublishedMotorMeshes")
if not manifest then
    manifest=Instance.new("Folder")
    manifest.Name="OPENWORKS_PublishedMotorMeshes"
    manifest.Parent=RS
end
assert(manifest:IsA("Folder"),"Motor manifest name is occupied")
local oldReady=manifest:GetAttribute("Ready")
local oldVersion=manifest:GetAttribute("GeometryVersion")
local old={}
for _,key in ipairs(geometry.Keys) do
    local entry=manifest:FindFirstChild(key)
    assert(entry==nil or entry:IsA("StringValue"),
        "Unexpected manifest entry for "..key)
    old[key]=entry and entry.Value or nil
end
local ok,err=pcall(function()
    manifest:SetAttribute("Ready",false)
    for _,key in ipairs(geometry.Keys) do
        local entry=manifest:FindFirstChild(key)
        if not entry then
            entry=Instance.new("StringValue")
            entry.Name=key
            entry.Parent=manifest
        end
        entry.Value=tostring(IDS[key])
        entry:SetAttribute("GeometryVersion",4)
    end
    manifest:SetAttribute("GeometryVersion",4)
    manifest:SetAttribute("Ready",true)
    local prefab=motor.Ensure(true)
    assert(prefab:GetAttribute("PublishedMotorVisual")==true,
        "MotorLibrary did not activate the published V4 meshes")
end)
if not ok then
    manifest:SetAttribute("Ready",false)
    manifest:SetAttribute("GeometryVersion",oldVersion)
    for _,key in ipairs(geometry.Keys) do
        local entry=manifest:FindFirstChild(key)
        if old[key] then
            entry.Value=old[key]
        elseif entry then
            entry:Destroy()
        end
    end
    manifest:SetAttribute("Ready",oldReady)
    pcall(function() motor.Ensure(true) end)
    error("V4 motor registration rolled back: "..tostring(err))
end
print("[OW MOTOR] V4 published mesh assets registered.")
print("[OW MOTOR] Save/Publish the Roblox PLACE so the manifest persists.")
print("[OW MOTOR] Restart Play and confirm Build > Actuators > Brushed DC Motor.")
