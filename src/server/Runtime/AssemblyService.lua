--!strict
-- Assemblies are manually named, explicitly selected sets of owned primitive
-- models. A component selection EXPANDS to its primitives on the client,
-- but ComponentId never welds them, and mechanical connectivity never
-- implicitly registers unrelated parts. Each primitive stores AssemblyId/
-- AssemblyName for existing snapshot, undo and manual DataStore persistence.
local HttpService=game:GetService("HttpService")

local Service={}
Service.__index=Service
local MAX_MEMBERS=128
local MAX_NAME=48

function Service.new(deps)
    return setmetatable({D=deps},Service)
end

local function cleanName(raw)
    if type(raw)~="string" then return nil end
    local normalized=raw:match("^%s*(.-)%s*$")
    if not normalized or #normalized==0 or #normalized>MAX_NAME
        or normalized:find("[%c]") then
        return nil
    end
    return normalized
end

function Service:Members(player,id)
    local result={}
    for _,model in ipairs(self.D.folder:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("OwnerUserId")==player.UserId
            and model:GetAttribute("AssemblyId")==id then
            table.insert(result,model)
        end
    end
    return result
end

function Service:Requested(player,payload)
    local ids=payload.memberIds
    if type(ids)~="table" then
        return nil,"Select at least one primitive or component"
    end
    if #ids==0 or #ids>MAX_MEMBERS then
        return nil,"Assemblies must contain 1–128 primitives"
    end
    local unique,chosen={},{}
    for _,id in ipairs(ids) do
        if type(id)~="string" or #id==0 or #id>64
            or unique[id] then
            return nil,"Invalid or duplicate assembly member"
        end
        unique[id]=true
        local model=self.D.findOwned(player,id)
        if not model or not model.PrimaryPart then
            return nil,"A selected primitive no longer exists or isn't yours"
        end
        table.insert(chosen,model)
    end
    return chosen
end

function Service:Write(player,payload,updating)
    if type(payload)~="table" then return false,"Invalid assembly request" end
    local name=cleanName(payload.name)
    if not name then return false,"Enter an assembly name (1–48 characters)" end
    local selected,reason=self:Requested(player,payload)
    if not selected then return false,reason end
    local id
    local existing={}
    if updating then
        id=payload.assemblyId
        if type(id)~="string" or #id==0 or #id>64 then
            return false,"Choose an existing assembly first"
        end
        existing=self:Members(player,id)
        if #existing==0 then return false,"Assembly no longer exists" end
    else
        id=HttpService:GenerateGUID(false)
    end

    local selectedSet={}
    for _,model in ipairs(selected) do
        local other=model:GetAttribute("AssemblyId")
        if type(other)=="string" and other~="" and other~=id then
            return false,"A selected primitive belongs to another assembly. Edit that assembly first"
        end
        selectedSet[model]=true
    end

    -- No hidden physics or geometric grouping. Only the explicitly
    -- selected primitive models receive the named membership attributes.
    local before,after={},{}
    local changed={}
    for _,model in ipairs(existing) do changed[model]=true end
    for _,model in ipairs(selected) do changed[model]=true end
    for model in pairs(changed) do
        local currentId=model:GetAttribute("AssemblyId")
        local currentName=model:GetAttribute("AssemblyName")
        local nextId=if selectedSet[model] then id else nil
        local nextName=if selectedSet[model] then name else nil
        if currentId~=nextId or currentName~=nextName then
            table.insert(before,self.D.snapshot(model))
            model:SetAttribute("AssemblyId",nextId)
            model:SetAttribute("AssemblyName",nextName)
            table.insert(after,self.D.snapshot(model))
        end
    end
    if #after>0 then self.D.commitBatch(player,before,after) end
    return true,
        (if updating then "Updated " else "Created ")..name
            .." / "..tostring(#selected).." primitives",
        id
end

function Service:Create(player,payload)
    return self:Write(player,payload,false)
end

function Service:Update(player,payload)
    return self:Write(player,payload,true)
end

function Service:ClearPlayer(_player)
    -- No transient assembly state; names and membership are saved directly
    -- on the owned primitives and persist only on explicit F6 saves.
end

return Service
