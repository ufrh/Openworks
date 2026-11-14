--!strict
-- Gear contact is not a generic solid intersection. Mating teeth are
-- permitted ONLY with matching module, parallel axes and a correct
-- transverse pitch-circle center distance.
local GearMath={}
local BEVEL_AXIS_TOLERANCE=0.025
local BEVEL_APEX_TOLERANCE=0.085
local RACK_POSITION_TOLERANCE=0.075

function GearMath.Kind(model:Model?):string
    if not model then return "None" end
    if type(model:GetAttribute("RackGuideLengthStuds"))=="number" then
        return "RackGuide"
    end
    if type(model:GetAttribute("RackPitchStuds"))=="number" then
        return "Rack"
    end
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

-- Tooth phase is measured at the actual pitch-contact direction. A phase
-- error of zero means the tooth tips on one gear face gaps on the other.
-- Rev 5 rotates ALL profile teeth by half a pitch: the local +Y/-Y
-- and +Z/-Z centerlines become root gaps. Published rev 4 assets still
-- have tooth zero on +Y. The phase attribute follows the installed mesh
-- asset version, so mixed old/new prefabs remain phase-correct.
-- Return signed error in tooth pitches, wrapped to [-0.5,+0.5).
function GearMath.ToothPhaseError(a:Model,b:Model,poseA:CFrame?):number?
    if not a or not b or not a.PrimaryPart or not b.PrimaryPart then return nil end
    local teethA,teethB=a:GetAttribute("GearTeeth"),b:GetAttribute("GearTeeth")
    if type(teethA)~="number" or type(teethB)~="number"
        or teethA<=0 or teethB<=0 then return nil end
    local kindA,kindB=GearMath.Kind(a),GearMath.Kind(b)
    if kindA~=kindB then return nil end
    local ca,cb=poseA or a:GetPivot(),b:GetPivot()
    local axa,axb=ca.RightVector.Unit,cb.RightVector.Unit
    local radialA,radialB
    if kindA=="Spur" then
        local delta=cb.Position-ca.Position
        radialA=delta-axa*delta:Dot(axa)
        radialB=-delta+axb*delta:Dot(axb)
    elseif kindA=="Bevel90" or kindA=="Bevel45" then
        -- Pitch-cone generator lies along the bisector of both apex-to-gear
        -- axes. Project that direction into each toothed gear face.
        local generator=axa+axb
        if generator.Magnitude<0.001 then return nil end
        generator=generator.Unit
        radialA=generator-axa*generator:Dot(axa)
        radialB=generator-axb*generator:Dot(axb)
    else
        return nil
    end
    if radialA.Magnitude<0.001 or radialB.Magnitude<0.001 then return nil end
    radialA=radialA.Unit
    radialB=radialB.Unit
    -- LookVector is local -Z in Roblox; the authored teeth use local +Z.
    local angleA=math.atan2(radialA:Dot(ca:VectorToWorldSpace(Vector3.zAxis)),
        radialA:Dot(ca.UpVector))
    local angleB=math.atan2(radialB:Dot(cb:VectorToWorldSpace(Vector3.zAxis)),
        radialB:Dot(cb.UpVector))
    local phaseA=a:GetAttribute("GearToothPhaseFraction")
    local phaseB=b:GetAttribute("GearToothPhaseFraction")
    local shiftA=if type(phaseA)=="number" then phaseA else 0
    local shiftB=if type(phaseB)=="number" then phaseB else 0
    local toothTurns=(teethA*angleA+teethB*angleB)/(2*math.pi)
        -shiftA-shiftB
    return (toothTurns%1)-0.5
end

-- True 45° and 90° bevel sets require equal teeth and shared pitch cone apexes.
-- Mixed-angle bevel sets and unequal tooth ratios are not conjugate mates.
function GearMath.AutoBevelStatus(a:Model,b:Model,held: boolean?):(boolean,string,number)
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
    if axisError>(if held then BEVEL_AXIS_TOLERANCE*1.5 else BEVEL_AXIS_TOLERANCE) then
        return false,"Bevel shaft axes must intersect at "..shaftAngle.." degrees",proximity
    end
    if apexError>(if held then BEVEL_APEX_TOLERANCE*1.5 else BEVEL_APEX_TOLERANCE) then
        return false,"Bevel pitch-cone apexes do not coincide",proximity
    end
    return true,tostring(shaftAngle).."-degree bevel mesh",proximity
end

-- An unpowered, grounded rack guide constrains ONLY translation.
-- A guide must be at least as long as the toothed rack and share its
-- X/Up/slide orientation. Small clearance between rail and rack is
-- geometric, not simulated Roblox PrismaticConstraint force.
function GearMath.AutoGuideStatus(a:Model,b:Model):(boolean,string,number)
    local rack=if GearMath.Kind(a)=="Rack" then a else b
    local guide=if rack==a then b else a
    if GearMath.Kind(rack)~="Rack"
        or GearMath.Kind(guide)~="RackGuide" then
        return false,"Rack requires a matching stationary guide",math.huge
    end
    local rackLength=rack:GetAttribute("RackLengthStuds")
    local guideLength=guide:GetAttribute("RackGuideLengthStuds")
    if type(rackLength)~="number" or type(guideLength)~="number"
        or rackLength>guideLength-0.25 then
        return false,"Guide is too short for the rack",math.huge
    end
    local rf,gf=rack:GetPivot(),guide:GetPivot()
    local alignment=1-rf.LookVector:Dot(gf.LookVector)
    local difference=rf.Position-gf.Position
    local x=math.abs(difference:Dot(gf.RightVector))
    local y=math.abs(difference:Dot(gf.UpVector))
    local travel=math.abs(difference:Dot(gf.LookVector))
    local limit=(guideLength-rackLength)*0.5
    local error=x+y+math.max(0,travel-limit)
    if alignment>0.001 or rf.UpVector:Dot(gf.UpVector)<0.999 then
        return false,"Rack and guide axes must match",error+1
    end
    if x>0.09 or y>0.10 then
        return false,"Rack is outside guide lane",error
    end
    if travel>limit+0.03 then
        return false,"Rack would slide beyond the guide",error
    end
    return true,"Rack in guide",error
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
-- Building uses fractional-stud snap and real teeth have finite addendum.
-- The old fixed 0.09 stud limit silently rejected visually engaged gears,
-- especially the larger authored module sizes. Do not allow arbitrarily
-- separated tooth rings: use module-scaled allowance capped at 0.28 studs.
local function toothEngagementTolerance(a,b,held)
    local m=a:GetAttribute("GearModuleStuds")
    local n=b:GetAttribute("GearModuleStuds")
    if type(m)~="number" or type(n)~="number"
        or math.abs(m-n)>0.0001 then return MESH_PITCH_TOLERANCE end
    local allowance=math.clamp(m*0.32,MESH_PITCH_TOLERANCE,0.28)
    return allowance+(if held then math.min(m*0.08,0.06) else 0)
end
function GearMath.AutoMeshStatus(a:Model,b:Model,held: boolean?):(boolean,string,number)
    local kindA=GearMath.Kind(a)
    local kindB=GearMath.Kind(b)
    if kindA=="RackGuide" or kindB=="RackGuide" then
        return GearMath.AutoGuideStatus(a,b)
    end
    if kindA=="Rack" or kindB=="Rack" then
        return GearMath.AutoRackStatus(a,b)
    end
    if kindA=="Bevel45" or kindA=="Bevel90"
        or kindB=="Bevel45" or kindB=="Bevel90" then
        return GearMath.AutoBevelStatus(a,b,held)
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
    if math.abs(axis:Dot(cb.RightVector))<(if held then 0.997 else 0.999) then
        return false,"Gear axles are not parallel",proximity+0.5
    end
    if axial>=faceLimit+(if held then 0.025 else 0) then
        return false,string.format("Gear faces separated by %.3f studs",
            axial-faceLimit),proximity
    end
    local tolerance=toothEngagementTolerance(a,b,held)
    -- Visible tooth intersection matters; metadata alone is not enough.
    local tipA=a:GetAttribute("TipDiameter")
    local tipB=b:GetAttribute("TipDiameter")
    if type(tipA)=="number" and type(tipB)=="number"
        and radial>(tipA+tipB)*0.5+0.001 then
        return false,"Gear tooth tips do not touch",proximity
    end
    if spacingError>tolerance then
        return false,string.format(
            "Gear centers off %.3f studs (max %.3f for these teeth)",
            spacingError,tolerance),proximity
    end
    return true,"Meshed",proximity
end

function GearMath.AutoMeshable(a:Model,b:Model):boolean
    local valid=GearMath.AutoMeshStatus(a,b)
    return valid
end

return table.freeze(GearMath)
