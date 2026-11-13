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

function Panel:ChooseFit(kind,callback,count)
    local options=ConnectionCatalog.Fit(kind)
    local title=if kind=="Hub" then "GEAR OR PULLEY / SHAFT"
        elseif (count or 0)>1 then
            tostring(count).." OPENINGS / SHAFT"
        else "SHAFT / HOLE"
    return self:ChooseConnection(options,callback,title)
end

function Panel:ChoosePair(first,second,callback)
    local options=ConnectionCatalog.Pair(first,second)
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
        Size=UDim2.fromOffset(370,495),
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
            self.CurrentPage="object"
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
    local node=self:NodeForModel(model,true)
    self:Select(node,true)
    return node
end

function Panel:OpenSelectedContext()
    local node=self.Selected
    if not node then
        self:Message("Select a primitive or component first")
        return
    end
    self:OpenForNode(node,UIS:GetMouseLocation())
end

function Panel:OpenForNode(node,pos)
    if not node then return end
    self:CloseConnectionChoice(true)
    self.Selected=node
    self.RelationView=nil
    self.CurrentPage="object"
    self.Removing=nil
    local viewport=workspace.CurrentCamera and
        workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
    local p=pos or Vector2.new(viewport.X/2,viewport.Y/2)
    self.Surface.Position=UDim2.fromOffset(
        math.clamp(p.X+25,8,math.max(8,viewport.X-378)),
        math.clamp(p.Y-75,8,math.max(8,viewport.Y-510)))
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

function Panel:ActionButton(name,tip,callback)
    local r=row(self.Properties,29)
    local item=button(r,name,UDim2.fromOffset(3,0),
        UDim2.new(1,-7,1,0),callback)
    self:Hint(item,tip)
    return item
end

function Panel:Cycle(name,values,selected)
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
    self:Message(if ok then "Applied" else "Request rejected")
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
    self:Value("Members",#node.members)
    local part=member.PrimaryPart
    if part then
        self:Value("Position (U)",formatVector(member:GetPivot().Position))
        self:Value("Size (U)",formatVector(part.Size))
    end
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
        self:Cycle("Finish",Paint.List(),
            member:GetAttribute("PaintFinish") or "Factory")
        self:Field("Color HEX",member:GetAttribute("PaintColorHex") or "#D61F2C")
        local colors=Paint.Palette()
        local r=row(self.Properties,48)
        for i=1,math.min(9,#colors) do
            local swatch=colors[i]
            local color=Paint.ToColor(swatch.Hex)
            local sw=button(r,"",UDim2.new((i-1)/9,1,0,4),
                UDim2.new(1/9,-3,0,32),function()
                    self.Fields["Color HEX"].Text="#"..swatch.Hex
                end)
            sw.BackgroundColor3=color or Theme.Accent
            self:Hint(sw,swatch.Name)
        end
        self:ActionButton("CONFIRM APPEARANCE",
            "Save changed material and finish via original server actions",function()
                self:ConfirmAppearance(node)
            end)
        self:ActionButton("Restore factory finish",
            "Reset cosmetic finish, leaving physical material intact",function()
                self:Send({action="SetPaint",
                    scope=if node.kind=="component" then "Component" else "Primitive",
                    id=if node.kind=="component" then node.componentId
                        else entityId(member),paintFinish="Factory"})
            end)
        self:ActionButton("Select / resize",
            "Select actual authored geometry in Build",function()
                if self.Tools.PrimaryId=="Edit" then
                    self:Select(node,true)
                    self:CloseContext()
                else self:Message("Equip Edit (hotbar 2) to resize") end
            end)
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
    local related=self:RelevantRelations(node)
    self:Section("Mechanical relationships · "..tostring(#related))
    if #related==0 then
        self:Value("Connections","None")
    end
    for i,relation in ipairs(related) do
        local item=relation
        local raw=relation.relation
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
        self:Value("Relationship","No longer exists") return
    end
    local kind=tostring(rel:GetAttribute("Kind") or "Connection")
    self:Section("Mechanical relationship")
    self:Value("Type",kind)
    self:Value("From",node.first and node.first.Name or "?")
    self:Value("To",node.second and node.second.Name or "?")
    if simulating() then
        self:Value("Status","Read-only during simulation")
        return
    end
    if kind=="Spring" then
        self:Field("Stiffness",rel:GetAttribute("Stiffness") or 120)
        self:Field("Damping",rel:GetAttribute("Damping") or 14)
        self:Field("Rest length (U)",
            (rel:GetAttribute("FreeLength") or 0.5)/Grid.Unit)
        self:ActionButton("CONFIRM",
            "Apply all spring parameters together",function()
                local stiffness=tonumber(self.Fields.Stiffness.Text)
                local damping=tonumber(self.Fields.Damping.Text)
                local length=tonumber(self.Fields["Rest length (U)"].Text)
                if not stiffness or not damping or not length then
                    self:Message("Invalid spring values") return
                end
                self:Send({action="TuneSpring",relationId=node.id,
                    stiffness=stiffness,damping=damping,
                    freeLength=length*Grid.Unit},true)
            end)
    elseif kind=="Bearing" or kind=="Slider" or kind=="Cylindrical" then
        self:Field("Lower limit",rel:GetAttribute("LowerLimit") or -4)
        self:Field("Upper limit",rel:GetAttribute("UpperLimit") or 4)
        self.Flags.Limits=rel:GetAttribute("LimitsEnabled")==true
        local toggle
        toggle=self:ActionButton(
            if self.Flags.Limits then "Limits enabled" else "Limits disabled",
            "Toggle finite travel limits",function()
                self.Flags.Limits=not self.Flags.Limits
                toggle.Text=if self.Flags.Limits then "Limits enabled"
                    else "Limits disabled"
            end)
        if kind=="Bearing" then
            self:Section("Motor")
            self.Flags.Motor=rel:GetAttribute("MotorEnabled")==true
            local motor
            motor=self:ActionButton(
                if self.Flags.Motor then "Motor enabled" else "Motor disabled",
                "Toggle powered bearing",function()
                    self.Flags.Motor=not self.Flags.Motor
                    motor.Text=if self.Flags.Motor then "Motor enabled"
                        else "Motor disabled"
                end)
            self:Field("Motor key",rel:GetAttribute("MotorKey") or "F")
            self:Field("Speed (rad/s)",rel:GetAttribute("MotorSpeed") or 3)
            self:Field("Max torque",rel:GetAttribute("MotorTorque") or 3000)
            self:Field("Acceleration",rel:GetAttribute("MotorAcceleration") or 40)
        end
        self:ActionButton("CONFIRM",
            "Apply joint limits and, when present, motor settings",function()
                local lower=tonumber(self.Fields["Lower limit"].Text)
                local upper=tonumber(self.Fields["Upper limit"].Text)
                if not lower or not upper or lower>upper then
                    self:Message("Invalid joint limits") return
                end
                local changes=lower~=rel:GetAttribute("LowerLimit")
                    or upper~=rel:GetAttribute("UpperLimit")
                    or self.Flags.Limits~=(rel:GetAttribute("LimitsEnabled")==true)
                local motorPayload
                if kind=="Bearing" then
                    local speed=tonumber(self.Fields["Speed (rad/s)"].Text)
                    local torque=tonumber(self.Fields["Max torque"].Text)
                    local accel=tonumber(self.Fields.Acceleration.Text)
                    if not speed or not torque or not accel then
                        self:Message("Invalid motor values") return
                    end
                    motorPayload={action="TuneBearingMotor",relationId=node.id,
                        motorEnabled=self.Flags.Motor,
                        motorKey=self.Fields["Motor key"].Text:gsub("%s+",""),
                        motorSpeed=speed,motorTorque=torque,
                        motorAcceleration=accel}
                end
                if changes and not self:Send({action="AdjustJoint",
                    relationId=node.id,lowerLimit=lower,upperLimit=upper,
                    limitsEnabled=self.Flags.Limits},true) then return end
                if motorPayload then
                    if not self:Send(motorPayload,true) then
                        self:Message("Limits may have saved; motor rejected")
                        return
                    end
                end
                self:Message("Connection confirmed")
            end)
    else
        self:Value("Settings","No configurable parameters")
    end
    -- Keep non-editable relationship metadata available in the same
    -- contextual inspector, including gear and rigid coupling attributes.
    -- A property is only offered for editing if an existing server action
    -- validates that field; arbitrary attributes are never written.
    self:Section("Other relationship properties")
    local attributes=rel:GetAttributes()
    local names={}
    for name in pairs(attributes) do
        if name~="OwnerUserId" and name~="RelationId"
            and name~="SourceId" and name~="TargetId"
            and name~="SecondTargetId" and name~="Kind" then
            table.insert(names,name)
        end
    end
    table.sort(names)
    for _,name in ipairs(names) do
        local value=attributes[name]
        if typeof(value)=="Vector3" then
            value=string.format("%.2f / %.2f / %.2f",
                value.X,value.Y,value.Z)
        else value=tostring(value) end
        self:Value(name,value)
    end
    self:ActionButton(
        if self.Removing==node.id then "CONFIRM REMOVE RELATIONSHIP"
            else "Remove relationship",
        "Removes the joint, not its physical primitives",function()
            if self.Removing~=node.id then
                self.Removing=node.id
                self:RenderContext()
                return
            end
            if self:Send({action="RemoveRelation",relationId=node.id},true) then
                self.RelationView=nil
                self.CurrentPage="object"
                self.Removing=nil
                self:RenderContext()
            end
        end)
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

function Panel:RenderContext()
    if not self.ContextOpen or not self.Properties then return end
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
