--!strict
-- Both seat roles share ONE resizable, flat plate primitive. Use Roblox's
-- native Seat so a normal Humanoid can sit without a prefab chair body.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Library={}
local ROLE_COLORS={
    Operator=Color3.fromRGB(245,144,48),
    Passenger=Color3.fromRGB(69,153,238),
}
Library.TemplateId="SeatPlate"
function Library.IsSeat(model)
    return model and model:GetAttribute("TemplateId")==Library.TemplateId
end
function Library.ValidRole(role)
    return role=="Operator" or role=="Passenger"
end
function Library.Apply(model,role)
    if not model or not model.PrimaryPart then return end
    local selected=if Library.ValidRole(role) then role else "Operator"
    model:SetAttribute("SeatRole",selected)
    for _,part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Color=ROLE_COLORS[selected]
            part.Material=Enum.Material.Metal
            part.MaterialVariant=""
            part.Reflectance=0.03
            if part:IsA("Seat") then
                part.Disabled=false
                part.CanTouch=true
            end
        end
    end
end
function Library.Ensure()
    local root=ReplicatedStorage:FindFirstChild("OPENWORKS_PrimitiveLibrary_DRAFT")
    if not root then
        root=Instance.new("Folder")
        root.Name="OPENWORKS_PrimitiveLibrary_DRAFT"
        root.Parent=ReplicatedStorage
    end
    local category=root:FindFirstChild("Seats")
    if not category then
        category=Instance.new("Folder")
        category.Name="Seats"
        category.Parent=root
    end
    local old=category:FindFirstChild(Library.TemplateId)
    if old and old:IsA("Model") then return old end
    if old then old:Destroy() end
    local model=Instance.new("Model")
    model.Name=Library.TemplateId
    model:SetAttribute("TemplateId",Library.TemplateId)
    model:SetAttribute("ResizeMode","XYZ_1U")
    model:SetAttribute("PrimitiveFamily","Seat")
    model:SetAttribute("CatalogGroup","Seats")
    model:SetAttribute("CatalogName","Seat plate · Operator / Passenger")
    local seat=Instance.new("Seat")
    seat.Name="Geometry"
    seat.Size=Vector3.new(2,0.25,2)
    seat.TopSurface=Enum.SurfaceType.Smooth
    seat.BottomSurface=Enum.SurfaceType.Smooth
    seat.LeftSurface=Enum.SurfaceType.Smooth
    seat.RightSurface=Enum.SurfaceType.Smooth
    seat.FrontSurface=Enum.SurfaceType.Smooth
    seat.BackSurface=Enum.SurfaceType.Smooth
    seat.Anchored=true
    seat.Parent=model
    model.PrimaryPart=seat
    Library.Apply(model,"Operator")
    model.Parent=category
    return model
end
return table.freeze(Library)
