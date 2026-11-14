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
local refreshButton = toolbar:CreateButton("Update Mesh Versions", "Create eight compact v6 gear meshes with original bore sizes; stage new IDs and preserve existing plots", "rbxassetid://0")

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

-- Roblox Studio currently rejects Mesh in CreateAssetVersionAsync even if
-- it is listed by some API documentation. Only CreateAssetAsync is used.
-- Published gear asset IDs change, but the manifest swap is staged and safe.
local function uploadMesh(editableMesh, key)
    local ok, result, idOrError = pcall(function()
        return AssetService:CreateAssetAsync(editableMesh,
            Enum.AssetType.Mesh, assetParams(key))
    end)
    checkUploadCall(ok, result, key, "Mesh upload")
    assert(result == Enum.CreateAssetResult.Success and type(idOrError) == "number"
        and idOrError > 0,
        string.format("Mesh upload failed for %s: %s / %s",
            key, tostring(result), tostring(idOrError)))
    log(string.format("Uploaded %s as NEW permanent mesh ID %.0f", key, idOrError))
    return idOrError
end

local function pendingIdFor(entry)
    if not entry or entry:GetAttribute("PendingProfileVersion") ~= 6 then
        return nil
    end
    local raw = entry:GetAttribute("PendingAssetId")
    if type(raw) ~= "string" or not raw:match("^%d+$") then return nil end
    local id=tonumber(raw)
    if not id or id<=0 then return nil end
    return id
end

local function verifyReplacement(key, assetId)
    -- Upload success does NOT guarantee the asset has finished processing
    -- or moderation. Probe loading before switching any live manifest IDs.
    local ok, meshOrError=pcall(function()
        return AssetService:CreateMeshPartAsync(Content.fromAssetId(assetId), {
            CollisionFidelity=Enum.CollisionFidelity.Box,
            RenderFidelity=Enum.RenderFidelity.Precise,
        })
    end)
    if not ok or not meshOrError or not meshOrError:IsA("MeshPart") then
        return false, string.format(
            "%s (%.0f) is not ready to load yet: %s",
            key, assetId, tostring(meshOrError))
    end
    meshOrError:Destroy()
    return true
end

local function run(replaceGears)
    if busy then fail("Already publishing; no second operation started") return end
    if not RunService:IsStudio() then fail("Run this plugin in Studio Edit mode") return end
    busy=true
    local success,message=pcall(function()
        local generator=getGenerator()
        local manifest=getManifest()
        local previouslyReady=manifest:GetAttribute("Ready")==true
        local installedGearVersion=manifest:GetAttribute("GearGeometryVersion")
        if not replaceGears and previouslyReady
            and type(installedGearVersion)=="number"
            and installedGearVersion<6 then
            error("Compact gear profile v6 required: choose OpenWorks Meshes > "
                .."Update Mesh Versions. Mesh uploads require NEW IDs; "
                .."your current published IDs will remain in place until replacements load.")
        end

        -- Existing ready manifests MUST remain active during upload. Only
        -- first-time publication ever sets Ready=false during preparation.
        if not previouslyReady then manifest:SetAttribute("Ready",false) end
        manifest:SetAttribute("SchemaVersion",SCHEMA_VERSION)
        local progress=0
        local ids
        local preparedOK,preparedError=pcall(function()
            ids=generator.PublishBaseAssets(function(key,editableMesh)
                progress+=1
                local entry=manifest:FindFirstChild(key)
                local previousId=assetIdFor(manifest,key)
                local isGear=key~="Bolt_SharpThread"
                local upToDate=entry and entry:GetAttribute("ProfileVersion")==6
                    and (type(installedGearVersion)=="number"
                        and installedGearVersion>=6)
                -- Bolt geometry is not changing. Publish Missing never
                -- overwrites any ID; a completed gear update is idempotent.
                if previousId and (not replaceGears or not isGear or upToDate) then
                    log(string.format("[%d/9] %s already published (%.0f)",
                        progress,key,previousId))
                    return previousId
                end
                if replaceGears and previousId then
                    local pending=pendingIdFor(entry)
                    if pending then
                        log(string.format("[%d/9] %s pending replacement %.0f reused",
                            progress,key,pending))
                        return pending
                    end
                end

                log(string.format("[%d/9] %s: uploading a new mesh...",
                    progress,key))
                local newId=uploadMesh(editableMesh,key)
                if replaceGears and previousId and isGear then
                    -- Saving the place after a partial upload preserves these
                    -- candidates. NEVER change entry.Value until ALL eight
                    -- are loadable. Retry uses the same IDs (no upload loop).
                    entry:SetAttribute("PendingAssetId",
                        string.format("%.0f",newId))
                    entry:SetAttribute("PendingProfileVersion",6)
                else
                    if not entry then
                        entry=Instance.new("StringValue")
                        entry.Name=key
                        entry.Parent=manifest
                    end
                    entry.Value=string.format("%.0f",newId)
                    if isGear then entry:SetAttribute("ProfileVersion",6) end
                end
                return newId
            end)
        end)
        if not preparedOK then
            manifest:SetAttribute("Ready",previouslyReady)
            error("Upload interrupted; existing active mesh IDs preserved. "
                .."Pending replacement IDs are saved on individual gear entries. "
                .."Save the place and retry Update Mesh Versions. "
                ..tostring(preparedError))
        end
        assert(progress==9 and ids and ids.Bolt_SharpThread
            and ids.Spur_08T and ids.Bevel90_32T,
            "Generator returned an incomplete nine-mesh manifest")

        if replaceGears and previouslyReady then
            -- Verify every NEW MeshPart ID first; validation is all-or-none.
            -- Old published gear meshes and prefabs continue to work while
            -- Roblox processes uploads, or when one upload is rejected.
            local originals={}
            local needsSwap=false
            for _,teeth in ipairs({8,12,20,32}) do
                for _,kind in ipairs({"Spur","Bevel90"}) do
                    local key=string.format("%s_%02dT",kind,teeth)
                    local entry=manifest:FindFirstChild(key)
                    assert(entry and entry:IsA("StringValue"),
                        "Missing active gear manifest entry: "..key)
                    local candidate=pendingIdFor(entry)
                    if candidate then
                        local isReady,reason=verifyReplacement(key,candidate)
                        if not isReady then
                            error("Replacement assets are still processing. "
                                .."Original IDs are untouched. Save the place "
                                .."and retry Update Mesh Versions later: "..reason)
                        end
                        originals[key]={
                            Id=entry.Value,
                            Version=entry:GetAttribute("ProfileVersion"),
                        }
                        needsSwap=true
                    elseif entry:GetAttribute("ProfileVersion")~=6 then
                        error("No replacement was staged for "..key
                            .."; old IDs are still active. Retry Update Mesh Versions.")
                    end
                end
            end

            if not needsSwap then
                if type(installedGearVersion)=="number"
                    and installedGearVersion>=6 then
                    log("All eight gear profiles are already at geometry v6.")
                    return
                end
                error("No replacement assets were staged but the active "
                    .."manifest is still marked older than v6. "
                    .."Retry Update Mesh Versions; old assets are untouched.")
            end
            local oldVersion=installedGearVersion
            for key in pairs(originals) do
                local entry=manifest:FindFirstChild(key)
                entry.Value=string.format("%.0f",ids[key])
                entry:SetAttribute("ProfileVersion",6)
            end
            manifest:SetAttribute("GearGeometryVersion",6)
            manifest:SetAttribute("GeneratedBaseMeshCount",9)
            manifest:SetAttribute("Ready",true)

            local rebuilt,problem=pcall(function()
                generator.Ensure(true)
                generator.BuildGallery(false)
            end)
            if not rebuilt then
                -- Atomic rollback of the manifest's active IDs if creating
                -- any runtime prefab fails (moderation/cache errors).
                for key,old in pairs(originals) do
                    local entry=manifest:FindFirstChild(key)
                    entry.Value=old.Id
                    entry:SetAttribute("ProfileVersion",old.Version)
                end
                manifest:SetAttribute("GearGeometryVersion",oldVersion)
                manifest:SetAttribute("Ready",previouslyReady)
                local restored,restoreReason=pcall(function()
                    generator.Ensure(true)
                end)
                if not restored then
                    fail("Restoring old prefab gallery also failed: "
                        ..tostring(restoreReason))
                end
                error("Updated meshes could not be installed; ACTIVE manifest "
                    .."IDs were rolled back. Pending IDs retained for retry. "
                    ..tostring(problem))
            end

            -- Only clear staged IDs after successful prefab installation.
            for key in pairs(originals) do
                local entry=manifest:FindFirstChild(key)
                entry:SetAttribute("PendingAssetId",nil)
                entry:SetAttribute("PendingProfileVersion",nil)
            end
            log("Eight new gear mesh IDs activated; compact gear bodies are v6. "
                .."Original bolt ID and existing constructions preserved.")
        else
            -- First-time publishing, or an incomplete manifest resumed via
            -- Publish Missing. No existing ready asset is ever overridden.
            manifest:SetAttribute("GearGeometryVersion",6)
            manifest:SetAttribute("BoltGeometryVersion",5)
            manifest:SetAttribute("GeneratedBaseMeshCount",9)
            manifest:SetAttribute("Ready",true)
            local ok,problem=pcall(function()
                generator.Ensure(true)
                generator.BuildGallery(false)
            end)
            if not ok then
                manifest:SetAttribute("Ready",previouslyReady)
                error("Assets uploaded, but meshes are not ready to load. "
                    .."IDs remain saved; retry Publish Missing after processing: "
                    ..tostring(problem))
            end
            log("Nine permanent meshes installed.")
        end
        log("IMPORTANT: Save/Publish this Roblox place to persist the new IDs!")
    end)
    busy=false
    if not success then fail(message) end
end

publishButton.Click:Connect(function()
    run(false)
end)
refreshButton.Click:Connect(function()
    run(true)
end)
log("Ready. Use Update Mesh Versions for compact v6 gear geometry, then SAVE the Roblox place.")
