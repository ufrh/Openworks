-- OPENWORKS | Permanent Precision Mesh Publisher (LOCAL STUDIO PLUGIN)
-- The publisher MUST run as a locally installed plugin (not Command Bar,
-- not a server Script, not inside a live game). CreateAssetAsync requires it.
-- Sync the latest dev source into Studio before publishing.
-- REQUIRED: File > Beta Features > CreateAssetAsync Luau API (restart Studio).
local plugin = plugin
assert(plugin, "Install this Script as a LOCAL STUDIO PLUGIN first (Plugins > Save as Local Plugin)")

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MANIFEST_NAME = "OPENWORKS_PublishedMeshAssets"
local SCHEMA_VERSION = 1
local busy = false

local toolbar = plugin:CreateToolbar("OpenWorks Meshes")
local publishButton = toolbar:CreateButton("Publish Missing", "Upload missing permanent gear/bolt meshes and install 45 prefabs", "rbxassetid://0")
local refreshButton = toolbar:CreateButton("Update Mesh Versions", "Re-upload all nine source meshes as new versions of the same permanent asset IDs", "rbxassetid://0")

local function log(message)
    print("[OPENWORKS][MESH PUBLISHER] " .. message)
end
local function fail(message)
    warn("[OPENWORKS][MESH PUBLISHER] " .. tostring(message))
end
local function getGenerator()
    local root = ReplicatedStorage:FindFirstChild("Openworks")
    local construction = root and root:FindFirstChild("Construction")
    local scriptModule = construction and construction:FindFirstChild("ProceduralPrefabLibrary")
    assert(scriptModule and scriptModule:IsA("ModuleScript"),
        "Sync the latest OpenWorks dev code first: "
        .. "ReplicatedStorage.Openworks.Construction.ProceduralPrefabLibrary is missing")
    local generator = require(scriptModule)
    assert(type(generator.PublishBaseAssets) == "function" and
        type(generator.Ensure) == "function", "Your OpenWorks source is outdated; sync dev")
    return generator
end

local function getManifest()
    local manifest = ReplicatedStorage:FindFirstChild(MANIFEST_NAME)
    if not manifest then
        manifest = Instance.new("Folder")
        manifest.Name = MANIFEST_NAME
        manifest.Parent = ReplicatedStorage
    end
    assert(manifest:IsA("Folder"), "The published manifest path is occupied")
    return manifest
end

local function assetIdFor(manifest, key)
    local v = manifest:FindFirstChild(key)
    if not v then return nil end
    assert(v:IsA("StringValue"), "Published asset entry is not a StringValue: " .. key)
    local id = tonumber(v.Value)
    assert(id and id > 0 and v.Value:match("^%d+$"),
        "Invalid saved asset ID for " .. key .. ": " .. v.Value)
    return id
end

local function assetParams(key)
    local p = {
        Name = "OPENWORKS " .. key,
        Description = "OpenWorks permanent precision gear/bolt base mesh. "
            .. "Cloned and resized by the shared primitive prefab generator.",
    }
    -- For group-owned experiences use assets owned by the same group, so
    -- experience servers can load them without individual asset sharing.
    if game.CreatorType == Enum.CreatorType.Group and game.CreatorId > 0 then
        p.CreatorId = game.CreatorId
        p.CreatorType = Enum.AssetCreatorType.Group
    end
    -- For user-owned places the API defaults to the logged-in Studio user.
    return p
end

-- Roblox's upload API is currently gated behind an opt-in Studio beta.
-- Detect the exact engine exception and explain how to unblock publication.
local function checkUploadCall(ok, result, key, action)
    if ok then return end
    local reason = tostring(result)
    if reason:find("CreateAssetAsync and CreateAssetVersionAsync are not available yet", 1, true) then
        error("Roblox mesh upload is disabled in this Studio session. Open File > Beta Features, "
            .. "enable 'CreateAssetAsync Luau API', save, and COMPLETELY RESTART Studio. "
            .. "Then click OpenWorks Meshes > Publish Missing again. No existing mesh IDs were discarded. "
            .. "Original Roblox error: " .. reason, 0)
    end
    error(string.format("%s threw for %s: %s", action, key, reason), 0)
end

local function uploadMesh(editableMesh, key, previousId, updateVersion)
    if previousId and updateVersion then
        local ok, result, versionOrError = pcall(function()
            return AssetService:CreateAssetVersionAsync(editableMesh,
                Enum.AssetType.Mesh, previousId, assetParams(key))
        end)
        checkUploadCall(ok, result, key, "Version upload")
        assert(result == Enum.CreateAssetResult.Success,
            string.format("Version upload failed for %s: %s / %s",
                key, tostring(result), tostring(versionOrError)))
        log(string.format("Updated %s asset %d to version %s", key, previousId, tostring(versionOrError)))
        return previousId
    end
    local ok, result, idOrError = pcall(function()
        return AssetService:CreateAssetAsync(editableMesh,
            Enum.AssetType.Mesh, assetParams(key))
    end)
    checkUploadCall(ok, result, key, "Upload")
    assert(result == Enum.CreateAssetResult.Success and type(idOrError) == "number",
        string.format("Upload failed for %s: %s / %s", key, tostring(result), tostring(idOrError)))
    log(string.format("Published %s as permanent mesh asset %d", key, idOrError))
    return idOrError
end

local function run(updateVersion)
    if busy then fail("Already publishing; no second operation started") return end
    if not RunService:IsStudio() then fail("Run this plugin in Studio Edit mode") return end
    busy = true
    local success, message = pcall(function()
        local generator = getGenerator()
        local manifest = getManifest()
        local previouslyReady = manifest:GetAttribute("Ready") == true
        manifest:SetAttribute("Ready", false)
        manifest:SetAttribute("SchemaVersion", SCHEMA_VERSION)
        local progress = 0
        local ids
        local uploadOK, uploadError = pcall(function()
            ids = generator.PublishBaseAssets(function(key, editableMesh)
                progress += 1
                local previousId = assetIdFor(manifest, key)
                if previousId and not updateVersion then
                    log(string.format("[%d/9] %s already published (%d)", progress, key, previousId))
                    return previousId
                end
                log(string.format("[%d/9] %s: uploading...", progress, key))
                local id = uploadMesh(editableMesh, key, previousId, updateVersion)
                local entry = manifest:FindFirstChild(key)
                if not entry then
                    entry = Instance.new("StringValue")
                    entry.Name = key
                    entry.Parent = manifest
                end
                entry.Value = string.format("%.0f", id) -- Never save scientific notation
                return id
            end)
        end)
        if not uploadOK then
            -- Existing known-good manifest stays usable if an update fails;
            -- first-time publishing remains resumable with saved partial IDs.
            manifest:SetAttribute("Ready", previouslyReady)
            error(uploadError)
        end
        assert(progress == 9, "The generator must provide exactly nine base meshes")
        assert(ids and ids.Bolt_SharpThread and ids.Spur_08T and ids.Bevel90_32T,
            "The generator returned an incomplete base asset manifest")
        manifest:SetAttribute("Ready", true)
        manifest:SetAttribute("GearGeometryVersion", 4)
        manifest:SetAttribute("BoltGeometryVersion", 5)
        manifest:SetAttribute("GeneratedBaseMeshCount", 9)
        log("Nine permanent mesh IDs recorded under ReplicatedStorage." .. MANIFEST_NAME)
        -- Rebuild the 45 prefabs from the saved IDs immediately. This step
        -- may fail before Roblox finishes processing a fresh upload; the IDs
        -- remain saved, so the operation is safe to retry after moderation.
        local ready, installError = pcall(function()
            generator.Ensure(true)
            generator.BuildGallery(false)
        end)
        if not ready then
            fail("Asset IDs are saved, but some meshes aren't ready to load yet: "
                .. tostring(installError))
            fail("Save the place, then retry Publish Missing later. DO NOT regenerate temporary assets.")
        else
            log("Installed 40 persistent gears + 5 persistent bolts, refreshed gallery")
        end
        log("IMPORTANT: Save/Publish your Roblox place to persist the manifest!")
    end)
    busy = false
    if not success then fail(message) end
end

publishButton.Click:Connect(function()
    run(false)
end)
refreshButton.Click:Connect(function()
    run(true)
end)
log("Ready. Sync dev, click Publish Missing, then SAVE the Roblox place.")
