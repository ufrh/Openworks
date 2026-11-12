--!strict
-- One logical alignment origin for every primitive, and one for each grouped
-- component. Origins do not change Roblox PrimaryPart, CFrame or physics roots.
local Origin={}
local ComponentGeometry=require(script.Parent:WaitForChild("ComponentGeometry"))
local LIMIT=256
local function valid(v)
    return typeof(v)=="Vector3" and v.X==v.X and v.Y==v.Y and v.Z==v.Z
        and math.abs(v.X)<=LIMIT and math.abs(v.Y)<=LIMIT
        and math.abs(v.Z)<=LIMIT
end
function Origin.Valid(v)
    return valid(v)
end
function Origin.ComponentAnchor(members)
    if #members==0 then return nil end
    local anchorId=members[1]:GetAttribute("ComponentAnchorId")
    if type(anchorId)=="string" then
        for _,model in ipairs(members) do
            if model:GetAttribute("InstanceId")==anchorId then return model end
        end
    end
    return ComponentGeometry.CentralPrimitive(members)
end
function Origin.PrimitiveLocal(model)
    local value=model and model:GetAttribute("FitPivotLocal")
    return if valid(value) then value else Vector3.zero
end
function Origin.ComponentLocal(anchor)
    local value=anchor and anchor:GetAttribute("ComponentFitPivotLocal")
    return if valid(value) then value else Vector3.zero
end
function Origin.HasPrimitive(model)
    return model and valid(model:GetAttribute("FitPivotLocal"))
end
function Origin.HasComponent(anchor)
    return anchor and valid(anchor:GetAttribute("ComponentFitPivotLocal"))
end
function Origin.World(model,scope)
    local offset=if scope=="Component" then Origin.ComponentLocal(model)
        else Origin.PrimitiveLocal(model)
    return model:GetPivot():PointToWorldSpace(offset)
end
-- The preview is either one primitive or a Model of several cloned members.
-- Express the chosen handle in the preview's own local reference frame so
-- WorldPivot, clone ordering and other members never affect the grab point.
function Origin.PreviewLocal(ghost)
    local members={}
    for _,child in ipairs(ghost:GetChildren()) do
        if child:IsA("Model") and child.PrimaryPart then
            table.insert(members,child)
        end
    end
    if #members>0 then
        local anchor=Origin.ComponentAnchor(members)
        if not anchor then return Vector3.zero,false end
        local localPoint=Origin.ComponentLocal(anchor)
        local worldPoint=anchor:GetPivot():PointToWorldSpace(localPoint)
        return ghost:GetPivot():PointToObjectSpace(worldPoint),Origin.HasComponent(anchor)
    end
    return Origin.PrimitiveLocal(ghost),Origin.HasPrimitive(ghost)
end
function Origin.PlaceAt(ghost,orientation,targetPosition)
    local offset=Origin.PreviewLocal(ghost)
    return CFrame.new(targetPosition)*orientation*CFrame.new(-offset)
end
return table.freeze(Origin)
