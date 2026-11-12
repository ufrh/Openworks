--!strict
-- Paint and engineering material are independent. Material changes affect
-- physics; finish and HEX only affect BasePart appearance.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local shared=RS:WaitForChild("Openworks"):WaitForChild("Construction")
local Materials=require(shared:WaitForChild("MaterialCatalog"))
local Paint=require(shared:WaitForChild("PaintCatalog"))
local Picker={}
Picker.__index=Picker
local BG=Color3.fromRGB(30,40,51)
local ROW=Color3.fromRGB(53,65,80)
local SELECTED=Color3.fromRGB(40,116,136)
local WHITE=Color3.fromRGB(237,244,249)
local MUTED=Color3.fromRGB(173,193,209)
local function make(parent,class,props)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
local function round(parent,r)
    make(parent,"UICorner",{CornerRadius=UDim.new(0,r or 6)})
end
local function button(parent,text,x,y,w,h,action)
    local b=make(parent,"TextButton",{
        Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundColor3=ROW,BorderSizePixel=0,
        Text=text,TextColor3=WHITE,TextSize=12,
        TextWrapped=true,Font=Enum.Font.GothamMedium,
        AutoButtonColor=true,
    })
    round(b,5)
    if action then b.Activated:Connect(action) end
    return b
end
local function label(parent,text,x,y,w,h,size)
    return make(parent,"TextLabel",{
        BackgroundTransparency=1,Position=UDim2.fromOffset(x,y),
        Size=UDim2.fromOffset(w,h),Text=text,TextSize=size or 12,
        TextColor3=MUTED,Font=Enum.Font.GothamMedium,
        TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true,
    })
end
function Picker.new(owner)
    return setmetatable({
        Owner=owner,Visible=false,Connections={},Tab="Paint",
        FinishId="Gloss",ColorHex="D61F2C",FinishButtons={},
    },Picker)
end
function Picker:Target()
    if self.Owner.SelectedComponentId then
        return "Component",self.Owner.SelectedComponentId,self.Owner.Selected
    end
    local selected=self.Owner.Selected
    if selected then
        return "Primitive",selected:GetAttribute("InstanceId"),selected
    end
    return nil,nil,nil
end
function Picker:Close()
    self.Visible=false
    if self.Gui then self.Gui.Enabled=false end
    player:SetAttribute("OPENWORKS_CursorUIOpen",false)
end
function Picker:Open()
    if self.Owner.Mode~="Edit" or self.Owner.Pending
        or self.Owner.ScaleMode or self.Owner.CatalogOpen then return end
    local _,id,selected=self:Target()
    if not id then
        self.Owner:Message("Select a primitive or component to paint")
        return
    end
    self.ColorHex=Paint.NormalizeHex(selected
        and selected:GetAttribute("PaintColorHex")) or "D61F2C"
    local previous=selected and selected:GetAttribute("PaintFinish")
    self.FinishId=if previous and previous~="Factory"
        and Paint.IsValidFinish(previous) then previous else "Gloss"
    self.HexBox.Text="#"..self.ColorHex
    self:RefreshAppearance()
    self:SetTab("Paint")
    self.Visible=true
    self.Gui.Enabled=true
    player:SetAttribute("OPENWORKS_CursorUIOpen",true)
end
function Picker:ApplyMaterial(materialId)
    local scope,id=self:Target()
    if not id then self:Close() return end
    if self.Owner:Request({
        action="SetMaterial",scope=scope,id=id,materialId=materialId,
    }) then
        self.Owner:Message("Material: "..Materials.Get(materialId).Name
            .." • physical density/grip unchanged by paint")
        self:Close()
    end
end
function Picker:RefreshAppearance()
    if not self.HexBox then return end
    local color=Paint.ToColor(self.ColorHex)
    if self.Preview then self.Preview.BackgroundColor3=color or BG end
    for finishId,control in pairs(self.FinishButtons) do
        control.BackgroundColor3=if finishId==self.FinishId
            then SELECTED else ROW
    end
    if self.PreviewCaption then
        local option=Paint.Get(self.FinishId)
        self.PreviewCaption.Text=if option then option.Name.."  •  #"
            ..self.ColorHex else "Choose a finish"
    end
end
function Picker:SetTab(tab)
    self.Tab=tab
    self.PaintPage.Visible=tab=="Paint"
    self.MaterialPage.Visible=tab=="Material"
    self.PaintTab.BackgroundColor3=if tab=="Paint" then SELECTED else ROW
    self.MaterialTab.BackgroundColor3=if tab=="Material" then SELECTED else ROW
end
function Picker:ApplyPaint(reset)
    local scope,id=self:Target()
    if not id then self:Close() return end
    local hex=if reset then nil else Paint.NormalizeHex(self.HexBox.Text)
    if not reset and not hex then
        self.Owner:Message("Paint color must be six-digit HEX (#RRGGBB)")
        self.HexBox.Text="#"..self.ColorHex
        return
    end
    local finish=if reset then "Factory" else self.FinishId
    if self.Owner:Request({
        action="SetPaint",scope=scope,id=id,paintFinish=finish,
        paintColorHex=hex,
    }) then
        self.Owner:Message(if reset then "Paint removed • original finish"
            else "Painted "..scope:lower().." • "..Paint.Get(finish).Name
                .." • #"..hex)
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
        Position=UDim2.new(1,-392,0,62),
        Size=UDim2.fromOffset(378,552),
        BackgroundColor3=BG,BorderSizePixel=0,
    })
    round(panel,9)
    label(panel,"PAINT  /  MATERIAL STUDIO",15,12,320,25,15).TextColor3=WHITE
    button(panel,"×",338,9,27,26,function() self:Close() end)
    self.PaintTab=button(panel,"PAINT & FINISH",13,46,171,34,
        function() self:SetTab("Paint") end)
    self.MaterialTab=button(panel,"PHYSICAL MATERIAL",193,46,171,34,
        function() self:SetTab("Material") end)
    local page=make(panel,"Frame",{
        Position=UDim2.fromOffset(12,90),
        Size=UDim2.fromOffset(354,449),BackgroundTransparency=1,
    })
    self.PaintPage=make(page,"Frame",{
        Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
    })
    self.MaterialPage=make(page,"Frame",{
        Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
        Visible=false,
    })
    label(self.PaintPage,"COLOR  /  SWATCHES",2,0,350,22,12)
    local swatches=Paint.Palette()
    for i,swatch in ipairs(swatches) do
        local column=(i-1)%6
        local row=math.floor((i-1)/6)
        local b=button(self.PaintPage,"",3+column*59,27+row*43,51,36,
            function()
                self.ColorHex=swatch.Hex
                self.HexBox.Text="#"..swatch.Hex
                self:RefreshAppearance()
            end)
        b.BackgroundColor3=Paint.ToColor(swatch.Hex)
        b.AutoButtonColor=false
        local stroke=make(b,"UIStroke",{
            Color=Color3.fromRGB(110,132,148),Thickness=1,
        })
        stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    end
    label(self.PaintPage,"CUSTOM HEX COLOR",2,159,166,23)
    self.HexBox=make(self.PaintPage,"TextBox",{
        Position=UDim2.fromOffset(158,159),
        Size=UDim2.fromOffset(187,30),
        BackgroundColor3=ROW,BorderSizePixel=0,
        Text="#D61F2C",TextColor3=WHITE,TextSize=14,
        Font=Enum.Font.Gotham,ClearTextOnFocus=false,
    })
    round(self.HexBox,5)
    table.insert(self.Connections,self.HexBox.FocusLost:Connect(function()
        local hex=Paint.NormalizeHex(self.HexBox.Text)
        if hex then
            self.ColorHex=hex
            self.HexBox.Text="#"..hex
            self:RefreshAppearance()
        end
    end))
    label(self.PaintPage,"SURFACE FINISH",2,198,347,22)
    for i,id in ipairs(Paint.List()) do
        local row=math.floor((i-1)/2)
        local col=(i-1)%2
        local finish=Paint.Get(id)
        local b=button(self.PaintPage,finish.Name,3+col*177,223+row*38,
            170,33,function()
                self.FinishId=id
                self:RefreshAppearance()
            end)
        self.FinishButtons[id]=b
    end
    self.Preview=make(self.PaintPage,"Frame",{
        Position=UDim2.fromOffset(4,379),
        Size=UDim2.fromOffset(31,27),BackgroundColor3=WHITE,
        BorderSizePixel=0,
    })
    round(self.Preview,5)
    self.PreviewCaption=label(self.PaintPage,"",44,378,300,28,12)
    button(self.PaintPage,"APPLY PAINT",3,412,221,34,
        function() self:ApplyPaint(false) end).BackgroundColor3=SELECTED
    button(self.PaintPage,"RESET",232,412,117,34,
        function() self:ApplyPaint(true) end)
    label(self.MaterialPage,"BASE MATERIAL  /  PHYSICAL",2,0,350,24,12)
    label(self.MaterialPage,
        "Changes mass, grip and restitution; paint stays intact.",
        2,26,346,38,12)
    for i,id in ipairs(Materials.List()) do
        local material=Materials.Get(id)
        local b=button(self.MaterialPage,
            material.Name.."  •  density "..material.Density
                .."  •  grip "..material.Friction,
            3,78+(i-1)*49,347,42,
            function() self:ApplyMaterial(id) end)
        b.TextXAlignment=Enum.TextXAlignment.Left
        make(b,"UIPadding",{PaddingLeft=UDim.new(0,53)})
        make(b,"Frame",{
            Position=UDim2.fromOffset(-42,8),
            Size=UDim2.fromOffset(26,26),
            BackgroundColor3=material.Color,BorderSizePixel=0,
        })
    end
    label(self.MaterialPage,"Physical selection is independent from paint.",
        3,395,349,39,12)
    table.insert(self.Connections,UIS.InputBegan:Connect(function(input)
        if self.Visible and input.KeyCode==Enum.KeyCode.Return
            and not UIS:GetFocusedTextBox() then
            self:Close()
        end
    end))
end
function Picker:Destroy()
    self:Close()
    for _,conn in ipairs(self.Connections) do conn:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
end
return Picker
