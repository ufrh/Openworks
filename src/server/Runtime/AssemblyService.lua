--!strict
-- Player-owned, non-rigid named assemblies. Components remain independent
-- physical bodies; the assembly is the SCOPE of simulation and inspection.
local HttpService=game:GetService("HttpService")
local Service={}
Service.__index=Service

function Service.new(deps)
    return setmetatable({D=deps,NextNumber={}},Service)
end

local function key(model)
    local component=model:GetAttribute("ComponentId")
    if type(component)=="string" and component~="" then
        return "c:"..component
    end
    return "p:"..tostring(model:GetAttribute("InstanceId"))
end

function Service:Connected(player,seed)
    local d=self.D
    local byId,bodies={},{}
    for _,model in ipairs(d.folder:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("OwnerUserId")==player.UserId then
            local id=model:GetAttribute("InstanceId")
            if type(id)=="string" then
                byId[id]=model
                local k=key(model)
                bodies[k]=bodies[k] or {}
                table.insert(bodies[k],model)
            end
        end
    end
    local adjacent={}
    for _,joint in ipairs(d.mechanical.Folder:GetChildren()) do
        if joint:GetAttribute("OwnerUserId")==player.UserId then
            local a=byId[joint:GetAttribute("SourceId")]
            local b=byId[joint:GetAttribute("TargetId")]
            if a and b then
                local ka,kb=key(a),key(b)
                if ka~=kb then
                    adjacent[ka]=adjacent[ka] or {}
                    adjacent[kb]=adjacent[kb] or {}
                    table.insert(adjacent[ka],kb)
                    table.insert(adjacent[kb],ka)
                end
            end
        end
    end
    local visited={[key(seed)]=true}
    local queue={key(seed)}
    local index=1
    while index<=#queue do
        local current=queue[index]
        index+=1
        for _,other in ipairs(adjacent[current] or {}) do
            if not visited[other] then
                visited[other]=true
                table.insert(queue,other)
            end
        end
    end
    local result={}
    for _,body in ipairs(queue) do
        for _,model in ipairs(bodies[body] or {}) do
            table.insert(result,model)
        end
    end
    return result
end

function Service:Register(player,payload)
    local d=self.D
    local seed=d.findOwned(player,payload.seedId)
    if not seed or not d.nearPlayer(player,seed:GetPivot().Position) then
        return false,"Aim at one of your components to register an assembly"
    end
    local connected=self:Connected(player,seed)
    if #connected==0 or #connected>128 then
        return false,"Assembly must contain 1–128 parts"
    end
    local id=HttpService:GenerateGUID(false)
    local number=(self.NextNumber[player] or 0)+1
    self.NextNumber[player]=number
    local name="Assembly "..tostring(number)
    local before,after={},{}
    for _,model in ipairs(connected) do
        table.insert(before,d.snapshot(model))
        model:SetAttribute("AssemblyId",id)
        model:SetAttribute("AssemblyName",name)
        table.insert(after,d.snapshot(model))
    end
    d.commitBatch(player,before,after)
    return true,name,id
end

function Service:Add(player,payload)
    local d=self.D
    local seed=d.findOwned(player,payload.seedId)
    if not seed or not d.nearPlayer(player,seed:GetPivot().Position) then
        return false,"Aim at the part to add"
    end
    if type(payload.assemblyId)~="string" or #payload.assemblyId>64 then
        return false,"Register an assembly first (A)"
    end
    local target,assemblyName
    for _,member in ipairs(d.folder:GetChildren()) do
        if member:IsA("Model")
            and member:GetAttribute("OwnerUserId")==player.UserId
            and member:GetAttribute("AssemblyId")==payload.assemblyId then
            target=member
            assemblyName=member:GetAttribute("AssemblyName")
            break
        end
    end
    if not target then return false,"The selected assembly no longer exists" end
    local connected=self:Connected(player,seed)
    local members={}
    for _,member in ipairs(d.folder:GetChildren()) do
        if member:IsA("Model")
            and member:GetAttribute("OwnerUserId")==player.UserId
            and member:GetAttribute("AssemblyId")==payload.assemblyId then
            table.insert(members,member)
        end
    end
    local count=#members
    local before,after={},{}
    for _,member in ipairs(connected) do
        if member:GetAttribute("AssemblyId")~=payload.assemblyId then
            count+=1
            if count>128 then return false,"Assembly limit is 128 parts" end
            table.insert(before,d.snapshot(member))
        end
    end
    for _,state in ipairs(before) do
        local member=d.findOwned(player,state.instanceId)
        member:SetAttribute("AssemblyId",payload.assemblyId)
        member:SetAttribute("AssemblyName",assemblyName)
        table.insert(after,d.snapshot(member))
    end
    if #after==0 then return false,"That component is already in this assembly" end
    d.commitBatch(player,before,after)
    return true,tostring(#after).." part(s) added to "..tostring(assemblyName),
        payload.assemblyId
end

function Service:ClearPlayer(player)
    self.NextNumber[player]=nil
end

return Service
