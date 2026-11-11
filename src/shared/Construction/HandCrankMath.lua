--!strict
-- Shared manual hand-crank coupling geometry. A coupling is an explicit
-- physical Weld: editor ComponentId alone never transmits input torque.
local Alignment=require(script.Parent:WaitForChild("AlignmentMath"))

local Crank={}
Crank.EndTolerance=0.045 -- studs; reject floating shaft-to-shaft welds
Crank.AlignmentTolerance=0.9995
Crank.MaxTorque=1400 -- maximum native AngularVelocity motor effort
Crank.FixedAngularSpeed=2.0 -- rad/s, fixed target while LMB is held
Crank.MinOutputDiameter=0.06
Crank.MaxOutputDiameter=4.0

function Crank.IsCrank(model)
    return model and model:IsA("Model") and model.PrimaryPart~=nil
        and (model:GetAttribute("ActuatorKind")=="HandCrank"
            or model:GetAttribute("TemplateId")=="HandCrank"
            or model.Name=="HandCrank" or model.Name=="Sim_HandCrank")
end

function Crank.IsOutputShaft(model)
    if not model or not model.PrimaryPart or Crank.IsCrank(model) then
        return false
    end
    if model:GetAttribute("BoltDiameterU")~=nil
        or model:GetAttribute("GearTeeth")~=nil then return false end
    return Alignment.IsShaft(model)
end

-- Cranks keep their 1-stud output length but adapt the complete handle's
-- radial geometry to the actual attached cylinder. No permanent template edit.
-- A fitted primary-part size is enough to reconstruct the crank after undo,
-- redo and plot load, without adding a second persistence field.
function Crank.ValidSize(templateSize, size)
    return typeof(size)=="Vector3"
        and math.abs(size.X-templateSize.X)<0.001
        and math.abs(size.Y-size.Z)<0.001
        and size.Y>=Crank.MinOutputDiameter
        and size.Y<=Crank.MaxOutputDiameter
end

function Crank.ShaftSize(crank,shaft)
    if not Crank.IsCrank(crank) or not Crank.IsOutputShaft(shaft) then
        return nil,"A hand crank and a separate cylindrical shaft are required"
    end
    local size=shaft.PrimaryPart.Size
    if math.abs(size.Y-size.Z)>0.001
        or size.Y<Crank.MinOutputDiameter or size.Y>Crank.MaxOutputDiameter then
        return nil,"Shaft diameter is outside the hand crank's supported range"
    end
    return Vector3.new(crank.PrimaryPart.Size.X,size.Y,size.Y)
end

function Crank.ApplySize(model,size)
    if not Crank.IsCrank(model) or not model.PrimaryPart then return end
    local primary=model.PrimaryPart
    if math.abs(primary.Size.Y-size.Y)<0.000001 then
        primary.Size=size
        return
    end
    -- The pivot and the output face remain fixed along local X. Re-scale
    -- all secondary geometry about the axle's Y/Z plane, including the
    -- arm and manual grip. This works repeatedly without compounding error.
    local ratio=size.Y/primary.Size.Y
    local frame=primary.CFrame
    for _,part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") and part~=primary then
            local relative=frame:ToObjectSpace(part.CFrame)
            local p=relative.Position
            part.Size=Vector3.new(part.Size.X,
                math.max(0.05,part.Size.Y*ratio),
                math.max(0.05,part.Size.Z*ratio))
            part.CFrame=frame*CFrame.new(p.X,p.Y*ratio,p.Z*ratio)
                *relative.Rotation
        end
    end
    primary.Size=size
end

function Crank.OutputEnd(model)
    if not Crank.IsCrank(model) then return nil end
    local cf=model:GetPivot()
    return cf.Position+cf.RightVector*model.PrimaryPart.Size.X*0.5
end

function Crank.NearestShaftEnd(shaft,worldPoint)
    if not Crank.IsOutputShaft(shaft) then return nil end
    local cf=shaft:GetPivot()
    local half=shaft.PrimaryPart.Size.X*0.5
    local a=cf.Position+cf.RightVector*half
    local b=cf.Position-cf.RightVector*half
    return if (a-worldPoint).Magnitude<(b-worldPoint).Magnitude then a else b
end

function Crank.Fits(crank,shaft)
    if not Crank.IsCrank(crank) or not Crank.IsOutputShaft(shaft) then
        return false,"Choose HandCrank and a separate cylindrical shaft"
    end
    local axis=crank:GetPivot().RightVector
    if math.abs(axis:Dot(shaft:GetPivot().RightVector))<Crank.AlignmentTolerance then
        return false,"Crank output and shaft must be coaxial"
    end
    local output=Crank.OutputEnd(crank)
    local target=Crank.NearestShaftEnd(shaft,output)
    if not output or not target then return false,"Crank output is unavailable" end
    local diff=target-output
    local axial=diff:Dot(axis)
    local radial=(diff-axis*axial).Magnitude
    if radial>0.045 or math.abs(axial)>Crank.EndTolerance
        or diff.Magnitude>Crank.EndTolerance then
        return false,"Place the crank's +X output face against a shaft end"
    end
    return true
end

-- Pure transform for automatic end-face snap. Preserve the input crank's
-- current roll as closely as possible; do not twist unrelated assembly parts.
function Crank.Snap(source,shaft)
    if not Crank.IsCrank(source) or not Crank.IsOutputShaft(shaft) then return nil end
    local sourceCF=source:GetPivot()
    local targetCF=shaft:GetPivot()
    local axis=targetCF.RightVector.Unit
    local sourceOutput=Crank.OutputEnd(source)
    local plus=targetCF.Position+axis*shaft.PrimaryPart.Size.X*0.5
    local minus=targetCF.Position-axis*shaft.PrimaryPart.Size.X*0.5
    local targetEnd=if (sourceOutput-plus).Magnitude<=(sourceOutput-minus).Magnitude
        then plus else minus
    local outward=if targetEnd==plus then axis else -axis
    local crankAxis=-outward
    local up=sourceCF.UpVector-crankAxis*sourceCF.UpVector:Dot(crankAxis)
    if up.Magnitude<0.01 then
        up=Vector3.yAxis-crankAxis*crankAxis:Dot(Vector3.yAxis)
    end
    if up.Magnitude<0.01 then
        up=Vector3.zAxis-crankAxis*crankAxis:Dot(Vector3.zAxis)
    end
    up=up.Unit
    local center=targetEnd+outward*source.PrimaryPart.Size.X*0.5
    local cf=CFrame.fromMatrix(center,crankAxis,up,crankAxis:Cross(up))
    local distance=(sourceCF.Position-center).Magnitude
    return cf,distance
end

return table.freeze(Crank)
