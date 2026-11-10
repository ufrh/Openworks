--!strict
-- World-scale, physical hex-head bolt prefabs. No cosmetic-only bolt:
-- the shaft and head are physical welded parts in a registered fastener.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Fastener={}
local LIBRARY="OPENWORKS_PrimitiveLibrary_DRAFT"
local SIZES={
    {name="Bolt_050U",diameterU=0.5,lengthU=4},
    {name="Bolt_100U",diameterU=1,lengthU=8},
    {name="Bolt_150U",diameterU=1.5,lengthU=12},
}
local function part(parent,name,size,cf)
    local p=Instance.new("Part")
    p.Name=name
    p.Shape=Enum.PartType.Cylinder
    p.Size=size
    p.CFrame=cf
    p.Anchored=true
    p.CanCollide=true
    p.CanTouch=false
    p.Material=Enum.Material.Metal
    p.Color=Color3.fromRGB(166,180,190)
    p.TopSurface=Enum.SurfaceType.Smooth
    p.BottomSurface=Enum.SurfaceType.Smooth
    p.Parent=parent
    return p
end
function Fastener.Ensure()
    local library=ReplicatedStorage:FindFirstChild(LIBRARY)
    if not library then
        library=Instance.new("Folder")
        library.Name=LIBRARY
        library.Parent=ReplicatedStorage
    end
    local folder=library:FindFirstChild("Fasteners")
    if not folder then
        folder=Instance.new("Folder")
        folder.Name="Fasteners"
        folder.Parent=library
    end
    for _,size in ipairs(SIZES) do
        if folder:FindFirstChild(size.name) then continue end
        local model=Instance.new("Model")
        model.Name=size.name
        model:SetAttribute("PrimitiveFamily","Bolt")
        model:SetAttribute("ResizeMode","None")
        model:SetAttribute("BoltDiameterU",size.diameterU)
        model:SetAttribute("BoltLengthU",size.lengthU)
        local scale=0.25
        local shaftLen=size.lengthU*scale
        local diameter=size.diameterU*scale
        local shaft=part(model,"Geometry",
            Vector3.new(shaftLen,diameter,diameter),CFrame.identity)
        model.PrimaryPart=shaft
        -- Head is separate geometry with a visibly hex-like six-face rim.
        local headRadius=diameter*0.83
        local head=part(model,"BoltHead",
            Vector3.new(scale*0.28,headRadius*2,headRadius*2),
            CFrame.new(-shaftLen*0.5-scale*0.14,0,0))
        head.Material=Enum.Material.DiamondPlate
        for i=1,6 do
            local ang=i*math.pi/3
            local tooth=Instance.new("Part")
            tooth.Name="HexFace_"..i
            tooth.Size=Vector3.new(scale*0.29,diameter*0.36,scale*0.16)
            tooth.CFrame=CFrame.new(-shaftLen*0.5-scale*0.14,
                math.cos(ang)*headRadius*0.8,
                math.sin(ang)*headRadius*0.8)
                *CFrame.Angles(ang,0,0)
            tooth.Anchored=true
            tooth.Material=Enum.Material.Metal
            tooth.Color=Color3.fromRGB(113,124,135)
            tooth.CanTouch=false
            tooth.Parent=model
        end
        model.Parent=folder
    end
end
return Fastener
