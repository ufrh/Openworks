--!strict
-- Read-only view of authored OPENWORKS models/relationships.
-- AssemblyId is explicit simulation membership; ComponentId is only an
-- editor selection grouping. Partial components are represented accurately
-- under whichever assembly actually owns their primitive members.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Construction=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Config=require(Construction:WaitForChild("BuildConfig"))

local Data={}

local function idOf(model)
    local id=model:GetAttribute("InstanceId")
    return if type(id)=="string" and id~="" then id else nil
end

local function sortNames(items)
    table.sort(items,function(a,b)
        if a.name==b.name then return a.key<b.key end
        return a.name:lower()<b.name:lower()
    end)
end

function Data.Snapshot(player)
    local root=workspace:FindFirstChild(Config.FolderName)
    local byId={}
    local models={}
    if root then
        for _,model in ipairs(root:GetChildren()) do
            if model:IsA("Model") and model.PrimaryPart
                and model:GetAttribute("OwnerUserId")==player.UserId then
                local id=idOf(model)
                if id then
                    byId[id]=model
                    table.insert(models,model)
                end
            end
        end
    end
    table.sort(models,function(a,b)
        return tostring(idOf(a))<tostring(idOf(b))
    end)
    local assemblies={}
    local groups={}
    local function getGroup(aid,model)
        local key=if aid then "a:"..aid else "unassigned"
        local group=groups[key]
        if not group then
            group={
                kind=if aid then "assembly" else "unassigned",
                id=aid or "",key=key,
                name=if aid then tostring(model:GetAttribute("AssemblyName")
                    or "Assembly") else "Unassigned objects",
                members={},children={},components={},primitives={},
            }
            groups[key]=group
            table.insert(assemblies,group)
        end
        return group
    end
    for _,model in ipairs(models) do
        local aid=model:GetAttribute("AssemblyId")
        if type(aid)~="string" or aid=="" then aid=nil end
        local group=getGroup(aid,model)
        table.insert(group.members,model)
        local cid=model:GetAttribute("ComponentId")
        local item={
            kind="primitive",id=idOf(model),model=model,
            key="p:"..tostring(idOf(model)),
            name=model.Name,members={model},
            assemblyId=aid,componentId=cid,
        }
        if type(cid)=="string" and cid~="" then
            local comp=group.components[cid]
            if not comp then
                comp={
                    kind="component",id=cid,componentId=cid,
                    key=group.key..":c:"..cid,
                    name="Component "..cid:sub(1,8),members={},
                    children={},assemblyId=aid,
                }
                group.components[cid]=comp
                table.insert(group.children,comp)
            end
            table.insert(comp.members,model)
            table.insert(comp.children,item)
        else
            table.insert(group.children,item)
        end
    end
    for _,group in ipairs(assemblies) do
        for _,comp in pairs(group.components) do
            sortNames(comp.children)
        end
        sortNames(group.children)
    end
    sortNames(assemblies)

    local relations={}
    local relationships=workspace:FindFirstChild("OPENWORKS_Relationships")
    if relationships then
        for _,relation in ipairs(relationships:GetChildren()) do
            if relation:GetAttribute("OwnerUserId")==player.UserId then
                local id=relation:GetAttribute("RelationId")
                if type(id)=="string" and id~="" then
                    local kind=tostring(relation:GetAttribute("Kind") or "Connection")
                    local first=byId[relation:GetAttribute("SourceId")]
                    local second=byId[relation:GetAttribute("TargetId")]
                    table.insert(relations,{
                        kind="relation",id=id,key="r:"..id,
                        name=kind,relation=relation,
                        first=first,second=second,
                        members=if first and second then {first,second}
                            elseif first then {first}
                            elseif second then {second} else {},
                    })
                end
            end
        end
    end
    sortNames(relations)
    local signature={tostring(#models),tostring(#relations)}
    for _,m in ipairs(models) do
        table.insert(signature,table.concat({
            tostring(idOf(m)),
            tostring(m.Name),
            tostring(m:GetAttribute("ComponentId") or ""),
            tostring(m:GetAttribute("AssemblyId") or ""),
            tostring(m:GetAttribute("AssemblyName") or ""),
        },"|"))
    end
    for _,r in ipairs(relations) do
        table.insert(signature,r.id.."|"..r.name)
    end
    return {
        assemblies=assemblies,relations=relations,byId=byId,
        models=models,signature=table.concat(signature,";"),
    }
end

return table.freeze(Data)
