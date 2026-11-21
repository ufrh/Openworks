-- Minimal persistence adapter for the first vertical slice.
-- Player documents save as versioned Luau data, never Roblox Instance trees.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FORGE = require(ReplicatedStorage.FORGE)
local Document = require(ReplicatedStorage.OpenWorks.Shared.BlockDocument)

local PersistenceService = FORGE.Class("Service", {
    Name = "PersistenceService",
})

local store

function PersistenceService:Init()
    store = DataStoreService:GetDataStore("OpenWorks_BlockSlice_v1")
end

function PersistenceService:Load(userId)
    local ok, saved = pcall(function()
        return store:GetAsync("player:" .. tostring(userId))
    end)
    if not ok then
        warn("[OpenWorks] Cannot load player document; working in volatile mode: " .. tostring(saved))
        return Document.New(), false
    end
    return Document.Sanitize(saved), true
end

function PersistenceService:Save(userId, document)
    local snapshot = Document.Snapshot(document)
    local ok, err = pcall(function()
        store:UpdateAsync("player:" .. tostring(userId), function()
            return snapshot
        end)
    end)
    if not ok then
        warn("[OpenWorks] Save failed: " .. tostring(err))
        return false
    end
    return true
end

return PersistenceService
