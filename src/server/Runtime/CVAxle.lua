--!strict
-- Automatic, physically coupled CV half-shaft.
-- Two universal end joints transmit rotation through two telescopic metal
-- sleeves. A passive prismatic between sleeves permits plunge, but prevents
-- relative twist; its travel stops keep the half-shaft captive.
-- Visible hardware is generated from endpoint geometry, not stored as parts
-- in the player's editable primitive count.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Alignment=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("AlignmentMath"))

local CV={}
local MIN_LENGTH=0.45
local MAX_LENGTH=32
local DEFAULT_ANGLE=50
local METAL=Color3.fromRGB(127,143,158)
local DARK=Color3.fromRGB(44,55,65)
local CHROME=Color3.fromRGB(189,199,208)

local function finite(x)
    return type(x)=="number" and x==x and math.abs(x)<math.huge
end

local function shaftEnd(model,toward)
    local part=model.PrimaryPart
    local axis=part.CFrame.RightVector
    local sign=if (toward-part.Position):Dot(axis)>=0 then 1 else -1
    local outward=axis*sign
    return part.Position+outward*(part.Size.X*0.5),outward
end

-- The ends face each other, and their axial directions must fall within
-- the real U-joint articulation range. This rejects imaginary bent axles.
function CV.Measure(source,target,angle,plunge)
    if source==target or not Alignment.IsShaft(source)
        or not Alignment.IsShaft(target)
        or not source.PrimaryPart or not target.PrimaryPart then
        return nil,"A CV axle requires two different cylindrical shafts"
    end
    local limit=if angle==nil then DEFAULT_ANGLE else angle
    if not finite(limit) or limit<5 or limit>70 then
        return nil,"CV articulation must be between 5 and 70 degrees"
    end
    local p0,axis0=shaftEnd(source,target.PrimaryPart.Position)
    local p1,axis1=shaftEnd(target,source.PrimaryPart.Position)
    local delta=p1-p0
    local distance=delta.Magnitude
    if distance<MIN_LENGTH or distance>MAX_LENGTH then
        return nil,"CV shaft endpoints must be 0.45 to 32 studs apart"
    end
    local link=delta/distance
    local cosLimit=math.cos(math.rad(limit))
    if axis0:Dot(link)<cosLimit or (-axis1):Dot(link)<cosLimit then
        return nil,"The two shaft ends exceed the CV joint articulation angle"
    end
    local travel=if plunge==nil then math.min(
        math.clamp(distance*0.16,0.14,1.5),distance*0.25)
        else plunge
    if not finite(travel) or travel<0.05 or travel>distance*0.29 then
        return nil,"CV plunge must be positive and leave both sleeves engaged"
    end
    local diameter=math.min(source.PrimaryPart.Size.Y,
        source.PrimaryPart.Size.Z,target.PrimaryPart.Size.Y,
        target.PrimaryPart.Size.Z)
    local radius=math.clamp(diameter*0.52,0.075,0.42)
    return {
        P0=p0,P1=p1,Link=link,Axis0=axis0,Axis1=axis1,
        Length=distance,Plunge=travel,MaxAngle=limit,Radius=radius,
    }
end

local function tangent(axis)
    local hint=if math.abs(axis:Dot(Vector3.yAxis))<0.90
        then Vector3.yAxis else Vector3.xAxis
    return axis:Cross(hint).Unit
end

local function frame(position,axis,secondary)
    local right=axis.Unit
    local up=secondary-right*secondary:Dot(right)
    if up.Magnitude<1e-5 then up=tangent(right) end
    up=up.Unit
    return CFrame.fromMatrix(position,right,up,right:Cross(up))
end

local function cylinderFrame(position,axis)
    local x=tangent(axis)
    return CFrame.fromMatrix(position,x,axis,x:Cross(axis))
end

local function createPart(parent,name,shape,size,cf,color,material,simulation,massless)
    local part=Instance.new("Part")
    part.Name=name
    part.Shape=shape
    part.Size=size
    part.CFrame=cf
    part.Color=color
    part.Material=material
    part.Anchored=not simulation
    part.CanCollide=false
    part.CanTouch=false
    part.CanQuery=false
    part.CastShadow=false
    part.Massless=massless==true
    part:SetAttribute("OPENWORKS_VisualOnly",true)
    part.Parent=parent
    return part
end

local function weld(parent,root,cosmetic)
    local w=Instance.new("WeldConstraint")
    w.Name="CVAxleHardwareWeld"
    w.Part0=root
    w.Part1=cosmetic
    w.Parent=parent
end

-- Same visible assembly in Build and Simulate. In simulation, the two metal
-- sleeves are real, independently rotating rigid bodies. Boots are cosmetic,
-- massless and welded to the appropriate sleeve (never to wheel/chassis).
function CV.Hardware(parent,g,simulation)
    local folder=Instance.new("Folder")
    folder.Name="CVAxleHardware"
    folder.Parent=parent
    local d,L,r=g.Link,g.Length,g.Radius
    local innerLen=L*0.61
    local outerLen=L*0.61
    local inner=createPart(folder,"DriveSpline",
        Enum.PartType.Cylinder,
        Vector3.new(r*1.55,innerLen,r*1.55),
        cylinderFrame(g.P0+d*(L*0.335),d),
        CHROME,Enum.Material.Metal,simulation,false)
    local outer=createPart(folder,"SlidingSleeve",
        Enum.PartType.Cylinder,
        Vector3.new(r*2.15,outerLen,r*2.15),
        cylinderFrame(g.P1-d*(L*0.335),d),
        METAL,Enum.Material.Metal,simulation,false)
    for i=0,1 do
        local p=if i==0 then g.P0 else g.P1
        local root=if i==0 then inner else outer
        local cap=createPart(folder,
            if i==0 then "InnerCVHousing" else "OuterCVHousing",
            Enum.PartType.Ball,Vector3.one*r*3.3,CFrame.new(p),
            METAL,Enum.Material.Metal,simulation,true)
        if simulation then weld(folder,root,cap) end
        local sign=if i==0 then 1 else -1
        for n=1,3 do
            local pos=p+d*(sign*r*(1+n*0.42))
            local boot=createPart(folder,
                (if i==0 then "Inner" else "Outer").."Boot_"..n,
                Enum.PartType.Cylinder,
                Vector3.new(r*(2.75-n*0.23),r*0.35,
                    r*(2.75-n*0.23)),
                cylinderFrame(pos,d),
                DARK,Enum.Material.SmoothPlastic,simulation,true)
            if simulation then weld(folder,root,boot) end
        end
    end
    return inner,outer,folder
end

local function attachment(part,name,world)
    local a=Instance.new("Attachment")
    a.Name=name
    a.CFrame=part.CFrame:ToObjectSpace(world)
    a.Parent=part
    return a
end

local function universal(parent,name,aPart,bPart,position,aAxis,bAxis,g,id)
    -- UniversalConstraint requires its attachment SECONDARY axes to be
    -- perpendicular. This construction maintains that even at zero angle.
    local cross=aAxis:Cross(bAxis)
    if cross.Magnitude<1e-5 then cross=tangent(aAxis) end
    local y0=cross.Unit
    local y1=bAxis:Cross(y0).Unit
    local a=attachment(aPart,name.."_Drive",
        frame(position,aAxis,y0))
    local b=attachment(bPart,name.."_Driven",
        frame(position,bAxis,y1))
    local u=Instance.new("UniversalConstraint")
    u.Name=name
    u.Attachment0=a
    u.Attachment1=b
    u.LimitsEnabled=true
    u.MaxAngle=g.MaxAngle
    u.Restitution=0
    u.Radius=g.Radius*1.65
    u:SetAttribute("AuthoredRelationId",id)
    u.Parent=parent
    return u
end

function CV.Compile(relation,source,target,runtime)
    local g,why=CV.Measure(source,target,
        relation:GetAttribute("AxleMaxAngle"),
        relation:GetAttribute("AxlePlunge"))
    if not g then error(why or "Invalid CV axle geometry") end
    local inner,outer=CV.Hardware(runtime,g,true)
    local id=relation:GetAttribute("RelationId")
    local first=universal(runtime,"InnerCVUniversal",
        source.PrimaryPart,inner,g.P0,g.Axis0,g.Link,g,id)
    local second=universal(runtime,"OuterCVUniversal",
        outer,target.PrimaryPart,g.P1,g.Link,-g.Axis1,g,id)
    local midpoint=(g.P0+g.P1)*0.5
    local axisFrame=frame(midpoint,g.Link,tangent(g.Link))
    local a=attachment(inner,"PlungeDrive",axisFrame)
    local b=attachment(outer,"PlungeWheel",axisFrame)
    local sliding=Instance.new("PrismaticConstraint")
    sliding.Name="CVTelescopicSpline"
    sliding.Attachment0=a
    sliding.Attachment1=b
    sliding.ActuatorType=Enum.ActuatorType.None
    sliding.LimitsEnabled=true
    sliding.LowerLimit=-g.Plunge
    sliding.UpperLimit=g.Plunge
    sliding.Restitution=0
    sliding:SetAttribute("AuthoredRelationId",id)
    sliding.Parent=runtime
    return {first,second,sliding}
end

return CV
