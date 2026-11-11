--!strict
-- Backfills the v5.2 Studio-generated HandCrank when absent. Does NOT
-- overwrite existing precompiled banks or change saved template IDs.
local ReplicatedStorage=game:GetService("ReplicatedStorage")

local Library={}
local SCALE=0.25
local LIBRARY="OPENWORKS_PrimitiveLibrary_DRAFT"

local function metal(parent,name,size,cf,color,shape)
    local p=Instance.new("Part")
    p.Name=name
    p.Size=size
    p.CFrame=cf
    p.Shape=shape or Enum.PartType.Block
    p.Material=Enum.Material.Metal
    p.Color=color
    p.Anchored=true
    p.CanCollide=true
    p.CanQuery=true
    p.CanTouch=false
    p.TopSurface=Enum.SurfaceType.Smooth
    p.BottomSurface=Enum.SurfaceType.Smooth
    p.Parent=parent
    return p
end

function Library.Ensure()
    local root=ReplicatedStorage:FindFirstChild(LIBRARY)
    if not root then
        root=Instance.new("Folder")
        root.Name=LIBRARY
        root.Parent=ReplicatedStorage
    end
    local category=root:FindFirstChild("Actuators")
    if not category then
        category=Instance.new("Folder")
        category.Name="Actuators"
        category.Parent=root
    end
    if category:FindFirstChild("HandCrank") then return end

    local model=Instance.new("Model")
    model.Name="HandCrank"
    model:SetAttribute("PrimitiveFamily","Cylinder")
    model:SetAttribute("ResizeMode","None")
    model:SetAttribute("ActuatorKind","HandCrank")
    model:SetAttribute("ActuatorInput","ManualGrip")
    model:SetAttribute("ActuatorOutputAxis","X")
    model:SetAttribute("ActuatorRequiresPlayerInput",true)
    model:SetAttribute("CrankRadiusU",5)
    model:SetAttribute("CrankShaftDiameterU",0.75)
    model:SetAttribute("CrankShaftLengthU",4)
    model:SetAttribute("StudsPerUnit",SCALE)
    model:SetAttribute("StudioPrecompiled",true)

    local steel=Color3.fromRGB(193,151,103)
    local dark=Color3.fromRGB(68,77,86)
    local length=4*SCALE
    local radius=5*SCALE
    local shaft=metal(model,"Geometry",Vector3.new(length,0.75*SCALE,0.75*SCALE),
        CFrame.identity,steel,Enum.PartType.Cylinder)
    model.PrimaryPart=shaft
    local output=Instance.new("Attachment")
    output.Name="ActuatorOutput"
    output.CFrame=CFrame.new(length*0.5,0,0)
    output.Parent=shaft

    local crankX=-length*0.5-SCALE*0.4
    metal(model,"CrankHub",Vector3.new(SCALE*0.95,SCALE*1.6,SCALE*1.6),
        CFrame.new(crankX,0,0),steel,Enum.PartType.Cylinder)
    metal(model,"CrankArm",Vector3.new(SCALE*0.7,radius+SCALE*0.9,SCALE*0.75),
        CFrame.new(crankX,radius*0.5,0),steel)
    local gripX=crankX-SCALE*1
    metal(model,"GripAxle",Vector3.new(SCALE*2.2,SCALE*0.5,SCALE*0.5),
        CFrame.new(gripX,radius,0),steel,Enum.PartType.Cylinder)
    local grip=metal(model,"Grip",Vector3.new(SCALE*1.9,SCALE*1.1,SCALE*1.1),
        CFrame.new(gripX-SCALE*0.45,radius,0),dark,Enum.PartType.Cylinder)
    local anchor=Instance.new("Attachment")
    anchor.Name="ManualGrip"
    anchor.Parent=grip
    metal(model,"GripEndCap",Vector3.new(SCALE*0.23,SCALE*1.18,SCALE*1.18),
        CFrame.new(gripX-SCALE*1.47,radius,0),steel,Enum.PartType.Cylinder)
    model.Parent=category
end

return Library
