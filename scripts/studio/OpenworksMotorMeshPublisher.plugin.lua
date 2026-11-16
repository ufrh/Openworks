-- OPENWORKS | Publish the Brushed DC Motor meshes as permanent Roblox assets.
-- Install THIS SCRIPT as a LOCAL STUDIO PLUGIN, not via Command Bar.
-- Requires CreateAssetAsync Luau API Studio beta and Mesh / Image API permissions.
local plugin = assert(plugin, "Save this as a local Studio Plugin first")
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Geometry = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("MotorMeshGeometry"))
local toolbar = plugin:CreateToolbar("OpenWorks Meshes")
local button = toolbar:CreateButton("Publish DC Motor",
    "Upload the three watertight DC motor material sections, then refresh Actuators",
    "rbxassetid://0")
local NAME = "OPENWORKS_PublishedMotorMeshes"
local busy = false
local function log(message)
    print("[OPENWORKS][MOTOR PUBLISHER] "..message)
end
local function ensureManifest()
    local folder = ReplicatedStorage:FindFirstChild(NAME)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = NAME
        folder.Parent = ReplicatedStorage
    end
    assert(folder:IsA("Folder"),"Motor mesh manifest name occupied")
    return folder
end
local function publish(mesh, key)
    local params = {
        Name = "OpenWorks Motor "..key,
        Description = "Watertight, selectively hard-edged DC motor mesh; "
            .. "static visual geometry for the OpenWorks primitive library.",
    }
    if game.CreatorType == Enum.CreatorType.Group and game.CreatorId > 0 then
        params.CreatorType = Enum.AssetCreatorType.Group
        params.CreatorId = game.CreatorId
    end
    local ok, status, assetId = pcall(function()
        return AssetService:CreateAssetAsync(mesh, Enum.AssetType.Mesh, params)
    end)
    if not ok then
        error("Could not publish "..key..": "..tostring(status)
            ..". Enable CreateAssetAsync Luau API beta and restart Studio.",0)
    end
    assert(status == Enum.CreateAssetResult.Success
        and type(assetId)=="number" and assetId>0,
        "Upload failed for "..key..": "..tostring(status).." "..tostring(assetId))
    return assetId
end
local function verifyAsset(id)
    local ok, part = pcall(function()
        return AssetService:CreateMeshPartAsync(Content.fromAssetId(id), {
            CollisionFidelity = Enum.CollisionFidelity.Box,
            RenderFidelity = Enum.RenderFidelity.Precise,
        })
    end)
    if ok then part:Destroy() end
    return ok, part
end
local function run()
    if busy then return end
    busy = true
    local ok, reason = pcall(function()
        local manifest = ensureManifest()
        local revision = manifest:GetAttribute("GeometryVersion")
        if manifest:GetAttribute("Ready")==true and revision==Geometry.Version then
            log("Motor meshes are already published; refreshing primitive.")
        else
            manifest:SetAttribute("Ready",false)
            for i,key in ipairs(Geometry.Keys) do
                local entry = manifest:FindFirstChild(key)
                local saved = entry and entry:IsA("StringValue")
                    and entry.Value:match("^%d+$") and tonumber(entry.Value)
                if saved and entry:GetAttribute("GeometryVersion")==Geometry.Version then
                    log(string.format("[%d/%d] %s already uploaded",i,#Geometry.Keys,key))
                else
                    local mesh, tris = Geometry.Build(key)
                    local success, result = pcall(publish, mesh, key)
                    mesh:Destroy()
                    assert(success, tostring(result))
                    local id = result
                    if not entry then
                        entry = Instance.new("StringValue")
                        entry.Name = key
                        entry.Parent = manifest
                    end
                    assert(entry:IsA("StringValue"), "Bad mesh entry for "..key)
                    entry.Value = tostring(id)
                    log(string.format("[%d/%d] Uploaded %s: %.0f (%d tris)",
                        i,#Geometry.Keys,key,id,tris))
                end
            end
            manifest:SetAttribute("GeometryVersion",Geometry.Version)
        end
        for _,key in ipairs(Geometry.Keys) do
            local entry = manifest:FindFirstChild(key)
            local id = entry and tonumber(entry.Value)
            assert(id and id>0,"Missing permanent motor asset: "..key)
            local valid, err = verifyAsset(id)
            if not valid then
                error("Motor mesh "..key.." asset "..id.." is not loadable yet ("
                    ..tostring(err).."). Save Studio and rerun Publish DC Motor "
                    .."after Roblox asset processing completes.",0)
            end
        end
        manifest:SetAttribute("Ready",true)
        local runtime = ServerScriptService:WaitForChild("Openworks")
            :WaitForChild("Runtime"):WaitForChild("MotorLibrary")
        local success,err = pcall(function() require(runtime).Ensure(true) end)
        if not success then
            manifest:SetAttribute("Ready",false)
            error("Assets published but primitive refresh failed: "..tostring(err),0)
        end
        log("Ready! Brushed DC Motor registered under Actuators/ DC Motor.")
        log("IMPORTANT: Save / Publish this Roblox place to retain the manifest.")
    end)
    busy = false
    if not ok then warn("[OPENWORKS][MOTOR PUBLISHER] "..tostring(reason)) end
end
button.Click:Connect(run)
log("Ready. Click OpenWorks Meshes > Publish DC Motor.")
