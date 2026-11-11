--!strict
-- Gear contact is not a generic solid intersection. Mating teeth are
-- permitted ONLY with matching module, parallel axes and a correct
-- transverse pitch-circle center distance.
local GearMath={}
function GearMath.Meshable(a:Model,b:Model):(boolean,string?)
    if not a or not b or a==b then return false,"Choose two separate gears" end
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
