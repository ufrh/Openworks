--!strict
-- Mouse-first relationship choice, shown over the build world after a valid
-- shaft/hole or gear/shaft alignment. Number keys NEVER select relationships:
-- they belong to the native Tool hotbar and previously caused collisions.
local ContextActionService=game:GetService("ContextActionService")
local StarterGui=game:GetService("StarterGui")
local UserInputService=game:GetService("UserInputService")
local Players=game:GetService("Players")

local Mate={}
Mate.__index=Mate

-- Do not silently create a rigid weld for a hole/shaft fit.
local TYPES={"Cylindrical","Slider","Bearing","FreeFit"}
local HUB_TYPES={"Rotation","Rigid"}
local BORE_LABELS={
    "ROTATE + SLIDE   •   Free axial and rotary motion",
    "SLIDE ONLY   •   Guided linear movement",
    "ROTATE ONLY   •   Bearing, no axial movement",
    "FIT ONLY   •   Placement without a physical joint",
}
local HUB_LABELS={
    "ROTATION   •   Gear spins freely around shaft",
    "RIGID   •   Gear is welded to shaft",
}
-- Keys are swallowed while the modal is open, NOT interpreted as options.
-- Disabling the CoreGui alone does not reliably block the numeric Tool bar.
local BLOCKED_KEYS={
    Enum.KeyCode.Zero,Enum.KeyCode.One,Enum.KeyCode.Two,
    Enum.KeyCode.Three,Enum.KeyCode.Four,Enum.KeyCode.Five,
    Enum.KeyCode.Six,Enum.KeyCode.Seven,Enum.KeyCode.Eight,
    Enum.KeyCode.Nine,Enum.KeyCode.KeypadZero,Enum.KeyCode.KeypadOne,
    Enum.KeyCode.KeypadTwo,Enum.KeyCode.KeypadThree,
    Enum.KeyCode.KeypadFour,Enum.KeyCode.KeypadFive,
    Enum.KeyCode.KeypadSix,Enum.KeyCode.KeypadSeven,
    Enum.KeyCode.KeypadEight,Enum.KeyCode.KeypadNine,
    Enum.KeyCode.Return,Enum.KeyCode.KeypadEnter,
    Enum.KeyCode.Escape,
}

local function create(className,parent,properties)
    local object=Instance.new(className)
    for key,value in pairs(properties) do object[key]=value end
    object.Parent=parent
    return object
end

local function corner(parent,radius)
    create("UICorner",parent,{CornerRadius=UDim.new(0,radius)})
end

local function text(parent,value,position,size,fontSize,muted)
    return create("TextLabel",parent,{
        BackgroundTransparency=1,
        Text=value,
        Position=position,
        Size=size,
        TextColor3=if muted then Color3.fromRGB(170,192,205)
            else Color3.fromRGB(232,240,245),
        Font=Enum.Font.GothamMedium,
        TextSize=fontSize,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        TextWrapped=true,
        ZIndex=31,
    })
end

function Mate.new(_ownerGui)
    local self=setmetatable({
        Active=false,Callback=nil,Types=TYPES,Buttons={},
        BackpackWasVisible=nil,
    },Mate)

    -- Separate, higher DisplayOrder ScreenGui: ordinary HUD surfaces or
    -- crosshairs cannot steal clicks from this dialog.
    local gui=create("ScreenGui",Players.LocalPlayer:WaitForChild("PlayerGui"),{
        Name="OPENWORKS_RelationshipPicker",
        Enabled=false,
        ResetOnSpawn=false,
        IgnoreGuiInset=true,
        DisplayOrder=85,
        ZIndexBehavior=Enum.ZIndexBehavior.Global,
    })
    -- Modal GuiButton releases Roblox's first-person cursor and consumes
    -- outside-world clicks. It sits BEHIND the actual option buttons.
    local backdrop=create("TextButton",gui,{
        Name="ModalPointerSurface",
        Size=UDim2.fromScale(1,1),
        Position=UDim2.fromOffset(0,0),
        BackgroundColor3=Color3.fromRGB(8,14,21),
        BackgroundTransparency=0.46,
        BorderSizePixel=0,
        Text="",
        AutoButtonColor=false,
        Active=true,
        Modal=true,
        ZIndex=20,
    })

    local frame=create("Frame",gui,{
        Name="RelationshipOptions",
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(372,368),
        BackgroundColor3=Color3.fromRGB(24,32,41),
        BorderSizePixel=0,
        Active=true,
        ZIndex=30,
    })
    corner(frame,10)
    create("UIStroke",frame,{
        Color=Color3.fromRGB(105,160,186),
        Transparency=0.4,Thickness=1,
    })

    self.Heading=text(frame,"CHOOSE RELATIONSHIP",
        UDim2.fromOffset(18,14),UDim2.fromOffset(338,26),17,false)
    self.Detail=text(frame,"Choose a physical connection.",
        UDim2.fromOffset(18,43),UDim2.fromOffset(338,28),12,true)

    for i=1,4 do
        local button=create("TextButton",frame,{
            Name="RelationshipChoice_"..tostring(i),
            Position=UDim2.fromOffset(16,78+(i-1)*51),
            Size=UDim2.fromOffset(340,45),
            BackgroundColor3=if i==1 then Color3.fromRGB(63,107,129)
                else Color3.fromRGB(42,55,67),
            TextColor3=Color3.fromRGB(229,241,247),
            TextWrapped=true,
            TextSize=12,
            TextXAlignment=Enum.TextXAlignment.Left,
            Font=Enum.Font.GothamMedium,
            Text="  "..BORE_LABELS[i],
            AutoButtonColor=true,
            Active=true,
            Selectable=true,
            BorderSizePixel=0,
            ZIndex=32,
        })
        corner(button,6)
        button.Activated:Connect(function()
            self:Choose(i)
        end)
        table.insert(self.Buttons,button)
    end

    self.Adjust=create("TextButton",frame,{
        Name="AdjustBeforeChoosing",
        Position=UDim2.fromOffset(16,284),
        Size=UDim2.fromOffset(340,32),
        BackgroundColor3=Color3.fromRGB(45,68,81),
        TextColor3=Color3.fromRGB(221,237,246),
        Font=Enum.Font.GothamMedium,TextSize=12,
        Text="ADJUST DEPTH / ROLL FIRST",
        AutoButtonColor=true,Active=true,BorderSizePixel=0,ZIndex=32,
    })
    corner(self.Adjust,6)
    self.Adjust.Activated:Connect(function()
        self:ChooseAdjust()
    end)

    self.CancelButton=create("TextButton",frame,{
        Name="CancelRelationshipChoice",
        Position=UDim2.fromOffset(16,326),
        Size=UDim2.fromOffset(340,28),
        BackgroundTransparency=1,
        TextColor3=Color3.fromRGB(183,203,214),
        Font=Enum.Font.GothamMedium,TextSize=12,
        Text="CANCEL  •  ESC",
        AutoButtonColor=true,Active=true,BorderSizePixel=0,ZIndex=32,
    })
    self.CancelButton.Activated:Connect(function() self:Cancel() end)
    backdrop.Activated:Connect(function() self:Cancel() end)

    self.Gui=gui
    self.Frame=frame
    return self
end

function Mate:Show(callback,fitCount,gearMount)
    if self.Active then return end
    fitCount=math.max(1,math.floor(tonumber(fitCount) or 1))
    self.Types=if gearMount then HUB_TYPES else TYPES
    self.Heading.Text=if gearMount then "GEAR / SHAFT RELATIONSHIP"
        elseif fitCount>1 then
            "SHAFT / "..tostring(fitCount).." ALIGNED HOLES"
        else "SHAFT / HOLE RELATIONSHIP"
    self.Detail.Text=if gearMount then
        "Choose one physical gear mount."
        elseif fitCount>1 then
            "Choose motion for the aligned guide pattern."
        else "Choose motion after the hole and shaft align."

    local optionCount=if gearMount then 2 else 4
    for i,button in ipairs(self.Buttons) do
        button.Visible=i<=optionCount
        button.Text="  "..(if gearMount then HUB_LABELS[i] or ""
            else BORE_LABELS[i])
    end
    self.Adjust.Visible=not gearMount
    self.Adjust.Position=UDim2.fromOffset(16,if gearMount then 180 else 284)
    self.CancelButton.Position=UDim2.fromOffset(16,
        if gearMount then 194 else 326)
    self.Frame.Size=UDim2.fromOffset(372,if gearMount then 236 else 368)

    self.Active=true
    self.Callback=callback
    -- Suppress the native hotbar while choosing. Even when it is restored,
    -- the relationship buttons never use number-key selection.
    local ok,previous=pcall(function()
        return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
    end)
    self.BackpackWasVisible=if ok then previous else nil
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,false)
    end)
    ContextActionService:BindActionAtPriority(
        "OPENWORKS_ShaftChoice",function(_,state,input)
            if state==Enum.UserInputState.Begin
                and input.KeyCode==Enum.KeyCode.Escape then
                self:Cancel()
            end
            return Enum.ContextActionResult.Sink
        end,false,Enum.ContextActionPriority.High.Value+1000,
        table.unpack(BLOCKED_KEYS)
    )
    self.Gui.Enabled=true
    UserInputService.MouseBehavior=Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled=true
end

function Mate:Choose(index)
    if not self.Active then return end
    local value=self.Types[index]
    if not value then return end
    local callback=self.Callback
    self:Hide()
    if callback then callback(value) end
end

function Mate:ChooseAdjust()
    if not self.Active or self.Types==HUB_TYPES then return end
    local callback=self.Callback
    self:Hide()
    if callback then callback("__Adjust") end
end

function Mate:Cancel()
    if not self.Active then return end
    local callback=self.Callback
    self:Hide()
    if callback then callback(nil) end
end

function Mate:Hide()
    if not self.Active then return end
    self.Active=false
    self.Callback=nil
    self.Gui.Enabled=false
    ContextActionService:UnbindAction("OPENWORKS_ShaftChoice")
    if self.BackpackWasVisible~=nil then
        local visible=self.BackpackWasVisible
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,visible)
        end)
    end
    self.BackpackWasVisible=nil
end

function Mate:Destroy()
    self:Hide()
    self.Gui:Destroy()
end

return Mate
