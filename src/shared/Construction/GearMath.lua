--!strict
-- Gear contact is not a generic solid intersection. Mating teeth are
-- permitted ONLY with matching module, parallel axes and a correct
-- transverse pitch-circle center distance.
local GearMath={}
local BEVEL_AXIS_TOLERANCE=0.025
local BEVEL_APEX_TOLERANCE=0.085

function GearMath.Kind(model:Model?):string
    if not model then return "None" end
    if type(model:GetAttribute("GearTeeth"))=="number" then
        local kind=model:GetAttribute("GearKind")
        if kind=="Bevel45" or kind=="Bevel90" then return kind end
        return "Spur"
    end
    return "None"
end

function GearMath.PitchRadius(model:Model):number
    return (model:GetAttribute("GearTeeth") or 0)
        *(model:GetAttribute("GearModuleStuds") or 0)/(2*math.pi)
end

function GearMath.BevelApex(model:Model):Vector3
    local cf=model:GetPivot()
    local cone=math.rad(model:GetAttribute("BevelConeDeg") or 22.5)
    return cf.Position-cf.RightVector
        *(GearMath.PitchRadius(model)/math.tan(cone))
end

-- True 45° and 90° bevel sets require equal teeth and shared pitch cone apexes.
-- Mixed-angle bevel sets and unequal tooth ratios are not conjugate mates.
function GearMath.AutoBevelStatus(a:Model,b:Model):(boolean,string,number)
    local kindA,kindB=GearMath.Kind(a),GearMath.Kind(b)
    if (kindA~="Bevel45" and kindA~="Bevel90") or kindB~=kindA then
        return false,"Use a matching pair of 45° or 90° bevel gears",math.huge
    end
    local shaftAngle=a:GetAttribute("BevelShaftAngleDeg")
    if shaftAngle~=(kindA=="Bevel90" and 90 or 45)
        or b:GetAttribute("BevelShaftAngleDeg")~=shaftAngle then
        return false,"Bevel shaft angles are inconsistent",math.huge
    end
    local na,nb=a:GetAttribute("GearTeeth"),b:GetAttribute("GearTeeth")
    local ma,mb=a:GetAttribute("GearModuleStuds"),
        b:GetAttribute("GearModuleStuds")
    if type(na)~="number" or type(nb)~="number"
        or type(ma)~="number" or type(mb)~="number"
        or na~=nb or math.abs(ma-mb)>0.0001 then
        return false,"Bevel gears need matching teeth and pitch",
            math.huge
    end
    local aaxis=a:GetPivot().RightVector.Unit
    local baxis=b:GetPivot().RightVector.Unit
    local axisError=math.abs(math.abs(aaxis:Dot(baxis))
        -math.cos(math.rad(shaftAngle)))
    local apexError=(GearMath.BevelApex(a)-GearMath.BevelApex(b)).Magnitude
    local proximity=apexError+axisError*2
    if axisError>BEVEL_AXIS_TOLERANCE then
        return false,"Bevel shaft axes must intersect at "..shaftAngle.." degrees",proximity
    end
    if apexError>BEVEL_APEX_TOLERANCE then
        return false,"Bevel pitch-cone apexes do not coincide",proximity
    end
    return true,tostring(shaftAngle).."-degree bevel mesh",proximity
end

function GearMath.Meshable(a:Model,b:Model):(boolean,string?)
    if not a or not b or a==b then return false,"Choose two separate gears" end
    if GearMath.Kind(a)~="Spur" or GearMath.Kind(b)~="Spur" then
        local ok,reason=GearMath.AutoMeshStatus(a,b)
        return ok,reason
    end
    local n1,n2=a:GetAttribute("GearTeeth"),b:GetAttribute("GearTeeth")
    local module1,module2=a:GetAttribute("GearModuleStuds"),
        b:GetAttribute("GearModuleStuds")
    if type(n1)~="number" or type(n2)~="number"
        or type(module1)~="number" or type(module2)~="number"
        or math.abs(module1-module2)>0.0001 then
        return false,"Gears need the same tooth module"
    end
    local cfA,cfB=a:GetPivot(),b:GetPivot()
    local axis=cfA.RightVector
    if math.abs(axis:Dot(cfB.RightVector))<0.999 then
        return false,"Gear axes must be parallel"
    end
    local delta=cfB.Position-cfA.Position
    local depth=math.abs(delta:Dot(axis))
    local lateral=(delta-axis*delta:Dot(axis)).Magnitude
    local pitch=(n1+n2)*module1/(2*math.pi)
    if math.abs(lateral-pitch)>0.09 or depth>0.18 then
        return false,string.format("Gear centers need %.2f stud spacing",pitch)
    end
    return true
end

-- Runtime contact must use PHYSICAL tooth face overlap, not the
-- editor's 0.18-stud center-plane shortcut. With a third gear added on
-- a second axle the faces may still overlap at >0.18 axial offset.
-- Respect the same 0.09-stud pitch-spacing tolerance as construction,
-- so a gear the editor accepts is not mysteriously rejected in Simulate.
local MESH_PITCH_TOLERANCE=0.09
function GearMath.AutoMeshStatus(a:Model,b:Model):(boolean,string,number)
    local kindA=GearMath.Kind(a)
    local kindB=GearMath.Kind(b)
    if kindA=="Bevel45" or kindA=="Bevel90"
        or kindB=="Bevel45" or kindB=="Bevel90" then
        return GearMath.AutoBevelStatus(a,b)
    end
    if not a or not b or a==b or not a.PrimaryPart or not b.PrimaryPart then
        return false,"Missing gear geometry",math.huge
    end
    local n1,n2=a:GetAttribute("GearTeeth"),b:GetAttribute("GearTeeth")
    local m1,m2=a:GetAttribute("GearModuleStuds"),
        b:GetAttribute("GearModuleStuds")
    if type(n1)~="number" or type(n2)~="number"
        or type(m1)~="number" or type(m2)~="number"
        or n1<=0 or n2<=0 or m1<=0 or m2<=0 then
        return false,"Invalid gear tooth data",math.huge
    end
    local ca,cb=a:GetPivot(),b:GetPivot()
    local axis=ca.RightVector.Unit
    local delta=cb.Position-ca.Position
    local axial=math.abs(delta:Dot(axis))
    local radial=(delta-axis*delta:Dot(axis)).Magnitude
    local pitch=(n1+n2)*m1/(2*math.pi)
    local spacingError=math.abs(radial-pitch)
    local faceLimit=(a.PrimaryPart.Size.X+b.PrimaryPart.Size.X)*0.5
        -math.max(0.012,math.min(a.PrimaryPart.Size.X,b.PrimaryPart.Size.X)*0.07)
    local proximity=spacingError+math.max(0,axial-faceLimit)*2
    if math.abs(m1-m2)>0.0001 then
        return false,"Different tooth pitches",proximity+1
    end
    if math.abs(axis:Dot(cb.RightVector))<0.999 then
        return false,"Gear axles are not parallel",proximity+0.5
    end
    if axial>=faceLimit then
        return false,string.format("Gear faces separated by %.3f studs",
            axial-faceLimit),proximity
    end
    if spacingError>MESH_PITCH_TOLERANCE then
        return false,string.format("Gear center spacing is off by %.3f studs",
            spacingError),proximity
    end
    return true,"Meshed",proximity
end

function GearMath.AutoMeshable(a:Model,b:Model):boolean
    local valid=GearMath.AutoMeshStatus(a,b)
    return valid
end

return table.freeze(GearMath)
