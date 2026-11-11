--!strict
-- One-click, adjustable default cylinder shaft. Dimensions are in U.
-- Kept separate from Cylinder, which remains a general-purpose primitive.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Grid=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))

local ShaftLibrary={}
local LIBRARY="OPENWORKS_PrimitiveLibrary_DRAFT"

function ShaftLibrary.Ensure()
    local library=ReplicatedStorage:FindFirstChild(LIBRARY)
    if not library then
        library=Instance.new("Folder")
        library.Name=LIBRARY
        library.Parent=ReplicatedStorage
    end
    local category=library:FindFirstChild("Mechanics")
    if not category then
        category=Instance.new("Folder")
        category.Name="Mechanics"
        category.Parent=library
    end
    if category:FindFirstChild("Shaft") then return end

    local model=Instance.new("Model")
    model.Name="Shaft"
    model:SetAttribute("PrimitiveFamily","CylinderShaft")
    model:SetAttribute("ResizeMode","LengthAndDiameter_1U")
    model:SetAttribute("AxialAxis","X")
    local body=Instance.new("Part")
    body.Name="Geometry"
    body.Shape=Enum.PartType.Cylinder
    body.Size=Vector3.new(2*Grid.Unit,0.95*Grid.Unit,0.95*Grid.Unit)
    body.CFrame=CFrame.new()
    body.Anchored=true
    body.Material=Enum.Material.Metal
    body.CanCollide=true
    body.CanQuery=true
    body.CanTouch=false
    body.TopSurface=Enum.SurfaceType.Smooth
    body.BottomSurface=Enum.SurfaceType.Smooth
    body.Parent=model
    model.PrimaryPart=body
    model.Parent=category
end

return ShaftLibrary
