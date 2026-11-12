--!strict
-- OPENWORKS UI v2 left-side controls: one compact subtool column and
-- a separate contextual keybind panel. It never creates geometry, joints,
-- or privileged remote requests. Switch buttons call ToolController only.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")

local player=Players.LocalPlayer
local Theme=require(script.Parent:WaitForChild("StudioTheme"))
local Help=require(script.Parent:WaitForChild("ToolHelpDefinitions"))
local definitions=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("SubtoolDefinitions"))

local Palette={}
Palette.__index=Palette
local PANEL_W=222
local LEFT=14
local TOP=63
local ROW_H=32
local TITLE_H=49

local TOOL_NAMES={
    Build="BUILD",
    Mechanics="MECHANICS",
    AssemblySimulation="ASSEMBLY / SIM",
}
local SUBTOOL_NAMES={
    Place="Place",Edit="Edit",Resize="Resize",Paint="Paint",
    Connect="Connect",Configure="Configure",
    AssemblyEditor="Assembly Editor",Simulation="Simulation",
}

local function make(class,parent,props)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent
    return obj
end

local function clearRows(parent)
    for _,child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
end

local function label(parent,content,x,y,width,height,color,size,strong)
    return make("TextLabel",parent,{
        Text=content,BackgroundTransparency=1,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        TextColor3=color or Theme.Text,TextSize=size or 12,
        Font=if strong then Enum.Font.GothamBold else Enum.Font.GothamMedium,
        Position=UDim2.fromOffset(x,y),
        Size=UDim2.new(width or 1,if type(width)=="number" then -x else 0,
            0,height or 25),
        ZIndex=5,
    })
end

local function keycap(parent,key,width)
    local item=make("TextLabel",parent,{
        Name="Keycap",Text=key,
        TextColor3=Theme.Text,
        TextSize=11,Font=Enum.Font.GothamBold,
        BackgroundColor3=Theme.Input,
        BorderSizePixel=0,
        TextXAlignment=Enum.TextXAlignment.Center,
        ZIndex=6,
        Size=UDim2.fromOffset(width or 52,22),
    })
    Theme.Chrome(item,Theme.Input)
    return item
end

function Palette.new(tools,build,mechanics,assembly)
    return setmetatable({
        Tools=tools,Build=build,Mechanics=mechanics,Assembly=assembly,
        Connections={},Started=false,Signature="",RefreshElapsed=0,
        CachedPrimary=nil,PrimaryButtons={},
    },Palette)
end

function Palette:CreateUI()
    local gui=make("ScreenGui",player:WaitForChild("PlayerGui"),{
        Name="OPENWORKS_ToolKeybinds",
        ResetOnSpawn=false,IgnoreGuiInset=true,
        DisplayOrder=89,
        ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    })
    self.Gui=gui
    self.SubtoolsPanel=make("Frame",gui,{
        Name="SubtoolsColumn",BackgroundColor3=Theme.Window,
        BorderSizePixel=0,Visible=false,
        Position=UDim2.fromOffset(LEFT,TOP),
        Size=UDim2.fromOffset(PANEL_W,TITLE_H),
    })
    Theme.Chrome(self.SubtoolsPanel,Theme.Window)
    label(self.SubtoolsPanel,"SUBTOOLS",10,7,1,17,Theme.Muted,10,true)
    self.PrimaryLabel=label(self.SubtoolsPanel,"",10,25,1,20,
        Theme.Text,12,true)
    self.SubtoolsList=make("Frame",self.SubtoolsPanel,{
        Name="SubtoolRows",BackgroundTransparency=1,
        Position=UDim2.fromOffset(8,TITLE_H),
        Size=UDim2.new(1,-16,1,-TITLE_H-8),
    })
    make("UIListLayout",self.SubtoolsList,{
        SortOrder=Enum.SortOrder.LayoutOrder,
        Padding=UDim.new(0,4),
    })

    self.ControlsPanel=make("Frame",gui,{
        Name="ToolSpecificControls",BackgroundColor3=Theme.Window,
        BorderSizePixel=0,Visible=false,
        Position=UDim2.fromOffset(LEFT,TOP+180),
        Size=UDim2.new(0,PANEL_W,1,-TOP-190),
    })
    Theme.Chrome(self.ControlsPanel,Theme.Window)
    label(self.ControlsPanel,"CONTROLS",10,7,1,16,Theme.Muted,10,true)
    self.ContextLabel=label(self.ControlsPanel,"",10,24,1,21,
        Theme.Text,12,true)
    self.ControlsList=make("ScrollingFrame",self.ControlsPanel,{
        Name="ContextualKeybindRows",
        BackgroundTransparency=1,BorderSizePixel=0,
        Position=UDim2.fromOffset(8,TITLE_H),
        Size=UDim2.new(1,-16,1,-TITLE_H-10),
        ScrollBarThickness=3,
        ScrollingDirection=Enum.ScrollingDirection.Y,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,
        CanvasSize=UDim2.fromOffset(0,0),
    })
    make("UIListLayout",self.ControlsList,{
        SortOrder=Enum.SortOrder.LayoutOrder,
        Padding=UDim.new(0,4),
    })
end

function Palette:RenderSubtools()
    local primary=self.Tools.PrimaryId
    local def=definitions[primary]
    clearRows(self.SubtoolsList)
    table.clear(self.PrimaryButtons)
    if not def then return end
    self.PrimaryLabel.Text=TOOL_NAMES[primary] or tostring(primary)
    local total=TITLE_H+9+(#def.Items*(ROW_H+4))
    self.SubtoolsPanel.Size=UDim2.fromOffset(PANEL_W,total)
    self.ControlsPanel.Position=UDim2.fromOffset(LEFT,TOP+total+8)
    self.ControlsPanel.Size=UDim2.new(0,PANEL_W,1,-TOP-total-20)
    for i,item in ipairs(def.Items) do
        local current=self.Tools.SubtoolId==item.Id
        local blocked=primary=="AssemblySimulation" and
            item.Id=="AssemblyEditor" and
            player:GetAttribute("OPENWORKS_Simulating")==true
        local row=make("TextButton",self.SubtoolsList,{
            Name=item.Id,
            LayoutOrder=i,
            Text="",AutoButtonColor=false,
            Size=UDim2.new(1,0,0,ROW_H),
            BorderSizePixel=0,
            BackgroundColor3=if current then Theme.Active else Theme.Panel,
        })
        Theme.Chrome(row,if current then Theme.Active else Theme.Panel)
        local stripe=make("Frame",row,{
            Name="SelectedStripe",BackgroundColor3=Theme.Accent,
            BorderSizePixel=0,
            Size=UDim2.fromOffset(3,ROW_H-6),
            Position=UDim2.fromOffset(2,3),
            Visible=current,
            ZIndex=6,
        })
        local key=keycap(row,item.Key.Name,28)
        key.Position=UDim2.fromOffset(11,5)
        local textLabel=label(row,SUBTOOL_NAMES[item.Id] or item.Id,
            48,4,1,ROW_H-8,
            if blocked then Theme.Muted else Theme.Text,12,current)
        textLabel.ZIndex=6
        self.PrimaryButtons[item.Id]={Row=row,Stripe=stripe,Label=textLabel}
        row.Activated:Connect(function()
            if blocked or
                player:GetAttribute("OPENWORKS_ExplorerOpen")~=true
                or player:GetAttribute("OPENWORKS_PlotMenuOpen")==true then return end
            self.Tools:SetSubtool(item.Id)
        end)
    end
    self.CachedPrimary=primary
end

function Palette:RenderControls(info)
    clearRows(self.ControlsList)
    self.ContextLabel.Text=info.title or "CONTROLS"
    for i,item in ipairs(info.rows) do
        local row=make("Frame",self.ControlsList,{
            Name="Action_"..tostring(i),LayoutOrder=i,
            BackgroundColor3=Theme.Panel,BackgroundTransparency=0.1,
            BorderSizePixel=0,
            Size=UDim2.new(1,0,0,29),
        })
        local w=if #item.key>=10 then 94
            elseif #item.key>=7 then 83
            elseif #item.key>=5 then 74 else 60
        local key=keycap(row,item.key,w)
        key.Position=UDim2.fromOffset(4,3)
        local action=label(row,item.action,w+11,2,1,25,
            Theme.Text,11,false)
        action.TextTruncate=Enum.TextTruncate.AtEnd
    end
end

function Palette:SignatureOf()
    local tools=self.Tools
    local align=self.Build.Layered and self.Build.Layered.Alignment
    local parts={
        tostring(tools.PrimaryId or ""),
        tostring(tools.SubtoolId or ""),
        tostring(self.Build.Pending or ""),
        tostring(self.Build.PendingMateChoice or ""),
        tostring(self.Build.LockedAlignment or ""),
        tostring(self.Build.SmartMatch and self.Build.SmartMatch.kind or ""),
        tostring(align and align.Stage or ""),
        tostring(self.Mechanics.Stage or ""),
        tostring(self.Assembly.Stage or ""),
        tostring(self.Assembly.EditingId or ""),
        tostring(player:GetAttribute("OPENWORKS_Simulating")==true),
        tostring(player:GetAttribute("OPENWORKS_SimulationPaused")==true),
    }
    return table.concat(parts,"|")
end

function Palette:Refresh(force)
    if not self.Gui then return end
    local primary=self.Tools.PrimaryId
    local visible=primary~=nil
    self.SubtoolsPanel.Visible=visible
    self.ControlsPanel.Visible=visible
    if not visible then self.Signature="" return end
    local signature=self:SignatureOf()
    if not force and signature==self.Signature then return end
    self.Signature=signature
    if primary~=self.CachedPrimary then self:RenderSubtools() end
    -- Subtools remain stable when only the active row changes.
    for id,record in pairs(self.PrimaryButtons) do
        local active=id==self.Tools.SubtoolId
        local blocked=primary=="AssemblySimulation" and
            id=="AssemblyEditor" and player:GetAttribute("OPENWORKS_Simulating")==true
        record.Stripe.Visible=active
        record.Row.BackgroundColor3=if active then Theme.Active else Theme.Panel
        record.Label.TextColor3=if blocked then Theme.Muted else Theme.Text
        record.Label.Font=if active then Enum.Font.GothamBold
            else Enum.Font.GothamMedium
    end
    self:RenderControls(Help.Context(self.Tools,
        self.Build,self.Mechanics,self.Assembly,player))
end

function Palette:Start()
    if self.Started then return end
    self.Started=true
    self:CreateUI()
    table.insert(self.Connections,self.Tools.SubtoolChanged.Event:Connect(function()
        self:Refresh(true)
    end))
    table.insert(self.Connections,self.Tools.Changed.Event:Connect(function()
        self:Refresh(true)
    end))
    -- Fitting and assembly-draft states don't all publish events. A bounded
    -- 5Hz signature check updates the hints without rebuilding each frame.
    table.insert(self.Connections,RunService.Heartbeat:Connect(function(dt)
        self.RefreshElapsed+=math.min(dt,0.2)
        if self.RefreshElapsed>=0.2 then
            self.RefreshElapsed=0
            self:Refresh(false)
        end
    end))
    self:Refresh(true)
end

function Palette:Destroy()
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    if self.Gui then self.Gui:Destroy() end
    self.Started=false
end

return Palette
