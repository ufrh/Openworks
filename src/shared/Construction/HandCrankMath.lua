--!strict
-- Shared manual hand-crank coupling geometry. A coupling is an explicit
-- physical Weld: editor ComponentId alone never transmits input torque.
local Alignment=require(script.Parent:WaitForChild("AlignmentMath"))

local Crank={}
Crank.EndTolerance=0.23 -- studs, for manually placed end faces
Crank.AlignmentTolerance=0.994
Crank.MaxTorque=1400
Crank.MaxAngularSpeed=4.0
Crank.VelocityGain=420

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
    if radial>0.055 or math.abs(axial)>Crank.EndTolerance
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
