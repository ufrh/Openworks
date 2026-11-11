--!strict
-- One compact drilled block with a true through-bore, not a painted hole.
-- Generated ONCE per server start and reused as a template for every copy.
-- Startup-only CSG: never call SubtractAsync during drag, build or simulation.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local GeometryService=game:GetService("GeometryService")
local Grid=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))

local CompactHole={}
local LIBRARY="OPENWORKS_PrimitiveLibrary_DRAFT"
local TEMPLATE_ID="DrilledBlock_1U_D098"
local OUTER_U=1
local HOLE_U=0.98

function CompactHole.Ensure()
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
    local existing=category:FindFirstChild(TEMPLATE_ID)
    if existing and existing:IsA("Model") and existing.PrimaryPart
        and existing:GetAttribute("HoleDiameterU")==HOLE_U then
        return
    end
    local side=OUTER_U*Grid.Unit
    local aperture=HOLE_U*Grid.Unit
    local base=Instance.new("Part")
    base.Name="TemporaryBlock"
    base.Size=Vector3.new(side,side,side)
    base.Anchored=true
    base.CanCollide=true
    base.Material=Enum.Material.Metal
    local cutter=Instance.new("Part")
    cutter.Name="TemporaryBore"
    cutter.Shape=Enum.PartType.Cylinder
    -- Roblox cylinders have their axis along local X; the drilled block
    -- convention requires a world/local Y through-hole.
    cutter.Size=Vector3.new(side*1.4,aperture,aperture)
    cutter.CFrame=CFrame.Angles(0,0,math.pi/2)
    cutter.Anchored=true
    local ok,solids=pcall(function()
        return GeometryService:SubtractAsync(base,{cutter},{
            CollisionFidelity=Enum.CollisionFidelity.PreciseConvexDecomposition,
            SplitApart=false,
        })
    end)
    base:Destroy()
    cutter:Destroy()
    if not ok or type(solids)~="table" or #solids~=1
        or not solids[1]:IsA("BasePart") then
        if ok and type(solids)=="table" then
            for _,part in ipairs(solids) do part:Destroy() end
        end
        warn("[OPENWORKS] Could not generate the 1U drilled block with 0.98U bore: "
            ..tostring(if ok then "no single solid returned" else solids))
        -- Never add a solid cube that falsely claims to have a real hole.
        return
    end
    local geometry=solids[1]
    if (geometry.Size-Vector3.new(side,side,side)).Magnitude>0.003 then
        warn("[OPENWORKS] Compact drilled-block CSG bounds changed; template discarded")
        geometry:Destroy()
        return
    end
    if existing then existing:Destroy() end
    local model=Instance.new("Model")
    model.Name=TEMPLATE_ID
    model:SetAttribute("PrimitiveFamily","DrilledBlock")
    model:SetAttribute("ResizeMode","None")
    model:SetAttribute("HoleDiameterU",HOLE_U)
    model:SetAttribute("HoleDiameterStuds",aperture)
    model:SetAttribute("OpeningAxis","Y")
    model:SetAttribute("GeometryVersion",1)
    geometry.Name="Geometry"
    geometry.Anchored=true
    geometry.CanCollide=true
    geometry.CanQuery=true
    geometry.CanTouch=false
    geometry.Material=Enum.Material.Metal
    geometry.Color=Color3.fromRGB(78,83,91)
    if geometry:IsA("PartOperation") then geometry.UsePartColor=true end
    geometry.Parent=model
    model.PrimaryPart=geometry
    model.Parent=category
end

return CompactHole
