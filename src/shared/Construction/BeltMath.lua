--!strict
-- Geometric, server-revalidated two-pulley open-belt path.
-- No invisible motor, teleport, or automatic linear guide.
local Belt={}
local EPS=0.0001
local MAX_SPAN=64

function Belt.IsPulley(model)
    return model~=nil and model:IsA("Model")
        and model.PrimaryPart~=nil
        and model:GetAttribute("PrimitiveFamily")=="Pulley"
        and type(model:GetAttribute("BeltRadiusStuds"))=="number"
end

function Belt.Path(a,b)
    if not Belt.IsPulley(a) or not Belt.IsPulley(b) or a==b then
        return nil,"Choose two different belt pulleys"
    end
    local acf,bcf=a:GetPivot(),b:GetPivot()
    local axisA,axisB=acf.RightVector.Unit,bcf.RightVector.Unit
    if math.abs(axisA:Dot(axisB))<0.995 then
        return nil,"Belt pulley shafts must be parallel"
    end
    local delta=bcf.Position-acf.Position
    local axial=delta:Dot(axisA)
    if math.abs(axial)>0.075 then
        return nil,"Pulley belt tracks must lie in the same plane"
    end
    local planar=delta-axisA*axial
    local distance=planar.Magnitude
    local ra=a:GetAttribute("BeltRadiusStuds")
    local rb=b:GetAttribute("BeltRadiusStuds")
    if not ra or not rb or ra<=EPS or rb<=EPS
        or distance>MAX_SPAN or distance<=ra+rb+0.03 then
        return nil,"Separate the pulleys: belts need a clear tangent span (max 64 studs)"
    end
    local u=planar.Unit
    local v=axisA:Cross(u).Unit
    local cosine=(ra-rb)/distance
    local theta=math.acos(math.clamp(cosine,-1,1))
    local tangent=math.sqrt(math.max(0,distance*distance-(ra-rb)^2))
    local wrapA=2*math.pi-2*theta
    local wrapB=2*theta
    local length=2*tangent+ra*wrapA+rb*wrapB
    return {A=acf.Position,B=bcf.Position,AxisA=axisA,AxisB=axisB,
        U=u,V=v,RadiusA=ra,RadiusB=rb,Theta=theta,
        WrapA=wrapA,WrapB=wrapB,Length=length,Distance=distance}
end

-- A closed polygon on the TRUE external tangents and contact arcs.
function Belt.Points(path)
    local u,v=path.U,path.V
    local function at(center,r,angle)
        return center+r*(u*math.cos(angle)+v*math.sin(angle))
    end
    local points={at(path.A,path.RadiusA,path.Theta),
        at(path.B,path.RadiusB,path.Theta)}
    local divisions=15
    for k=1,divisions do
        table.insert(points,at(path.B,path.RadiusB,
            path.Theta-2*path.Theta*k/divisions))
    end
    table.insert(points,at(path.A,path.RadiusA,-path.Theta))
    for k=1,divisions-1 do
        table.insert(points,at(path.A,path.RadiusA,
            -path.Theta-(2*math.pi-2*path.Theta)*k/divisions))
    end
    return points
end

return table.freeze(Belt)
