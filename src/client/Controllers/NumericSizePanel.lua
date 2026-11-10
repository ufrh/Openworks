--!strict
-- Precision dimension entry expressed exclusively in OPENWORKS units (U).
-- This is a small in-tool editor, not a separate modal CAD workflow.
local Grid = require(game:GetService("ReplicatedStorage")
    :WaitForChild("Openworks"):WaitForChild("Construction")
    :WaitForChild("GridMath"))
local Numeric={}
Numeric.__index=Numeric

local function make(class,parent,properties)
    local instance=Instance.new(class)
    for name,value in pairs(properties) do instance[name]=value end
    instance.Parent=parent
    return instance
end

function Numeric.new(gui)
    local self=setmetatable({Active=false,Fields={},Mode=nil,OnApply=nil},Numeric)
    local frame=make("Frame",gui,{
        Name="OPENWORKS_PrecisionSize",Visible=false,
        Size=UDim2.fromOffset(330,222),AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.62),BorderSizePixel=0,
        BackgroundColor3=Color3.fromRGB(23,31,40),ZIndex=110,
    })
    make("UICorner",frame,{CornerRadius=UDim.new(0,10)})
    make("UIStroke",frame,{Color=Color3.fromRGB(91,133,158),Transparency=0.5,
        Thickness=1})
    local function text(parent,caption,x,y,w,h,size,color)
        return make("TextLabel",parent,{
            Text=caption,BackgroundTransparency=1,BorderSizePixel=0,
            Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
            TextColor3=color or Color3.fromRGB(225,235,243),
            Font=Enum.Font.GothamMedium,TextSize=size or 12,
            TextXAlignment=Enum.TextXAlignment.Left,ZIndex=111,
        })
    end
    text(frame,"PRECISE DIMENSIONS",16,11,270,25,15)
    text(frame,"All values in U • exact to 0.01 U",16,38,300,20,11,
        Color3.fromRGB(146,180,199))
    for i,name in ipairs({"X","Y","Z"}) do
        text(frame,name,16,65+(i-1)*36,26,29,13)
        local field=make("TextBox",frame,{
            Name="Dimension_"..name,Position=UDim2.fromOffset(46,65+(i-1)*36),
            Size=UDim2.fromOffset(245,28),
            BackgroundColor3=Color3.fromRGB(37,49,60),
            BorderSizePixel=0,ClearTextOnFocus=false,
            Font=Enum.Font.GothamMedium,TextSize=14,
            TextColor3=Color3.fromRGB(229,241,249),
            TextXAlignment=Enum.TextXAlignment.Center,
            PlaceholderText="Size in U",ZIndex=112,
        })
        make("UICorner",field,{CornerRadius=UDim.new(0,5)})
        table.insert(self.Fields,field)
        field.FocusLost:Connect(function(enter)
            if enter and self.Active then self:Apply() end
        end)
    end
    local apply=make("TextButton",frame,{
        Name="Apply",Text="APPLY SIZE",Size=UDim2.fromOffset(170,30),
        Position=UDim2.fromOffset(16,179),BorderSizePixel=0,
        BackgroundColor3=Color3.fromRGB(78,147,174),
        TextColor3=Color3.fromRGB(244,250,254),
        Font=Enum.Font.GothamBold,TextSize=12,ZIndex=112,
    })
    make("UICorner",apply,{CornerRadius=UDim.new(0,5)})
    apply.Activated:Connect(function() self:Apply() end)
    local cancel=make("TextButton",frame,{
        Name="Cancel",Text="CANCEL",Size=UDim2.fromOffset(101,30),
        Position=UDim2.fromOffset(190,179),BorderSizePixel=0,
        BackgroundColor3=Color3.fromRGB(49,61,72),
        TextColor3=Color3.fromRGB(213,226,236),
        Font=Enum.Font.GothamMedium,TextSize=12,ZIndex=112,
    })
    make("UICorner",cancel,{CornerRadius=UDim.new(0,5)})
    cancel.Activated:Connect(function() self:Hide() end)
    self.Frame=frame
    self.Status=text(frame,"",16,159,296,17,10,Color3.fromRGB(217,153,141))
    return self
end

function Numeric:Show(size,mode,onApply)
    if typeof(size)~="Vector3" then return end
    self.Active=true
    self.Mode=mode
    self.OnApply=onApply
    self.Frame.Visible=true
    self.Status.Text=""
    for i,axis in ipairs({"X","Y","Z"}) do
        local field=self.Fields[i]
        field.Text=string.format("%.2f",size[axis]/Grid.Unit)
        local available=mode=="XYZ_1U" or i==1
            or (i==2 and mode=="LengthAndDiameter_1U")
        field.TextEditable=available
        field.BackgroundTransparency=if available then 0 else 0.68
        field.TextTransparency=if available then 0 else 0.45
    end
    -- Focus asynchronously to allow native first-person pointer unlock.
    task.defer(function()
        if self.Active then
            self.Fields[1]:CaptureFocus()
        end
    end)
end

function Numeric:Apply()
    if not self.Active then return end
    local v={}
    for i=1,3 do
        local n=tonumber(self.Fields[i].Text)
        if not n or n~=n or n==math.huge or n==-math.huge
            or n<0.25 or n>Grid.MaxUnits then
            self.Status.Text="Enter a value between 0.25 and 64 U"
            return
        end
        local ticks=n*100
        if math.abs(ticks-math.round(ticks))>1e-5 then
            self.Status.Text="Use at most two decimal places (0.01 U)"
            return
        end
        v[i]=math.round(ticks)/100
    end
    if self.Mode=="UniformDiameter_1U" then
        v[2],v[3]=v[1],v[1]
    elseif self.Mode=="LengthAndDiameter_1U" then
        v[3]=v[2]
    elseif self.Mode=="LengthOnly_1U" then
        -- These are read-only; still send values that were displayed.
        v[2],v[3]=tonumber(self.Fields[2].Text),
            tonumber(self.Fields[3].Text)
    end
    local size=Vector3.new(v[1],v[2],v[3])*Grid.Unit
    if self.OnApply then
        local ok,message=self.OnApply(size)
        if ok then self:Hide()
        else self.Status.Text=tostring(message or "Dimension was rejected") end
    end
end

function Numeric:Hide()
    self.Active=false
    self.Frame.Visible=false
    self.OnApply=nil
    for _,field in ipairs(self.Fields) do
        if field:IsFocused() then field:ReleaseFocus() end
    end
end

function Numeric:Destroy()
    self:Hide()
    self.Frame:Destroy()
end

return Numeric
