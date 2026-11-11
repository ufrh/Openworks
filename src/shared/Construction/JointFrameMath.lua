--!strict
-- Native arbitrary-axis joint coordinates in each endpoint's local frame.
-- Frames are saved as 12 finite numbers for ordinary JSON plot storage.
local Frames={}
local function finite(n)
    return type(n)=="number" and n==n and math.abs(n)<1000000
end
function Frames.Encode(cf:CFrame)
    local a={cf:GetComponents()}
    return a
end
function Frames.Decode(values)
    if type(values)~="table" or #values~=12 then return nil end
    for _,n in ipairs(values) do if not finite(n) then return nil end end
    local ok,cf=pcall(function() return CFrame.new(table.unpack(values)) end)
    if not ok or cf.RightVector.Magnitude<0.99
        or cf.RightVector.Magnitude>1.01
        or cf.UpVector.Magnitude<0.99
        or cf.UpVector.Magnitude>1.01
        or math.abs(cf.RightVector:Dot(cf.UpVector))>0.02 then return nil end
    return cf
end
function Frames.Validate(kind,a,b,frameA,frameB)
    if not (kind=="AxisHinge" or kind=="AxisBall"
        or kind=="AxisUniversal" or kind=="PoweredHinge") then
        return false,"Unknown angular joint"
    end
    if not a or not b or not a.PrimaryPart or not b.PrimaryPart then
        return false,"Missing joint endpoint"
    end
    local ca,cb=Frames.Decode(frameA),Frames.Decode(frameB)
    if not ca or not cb then return false,"Invalid joint anchor frames" end
    local wa=a.PrimaryPart.CFrame*ca
    local wb=b.PrimaryPart.CFrame*cb
    if (wa.Position-wb.Position).Magnitude>0.035 then
        return false,"Both joint anchors must coincide"
    end
    local function inside(part,point)
        local localPoint=part.CFrame:PointToObjectSpace(point)
        local half=part.Size*0.5+Vector3.new(0.3,0.3,0.3)
        return math.abs(localPoint.X)<=half.X
            and math.abs(localPoint.Y)<=half.Y
            and math.abs(localPoint.Z)<=half.Z
    end
    if not inside(a.PrimaryPart,wa.Position)
        or not inside(b.PrimaryPart,wb.Position) then
        return false,"Joint anchor must be near both components"
    end
    if kind=="AxisUniversal" then
        if math.abs(wa.RightVector:Dot(wb.RightVector))>0.02 then
            return false,"Universal joint axes must be perpendicular"
        end
    elseif wa.RightVector:Dot(wb.RightVector)<0.999 then
        return false,"Joint axes do not align"
    end
    return true
end
function Frames.LocalPair(partA,partB,worldFrame,kind)
    local worldB=if kind=="AxisUniversal"
        then worldFrame*CFrame.Angles(0,0,math.pi/2)
        else worldFrame
    return Frames.Encode(partA.CFrame:ToObjectSpace(worldFrame)),
        Frames.Encode(partB.CFrame:ToObjectSpace(worldB))
end
return table.freeze(Frames)
