--!strict
-- OPENWORKS temporary unified UI language: Roblox Studio-like editor
-- panels, narrow borders, square corners, small labels, neutral palette.
-- This is only styling; it does not alter engine/physics interactions.
local Theme={}
Theme.Window=Color3.fromRGB(34,36,41)
Theme.Panel=Color3.fromRGB(44,47,53)
Theme.Raised=Color3.fromRGB(54,58,65)
Theme.Input=Color3.fromRGB(28,30,34)
Theme.Edge=Color3.fromRGB(78,82,89)
Theme.Text=Color3.fromRGB(231,233,236)
Theme.Muted=Color3.fromRGB(159,164,172)
Theme.Accent=Color3.fromRGB(0,162,255)
Theme.Active=Color3.fromRGB(48,85,113)
Theme.Error=Color3.fromRGB(234,132,123)
Theme.Success=Color3.fromRGB(111,204,143)
Theme.Radius=2

function Theme.Chrome(object,color)
    if not object or not object:IsA("GuiObject") then return object end
    if color then object.BackgroundColor3=color end
    object.BorderSizePixel=0
    local corner=object:FindFirstChildOfClass("UICorner")
    if not corner then
        corner=Instance.new("UICorner")
        corner.Parent=object
    end
    corner.CornerRadius=UDim.new(0,Theme.Radius)
    local stroke=object:FindFirstChildOfClass("UIStroke")
    if not stroke then
        stroke=Instance.new("UIStroke")
        stroke.Parent=object
    end
    stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    stroke.Color=Theme.Edge
    stroke.Transparency=0.35
    stroke.Thickness=1
    return object
end

function Theme.Button(object,selected)
    Theme.Chrome(object,if selected then Theme.Active else Theme.Raised)
    if object:IsA("TextButton") then
        object.TextColor3=Theme.Text
        object.Font=Enum.Font.GothamMedium
        object.TextSize=12
    end
    return object
end

function Theme.Label(object)
    if object:IsA("TextLabel") then
        object.Font=Enum.Font.GothamMedium
        object.TextSize=math.min(object.TextSize,13)
        object.TextColor3=Theme.Text
    end
    return object
end

-- Consistent restyling for both static and dynamically created GUI trees.
-- Construction, Numeric, Mate, Plot and Properties all share these rules.
function Theme.Apply(object)
    if object:IsA("UICorner") then
        object.CornerRadius=UDim.new(0,Theme.Radius)
        return
    end
    if object:IsA("UIStroke") then
        if object.Parent and object.Parent:IsA("GuiObject") then
            object.Color=Theme.Edge
            object.Transparency=0.35
            object.Thickness=1
        end
        return
    end
    if object:IsA("TextBox") then
        if object.BackgroundTransparency<0.92 then
            Theme.Chrome(object,Theme.Input)
        end
        object.Font=Enum.Font.Gotham
        object.TextColor3=Theme.Text
        object.TextSize=math.min(object.TextSize,13)
    elseif object:IsA("TextButton") then
        if object.BackgroundTransparency<0.92 and object.Text~="" then
            Theme.Button(object,false)
        end
    elseif object:IsA("Frame") then
        if object.BackgroundTransparency<0.92 then
            local name=string.lower(object.Name)
            local panel=string.find(name,"panel",1,true)
                or string.find(name,"catalog",1,true)
                or string.find(name,"status",1,true)
                or string.find(name,"menu",1,true)
                or string.find(name,"properties",1,true)
            Theme.Chrome(object,if panel then Theme.Window else Theme.Panel)
            object.BackgroundTransparency=math.min(object.BackgroundTransparency,0.04)
        end
    elseif object:IsA("TextLabel") then
        if not string.find(string.lower(object.Name),"crosshair",1,true) then
            object.Font=Enum.Font.GothamMedium
            object.TextSize=math.min(object.TextSize,13)
        end
    end
end

function Theme.Attach(root)
    for _,child in ipairs(root:GetDescendants()) do
        Theme.Apply(child)
    end
    return root.DescendantAdded:Connect(function(child)
        Theme.Apply(child)
    end)
end

return table.freeze(Theme)
