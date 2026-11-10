--!strict
-- Physical spring authoring in OPENWORKS. No fake cosmetic-only relation:
-- a native SpringConstraint is created during physics simulation.
local Alignment=require(script.Parent:WaitForChild("AlignmentMath"))
local Grid=require(script.Parent:WaitForChild("GridMath"))
local Spring={}
local function thinAxis(model)
    local s=model.PrimaryPart.Size
    if s.X<=s.Y and s.X<=s.Z then return "X",s.X end
    if s.Y<=s.Z then return "Y",s.Y end
    return "Z",s.Z
end

local function plateNormal(model)
    local axis=thinAxis(model)
    local cf=model:GetPivot()
    if axis=="X" then return cf.RightVector end
    if axis=="Z" then return cf.LookVector end
    return cf.UpVector
end

local function plate(model)
    if not model or not model.PrimaryPart then return false end
    local id=string.lower(tostring(model:GetAttribute("TemplateId") or model.Name))
    if string.find(id,"gear",1,true)
        or string.find(id,"bolt",1,true)
        or string.find(id,"cylinder",1,true)
        or string.find(id,"tube",1,true) then return false end
    if string.find(id,"plate",1,true) then return true end
    -- A user can build plates by flattening ordinary Blocks. Physical
    -- proportions count; forcing a special catalog template would make
    -- this unnecessarily cumbersome.
    local s=model.PrimaryPart.Size
    local _,thickness=thinAxis(model)
    return thickness<=math.max(s.X,s.Y,s.Z)*0.45
end

function Spring.Mode(source,target)
    if Alignment.IsShaft(source) and Alignment.TargetAxis(target) then
        return "Piston"
    end
    if plate(source) and plate(target) then return "Plates" end
    return nil
end

function Spring.Validate(source,target)
    local mode=Spring.Mode(source,target)
    if not mode then
        return nil,"Spring requires a shaft+tube or two equal-size plates"
    end
    if mode=="Piston" then
        if not Alignment.Engaged(source,target) then
            return nil,"The spring shaft must remain engaged with its housing"
        end
        local axis=target:GetPivot():VectorToWorldSpace(
            Alignment.TargetAxis(target)
        )
        if math.abs(axis:Dot(source:GetPivot().RightVector))<0.999 then
            return nil,"Spring shaft must be coaxial with the tube"
        end
    else
        local a,b=source.PrimaryPart.Size,target.PrimaryPart.Size
        if (a-b).Magnitude>Grid.Unit*0.02 then
            return nil,"Spring plates must have equal X/Y/Z dimensions"
        end
        local normalA=plateNormal(source)
        local normalB=plateNormal(target)
        if math.abs(normalA:Dot(normalB))<0.995 then
            return nil,"Spring plates must have parallel faces"
        end
        local axis=target:GetPivot().Position-source:GetPivot().Position
        if axis.Magnitude<Grid.Unit or axis.Magnitude>Grid.Unit*32 then
            return nil,"Spring plate separation must be 1–32 U"
        end
        if math.abs(axis.Unit:Dot(normalA))<0.995 then
            return nil,"Spring plates must be centered face-to-face"
        end
        local radial=axis-normalA*axis:Dot(normalA)
        if radial.Magnitude>Grid.Unit*0.1 then
            return nil,"Plate spring centers must be aligned"
        end
    end
    return mode
end

-- Spring force points are distinct from guiding Prismatic attachments:
-- they remain on the real physical spring's line, instead of stacking two
-- perfectly coincident attachments and creating a directionless force.
function Spring.Frames(source,target,mode)
    local sc,tc=source:GetPivot(),target:GetPivot()
    if mode=="Piston" then
        local axis=tc:VectorToWorldSpace(Alignment.TargetAxis(target)).Unit
        local toward=if (sc.Position-tc.Position):Dot(axis)>=0 then axis else -axis
        local housingLength=target.PrimaryPart.Size:Dot(Alignment.TargetAxis(target))
        local shaftLength=source.PrimaryPart.Size.X
        local targetPoint=tc.Position-toward*housingLength*0.27
        local sourcePoint=sc.Position+toward*shaftLength*0.27
        return targetPoint,sourcePoint
    end
    local axis=(sc.Position-tc.Position).Unit
    local _,sourceThickness=thinAxis(source)
    local _,targetThickness=thinAxis(target)
    local extent=math.min(sourceThickness,targetThickness)*0.5
    return tc.Position+axis*extent,sc.Position-axis*extent
end

function Spring.Settings(request,freeLength)
    local stiff=request.stiffness or 120
    local damp=request.damping or 14
    if type(stiff)~="number" or stiff~=stiff or stiff<10 or stiff>3000
        or type(damp)~="number" or damp~=damp or damp<0 or damp>300 then
        return nil,"Spring strength must be 10–3000 and damping 0–300"
    end
    return {stiffness=stiff,damping=damp,
        freeLength=math.clamp(freeLength,0.05,32*Grid.Unit)}
end

return table.freeze(Spring)
