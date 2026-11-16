--!strict
-- UI v2 contextual editor: no Explorer tree or permanently docked Properties.
-- Tab unlocks the pointer to use the dock; RMB over an authored object
-- opens its contextual menu. No instructions are painted into the world.
-- All mutations go through existing authoritative server request actions.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Data=require(script.Parent:WaitForChild("AuthoredIndex"))
local ConnectionCatalog=require(script.Parent:WaitForChild("ConnectionCatalog"))
local Theme=require(script.Parent:WaitForChild("StudioTheme"))
local construction=RS:WaitForChild("Openworks"):WaitForChild("Construction")
local Config=require(construction:WaitForChild("BuildConfig"))
local Grid=require(construction:WaitForChild("GridMath"))
local ComponentGeometry=require(construction:WaitForChild("ComponentGeometry"))
local Materials=require(construction:WaitForChild("MaterialCatalog"))
local Paint=require(construction:WaitForChild("PaintCatalog"))
local player=Players.LocalPlayer

local Panel={}
Panel.__index=Panel
-- Matches the approved server motor-bindable key set. Keyboard capture
-- removes case-sensitive manual entry and prevents invalid binds.
local MOTOR_BINDINGS={
    F=true,R=true,T=true,Y=true,H=true,J=true,K=true,L=true,
    B=true,N=true,M=true,V=true,Z=true,X=true,C=true,
    One=true,Two=true,Three=true,Four=true,
}
local function mk(kind,parent,properties)
    local obj=Instance.new(kind)
    for key,val in pairs(properties or {}) do obj[key]=val end
    obj.Parent=parent
    return obj
end
local function clear(container)
    for _,item in ipairs(container:GetChildren()) do
        if item:IsA("GuiObject") then item:Destroy() end
    end
end
local function style(frame,color)
    Theme.Chrome(frame,color or Theme.Panel)
    return frame
end
local function button(parent,text,position,size,callback)
    local b=style(mk("TextButton",parent,{
        Text=text,Position=position,Size=size,AutoButtonColor=true,
        TextColor3=Theme.Text,TextSize=12,
        Font=Enum.Font.GothamMedium,
        BackgroundColor3=Theme.Raised,BorderSizePixel=0,
        ZIndex=13,
    }))
    b.Activated:Connect(callback)
    return b
end
local function label(parent,text,position,size,color)
    return mk("TextLabel",parent,{
        Text=text,Position=position,Size=size,
        TextColor3=color or Theme.Text,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        TextSize=12,Font=Enum.Font.GothamMedium,
        BackgroundTransparency=1,ZIndex=12,
    })
end
local function row(parent,height)
    local r=mk("Frame",parent,{
        BackgroundTransparency=1,
        Size=UDim2.new(1,-8,0,height or 28),
        LayoutOrder=#parent:GetChildren(),ZIndex=12,
    })
    return r
end
local function list(parent)
    mk("UIListLayout",parent,{
        SortOrder=Enum.SortOrder.LayoutOrder,
        Padding=UDim.new(0,3),
    })
end
local function own(model)
    return model and model.Parent and model:IsA("Model")
        and model:GetAttribute("OwnerUserId")==player.UserId
end
local function entityId(model)
    return model and model:GetAttribute("InstanceId")
end
local function formatVector(v)
    return string.format("%.2f / %.2f / %.2f",
        v.X/Grid.Unit,v.Y/Grid.Unit,v.Z/Grid.Unit)
end
local function simulating()
    return player:GetAttribute("OPENWORKS_Simulating")==true
end


function Panel.new(tools,build,mechanics,assemblyTool,feedback)
    return setmetatable({
        Tools=tools,Build=build,Mechanics=mechanics,
        AssemblyTool=assemblyTool,Feedback=feedback,
        Connections={},Selected=nil,SelectedKey=nil,Related={},
        Fields={},Flags={},Snapshot=nil,
        Focused=false,ContextOpen=false,CreatorOpen=false,
        ConnectionChoiceOpen=false,ChoiceCallback=nil,
        ChoiceWasFocused=false,Telemetry=nil,TelemetrySeed=nil,
        StatusUntil=0,LastScan=0,Busy=false,Started=false,
        RelationView=nil,Removing=nil,CurrentPage="object",
        RootPage="object",
    },Panel)
end

function Panel:Hint(control,description)
    if not control then return end
    control.MouseEnter:Connect(function()
        if not self.Gui or not self.Gui.Parent then return end
        local pos=UIS:GetMouseLocation()
        local viewport=workspace.CurrentCamera and
            workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
        self.Tooltip.Text=description
        self.Tooltip.Position=UDim2.fromOffset(
            math.clamp(pos.X+12,5,math.max(5,viewport.X-275)),
            math.clamp(pos.Y+16,5,math.max(5,viewport.Y-57)))
        self.Tooltip.Visible=true
    end)
    control.MouseLeave:Connect(function()
        if self.Tooltip then self.Tooltip.Visible=false end
    end)
end

function Panel:Focus(value)
    self.Focused=value==true
    local claimed=self.Focused or self.ContextOpen or
        self.ConnectionChoiceOpen or self.CreatorOpen
    player:SetAttribute("OPENWORKS_ExplorerOpen",claimed)
    UIS.MouseBehavior=if claimed then Enum.MouseBehavior.Default
        else Enum.MouseBehavior.LockCenter
    UIS.MouseIconEnabled=claimed
    if self.Crosshair then self.Crosshair.Visible=not claimed
        and self.Tools.PrimaryId~="Edit" end
    if self.Build and self.Build.Gui then self.Build:RefreshPointer() end
end

function Panel:CloseMenu()
    if self.KeyCapture then
        self.KeyCapture:Disconnect()
        self.KeyCapture=nil
    end
    self.ContextOpen=false
    if self.Surface then self.Surface.Visible=false end
    if self.Tooltip then self.Tooltip.Visible=false end
    self:Focus(false)
end

function Panel:CloseContext()
    self:CloseMenu()
end

function Panel:CloseConnectionChoice(cancel)
    if not self.ConnectionChoiceOpen then return end
    local callback=self.ChoiceCallback
    local restore=self.ChoiceWasFocused
    self.ConnectionChoiceOpen=false
    self.ChoiceCallback=nil
    self.ConnectionChoice.Visible=false
    if self.Tooltip then self.Tooltip.Visible=false end
    self:Focus(restore)
    if cancel==true and callback then callback(nil) end
end

function Panel:ChooseConnection(options,callback,heading)
    if not self.ConnectionChoice then return false end
    if self.ConnectionChoiceOpen then self:CloseConnectionChoice(true) end
    if type(options)~="table" or #options==0 then return false end
    self:CloseMenu()
    self.ChoiceWasFocused=self.Focused
    self.ConnectionChoiceOpen=true
    self.ChoiceCallback=callback
    self.ConnectionChoiceHeading.Text=heading or "CONNECTION"
    clear(self.ConnectionChoices)
    local count=math.min(#options,12)
    local height=math.clamp(count*35+89,135,405)
    self.ConnectionChoice.Size=UDim2.fromOffset(268,height)
    self.ConnectionChoices.Size=UDim2.new(1,-16,1,-84)
    for i=1,count do
        local choice=options[i]
        local holder=row(self.ConnectionChoices,32)
        local item=button(holder,choice.label,
            UDim2.fromOffset(0,0),UDim2.new(1,0,1,0),function()
                local result=self.ChoiceCallback
                self:CloseConnectionChoice(false)
                if result then result(choice.id) end
            end)
        item.TextXAlignment=Enum.TextXAlignment.Left
        item.ZIndex=43
        self:Hint(item,choice.tooltip or choice.label)
    end
    self.ConnectionChoice.Position=UDim2.fromScale(0.5,0.5)
    self.ConnectionChoice.Visible=true
    self:Focus(true)
    return true
end

function Panel:ChooseFit(kind,callback,count,hole)
    local options=ConnectionCatalog.Fit(kind,hole)
    if kind=="Hub" then
        callback("Rigid")
        return true
    end
    local title=if kind=="Hub" then "GEAR OR PULLEY / SHAFT"
        elseif (count or 0)>1 then
            tostring(count).." OPENINGS / SHAFT"
        else "SHAFT / HOLE"
    return self:ChooseConnection(options,callback,title)
end

function Panel:ChoosePair(first,second,callback)
    local options=ConnectionCatalog.Pair(first,second)
    if #options==1 and options[1].id=="Rigid" then
        callback("Rigid")
        return true
    end
    return self:ChooseConnection(options,callback,"CONNECT TWO PARTS")
end


function Panel:Message(message)
    if not self.Status then return end
    self.Status.Text=tostring(message)
    self.Status.Visible=true
    self.StatusUntil=os.clock()+3.2
end

function Panel:MakeUI()
    local gui=mk("ScreenGui",player:WaitForChild("PlayerGui"),{
        Name="OPENWORKS_ContextEditor",ResetOnSpawn=false,
        IgnoreGuiInset=true,DisplayOrder=96,
        ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    })
    self.Gui=gui
    self.Crosshair=mk("TextLabel",gui,{
        Name="ContextCrosshair",Text="+",
        AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(20,20),BackgroundTransparency=1,
        TextColor3=Theme.Text,TextSize=21,Font=Enum.Font.GothamMedium,
        Visible=false,ZIndex=3,
    })
    local popup=style(mk("Frame",gui,{
        Name="RightClickEditor",Visible=false,
        BackgroundColor3=Theme.Window,
        Size=UDim2.fromOffset(330,420),
        Position=UDim2.fromOffset(500,175),ZIndex=20,
    }),Theme.Window)
    self.Surface=popup
    self.Title=label(popup,"COMPONENT",UDim2.fromOffset(12,9),
        UDim2.new(1,-86,0,29),Theme.Text)
    self.Title.TextSize=14
    self.Title.ZIndex=22
    local close=button(popup,"×",UDim2.new(1,-41,0,8),
        UDim2.fromOffset(32,29),function() self:CloseContext() end)
    close.ZIndex=23
    self.Back=button(popup,"‹",UDim2.new(1,-77,0,8),
        UDim2.fromOffset(31,29),function()
            self.RelationView=nil
            self.CurrentPage=self.RootPage
                or (if self.Tools.PrimaryId=="Build"
                    then "object" else "relationships")
            self:RenderContext()
        end)
    self.Back.ZIndex=23
    self.Properties=mk("ScrollingFrame",popup,{
        Name="ContextProperties",BackgroundTransparency=1,
        BorderSizePixel=0,Position=UDim2.fromOffset(10,48),
        Size=UDim2.new(1,-20,1,-62),CanvasSize=UDim2.fromOffset(0,0),
        AutomaticCanvasSize=Enum.AutomaticSize.Y,
        ScrollBarThickness=4,ZIndex=21,
    })
    list(self.Properties)
    local propertyLayout=self.Properties:FindFirstChildOfClass("UIListLayout")
    if propertyLayout then
        propertyLayout:GetPropertyChangedSignal("AbsoluteContentSize")
            :Connect(function() self:ResizeContext() end)
    end
    self.Creator=style(mk("Frame",gui,{
        Name="AssemblyCreator",Visible=false,
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(405,214),
        BackgroundColor3=Theme.Window,ZIndex=45,
    }),Theme.Window)
    local heading=label(self.Creator,"NEW ASSEMBLY",
        UDim2.fromOffset(18,16),UDim2.new(1,-35,0,31))
    heading.TextSize=16
    heading.ZIndex=46
    label(self.Creator,"Name",UDim2.fromOffset(18,58),
        UDim2.new(1,-36,0,25),Theme.Muted).ZIndex=46
    self.DraftNameInput=style(mk("TextBox",self.Creator,{
        Name="AssemblyName",Text="",ClearTextOnFocus=false,
        PlaceholderText="Assembly name",TextSize=14,
        Font=Enum.Font.Gotham,TextColor3=Theme.Text,
        BackgroundColor3=Theme.Input,
        Position=UDim2.fromOffset(18,88),Size=UDim2.new(1,-36,0,37),
        ZIndex=47,
    }),Theme.Input)
    local begin=button(self.Creator,"SELECT PRIMITIVES",
        UDim2.fromOffset(18,148),UDim2.fromOffset(229,42),function()
            if self:ApplyDraftName() then
                self.CreatorOpen=false
                self.Creator.Visible=false
                self:OnAssemblyDraftChanged()
                self:Focus(false)
            end
        end)
    begin.ZIndex=47
    local discard=button(self.Creator,"CANCEL",
        UDim2.fromOffset(263,148),UDim2.fromOffset(124,42),function()
            self.CreatorOpen=false
            self.Creator.Visible=false
            self.AssemblyTool:Cancel()
            self:OnAssemblyDraftChanged()
            self:Focus(false)
        end)
    discard.ZIndex=47

    self.DraftBar=style(mk("Frame",gui,{
        Name="AssemblySelectionBar",Visible=false,
        AnchorPoint=Vector2.new(0.5,0),
        Position=UDim2.new(0.5,0,0,28),
        Size=UDim2.fromOffset(468,55),
        BackgroundColor3=Theme.Window,ZIndex=12,
    }),Theme.Window)
    self.DraftLabel=label(self.DraftBar,"ASSEMBLY",
        UDim2.fromOffset(12,8),UDim2.new(1,-250,0,38))
    self.DraftLabel.ZIndex=13
    button(self.DraftBar,"CONFIRM",UDim2.new(1,-232,0,10),
        UDim2.fromOffset(106,34),function()
            if not self:ApplyDraftName() then return end
            self.AssemblyTool:Confirm()
            self:OnAssemblyDraftChanged()
        end).ZIndex=14
    button(self.DraftBar,"CANCEL",UDim2.new(1,-119,0,10),
        UDim2.fromOffset(108,34),function()
            self.AssemblyTool:Cancel()
            self:OnAssemblyDraftChanged()
        end).ZIndex=14

    self.SimulationBar=style(mk("Frame",gui,{
        Name="SimulationControls",Visible=false,
        AnchorPoint=Vector2.new(0.5,0),
        Position=UDim2.new(0.5,0,0,28),
        Size=UDim2.fromOffset(382,57),
        BackgroundColor3=Theme.Window,ZIndex=12,
    }),Theme.Window)
    self.SimStatus=label(self.SimulationBar,"SIMULATING",
        UDim2.fromOffset(10,8),UDim2.new(0.3,-10,0,36))
    self.SimStatus.ZIndex=13
    button(self.SimulationBar,"STOP",UDim2.fromOffset(112,11),
        UDim2.fromOffset(72,34),function()
            self:RunSimulationAction("stop",self.Selected)
        end).ZIndex=14
    button(self.SimulationBar,"PAUSE",UDim2.fromOffset(190,11),
        UDim2.fromOffset(85,34),function()
            self:RunSimulationAction("pause",self.Selected)
        end).ZIndex=14
    button(self.SimulationBar,"RESET",UDim2.fromOffset(281,11),
        UDim2.fromOffset(89,34),function()
            self:RunSimulationAction("reset",self.Selected)
        end).ZIndex=14

    local choice=style(mk("Frame",gui,{
        Name="UnifiedConnectionChoice",Visible=false,
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.5),
        BackgroundColor3=Theme.Window,
        Size=UDim2.fromOffset(268,280),ZIndex=40,
    }),Theme.Window)
    self.ConnectionChoice=choice
    self.ConnectionChoiceHeading=label(choice,"CONNECTION",
        UDim2.fromOffset(10,8),UDim2.new(1,-35,0,26))
    self.ConnectionChoices=mk("ScrollingFrame",choice,{
        Name="CompatibleConnections",Position=UDim2.fromOffset(8,40),
        Size=UDim2.new(1,-16,1,-84),BackgroundTransparency=1,
        ScrollBarThickness=3,AutomaticCanvasSize=Enum.AutomaticSize.Y,
        CanvasSize=UDim2.fromOffset(0,0),ZIndex=41,
    })
    list(self.ConnectionChoices)
    self.ConnectionCancel=button(choice,"CANCEL",
        UDim2.new(0,8,1,-38),UDim2.new(1,-16,0,30),function()
            self:CloseConnectionChoice(true)
        end)
    self.ConnectionCancel.ZIndex=43
    self.Tooltip=style(mk("TextLabel",gui,{
        Name="ContextTooltip",Text="",Visible=false,
        BackgroundColor3=Theme.Panel,Size=UDim2.fromOffset(265,46),
        TextColor3=Theme.Text,TextSize=11,TextWrapped=true,
        Font=Enum.Font.Gotham,ZIndex=70,
    }),Theme.Panel)
    self.Status=style(mk("TextLabel",gui,{
        Name="ContextStatus",Text="",Visible=false,
        AnchorPoint=Vector2.new(0.5,0),Position=UDim2.new(0.5,0,0,92),
        Size=UDim2.fromOffset(405,39),TextColor3=Theme.Text,
        TextSize=12,Font=Enum.Font.Gotham,
        BackgroundColor3=Theme.Panel,ZIndex=61,
    }),Theme.Panel)
    self:Focus(false)
end

function Panel:Scan(force)
    local now=os.clock()
    if not force and now-self.LastScan<0.5 then return end
    self.LastScan=now
    self.Snapshot=Data.Snapshot(player)
    if self.Selected and self.Selected.kind=="primitive" then
        self.Selected=self:NodeForModel(self.Selected.model,false)
    elseif self.Selected and self.Selected.kind=="component" then
        local member=self.Selected.members and self.Selected.members[1]
        self.Selected=self:NodeForModel(member,true)
    elseif self.Selected and self.Selected.kind=="assembly" then
        local found=nil
        for _,node in ipairs(self.Snapshot.assemblies) do
            if node.kind=="assembly" and node.id==self.Selected.id then
                found=node break
            end
        end
        self.Selected=found
    end
    if not self.Selected then
        if self.Feedback then self.Feedback:Clear("context-selection") end
        if self.ContextOpen then self:CloseContext() end
    end
end

function Panel:NodeForModel(model,preferComponent)
    if not own(model) then return nil end
    local id=entityId(model)
    local cid=model:GetAttribute("ComponentId")
    if preferComponent and type(cid)=="string" and cid~="" then
        local members=self.Build:ComponentMembers(cid)
        if #members>0 then
            return {kind="component",id=cid,key="c:"..cid,
                name="Component "..cid:sub(1,8),componentId=cid,
                members=members}
        end
    end
    return {kind="primitive",id=id,key="p:"..tostring(id),
        name=model.Name,model=model,members={model},
        componentId=cid,assemblyId=model:GetAttribute("AssemblyId")}
end

function Panel:Select(node,propagate)
    if not node then
        self.Selected=nil
        if self.Feedback then self.Feedback:Clear("context-selection") end
        return
    end
    self.Selected=node
    if self.Feedback then
        self.Feedback:Clear("context-selection")
        if self.Tools.PrimaryId~="Edit" then
            local members={}
            for _,model in ipairs(node.members or {}) do
                if own(model) then table.insert(members,model) end
            end
            if #members>0 then
                if node.kind=="component" then
                    local anchor=ComponentGeometry.CentralPrimitive(members)
                    if anchor then
                        local ordered={anchor}
                        for _,model in ipairs(members) do
                            if model~=anchor then table.insert(ordered,model) end
                        end
                        members=ordered
                    end
                end
                self.Feedback:Set("context-selection","selected",
                    members,if node.kind=="assembly" then "assembly"
                    else "selection",node.kind=="assembly"
                        or node.kind=="component")
            end
        end
    end
    if propagate and self.Tools.PrimaryId=="Edit"
        and self.Build.Mode=="Edit" then
        if node.kind=="primitive" and own(node.model) then
            self.Build:SetSelection(node.model)
        elseif node.kind=="component" and #node.members>0 then
            self.Build:SetComponentSelection(node.componentId,node.members)
        end
    end
end

function Panel:OnConstructionSelection()
    local build=self.Build
    if self.Tools.PrimaryId~="Edit" then return end
    local node
    if build.SelectedComponentId and #build.SelectedParts>0 then
        node=self:NodeForModel(build.SelectedParts[1],true)
    elseif build.Selected and own(build.Selected) then
        node=self:NodeForModel(build.Selected,false)
    end
    self.Selected=node
    if self.Feedback then self.Feedback:Clear("context-selection") end
end

function Panel:SelectWorldAtCenter()
    local camera=workspace.CurrentCamera
    local authored=workspace:FindFirstChild(Config.FolderName)
    if not camera or not authored then return nil end
    local root=authored
    if simulating() then
        local simulations=workspace:FindFirstChild("OPENWORKS_Simulated")
        root=simulations and simulations:FindFirstChild(
            "Simulation_"..tostring(player.UserId)) or authored
    end
    local ray=camera:ViewportPointToRay(
        camera.ViewportSize.X*.5,camera.ViewportSize.Y*.5)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={root}
    params.IgnoreWater=true
    local hit=workspace:Raycast(ray.Origin,ray.Direction*Grid.MaxDistance,params)
    if not hit then
        self:Select(nil,false)
        return nil
    end
    local model=hit.Instance
    while model and model.Parent~=root do model=model.Parent end
    if not own(model) then return nil end
    if root~=authored then
        local id=entityId(model)
        model=self.Snapshot and self.Snapshot.byId[id]
        if not own(model) then return nil end
    end
    -- In non-Build tools the user right-clicked this EXACT primitive.
    -- Show its joints rather than silently expanding to an entire editor
    -- component containing unrelated internal connections.
    local node=self:NodeForModel(model,self.Tools.PrimaryId=="Build")
    self:Select(node,true)
    return node
end

function Panel:OpenSelectedContext(page)
    local node=self.Selected
    if not node then
        self:Message("Select a primitive or component first")
        return
    end
    self:OpenForNode(node,UIS:GetMouseLocation(),page)
end

function Panel:ResizeContext()
    if not self.ContextOpen or not self.Surface or not self.Properties then
        return
    end
    local layout=self.Properties:FindFirstChildOfClass("UIListLayout")
    if not layout then return end
    local viewport=workspace.CurrentCamera and
        workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
    local limit=math.max(160,math.min(495,viewport.Y-18))
    local height=math.clamp(layout.AbsoluteContentSize.Y+67,160,limit)
    if math.abs(self.Surface.Size.Y.Offset-height)>1 then
        self.Surface.Size=UDim2.fromOffset(330,height)
    end
    local p=self.Surface.Position
    local top=math.clamp(p.Y.Offset,8,math.max(8,viewport.Y-height-8))
    if top~=p.Y.Offset then
        self.Surface.Position=UDim2.fromOffset(p.X.Offset,top)
    end
end

function Panel:OpenForNode(node,pos,page)
    if not node then return end
    self:CloseConnectionChoice(true)
    self.Selected=node
    self.RelationView=nil
    self.RootPage=if page=="object" or self.Tools.PrimaryId=="Build"
        then "object" else "relationships"
    self.CurrentPage=self.RootPage
    self.Removing=nil
    local viewport=workspace.CurrentCamera and
        workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
    local p=pos or Vector2.new(viewport.X/2,viewport.Y/2)
    self.Surface.Position=UDim2.fromOffset(
        math.clamp(p.X+15,8,math.max(8,viewport.X-338)),
        math.clamp(p.Y-50,8,math.max(8,viewport.Y-430)))
    self.ContextOpen=true
    self.Surface.Visible=true
    self:Focus(true)
    self:Select(node,true)
    self:RenderContext()
end

function Panel:OpenMenu(node,pos)
    self:OpenForNode(node,pos)
end

function Panel:FocusAssemblyName()
    if self.AssemblyTool.Stage~="Selecting" then return end
    self:CloseContext()
    self.CreatorOpen=true
    self.Creator.Visible=true
    self.DraftNameInput.Text=self.AssemblyTool.Name or ""
    self:Focus(true)
    task.defer(function()
        if self.CreatorOpen then self.DraftNameInput:CaptureFocus() end
    end)
end

function Panel:ApplyDraftName()
    if self.AssemblyTool.Stage~="Selecting" then return true end
    local value=if self.CreatorOpen then self.DraftNameInput.Text
        else self.AssemblyTool.Name
    local name=tostring(value or ""):match("^%s*(.-)%s*$")
    if not name or #name==0 or #name>48 or name:find("[%c]") then
        self:Message("Enter an assembly name (1–48 characters)")
        return false
    end
    self.AssemblyTool.Name=name
    return true
end

function Panel:OnAssemblyDraftChanged()
    if not self.DraftBar then return end
    local draft=self.AssemblyTool
    local visible=draft.Stage=="Selecting"
        and self.Tools.PrimaryId=="AssemblySimulation"
        and self.Tools.SubtoolId=="AssemblyEditor"
    self.DraftBar.Visible=visible and not self.CreatorOpen
    if not visible then return end
    local count=0
    for _ in pairs(draft.Selected or {}) do count+=1 end
    self.DraftLabel.Text=tostring(draft.Name or "Assembly")
        .."  ·  "..count.." selected"
end

function Panel:OnSimulationSessionChanged()
    if not self.SimulationBar then return end
    local running=simulating()
    self.SimulationBar.Visible=running
    self.SimStatus.Text=if player:GetAttribute(
        "OPENWORKS_SimulationPaused")==true then "PAUSED" else "RUNNING"
    if self.ContextOpen and not UIS:GetFocusedTextBox() then
        self:RenderContext()
    end
end

function Panel:RunSimulationAction(action,node)
    local running=simulating()
    -- Stop is a safety escape hatch even when another native tool was
    -- equipped during physics; all other actions require Simulation.
    if action~="stop" and (self.Tools.PrimaryId~="AssemblySimulation"
        or self.Tools.SubtoolId~="Simulation") then return false end
    if action=="run" then
        if running or not node or node.kind~="assembly" then return false end
        local seed=node.members and node.members[1]
        if not own(seed) then return false end
        local ok=self.Mechanics:StartRegisteredAssembly(seed)
        if ok then
            self.Telemetry=nil
            self.TelemetrySeed=nil
            self:OnSimulationSessionChanged()
        end
        return ok
    elseif not running then
        self:Message("Select a saved assembly to simulate")
        return false
    end
    if action=="stop" then
        local ok=self.Mechanics:StopRegisteredAssembly()
        if ok then
            self.Telemetry=nil
            self.TelemetrySeed=nil
        end
        self:OnSimulationSessionChanged()
        return ok
    elseif action=="pause" or action=="reset" then
        local ok=self:Send({action=if action=="pause"
            then "PauseSimulation" else "ResetSimulation"},true)
        self:OnSimulationSessionChanged()
        return ok
    elseif action=="telemetry" then
        local id=self.Mechanics.SimSeedId
        if type(id)~="string" then return false end
        local ok,result=self.Mechanics:Request({
            action="GetMechanismInfo",seedId=id,
        })
        if ok and result then
            self.Telemetry=tostring(result.message or "")
            self.TelemetrySeed=id
            self:RenderProperties()
        end
        return ok
    end
    return false
end

function Panel:RenderSimulationControls(node)
    self:Section("Simulation")
    local running=simulating()
    if not running then
        self:Value("Status","Ready")
        if node and node.kind=="assembly" and node.members
            and #node.members>0 then
            self:Value("Selected",node.name)
            self:Value("Included primitives",#node.members)
            self:ActionButton("Run assembly",
                "Simulate exactly the registered assembly members",function()
                    self:RunSimulationAction("run",node)
                end)
        else
            self:Value("Target","Select a registered assembly")
        end
        return
    end
    self:Value("Status",if player:GetAttribute(
        "OPENWORKS_SimulationPaused")==true then "Paused" else "Running")
    self:Value("Assembly",self.Mechanics.SimAssemblyName or "Registered assembly")
    self:ActionButton("Stop and return to build",
        "Stop physics and restore the authored construction",function()
            self:RunSimulationAction("stop",node)
        end)
    if self.Tools.PrimaryId~="AssemblySimulation"
        or self.Tools.SubtoolId~="Simulation" then
        self:Value("Controls","Equip Assembly & Simulation to continue")
        return
    end
    self:ActionButton(
        if player:GetAttribute("OPENWORKS_SimulationPaused")==true
            then "Resume physics" else "Pause physics",
        "Toggle simulation pause without changing saved geometry",function()
            self:RunSimulationAction("pause",node)
        end)
    self:ActionButton("Reset simulation",
        "Restart the active assembly from its authored saved positions",function()
            self:RunSimulationAction("reset",node)
        end)
    self:ActionButton("Inspect mechanism",
        "Read current relationships, transmissions and constraints",function()
            self:RunSimulationAction("telemetry",node)
        end)
    if self.Telemetry and self.TelemetrySeed==self.Mechanics.SimSeedId then
        self:Section("Live inspection")
        for i,part in ipairs(string.split(self.Telemetry,"  /  ")) do
            if i>12 then break end
            local line=row(self.Properties,32)
            local t=label(line,part,UDim2.fromOffset(5,0),
                UDim2.new(1,-8,1,0),Theme.Muted)
            t.TextWrapped=true
        end
    end
end

function Panel:Section(title)
    local r=row(self.Properties,22)
    label(r,title:upper(),UDim2.fromOffset(5,0),
        UDim2.new(1,-10,1,0),Theme.Muted)
    return r
end

function Panel:Value(name,value)
    local r=row(self.Properties,28)
    label(r,name,UDim2.fromOffset(6,0),
        UDim2.new(0.40,-6,1,0),Theme.Muted)
    local v=label(r,tostring(value),UDim2.new(0.40,0,0,0),
        UDim2.new(0.60,-7,1,0))
    v.TextXAlignment=Enum.TextXAlignment.Right
    return v
end

function Panel:Field(name,value)
    local r=row(self.Properties,30)
    label(r,name,UDim2.fromOffset(6,0),
        UDim2.new(0.45,-6,1,0),Theme.Muted)
    local text=style(mk("TextBox",r,{
        Name="Property_"..name,Text=tostring(value or ""),
        ClearTextOnFocus=false,
        TextSize=12,Font=Enum.Font.Gotham,
        TextColor3=Theme.Text,
        Size=UDim2.new(0.55,-7,1,-3),
        Position=UDim2.new(0.45,0,0,1),
        BackgroundColor3=Theme.Input,ZIndex=13,
    }),Theme.Input)
    self.Fields[name]=text
    self:Hint(text,"Edit "..name.." · changes apply only when saved")
    return text
end

-- Simple Plane Crazy-like property controls: tap a mode, toggle a
-- feature, or drag a range. Exact values are still directly editable.
function Panel:Switch(name,value,tip,onChange)
    self.Flags[name]=value==true
    local holder=row(self.Properties,31)
    label(holder,name,UDim2.fromOffset(6,0),
        UDim2.new(0.64,-6,1,0),Theme.Text)
    local control
    local function redraw()
        control.Text=if self.Flags[name] then "ON" else "OFF"
        control.BackgroundColor3=if self.Flags[name] then Theme.Active
            else Theme.Raised
    end
    control=button(holder,"",UDim2.new(0.64,0,0,1),
        UDim2.new(0.36,-6,1,-2),function()
            self.Flags[name]=not self.Flags[name]
            redraw()
            if onChange then onChange(self.Flags[name]) end
        end)
    if tip then self:Hint(control,tip) end
    redraw()
    return holder
end

function Panel:Segment(name,options,selected,onChange)
    self.Flags[name]=selected
    local holder=row(self.Properties,33)
    label(holder,name,UDim2.fromOffset(6,0),
        UDim2.new(0.28,-6,1,0),Theme.Text)
    local buttons={}
    local function redraw()
        for id,control in pairs(buttons) do
            control.BackgroundColor3=if self.Flags[name]==id
                then Theme.Active else Theme.Raised
        end
    end
    for i,option in ipairs(options) do
        local chosen=option.id
        local width=0.72/#options
        local control=button(holder,option.label,
            UDim2.new(0.28+(i-1)*width,2,0,1),
            UDim2.new(width,-5,1,-2),function()
                self.Flags[name]=chosen
                redraw()
                if onChange then onChange(chosen) end
            end)
        buttons[chosen]=control
        if option.tip then self:Hint(control,option.tip) end
    end
    redraw()
    return holder
end

-- Paired with a normal editable TextBox above it. No technical percentages:
-- the displayed number is the value applied to the actual relationship.
-- Click the key field and press a valid key. No typing or key-name
-- memorization needed; the server still validates every binding.
function Panel:KeyPicker(name,current)
    local holder=row(self.Properties,31)
    label(holder,name,UDim2.fromOffset(6,0),
        UDim2.new(0.45,-6,1,0),Theme.Text)
    local control
    local function endCapture()
        if self.KeyCapture then self.KeyCapture:Disconnect() end
        self.KeyCapture=nil
    end
    control=button(holder,tostring(current or "F"),
        UDim2.new(0.45,0,0,1),UDim2.new(0.55,-7,1,-2),function()
            endCapture()
            local previous=if MOTOR_BINDINGS[control.Text] then control.Text
                else tostring(current or "F")
            control.Text="PRESS A KEY"
            self.KeyCapture=UIS.InputBegan:Connect(function(input)
                if not self.ContextOpen or not control.Parent then
                    endCapture()
                    return
                end
                local key=input.KeyCode.Name
                if key=="Escape" then
                    control.Text=previous
                    endCapture()
                elseif MOTOR_BINDINGS[key] then
                    control.Text=key
                    endCapture()
                elseif input.UserInputType==Enum.UserInputType.Keyboard then
                    self:Message("Choose a supported letter or 1–4")
                end
            end)
        end)
    self:Hint(control,"Click, then press the key to control the motor")
    self.Fields[name]=control
    return control
end

function Panel:RangeSlider(name,low,high,step,logarithmic,onRelease)
    local field=self.Fields[name]
    if not field then return nil end
    local holder=row(self.Properties,23)
    local track=mk("TextButton",holder,{
        Name="Range_"..name,Text="",AutoButtonColor=false,
        Position=UDim2.fromOffset(6,1),
        Size=UDim2.new(1,-12,0,20),BorderSizePixel=0,
        BackgroundTransparency=1,ZIndex=13,
    })
    mk("Frame",track,{
        Name="Rail",Position=UDim2.fromOffset(0,7),
        Size=UDim2.new(1,0,0,6),BorderSizePixel=0,
        BackgroundColor3=Theme.Input,ZIndex=13,
    })
    local fill=mk("Frame",track,{
        Name="Fill",Position=UDim2.fromOffset(0,7),
        Size=UDim2.new(0,0,0,6),
        BorderSizePixel=0,BackgroundColor3=Theme.Accent,
        ZIndex=14,
    })
    local thumb=mk("Frame",track,{
        Name="Thumb",AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0,0.5),
        Size=UDim2.fromOffset(13,15),BorderSizePixel=0,
        BackgroundColor3=Theme.Text,ZIndex=15,
    })
    local function fraction(value)
        local n=math.clamp(value,low,high)
        if logarithmic and low>0 then
            return math.log(n/low)/math.log(high/low)
        end
        return (n-low)/(high-low)
    end
    local function mapped(t)
        local raw=if logarithmic and low>0 then
            low*(high/low)^t else low+(high-low)*t
        local result=math.round(raw/step)*step
        return math.clamp(math.round(result*1000)/1000,low,high)
    end
    local function redraw()
        if not field.Parent or not track.Parent then return end
        local value=tonumber(field.Text)
        if value==nil then return end
        local t=fraction(value)
        fill.Size=UDim2.new(t,0,0,6)
        thumb.Position=UDim2.fromScale(t,0.5)
    end
    field:GetPropertyChangedSignal("Text"):Connect(redraw)
    local function setAt(x)
        local width=math.max(1,track.AbsoluteSize.X)
        local t=math.clamp((x-track.AbsolutePosition.X)/width,0,1)
        field.Text=tostring(mapped(t))
    end
    local dragging=false
    track.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true
            setAt(input.Position.X)
        end
    end)
    local moved=UIS.InputChanged:Connect(function(input)
        if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
            setAt(input.Position.X)
        end
    end)
    local released=UIS.InputEnded:Connect(function(input)
        if dragging and input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=false
            if onRelease then onRelease() end
        end
    end)
    track.Destroying:Connect(function()
        moved:Disconnect()
        released:Disconnect()
    end)
    redraw()
    return holder
end

function Panel:ActionButton(name,tip,callback)
    local r=row(self.Properties,29)
    local item=button(r,name,UDim2.fromOffset(3,0),
        UDim2.new(1,-7,1,0),callback)
    self:Hint(item,tip)
    return item
end

function Panel:Cycle(name,values,selected,onChange)
    local r=row(self.Properties,28)
    label(r,name,UDim2.fromOffset(6,0),
        UDim2.new(0.38,-6,1,0),Theme.Muted)
    local index=table.find(values,selected) or 1
    local nextButton
    nextButton=button(r,tostring(values[index]).."  ▾",
        UDim2.new(0.38,0,0,0),UDim2.new(0.62,-6,1,0),function()
            index=index%#values+1
            nextButton.Text=tostring(values[index]).."  ▾"
            self.Flags[name]=values[index]
            if onChange then onChange(self.Flags[name]) end
        end)
    self.Flags[name]=values[index]
    self:Hint(nextButton,"Cycle "..name:lower().." choices")
end

function Panel:Send(payload,mechanical)
    if self.Busy then return false end
    self.Busy=true
    local ok,result
    if mechanical then
        ok,result=self.Mechanics:Request(payload)
    else
        ok,result=self.Build:Request(payload)
    end
    self.Busy=false
    self:Message(if ok then "Saved"
        else (type(result)=="table" and result.message
            or "Couldn't save these settings"))
    self:Scan(true)
    return ok,result
end


function Panel:RelevantRelations(node)
    local ids={}
    for _,model in ipairs(node.members or {}) do
        local id=entityId(model)
        if type(id)=="string" then ids[id]=true end
    end
    local related={}
    self:Scan(true)
    for _,entry in ipairs(self.Snapshot.relations) do
        local rel=entry.relation
        if ids[rel:GetAttribute("SourceId")]
            or ids[rel:GetAttribute("TargetId")]
            or ids[rel:GetAttribute("SecondTargetId")] then
            table.insert(related,entry)
        end
    end
    table.sort(related,function(a,b)
        return a.name==b.name and a.id<b.id or a.name<b.name
    end)
    return related
end

function Panel:ConfirmAppearance(node)
    if simulating() then return end
    local part=node.members[1]
    if not own(part) then return end
    local scope=if node.kind=="component" then "Component" else "Primitive"
    local id=if scope=="Component" then node.componentId else entityId(part)
    local material=self.Flags.Material
    local finish=self.Flags.Finish
    local hex=Paint.NormalizeHex(self.Fields["Color HEX"].Text)
    if finish~="Factory" and not hex then
        self:Message("Invalid HEX color") return
    end
    if material~=part:GetAttribute("ConstructionMaterial") then
        if not self:Send({action="SetMaterial",scope=scope,
            id=id,materialId=material}) then return end
    end
    if finish~=part:GetAttribute("PaintFinish")
        or (finish~="Factory"
            and "#" .. tostring(hex)~=tostring(
                part:GetAttribute("PaintColorHex") or "")) then
        if not self:Send({action="SetPaint",scope=scope,id=id,
            paintFinish=finish,
            paintColorHex=if finish=="Factory" then nil else hex}) then
            return
        end
    end
    self:Message("Appearance confirmed")
end

function Panel:RenderObject(node)
    local member=node.members and node.members[1]
    if not own(member) then self:Value("Selection","Unavailable") return end
    self:Section(if node.kind=="component" then "Component" else "Primitive")
    self:Value("Name",node.name)
    if node.kind=="component" then self:Value("Parts",#node.members) end
    local part=member.PrimaryPart
    if part then self:Value("Size (U)",formatVector(part.Size)) end
    local assemblyId=member:GetAttribute("AssemblyId")
    if type(assemblyId)=="string" and assemblyId~="" then
        self:Value("Assembly",member:GetAttribute("AssemblyName") or "Assembly")
        self:ActionButton("Open assembly",
            "Inspect the exact registered assembly",function()
                for _,a in ipairs(self.Snapshot.assemblies) do
                    if a.id==assemblyId then
                        self.Selected=a
                        self:RenderContext()
                        return
                    end
                end
            end)
    end
    if not simulating() then
        self:Section("Appearance")
        self:Cycle("Material",Materials.List(),
            member:GetAttribute("ConstructionMaterial") or "Steel")
        local function showColor(finish)
            local visible=finish~="Factory"
            if self.ColorFieldRow then self.ColorFieldRow.Visible=visible end
            if self.ColorPaletteRow then self.ColorPaletteRow.Visible=visible end
        end
        self:Cycle("Finish",Paint.List(),
            member:GetAttribute("PaintFinish") or "Factory",showColor)
        local colorField=self:Field("Color HEX",
            member:GetAttribute("PaintColorHex") or "#D61F2C")
        self.ColorFieldRow=colorField.Parent
        local colors=Paint.Palette()
        local r=row(self.Properties,43)
        self.ColorPaletteRow=r
        for i=1,math.min(6,#colors) do
            local swatch=colors[i]
            local color=Paint.ToColor(swatch.Hex)
            local sw=button(r,"",UDim2.new((i-1)/6,1,0,4),
                UDim2.new(1/6,-3,0,30),function()
                    self.Fields["Color HEX"].Text="#"..swatch.Hex
                end)
            sw.BackgroundColor3=color or Theme.Accent
            self:Hint(sw,swatch.Name)
        end
        showColor(self.Flags.Finish)
        self:ActionButton("SAVE APPEARANCE",
            "Save changed material and finish via original server actions",function()
                self:ConfirmAppearance(node)
            end)
        if member:GetAttribute("PaintFinish")~="Factory"
            and member:GetAttribute("PaintFinish")~=nil then
            self:ActionButton("Reset finish",
                "Restore the original part finish",function()
                    self:Send({action="SetPaint",
                        scope=if node.kind=="component" then "Component" else "Primitive",
                        id=if node.kind=="component" then node.componentId
                            else entityId(member),paintFinish="Factory"})
                end)
        end
        if self.Tools.PrimaryId=="Edit"
            and self.Build.Mode=="Edit" then
            if node.kind=="component" then
                self:ActionButton("Save to component library",
                    "Register this assembled component as a reusable blueprint",function()
                        self.Build:SetComponentSelection(node.componentId,node.members)
                        self:CloseContext()
                        self.Build:OpenBankSave()
                    end)
            end
            self:ActionButton("Set alignment origin",
                "Author a custom snap origin on selected geometry",function()
                    self:Select(node,true)
                    self:CloseContext()
                    self.Build:EditFitPivot(false)
                end)
            self:ActionButton("Reset alignment origin",
                "Remove the custom origin without changing geometry",function()
                    self:Select(node,true)
                    self:CloseContext()
                    self.Build:EditFitPivot(true)
                end)
        end
        if self.Tools.PrimaryId=="AssemblySimulation" then
            self:ActionButton(
                if member:GetAttribute("Grounded")==true then
                    "Release grounding" else "Ground primitive",
                "Change authored grounding, not the simulated copy",function()
                    if node.kind=="primitive" then
                        self:Send({action="SetGrounded",
                            instanceId=entityId(member)},true)
                    end
                end)
        end
    end
    if node.kind=="component" and self.Tools.PrimaryId=="Mechanics"
        and not simulating() then
        self:Section("Rigid fabrication")
        self:ActionButton("SMART WELD COMPONENT",
            "Join every primitive in this registered component into one rigid body; reuse existing welds and preserve offsets",function()
                self:Send({action="WeldComponent",
                    componentId=node.componentId},true)
            end)
    end
    local related=self:RelevantRelations(node)
    self:Section("Mechanical relationships · "..tostring(#related))
    if #related==0 then
        self:Value("Connections","None")
    end
    for i,relation in ipairs(related) do
        local item=relation
        local other=if node.kind=="component" then
            tostring(relation.name) else
            tostring(relation.name).."  ·  "..
                tostring(relation.second and relation.second.Name
                    or relation.first and relation.first.Name or "Endpoint")
        self:ActionButton(tostring(i)..".  "..other,
            "Open this exact relationship's editable settings",function()
                self.RelationView=item
                self.CurrentPage="relation"
                self:RenderContext()
            end)
    end
    if self.Tools.PrimaryId=="Mechanics"
        and self.Tools.SubtoolId=="Connect" and not simulating()
        and node.kind=="primitive" then
        self:ActionButton("Connect to another part",
            "Use this as the first participant",function()
                self.Mechanics:BeginConnect(member)
                self:CloseContext()
            end)
    end
end

function Panel:RenderRelation(node)
    local rel=node.relation
    if not rel or not rel.Parent then
        self:Value("Connection","Unavailable")
        return
    end
    local kind=tostring(rel:GetAttribute("Kind") or "Connection")
    local isMotor=kind=="Bearing" and rel:GetAttribute("MotorRelationship")==true
    local hasMotor=kind=="Bearing" and
        (isMotor or rel:GetAttribute("MotorEnabled")==true)
    local displayName=if isMotor then "Motor" else kind
    self.Title.Text=string.upper(displayName)

    -- Show the relationship's purpose, not its internal IDs and metadata.
    local other=if self.Selected and self.Selected.model then
        (if node.first==self.Selected.model then node.second
            else node.first) else nil
    if other then
        self:Value("Connected to",other.Name)
    end
    if simulating() and kind~="Spring" then
        self:Value("Editing","Stop simulation to change settings")
        return
    end

    if kind=="Spring" then
        self:Section("Spring")
        local applySpring=function() end
        local function afterDrag()
            if simulating() then applySpring() end
        end
        self:Field("Strength",math.round(rel:GetAttribute("Stiffness") or 120))
        self:RangeSlider("Strength",10,3000,5,true,afterDrag)
        self:Field("Damping",math.round(rel:GetAttribute("Damping") or 14))
        self:RangeSlider("Damping",0,300,1,false,afterDrag)
        self:Field("Length (U)",
            math.round((rel:GetAttribute("FreeLength") or 0.5)/Grid.Unit*10)/10)
        self:RangeSlider("Length (U)",0.25,20,0.25,false,afterDrag)

        local presets=row(self.Properties,36)
        local function preset(title,stiff,damp,index)
            local b=button(presets,title,
                UDim2.new((index-1)/3,1,0,1),
                UDim2.new(1/3,-4,1,-2),function()
                    self.Fields.Strength.Text=tostring(stiff)
                    self.Fields.Damping.Text=tostring(damp)
                end)
            self:Hint(b,"Set spring strength and damping")
        end
        preset("SOFT",85,10,1)
        preset("MEDIUM",480,55,2)
        preset("FIRM",1600,125,3)

        applySpring=function()
            local strength=tonumber(self.Fields.Strength.Text)
            local damping=tonumber(self.Fields.Damping.Text)
            local length=tonumber(self.Fields["Length (U)"].Text)
            if not strength or not damping or not length then
                self:Message("Enter valid spring values")
                return
            end
            local ok=self:Send({action="TuneSpring",relationId=node.id,
                stiffness=strength,damping=damping,
                freeLength=length*Grid.Unit},true)
            if ok then self:Message("Spring saved") end
        end
        self:ActionButton("SAVE","Apply spring settings",function()
            applySpring()
        end)

    elseif kind=="Bearing" or kind=="Slider" or kind=="Cylindrical" then
        local isBearing=kind=="Bearing"
        local limitName=if isBearing then "Limit rotation" else "Limit travel"
        local lowName=if isBearing then "Min angle (°)" else "Min travel (U)"
        local highName=if isBearing then "Max angle (°)" else "Max travel (U)"
        local defaultLow=if isBearing then -180 else -4
        local defaultHigh=if isBearing then 180 else 4
        local initialLimited=rel:GetAttribute("LimitsEnabled")==true

        if hasMotor then
            self:Section("Power")
            self:Switch("Powered",rel:GetAttribute("MotorEnabled")==true,
                "Allow the motor to drive the shaft")

            local driveType=rel:GetAttribute("MotorDriveType") or "Continuous"
            local modeChange=function() end
            self:Segment("Type",{
                {id="Continuous",label="Motor",tip="Keep rotating at a set speed"},
                {id="Servo",label="Servo",tip="Turn to a specified angle"},
            },driveType,function() modeChange() end)
            self:Segment("Control",{
                {id="Hold",label="Hold",tip="Run while the key is down"},
                {id="Toggle",label="Toggle",tip="Press to start, press again to stop"},
            },rel:GetAttribute("MotorInputMode") or "Hold")
            self:KeyPicker("Key",rel:GetAttribute("MotorKey") or "F")

            local savedSpeed=rel:GetAttribute("MotorSpeed") or 3
            self:Field("Speed",math.abs(savedSpeed))
            self:RangeSlider("Speed",0.1,35,0.1,false)
            local reverseRow=self:Switch("Reverse",savedSpeed<0,
                "Change continuous motor rotation direction")

            local angleField=self:Field("Target angle (°)",
                rel:GetAttribute("MotorTargetAngle") or 90)
            local angleRow=angleField.Parent
            local angleSlider=self:RangeSlider("Target angle (°)",-180,180,1,false)

            self:Field("Torque",rel:GetAttribute("MotorTorque") or 3000)
            self:RangeSlider("Torque",1,100000,1,true)

            -- Keep the main motor panel short. Advanced controls preserve
            -- precision and joint limits without showing every value at once.
            local advanced=false
            local accelHeader=self:Section("Fine tuning")
            local acceleration=self:Field("Acceleration",
                rel:GetAttribute("MotorAcceleration") or 40)
            local accelerationSlider=self:RangeSlider(
                "Acceleration",0.1,1000,0.1,true)
            local limitRows={}
            local switchRow=self:Switch(limitName,initialLimited,
                "Restrict the shaft's rotation",function(enabled)
                    for _,item in ipairs(limitRows) do
                        item.Visible=advanced and enabled
                    end
                end)
            local lower=self:Field(lowName,
                rel:GetAttribute("LowerLimit") or defaultLow)
            local upper=self:Field(highName,
                rel:GetAttribute("UpperLimit") or defaultHigh)
            table.insert(limitRows,lower.Parent)
            table.insert(limitRows,upper.Parent)
            -- Reuse the simple switch component without exposing raw limits.
            local advancedButton
            local function visibility()
                local isServo=self.Flags.Type=="Servo"
                angleRow.Visible=isServo
                if angleSlider then angleSlider.Visible=isServo end
                reverseRow.Visible=not isServo
                accelHeader.Visible=advanced
                acceleration.Parent.Visible=advanced and not isServo
                if accelerationSlider then
                    accelerationSlider.Visible=advanced and not isServo
                end
                if switchRow then switchRow.Visible=advanced end
                for _,item in ipairs(limitRows) do
                    item.Visible=advanced and self.Flags[limitName]
                end
            end
            modeChange=visibility
            advancedButton=self:ActionButton("MORE SETTINGS  ▸",
                "Show acceleration and rotation limits",function()
                    advanced=not advanced
                    advancedButton.Text=if advanced then "FEWER SETTINGS  ▾"
                        else "MORE SETTINGS  ▸"
                    visibility()
                end)
            visibility()

            self:ActionButton("SAVE","Apply motor and shaft settings",function()
                local speed=tonumber(self.Fields.Speed.Text)
                local torque=tonumber(self.Fields.Torque.Text)
                local accel=tonumber(self.Fields.Acceleration.Text)
                local angle=tonumber(self.Fields["Target angle (°)"].Text)
                local lowerLimit=tonumber(self.Fields[lowName].Text)
                local upperLimit=tonumber(self.Fields[highName].Text)
                if not speed or not torque or not accel or not angle
                    or not lowerLimit or not upperLimit
                    or lowerLimit>upperLimit then
                    self:Message("Check the numeric settings")
                    return
                end
                local changeLimits=lowerLimit~=(rel:GetAttribute("LowerLimit")
                        or defaultLow)
                    or upperLimit~=(rel:GetAttribute("UpperLimit")
                        or defaultHigh)
                    or self.Flags[limitName]~=initialLimited
                if changeLimits then
                    local ok=self:Send({action="AdjustJoint",
                        relationId=node.id,lowerLimit=lowerLimit,
                        upperLimit=upperLimit,
                        limitsEnabled=self.Flags[limitName]},true)
                    if not ok then
                        self:Message("Check rotation limits")
                        return
                    end
                end
                if not MOTOR_BINDINGS[self.Fields.Key.Text] then
                    self:Message("Choose a motor key first")
                    return
                end
                local signedSpeed=math.abs(speed)
                    *(if self.Flags.Reverse then -1 else 1)
                local ok=self:Send({
                    action="TuneBearingMotor",relationId=node.id,
                    motorEnabled=self.Flags.Powered,
                    motorKey=self.Fields.Key.Text:gsub("%s+",""),
                    motorSpeed=signedSpeed,motorTorque=torque,
                    motorAcceleration=accel,
                    motorDriveType=self.Flags.Type,
                    motorInputMode=self.Flags.Control,
                    motorTargetAngle=angle,
                },true)
                if ok then self:Message("Motor saved") end
            end)
        else
            -- Passive bearings/sliders don't need a disabled motor panel.
            self:Section("Movement")
            local limitRows={}
            self:Switch(limitName,initialLimited,
                "Limit how far this joint can move",function(on)
                    for _,item in ipairs(limitRows) do item.Visible=on end
                end)
            local lower=self:Field(lowName,
                rel:GetAttribute("LowerLimit") or defaultLow)
            local upper=self:Field(highName,
                rel:GetAttribute("UpperLimit") or defaultHigh)
            table.insert(limitRows,lower.Parent)
            table.insert(limitRows,upper.Parent)
            for _,item in ipairs(limitRows) do item.Visible=initialLimited end
            self:ActionButton("SAVE","Save movement settings",function()
                local lowerLimit=tonumber(self.Fields[lowName].Text)
                local upperLimit=tonumber(self.Fields[highName].Text)
                if not lowerLimit or not upperLimit or lowerLimit>upperLimit then
                    self:Message("Enter valid movement limits")
                    return
                end
                local ok=self:Send({action="AdjustJoint",
                    relationId=node.id,lowerLimit=lowerLimit,
                    upperLimit=upperLimit,
                    limitsEnabled=self.Flags[limitName]},true)
                if ok then self:Message("Movement saved") end
            end)
        end
    else
        -- Welds, bolts, fixed joints and transmission links have no
        -- adjustable parameters. Do not dump raw Roblox attributes.
        self:Value("Settings","No settings needed")
    end

    if not simulating() then
        self:ActionButton(
            if self.Removing==node.id then "CONFIRM DELETE CONNECTION"
                else "Delete connection",
            "Only removes the connection; both parts remain",function()
                if self.Removing~=node.id then
                    self.Removing=node.id
                    self:RenderContext()
                    return
                end
                if self:Send({action="RemoveRelation",relationId=node.id},true) then
                    self.RelationView=nil
                    self.CurrentPage=self.RootPage or "relationships"
                    self.Removing=nil
                    self:RenderContext()
                end
            end)
    end
end

function Panel:RenderAssembly(node)
    self:Section("Registered assembly")
    self:Value("Name",node.name)
    self:Value("Primitives",#node.members)
    if self.Tools.PrimaryId=="AssemblySimulation"
        and self.Tools.SubtoolId=="AssemblyEditor"
        and not simulating() then
        self:ActionButton("Edit membership",
            "Open centered assembly editing workflow",function()
                self.AssemblyTool:LoadExisting(node.members[1])
                self:FocusAssemblyName()
            end)
    elseif self.Tools.PrimaryId=="AssemblySimulation"
        and self.Tools.SubtoolId=="Simulation" then
        self:RenderSimulationControls(node)
    end
end

function Panel:RenderRelationshipList(node)
    -- All relationship kinds are discoverable: motors, bearings, slides,
    -- welds, springs, belts, bolts, vector joints and future kinds.
    local related=self:RelevantRelations(node)
    self:Section("Mechanical relationships · "..tostring(#related))
    if #related==0 then
        self:Value("Connections","None on this part")
        return
    end
    for i,entry in ipairs(related) do
        local chosen=entry
        local otherName=if entry.first==node.model then
            entry.second and entry.second.Name
            elseif entry.second==node.model then
            entry.first and entry.first.Name
            else nil
        local caption=tostring(entry.name)
            ..(if otherName then " · "..tostring(otherName) else "")
        self:ActionButton(tostring(i)..".  "..caption,
            "Configure the exact "..tostring(entry.name).." relationship",function()
                if not chosen.relation or not chosen.relation.Parent then
                    self:Message("Connection is no longer available")
                    self:RenderContext()
                    return
                end
                self.RelationView=chosen
                self.CurrentPage="relation"
                self:RenderContext()
            end)
    end
end

function Panel:RenderContext()
    if not self.ContextOpen or not self.Properties then return end
    if self.KeyCapture then
        self.KeyCapture:Disconnect()
        self.KeyCapture=nil
    end
    if self.Tooltip then self.Tooltip.Visible=false end
    clear(self.Properties)
    self.Fields={}
    self.Flags={}
    local node=self.Selected
    self.Back.Visible=self.RelationView~=nil
    if self.RelationView then
        self.Title.Text="CONNECTION SETTINGS"
        self:RenderRelation(self.RelationView)
    elseif not node then
        self.Title.Text="SELECTION"
        self:Value("Object","None")
    elseif self.CurrentPage=="relationships" then
        self.Title.Text="MECHANICAL RELATIONSHIPS"
        self:Value("Part",node.name)
        self:RenderRelationshipList(node)
    else
        self.Title.Text=if node.kind=="component" then "COMPONENT"
            elseif node.kind=="assembly" then "ASSEMBLY"
            else "PRIMITIVE"
        if node.kind=="assembly" then
            self:RenderAssembly(node)
        else
            self:RenderObject(node)
        end
    end
    self:ResizeContext()
end

function Panel:RenderProperties()
    self:RenderContext()
end

function Panel:RenderTree()
    -- No permanent Explorer hierarchy or screen-side Properties panel.
end

function Panel:RunAction(action,node)
    if action=="new-assembly" then
        self.AssemblyTool:BeginNew()
    elseif action=="edit-members" and node.members and node.members[1] then
        self.AssemblyTool:LoadExisting(node.members[1])
        self:FocusAssemblyName()
    elseif action=="run" or action=="stop" then
        self:RunSimulationAction(action,node)
    elseif action=="connect" and node.model then
        self.Mechanics:BeginConnect(node.model)
        self:CloseContext()
    elseif action=="ground" and node.model then
        self:Send({action="SetGrounded",
            instanceId=entityId(node.model)},true)
    end
end

function Panel:Start()
    if self.Started then return end
    self.Started=true
    self.Snapshot=Data.Snapshot(player)
    self:MakeUI()
    table.insert(self.Connections,self.Tools.SubtoolChanged.Event:Connect(function()
        self:CloseConnectionChoice(true)
        self:CloseContext()
        self:OnAssemblyDraftChanged()
        self:OnSimulationSessionChanged()
        if self.Feedback then self.Feedback:Clear("context-selection") end
        -- Appearance is opened with M in the same Build workspace.
        -- No Paint subtool transition or unsolicited context popup.
    end))
    table.insert(self.Connections,UIS.InputBegan:Connect(function(input,processed)
        local key=input.KeyCode
        if key==Enum.KeyCode.Escape then
            if self.ConnectionChoiceOpen then
                self:CloseConnectionChoice(true)
                return
            end
            if self.CreatorOpen then
                self.CreatorOpen=false
                self.Creator.Visible=false
                self.AssemblyTool:Cancel()
                self:OnAssemblyDraftChanged()
                self:Focus(false)
                return
            end
            if self.ContextOpen then self:CloseContext() return end
            if self.Focused and not UIS:GetFocusedTextBox() then
                self:Focus(false)
                return
            end
        end
        if key==Enum.KeyCode.F2 and not processed
            and not UIS:GetFocusedTextBox()
            and not player:GetAttribute("OPENWORKS_PlotMenuOpen")
            and not player:GetAttribute("OPENWORKS_AssemblyNaming")
            and not self.ConnectionChoiceOpen
            and not self.CreatorOpen then
            if self.ContextOpen then
                self:CloseContext()
            elseif not self.Focused then
                if self.AssemblyTool.Stage=="Selecting" then
                    -- The centered assembly toolbar can be clicked while
                    -- selecting members without opening a property window.
                    self:Focus(true)
                elseif self.Selected then
                    self:OpenSelectedContext()
                else self:Focus(true) end
            else self:Focus(false) end
            return
        end
        if input.UserInputType==Enum.UserInputType.MouseButton2
            and not processed and not self.Focused
            and not self.ConnectionChoiceOpen
            and not self.CreatorOpen
            and not UIS:GetFocusedTextBox()
            and not player:GetAttribute("OPENWORKS_CursorUIOpen")
            and not player:GetAttribute("OPENWORKS_PlotMenuOpen")
            and not player:GetAttribute("OPENWORKS_PropertiesOpen") then
            local node=self:SelectWorldAtCenter()
            if node then self:OpenForNode(node,UIS:GetMouseLocation())
            else self:CloseContext() end
        end
    end))
    for _,attribute in ipairs({
        "OPENWORKS_Simulating","OPENWORKS_SimulationPaused",
    }) do
        table.insert(self.Connections,
            player:GetAttributeChangedSignal(attribute):Connect(function()
                self:OnSimulationSessionChanged()
                if not simulating() and self.ContextOpen
                    and not UIS:GetFocusedTextBox() then
                    self:RenderContext()
                end
            end))
    end
    table.insert(self.Connections,RunService.Heartbeat:Connect(function()
        self:Scan(false)
        if self.Status and self.Status.Visible
            and os.clock()>self.StatusUntil then
            self.Status.Visible=false
        end
    end))
    self:OnAssemblyDraftChanged()
    self:OnSimulationSessionChanged()
end

function Panel:Destroy()
    self:CloseConnectionChoice(true)
    self:CloseContext()
    self:Focus(false)
    for _,c in ipairs(self.Connections) do c:Disconnect() end
    table.clear(self.Connections)
    if self.Feedback then self.Feedback:Clear("context-selection") end
    if self.Gui then self.Gui:Destroy() end
end

return Panel
