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

return table.freeze(Theme)
