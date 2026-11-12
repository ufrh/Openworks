--!strict
-- Shared semantic fit features; one registry for primitive and component input.
-- Geometric shape checks remain in BoreClearance, GearMath and MultiFitMath.
local Alignment=require(script.Parent:WaitForChild("AlignmentMath"))
local Origin=require(script.Parent:WaitForChild("FitOrigin"))
local GearMath=require(script.Parent:WaitForChild("GearMath"))
local Features={}
function Features.Describe(model)
    if not model or not model:IsA("Model") or not model.PrimaryPart then
        return nil
    end
    local cf=model:GetPivot()
    local isShaft=Alignment.IsShaft(model)
    local axis=Alignment.TargetAxis(model)
    local gearKind=GearMath.Kind(model)
    local gear=if gearKind~="None" then gearKind else nil
    local pulley=model:GetAttribute("PrimitiveFamily")=="Pulley"
    return {
        Model=model,
        Center=cf.Position,
        ShaftAxis=if isShaft then cf.RightVector else nil,
        OpeningAxis=if axis then cf:VectorToWorldSpace(axis) else nil,
        Hub=pulley or type(model:GetAttribute("GearTeeth"))=="number",
        Gear=gear,
        Pulley=pulley,
        HasOrigin=Origin.HasPrimitive(model),
        Origin=Origin.World(model,"Primitive"),
        Bounds=model.PrimaryPart.Size,
    }
end
-- Every fit intent is classified HERE before the specialized,
-- geometry-aware clearance/mesh solvers determine an exact legal pose.
-- A custom pivot is a deliberate fallback, not a replacement for a bore.
function Features.Pair(a,b)
    local left,right=Features.Describe(a),Features.Describe(b)
    if not left or not right then return nil end
    if (left.Hub and right.ShaftAxis)
        or (left.ShaftAxis and right.Hub) then
        return "Hub"
    end
    if (left.ShaftAxis and right.OpeningAxis)
        or (left.OpeningAxis and right.ShaftAxis) then
        return "Bore"
    end
    if left.Gear and right.Gear then return "Gear" end
    return nil
end

function Features.Component(members)
    local anchor=Origin.ComponentAnchor(members)
    if not anchor then return nil end
    return {
        Anchor=anchor,Members=members,
        HasOrigin=Origin.HasComponent(anchor),
        Origin=Origin.World(anchor,"Component"),
    }
end
return table.freeze(Features)
