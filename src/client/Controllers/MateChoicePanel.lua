--!strict
-- A one-keystroke decision AFTER a shaft is snapped to a hole.
-- Does not require selecting a housing or shaft in separate tool modes.
local ContextActionService=game:GetService("ContextActionService")
local StarterGui=game:GetService("StarterGui")
local Mate={}
Mate.__index=Mate
-- Kinematic joints are the default. Rigid bonds require the Weld tool.
-- A FreeFit places geometry only; it adds no invisible solver constraint.
local TYPES={"Cylindrical","Slider","Bearing","FreeFit"}
local HUB_TYPES={"Rotation","Rigid"}
local HUB_LABELS={
    "Rotation only   •   gear spins freely on shaft",
    "Rigid   •   gear and shaft rotate together",
}
local KEYS={Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,
    Enum.KeyCode.Four,Enum.KeyCode.KeypadOne,Enum.KeyCode.KeypadTwo,
    Enum.KeyCode.KeypadThree,Enum.KeyCode.KeypadFour}

local function instance(class,parent,properties)
    local object=Instance.new(class)
    for key,value in pairs(properties) do object[key]=value end
    object.Parent=parent
    return object
end

function Mate.new(gui)
    local self=setmetatable({Active=false,Callback=nil,Types=TYPES,Buttons={}},Mate)
    local frame=instance("Frame",gui,{
        Name="OPENWORKS_ShaftConnectionChoice",
        Size=UDim2.fromOffset(314,268),
        Position=UDim2.fromScale(0.5,0.56),AnchorPoint=Vector2.new(0.5,0.5),
        BackgroundColor3=Color3.fromRGB(24,32,41),
        BorderSizePixel=0,Visible=false,ZIndex=120,
    })
    instance("UICorner",frame,{CornerRadius=UDim.new(0,10)})
    instance("UIStroke",frame,{Color=Color3.fromRGB(105,160,186),
        Transparency=0.42,Thickness=1})
    local function label(value,y,h,size,color)
        return instance("TextLabel",frame,{
            Text=value,BackgroundTransparency=1,BorderSizePixel=0,
            Position=UDim2.fromOffset(16,y),Size=UDim2.fromOffset(282,h),
            Font=Enum.Font.GothamMedium,TextSize=size or 12,
            TextColor3=color or Color3.fromRGB(230,239,245),
            TextXAlignment=Enum.TextXAlignment.Left,ZIndex=121,
        })
    end
    local heading=label("SHAFT / HOUSING",12,28,16)
    local detail=label("Choose the allowed motion (no automatic welds)",42,19,12,
        Color3.fromRGB(167,194,208))
    local subtitles={
        "Rotate + slide   •   DEFAULT",
        "Slide only   •   guided carriage",
        "Rotate only   •   bearing",
        "Fit only   •   physical contact, no joint",
    }
    for i,k in ipairs(TYPES) do
        local button=instance("TextButton",frame,{
            Name="Joint_"..k,
            Position=UDim2.fromOffset(14,69+(i-1)*40),
            Size=UDim2.fromOffset(286,35),
            BackgroundColor3=if i==1 then Color3.fromRGB(67,110,130)
                else Color3.fromRGB(42,55,67),
            TextColor3=Color3.fromRGB(229,241,247),
            BorderSizePixel=0,Font=Enum.Font.GothamMedium,TextSize=12,
            TextXAlignment=Enum.TextXAlignment.Left,
            Text="   "..i.."   "..subtitles[i],ZIndex=121,
        })
        instance("UICorner",button,{CornerRadius=UDim.new(0,5)})
        table.insert(self.Buttons,button)
        button.Activated:Connect(function()
            self:Choose(i)
        end)
    end
    self.Footnote=label("1–4 / Enter (default)   •   Esc cancels",238,18,11,
        Color3.fromRGB(158,184,196))
    self.Frame=frame
    self.Heading=heading
    self.Detail=detail
    return self
end

function Mate:Show(callback,fitCount,gearMount)
    if self.Active then return end
    fitCount=math.max(1,math.floor(tonumber(fitCount) or 1))
    self.Types=if gearMount then HUB_TYPES else TYPES
    self.Heading.Text=if gearMount then "GEAR / SHAFT"
        elseif fitCount>1
        then "MULTI-POINT FIT  /  "..tostring(fitCount).." GUIDES"
        else "SHAFT / HOUSING"
    self.Detail.Text=if gearMount
        then "Choose how the gear attaches to the shaft"
        elseif fitCount>1
        then "Slide only recommended for parallel guide rods"
        else "Choose motion; no automatic welding"
    self.Frame.Size=UDim2.fromOffset(314,if gearMount then 182 else 268)
    self.Footnote.Position=UDim2.fromOffset(16,if gearMount then 150 else 238)
    self.Footnote.Text=if gearMount
        then "1–2 / Enter (Rotation)   •   Esc cancels"
        else "1–4 / Enter (default)   •   Esc cancels"
    for i,button in ipairs(self.Buttons) do
        button.Visible=not gearMount or i<=2
        button.Text=if gearMount and HUB_LABELS[i]
            then "   "..i.."   "..HUB_LABELS[i]
            else "   "..i.."   "..subtitles[i]
    end
    self.Active=true
    self.Callback=callback
    self.Frame.Visible=true
    -- Native Roblox hotbar binds these same keys; suspend the bar for
    -- one modal choice, then restore exactly its previous visibility.
    local ok,previous=pcall(function()
        return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
    end)
    self.BackpackWasVisible=if ok then previous else nil
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,false)
    end)
    ContextActionService:BindActionAtPriority(
        "OPENWORKS_ShaftChoice",function(_,state,key)
            if state~=Enum.UserInputState.Begin then
                return Enum.ContextActionResult.Sink
            end
            if key.KeyCode==Enum.KeyCode.Return
                or key.KeyCode==Enum.KeyCode.KeypadEnter then
                self:Choose(1)
                return Enum.ContextActionResult.Sink
            end
            if key.KeyCode==Enum.KeyCode.Escape then
                self:Cancel()
                return Enum.ContextActionResult.Sink
            end
            for index,code in ipairs(KEYS) do
                if key.KeyCode==code then
                    self:Choose((index-1)%4+1)
                    return Enum.ContextActionResult.Sink
                end
            end
            return Enum.ContextActionResult.Sink
        end,false,Enum.ContextActionPriority.High.Value+1000,
        Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,
        Enum.KeyCode.Four,Enum.KeyCode.KeypadOne,
        Enum.KeyCode.KeypadTwo,Enum.KeyCode.KeypadThree,
        Enum.KeyCode.KeypadFour,Enum.KeyCode.Escape,
        Enum.KeyCode.Return,Enum.KeyCode.KeypadEnter
    )
end

function Mate:Choose(index)
    if not self.Active or not self.Types[index] then return end
    local callback=self.Callback
    -- Release the keyboard lock before issuing the request; the parent
    -- can show a validation error without leaving the hotbar disabled.
    self:Hide()
    if callback then callback(self.Types[index]) end
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
    self.Frame.Visible=false
    ContextActionService:UnbindAction("OPENWORKS_ShaftChoice")
    if self.BackpackWasVisible~=nil then
        local original=self.BackpackWasVisible
        pcall(function()
            StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,original)
        end)
    end
    self.BackpackWasVisible=nil
end

function Mate:Destroy()
    self:Hide()
    self.Frame:Destroy()
end

return Mate
