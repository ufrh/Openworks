--!strict
-- Gear contact is not a generic solid intersection. Mating teeth are
-- permitted ONLY with matching module, parallel axes and a correct
-- transverse pitch-circle center distance.
local GearMath={}
local BEVEL_SHAFT_ANGLE=math.rad(45)
local BEVEL_CONE_ANGLE=BEVEL_SHAFT_ANGLE*0.5
local BEVEL_AXIS_TOLERANCE=0.025
local BEVEL_APEX_TOLERANCE=0.085
local RACK_POSITION_TOLERANCE=0.075

function GearMath.Kind(model:Model?):string
    if not model then return "None" end
    if type(model:GetAttribute("RackPitchStuds"))=="number" then
        return "Rack"
    end
    if type(model:GetAttribute("GearTeeth"))=="number" then
        return if model:GetAttribute("GearKind")=="Bevel45"
            then "Bevel45" else "Spur"
    end
    return "None"
end

function GearMath.PitchRadius(model:Model):number
    return (model:GetAttribute("GearTeeth") or 0)
        *(model:GetAttribute("GearModuleStuds") or 0)/(2*math.pi)
end

function GearMath.BevelApex(model:Model):Vector3
    local cf=model:GetPivot()
    return cf.Position-cf.RightVector
        *(GearMath.PitchRadius(model)/math.tan(BEVEL_CONE_ANGLE))
end

-- Matched equal-tooth, 22.5-degree pitch cones mesh on shafts meeting at
-- 45 degrees. Unequal tooth counts require matched NON-22.5-degree cones
-- and must not be silently accepted as physically meaningful.
function GearMath.AutoBevelStatus(a:Model,b:Model):(boolean,string,number)
    if GearMath.Kind(a)~="Bevel45" or GearMath.Kind(b)~="Bevel45" then
        return false,"Bevel gears require matching Bevel45 profiles",math.huge
    end
    local na,nb=a:GetAttribute("GearTeeth"),b:GetAttribute("GearTeeth")
    local ma,mb=a:GetAttribute("GearModuleStuds"),
        b:GetAttribute("GearModuleStuds")
    if type(na)~="number" or type(nb)~="number"
        or type(ma)~="number" or type(mb)~="number"
        or na~=nb or math.abs(ma-mb)>0.0001 then
        return false,"45-degree bevel gears need matching teeth and pitch",
            math.huge
    end
    local aaxis=a:GetPivot().RightVector.Unit
    local baxis=b:GetPivot().RightVector.Unit
    local axisError=math.abs(aaxis:Dot(baxis)-math.cos(BEVEL_SHAFT_ANGLE))
    local apexError=(GearMath.BevelApex(a)-GearMath.BevelApex(b)).Magnitude
    local proximity=apexError+axisError*2
    if axisError>BEVEL_AXIS_TOLERANCE then
        return false,"Bevel shaft axes must intersect at 45 degrees",proximity
    end
    if apexError>BEVEL_APEX_TOLERANCE then
        return false,"Bevel pitch-cone apexes do not coincide",proximity
    end
    return true,"45-degree bevel mesh",proximity
end

-- Rack gear teeth run along local Z, with tooth pitch surface at local
-- +Y offset. Pinion axis must match rack's local X. Rack travel is along
-- its LookVector, and v_rack = omega_pinion * pitchRadius * handedness.
function GearMath.AutoRackStatus(a:Model,b:Model):(boolean,string,number)
    local rack=if GearMath.Kind(a)=="Rack" then a else b
    local pinion=if rack==a then b else a
    if GearMath.Kind(pinion)~="Spur" then
        return false,"Racks require a straight spur pinion",math.huge
    end
    if not rack.PrimaryPart or not pinion.PrimaryPart then
        return false,"Rack or pinion has no geometry",math.huge
    end
    local pitch=rack:GetAttribute("RackPitchStuds")
    local module=pinion:GetAttribute("GearModuleStuds")
    local length=rack:GetAttribute("RackLengthStuds")
    local pitchOffset=rack:GetAttribute("RackPitchOffsetStuds")
    if type(pitch)~="number" or type(module)~="number"
        or type(length)~="number" or type(pitchOffset)~="number"
        or math.abs(pitch-module)>0.0001 then
        return false,"Pinion and rack tooth pitches differ",math.huge
    end
    local rackCF,pinionCF=rack:GetPivot(),pinion:GetPivot()
    local axisError=1-math.abs(rackCF.RightVector:Dot(pinionCF.RightVector))
    local delta=pinionCF.Position-rackCF.Position
    local radialError=math.abs(delta:Dot(rackCF.UpVector)
        -(GearMath.PitchRadius(pinion)+pitchOffset))
    local along=math.abs(delta:Dot(rackCF.LookVector))
    local lateral=math.abs(delta:Dot(rackCF.RightVector))
    local maxAlong=math.max(0,length*0.5-pitch*1.5)
    local maxLateral=(rack.PrimaryPart.Size.X+pinion.PrimaryPart.Size.X)*0.5
        -0.014
    local proximity=radialError+math.max(0,along-maxAlong)
        +math.max(0,lateral-maxLateral)
    if axisError>0.001 then
        return false,"Rack and pinion axes must be parallel",proximity+1
    end
    if radialError>RACK_POSITION_TOLERANCE then
        return false,"Pinion pitch circle does not meet rack teeth",proximity
    end
    if along>maxAlong or lateral>=maxLateral then
        return false,"Pinion lies beyond rack teeth or face width",proximity
    end
    return true,"Rack and pinion engaged",proximity
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
    if kindA=="Rack" or kindB=="Rack" then
        return GearMath.AutoRackStatus(a,b)
    end
    if kindA=="Bevel45" or kindB=="Bevel45" then
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
