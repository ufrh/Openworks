--!strict
-- Stock OPENWORKS friction pulleys. Physical annular rims with REAL shaft holes.
-- Build places regular primitives; fitted shaft hubs are welded by SmartMate.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Library={}
local LIBRARY_NAME="OPENWORKS_PrimitiveLibrary_DRAFT"
local DIAMETERS={5,8,12} -- user-facing units, 1 U = 0.25 stud
local WIDTH=0.36
local BORE=0.215
local SEGMENTS=32

local function part(name,parent,sz,cf)
    local p=Instance.new("Part")
    p.Name=name
    p.Size=sz
    p.CFrame=cf
    p.Material=Enum.Material.Metal
    p.Color=Color3.fromRGB(89,102,116)
    p.Anchored=true
    p.CanTouch=false
    p.Parent=parent
    return p
end

function Library.Ensure()
    local library=ReplicatedStorage:FindFirstChild(LIBRARY_NAME)
    if not library then
        library=Instance.new("Folder")
        library.Name=LIBRARY_NAME
        library.Parent=ReplicatedStorage
    end
    local group=library:FindFirstChild("Transmission")
    if not group then
        group=Instance.new("Folder")
        group.Name="Transmission"
        group.Parent=library
    end
    for _,diameterU in ipairs(DIAMETERS) do
        local name="Pulley_"..tostring(diameterU).."U"
        local old=group:FindFirstChild(name)
        if old and old:GetAttribute("PulleyGeometryVersion")==1 then
            continue
        end
        local radius=diameterU*0.125
        local model=Instance.new("Model")
        model.Name=name
        model:SetAttribute("PrimitiveFamily","Pulley")
        model:SetAttribute("ResizeMode","None")
        model:SetAttribute("BeltRadiusStuds",radius)
        model:SetAttribute("PulleyWidthStuds",WIDTH)
        model:SetAttribute("BoreRadiusStuds",BORE)
        model:SetAttribute("AxialAxis","X")
        model:SetAttribute("PulleyGeometryVersion",1)

        local pivot=part("Geometry",model,
            Vector3.new(WIDTH,radius*2,radius*2),CFrame.identity)
        pivot.Shape=Enum.PartType.Cylinder
        pivot.Transparency=1
        pivot.CanCollide=false
        pivot.CanQuery=false
        pivot.CastShadow=false
        pivot:SetAttribute("GearPivotOnly",true)
        model.PrimaryPart=pivot

        local root=(radius+BORE)*0.5
        local thickness=radius-BORE
        for index=0,SEGMENTS-1 do
            local angle=(index+0.5)*2*math.pi/SEGMENTS
            local radial=Vector3.new(0,math.cos(angle),math.sin(angle))
            local tangent=Vector3.xAxis:Cross(radial)
            local location=radial*root
            -- Overlapping faceted rim leaves a true open bore. Unlike an
            -- ordinary cylinder, a shaft can pass through this annulus.
            part("Rim_"..index,model,
                Vector3.new(WIDTH,thickness*0.985,
                    2*math.pi*root/SEGMENTS*1.06),
                CFrame.fromMatrix(location,Vector3.xAxis,radial,tangent))
        end
        if old then old:Destroy() end
        model.Parent=group
    end
end
return Library
