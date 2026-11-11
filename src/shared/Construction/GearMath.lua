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

-- Continuous auto-engagement is tighter than the editor's generous
-- placement tolerance. The actual faces must overlap and pitch-circle
-- spacing must be accurate; touching outer tooth bounds is insufficient.
function GearMath.AutoMeshable(a:Model,b:Model):boolean
    if not GearMath.Meshable(a,b)
        or not a.PrimaryPart or not b.PrimaryPart then return false end
    local ca,cb=a:GetPivot(),b:GetPivot()
    local axis=ca.RightVector.Unit
    local separation=cb.Position-ca.Position
    local axial=math.abs(separation:Dot(axis))
    local radial=(separation-axis*separation:Dot(axis)).Magnitude
    local pitch=(a:GetAttribute("GearTeeth")+b:GetAttribute("GearTeeth"))
        *a:GetAttribute("GearModuleStuds")/(2*math.pi)
    local overlap=(a.PrimaryPart.Size.X+b.PrimaryPart.Size.X)*0.5-0.012
    return math.abs(radial-pitch)<=0.045 and axial<overlap
end

return table.freeze(GearMath)
