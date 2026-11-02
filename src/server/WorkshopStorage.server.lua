local DataStoreService = game:GetService('DataStoreService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Workshop = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('Workshop'))

local remote = Instance.new('RemoteFunction')
remote.Name = 'WorkshopStorage'
remote.Parent = ReplicatedStorage.Openworks

local available, store = pcall(function()
    return DataStoreService:GetDataStore('Openworks_Workshop_v1')
end)
local lastRequest = {}

local function respond(ok, detail, data)
    return {ok = ok, message = detail, data = data}
end

remote.OnServerInvoke = function(player, action, json)
    if action ~= 'save' and action ~= 'load' then
        return respond(false, 'UNKNOWN_ACTION')
    end

    local now = os.clock()
    if lastRequest[player.UserId] and now - lastRequest[player.UserId] < 2 then
        return respond(false, 'WAIT_BEFORE_RETRYING')
    end
    lastRequest[player.UserId] = now

    if not available then
        return respond(false, 'DATASTORE_UNAVAILABLE_USE_JSON_EXPORT')
    end

    local key = 'user_' .. tostring(player.UserId)
    if action == 'save' then
        if type(json) ~= 'string' or #json > Workshop.MAX_JSON_BYTES then
            return respond(false, 'INVALID_PROJECT_SIZE')
        end
        local valid, project = pcall(Workshop.deserialize, json)
        if not valid or not project then
            return respond(false, 'INVALID_PROJECT_OR_OPERATIONS')
        end
        local clean = project:serialize()
        local success, err = pcall(function()
            store:SetAsync(key, clean)
        end)
        if not success then
            warn('[WORKSHOP:Storage] Save unavailable: ' .. tostring(err))
            return respond(false, 'DATASTORE_UNAVAILABLE_USE_JSON_EXPORT')
        end
        return respond(true, 'PROJECT_SAVED')
    end

    local success, result = pcall(function() return store:GetAsync(key) end)
    if not success then
        warn('[WORKSHOP:Storage] Load unavailable: ' .. tostring(result))
        return respond(false, 'DATASTORE_UNAVAILABLE_USE_JSON_IMPORT')
    end
    if type(result) ~= 'string' then return respond(false, 'NO_SAVED_PROJECT') end
    local valid, project = pcall(Workshop.deserialize, result)
    if not valid or not project then return respond(false, 'SAVED_PROJECT_INVALID') end
    return respond(true, 'PROJECT_LOADED', project:serialize())
end

game:GetService('Players').PlayerRemoving:Connect(function(player)
    lastRequest[player.UserId] = nil
end)
