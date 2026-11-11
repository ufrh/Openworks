--!strict
-- Native Roblox Studio-style material palette. M in Edit on any selected
-- primitive/component. Every choice changes collision physics as well as
-- appearance, and is saved/undoable on the server.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local Catalog=require(RS:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("MaterialCatalog"))
local Picker={}
Picker.__index=Picker
local function make(parent,class,props)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
function Picker.new(controller)
    return setmetatable({Owner=controller,Visible=false,Connections={}},Picker)
end
function Picker:Close()
    self.Visible=false
    if self.Gui then self.Gui.Enabled=false end
    player:SetAttribute("OPENWORKS_CursorUIOpen",false)
end
function Picker:Open()
    if self.Owner.Mode~="Edit" or self.Owner.Pending
        or self.Owner.ScaleMode or self.Owner.CatalogOpen then return end
    if not self.Owner.SelectedComponentId and not self.Owner.Selected then
        self.Owner:Message("Select a primitive or component to apply material")
        return
    end
    self.Visible=true
    self.Gui.Enabled=true
    player:SetAttribute("OPENWORKS_CursorUIOpen",true)
end
function Picker:Apply(id)
    local scope,selected
    if self.Owner.SelectedComponentId then
        scope,selected="Component",self.Owner.SelectedComponentId
    elseif self.Owner.Selected then
        scope,selected="Primitive",
            self.Owner.Selected:GetAttribute("InstanceId")
    end
    if not selected then self:Close() return end
    if self.Owner:Request({
        action="SetMaterial",scope=scope,id=selected,materialId=id,
    }) then
        self.Owner:Message("Material: "..Catalog.Get(id).Name..
            " • native grip / mass / restitution")
        self:Close()
    end
end
function Picker:Start()
    local gui=make(player:WaitForChild("PlayerGui"),"ScreenGui",{
        Name="OPENWORKS_Materials",ResetOnSpawn=false,
        IgnoreGuiInset=true,DisplayOrder=110,Enabled=false,
    })
    self.Gui=gui
    local panel=make(gui,"Frame",{
        Position=UDim2.new(1,-324,0,76),Size=UDim2.fromOffset(310,326),
        BackgroundColor3=Color3.fromRGB(30,40,51),BorderSizePixel=0,
    })
    make(panel,"UICorner",{CornerRadius=UDim.new(0,8)})
    make(panel,"TextLabel",{
        Position=UDim2.fromOffset(12,9),Size=UDim2.fromOffset(285,32),
        Text="MATERIALS  /  PHYSICAL PRESETS",
        BackgroundTransparency=1,
        TextColor3=Color3.fromRGB(231,241,249),
        Font=Enum.Font.GothamBold,TextSize=14,
    })
    for i,id in ipairs(Catalog.List()) do
        local mat=Catalog.Get(id)
        local button=make(panel,"TextButton",{
            Position=UDim2.fromOffset(12,43+(i-1)*42),
            Size=UDim2.fromOffset(286,36),
            BackgroundColor3=Color3.fromRGB(55,67,81),
            TextColor3=Color3.fromRGB(235,241,248),
            Text=mat.Name.."  •  ρ "..mat.Density.."  •  μ "..mat.Friction,
            Font=Enum.Font.Gotham,TextSize=12,
            TextXAlignment=Enum.TextXAlignment.Left,
        })
        make(button,"UICorner",{CornerRadius=UDim.new(0,4)})
        make(button,"UIPadding",{PaddingLeft=UDim.new(0,45)})
        make(button,"Frame",{
            Position=UDim2.fromOffset(-35,5),Size=UDim2.fromOffset(26,26),
            BackgroundColor3=mat.Color,BorderSizePixel=0,
        })
        table.insert(self.Connections,button.Activated:Connect(function()
            self:Apply(id)
        end))
    end
    table.insert(self.Connections,UIS.InputBegan:Connect(function(input)
        if self.Visible and input.KeyCode==Enum.KeyCode.Escape then
            self:Close()
        end
    end))
end
function Picker:Destroy()
    self:Close()
    for _,con in ipairs(self.Connections) do con:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
end
return Picker
