--!strict
-- Appearance only: physical mass, friction, density, restitution and collision
-- remain controlled by MaterialCatalog, never by paint.
local Paint={}
local ORDER={"Factory","Matte","Satin","Gloss","Metallic","Chrome","Brushed","Pearl"}
local FINISH={
    Factory={Name="Original material",Description="Use base material appearance"},
    Matte={Name="Matte",Description="Flat non-reflective paint",Material=Enum.Material.SmoothPlastic,Reflectance=0},
    Satin={Name="Satin",Description="Soft sheen",Material=Enum.Material.SmoothPlastic,Reflectance=0.035},
    Gloss={Name="High Gloss",Description="Shiny clearcoat-like paint",Material=Enum.Material.SmoothPlastic,Reflectance=0.16},
    Metallic={Name="Metallic",Description="Reflective metallic paint",Material=Enum.Material.Metal,Reflectance=0.18},
    Chrome={Name="Chrome",Description="Polished mirrorlike metal",Material=Enum.Material.Metal,Reflectance=0.68},
    Brushed={Name="Brushed Metal",Description="Soft textured metallic sheen",Material=Enum.Material.Metal,Reflectance=0.045},
    Pearl={Name="Pearlescent",Description="Soft luminous pearlescent approximation",Material=Enum.Material.SmoothPlastic,Reflectance=0.10},
}
local PALETTE={
    {Name="Racing Red",Hex="D61F2C"},
    {Name="Crimson",Hex="8D1021"},
    {Name="Burnt Orange",Hex="DB6225"},
    {Name="Gold",Hex="DAAA48"},
    {Name="Sun Yellow",Hex="EEDB49"},
    {Name="Forest",Hex="186B46"},
    {Name="Mint",Hex="65CCAB"},
    {Name="Electric Blue",Hex="2875E9"},
    {Name="Midnight",Hex="172A55"},
    {Name="Violet",Hex="6D45B4"},
    {Name="Rose",Hex="D88CA9"},
    {Name="Pearl White",Hex="F4F1E8"},
    {Name="Silver",Hex="B5BDC9"},
    {Name="Graphite",Hex="4B515C"},
    {Name="Piano Black",Hex="101419"},
    {Name="Cream",Hex="E6D8B7"},
    {Name="Brown",Hex="74513A"},
    {Name="Turquoise",Hex="218C92"},
}
function Paint.List()
    return ORDER
end
function Paint.Get(id:string)
    return FINISH[id]
end
function Paint.Palette()
    return PALETTE
end
function Paint.IsValidFinish(id:any):boolean
    return type(id)=="string" and FINISH[id]~=nil
end
function Paint.NormalizeHex(value:any):string?
    if type(value)~="string" then return nil end
    local hex=value:upper():gsub("^#","")
    if #hex~=6 or not hex:match("^[0-9A-F]+$") then return nil end
    return hex
end
function Paint.ToColor(hex:string):Color3?
    local cleaned=Paint.NormalizeHex(hex)
    if not cleaned then return nil end
    return Color3.fromRGB(
        tonumber(cleaned:sub(1,2),16),
        tonumber(cleaned:sub(3,4),16),
        tonumber(cleaned:sub(5,6),16))
end
function Paint.Apply(model:Model,finishId:string?,hex:string?)
    local chosen=if Paint.IsValidFinish(finishId) then finishId else "Factory"
    local colorHex=Paint.NormalizeHex(hex)
    local finish=FINISH[chosen]
    model:SetAttribute("PaintFinish",chosen)
    model:SetAttribute("PaintColorHex",colorHex)
    local paintColor=if colorHex then Paint.ToColor(colorHex) else nil
    for _,part in ipairs(model:GetDescendants()) do
        if not part:IsA("BasePart") or part:GetAttribute("GearPivotOnly")==true then
            continue
        end
        -- MaterialCatalog already wrote native CustomPhysicalProperties.
        -- Override ONLY render material, color and reflectance.
        if chosen~="Factory" then
            part.Material=finish.Material
            part.Reflectance=finish.Reflectance
        end
        if paintColor then part.Color=paintColor end
        if part:IsA("PartOperation") then part.UsePartColor=true end
    end
end
return table.freeze(Paint)
