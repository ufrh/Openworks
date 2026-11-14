--!strict
-- True through-bore drilled stock, including the same 0.25-U minimum
-- exterior as resizable solid blocks. Fixed CSG stock is generated ONCE
-- at server initialization; construction/drag never recompiles geometry.
-- Preserve the legacy 1U ID so saved plots keep their original geometry.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local GeometryService=game:GetService("GeometryService")
local Grid=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))

local CompactHole={}
local LIBRARY="OPENWORKS_PrimitiveLibrary_DRAFT"
local PROFILES={
    -- Minimum structural block; fine-shaft diameters can fit the 0.16U bore.
    {id="DrilledBlock_025U_D016",outerU=0.25,holeU=0.16},
    -- Next practical stock size for ordinary 0.25U diameter shafts.
    {id="DrilledBlock_050U_D030",outerU=0.50,holeU=0.30},
    -- Existing precision hole remains untouched for saved constructions.
    {id="DrilledBlock_1U_D098",outerU=1,holeU=0.98},
}

local function ensureProfile(category,spec)
    local existing=category:FindFirstChild(spec.id)
    local side=spec.outerU*Grid.Unit
    local aperture=spec.holeU*Grid.Unit
    if existing and existing:IsA("Model") and existing.PrimaryPart
        and existing:GetAttribute("HoleDiameterU")==spec.holeU
        and (existing.PrimaryPart.Size-Vector3.new(side,side,side)).Magnitude<0.003 then
        return
    end
    local base=Instance.new("Part")
    base.Name="TemporaryBlock"
    base.Size=Vector3.new(side,side,side)
    base.Anchored=true
    base.CanCollide=true
    base.Material=Enum.Material.Metal
    local cutter=Instance.new("Part")
    cutter.Name="TemporaryBore"
    cutter.Shape=Enum.PartType.Cylinder
    -- Roblox cylinders run along local X; drilled blocks bore through Y.
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
        warn("[OPENWORKS] Drilled stock CSG failed for "..spec.id..": "
            ..tostring(if ok then "no single solid returned" else solids))
        -- Never misrepresent a solid cube as a drilled through-hole.
        return
    end
    local geometry=solids[1]
    if (geometry.Size-Vector3.new(side,side,side)).Magnitude>0.003 then
        warn("[OPENWORKS] Invalid drilled bounds for "..spec.id)
        geometry:Destroy()
        return
    end
    local model=Instance.new("Model")
    model.Name=spec.id
    model:SetAttribute("PrimitiveFamily","DrilledBlock")
    model:SetAttribute("ResizeMode","None")
    model:SetAttribute("HoleDiameterU",spec.holeU)
    model:SetAttribute("HoleDiameterStuds",aperture)
    model:SetAttribute("OpeningAxis","Y")
    model:SetAttribute("GeometryVersion",2)
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
    if existing then existing:Destroy() end
    model.Parent=category
end

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
    for _,profile in ipairs(PROFILES) do
        ensureProfile(category,profile)
    end
end

return CompactHole
