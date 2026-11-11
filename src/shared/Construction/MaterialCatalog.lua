--!strict
-- User-editable material presets. Roblox native physical properties supply
-- real mass, traction and restitution; not cosmetic material labels.
local Catalog={}
local ORDER={"Steel","Aluminum","Rubber","Plastic","Wood","Concrete"}
local DATA={
    Steel={Name="Steel",Material=Enum.Material.Metal,Color=Color3.fromRGB(82,91,104),Density=7.7,Friction=0.48,Elasticity=0.08},
    Aluminum={Name="Aluminum",Material=Enum.Material.Metal,Color=Color3.fromRGB(157,171,183),Density=2.7,Friction=0.48,Elasticity=0.1},
    Rubber={Name="Rubber (tires)",Material=Enum.Material.Rubber,Color=Color3.fromRGB(32,34,39),Density=1.12,Friction=1.65,Elasticity=0.18},
    Plastic={Name="Plastic",Material=Enum.Material.SmoothPlastic,Color=Color3.fromRGB(186,190,193),Density=1.18,Friction=0.42,Elasticity=0.16},
    Wood={Name="Wood",Material=Enum.Material.Wood,Color=Color3.fromRGB(145,96,61),Density=0.72,Friction=0.62,Elasticity=0.1},
    Concrete={Name="Concrete",Material=Enum.Material.Concrete,Color=Color3.fromRGB(143,146,148),Density=2.3,Friction=0.82,Elasticity=0.03},
}
function Catalog.List()
    return ORDER
end
function Catalog.Get(id)
    return DATA[id]
end
function Catalog.IsValid(id)
    return type(id)=="string" and DATA[id]~=nil
end
function Catalog.Apply(model:Model,id:string)
    local settings=DATA[id] or DATA.Steel
    model:SetAttribute("ConstructionMaterial",id)
    for _,part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            local pivot=part:GetAttribute("GearPivotOnly")==true
            if not pivot then
                part.MaterialVariant=""
                part.Material=settings.Material
                part.Color=settings.Color
                part.CustomPhysicalProperties=PhysicalProperties.new(
                    settings.Density,settings.Friction,settings.Elasticity,100,100)
                part.Reflectance=if id=="Steel" or id=="Aluminum"
                    then 0.045 else 0
                if part:IsA("PartOperation") then part.UsePartColor=true end
            end
        end
    end
end
return table.freeze(Catalog)
