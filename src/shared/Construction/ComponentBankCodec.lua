--!strict
-- Pure, portable construction transforms for reusable component blueprints.
-- A bank entry stores offsets relative to one anchor, NEVER world coordinates.
local Codec={}
local function finite(x)
    return type(x)=="number" and x==x and math.abs(x)<100000
end
function Codec.Vec(v)
    return {v.X,v.Y,v.Z}
end
function Codec.ReadVec(a)
    if type(a)~="table" or #a~=3 then return nil end
    for _,x in ipairs(a) do if not finite(x) then return nil end end
    return Vector3.new(a[1],a[2],a[3])
end
function Codec.Pose(cf)
    local a={cf:GetComponents()}
    return a
end
function Codec.ReadPose(a)
    if type(a)~="table" or #a~=12 then return nil end
    for _,x in ipairs(a) do if not finite(x) then return nil end end
    local cf=CFrame.new(table.unpack(a))
    local x,y,z=cf.RightVector,cf.UpVector,cf.LookVector
    if math.abs(x.Magnitude-1)>0.015 or math.abs(y.Magnitude-1)>0.015
        or math.abs(z.Magnitude-1)>0.015
        or math.abs(x:Dot(y))>0.015
        or math.abs(x:Dot(z))>0.015
        or math.abs(y:Dot(z))>0.015 then
        return nil
    end
    return cf
end
function Codec.PartValid(part)
    if type(part)~="table" or type(part.id)~="string"
        or #part.id>64 or type(part.template)~="string"
        or #part.template>80 or type(part.steps)~="table"
        or not Codec.ReadPose(part.relative)
        or not Codec.ReadVec(part.size)
        or (part.fitPivot~=nil and not Codec.ReadVec(part.fitPivot))
        or (part.componentPivot~=nil and not Codec.ReadVec(part.componentPivot))
        then return false end
    return true
end
return table.freeze(Codec)
