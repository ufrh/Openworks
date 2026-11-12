--!strict
-- Precise authoring of logical origins from a selected physical part.
-- Uses the hit part's oriented bounds; never changes its real geometry.
local Snap={}
Snap.Modes=table.freeze({"Cursor","Face","Edge","Corner"})
local function sign(value)
    return if value<0 then -1 else 1
end
function Snap.Point(part,world,mode)
    if not part or not part:IsA("BasePart") or typeof(world)~="Vector3" then
        return world
    end
    if mode=="Cursor" then return world end
    local half=part.Size*0.5
    local localP=part.CFrame:PointToObjectSpace(world)
    local components={localP.X,localP.Y,localP.Z}
    local extents={half.X,half.Y,half.Z}
    local order={1,2,3}
    table.sort(order,function(a,b)
        return math.abs(components[a])/math.max(extents[a],0.001)
            > math.abs(components[b])/math.max(extents[b],0.001)
    end)
    local out={0,0,0}
    local axes=if mode=="Face" then 1 elseif mode=="Edge" then 2 else 3
    for i=1,axes do
        local axis=order[i]
        out[axis]=sign(components[axis])*extents[axis]
    end
    return part.CFrame:PointToWorldSpace(Vector3.new(out[1],out[2],out[3]))
end
return table.freeze(Snap)
