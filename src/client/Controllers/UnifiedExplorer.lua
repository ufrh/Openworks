--!strict
-- UI v2 / Phase 3: one docked Explorer and Properties surface.
-- Tab unlocks the pointer to use the dock; RMB over an authored object
-- opens its contextual menu. No instructions are painted into the world.
-- All mutations go through existing authoritative server request actions.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Data=require(script.Parent:WaitForChild("ExplorerData"))
local Actions=require(script.Parent:WaitForChild("ContextActionRegistry"))
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
        Connections={},Selected=nil,SelectedKey=nil,View="Objects",
        Snapshot=nil,Signature="",Expanded={},
        Fields={},Flags={},Focused=false,MenuOpen=false,
        ConnectionChoiceOpen=false,ChoiceCallback=nil,ChoiceWasFocused=false,
        MenuRestoreFocus=false,StatusUntil=0,LastScan=0,
        Busy=false,Started=false,
        DraftSignature="",SessionSignature="",Telemetry=nil,TelemetrySeed=nil,
    },Panel)
end

function Panel:Hint(control,description)
    if not control then return end
    control.MouseEnter:Connect(function()
        if not self.Gui or not self.Gui.Parent then return end
        local cursor=UIS:GetMouseLocation()
        local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
            or Vector2.new(1280,720)
        self.Tooltip.Text=description
        self.Tooltip.Size=UDim2.fromOffset(268,45)
        self.Tooltip.Position=UDim2.fromOffset(
            math.clamp(cursor.X-275,5,math.max(5,viewport.X-275)),
            math.clamp(cursor.Y+13,5,math.max(5,viewport.Y-53)))
        self.Tooltip.Visible=true
    end)
    control.MouseLeave:Connect(function()
        if self.Tooltip then self.Tooltip.Visible=false end
    end)
end

function Panel:Focus(value)
    self.Focused=value==true
    player:SetAttribute("OPENWORKS_ExplorerOpen",
        self.Focused or self.MenuOpen or self.ConnectionChoiceOpen)
    if self.Focused or self.MenuOpen then
        UIS.MouseBehavior=Enum.MouseBehavior.Default
        UIS.MouseIconEnabled=true
    else
        UIS.MouseBehavior=Enum.MouseBehavior.LockCenter
        UIS.MouseIconEnabled=false
    end
    if self.FocusButton then
        self.FocusButton.Text=if self.Focused then "LOCK" else "OPEN"
    end
    if self.Crosshair then
        self.Crosshair.Visible=not self.Focused and not self.MenuOpen
            and not self.ConnectionChoiceOpen
            and (self.Tools.PrimaryId=="Mechanics"
                or self.Tools.PrimaryId=="AssemblySimulation")
    end
    -- Keep Build's legacy crosshair and catalog pointer state synchronized
    -- when this shared panel or a connection picker claims cursor focus.
    if self.Build and self.Build.Gui then self.Build:RefreshPointer() end
end

function Panel:CloseMenu()
    if not self.MenuOpen then return end
    self.MenuOpen=false
    self.Menu.Visible=false
    self.Tooltip.Visible=false
    self:Focus(self.MenuRestoreFocus)
end

-- One compact connection picker shared by Build's smart fit and
-- Mechanics' two-part Connect operation. All choices are click-driven;
-- no number keys, no duplicate fixed/weld entry paths.
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
    self.ConnectionChoice.Visible=true
    self:Focus(true)
    return true
end

function Panel:ChooseFit(kind,callback,count)
    local options=ConnectionCatalog.Fit(kind)
    local title=if kind=="Hub" then "GEAR / SHAFT"
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
    self.Status.Text=tostring(message)
    self.StatusUntil=os.clock()+3.2
end

function Panel:MakeUI()
    local gui=mk("ScreenGui",player:WaitForChild("PlayerGui"),{
        Name="OPENWORKS_UnifiedExplorerProperties",
        IgnoreGuiInset=true,ResetOnSpawn=false,
        DisplayOrder=93,Enabled=true,
    })
    self.Gui=gui
    self.Crosshair=mk("TextLabel",gui,{
        Name="SharedConnectCrosshair",Text="+",
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(20,20),
        BackgroundTransparency=1,
        TextColor3=Theme.Text,TextSize=21,
        Font=Enum.Font.GothamMedium,
        TextXAlignment=Enum.TextXAlignment.Center,
        TextYAlignment=Enum.TextYAlignment.Center,
        Visible=false,ZIndex=4,
    })
    local main=style(mk("Frame",gui,{
        Name="UnifiedExplorerProperties",
        AnchorPoint=Vector2.new(1,0),
        Position=UDim2.new(1,-12,0,53),
        Size=UDim2.new(0,352,1,-67),
        BackgroundColor3=Theme.Window,ZIndex=10,
    }),Theme.Window)
    self.Main=main
    label(main,"OPENWORKS",UDim2.fromOffset(11,7),UDim2.new(1,-100,0,28))
    self.FocusButton=button(main,"OPEN",UDim2.new(1,-66,0,8),
        UDim2.fromOffset(55,26),function()
            self:CloseMenu()
            self:Focus(not self.Focused)
        end)
    self.NewAssemblyButton=button(main,"+ NEW",UDim2.new(1,-133,0,8),
        UDim2.fromOffset(60,26),function()
            if self.Tools.PrimaryId=="AssemblySimulation"
                and self.Tools.SubtoolId=="AssemblyEditor"
                and not simulating() then
                self.AssemblyTool:BeginNew()
            end
        end)
    self.NewAssemblyButton.Visible=false
    self:Hint(self.NewAssemblyButton,"Create and name an assembly in Properties")
    self:Hint(self.FocusButton,"Tab · Unlock the cursor to inspect and edit the workspace")
    self.TabObjects=button(main,"OBJECTS",UDim2.fromOffset(10,43),
        UDim2.new(0.5,-15,0,27),function()
            self.View="Objects"
            self:RenderTree()
        end)
    self.TabConnections=button(main,"CONNECTIONS",UDim2.new(0.5,3,0,43),
        UDim2.new(0.5,-13,0,27),function()
            self.View="Connections"
            self:RenderTree()
        end)
    self:Hint(self.TabObjects,"Browse registered assemblies, components and individual primitives")
    self:Hint(self.TabConnections,"Browse actual mechanical relationships without creating fake hierarchy")
    self.Search=style(mk("TextBox",main,{
        Name="ExplorerSearch",PlaceholderText="Search...",
        ClearTextOnFocus=false,Text="",TextSize=12,
        Font=Enum.Font.Gotham,TextColor3=Theme.Text,
        PlaceholderColor3=Theme.Muted,
        BackgroundColor3=Theme.Input,
        Size=UDim2.new(1,-20,0,29),Position=UDim2.fromOffset(10,76),
        ZIndex=12,
    }),Theme.Input)
    self.Search:GetPropertyChangedSignal("Text"):Connect(function()
        self:RenderTree()
    end)
    self.Tree=mk("ScrollingFrame",main,{
        Name="ObjectsOrConnections",
        BackgroundTransparency=1,BorderSizePixel=0,
        Position=UDim2.fromOffset(10,113),
        Size=UDim2.new(1,-20,0.40,-113),
        ScrollBarThickness=4,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,
        CanvasSize=UDim2.fromOffset(0,0),
        ZIndex=11,
    })
    list(self.Tree)
    label(main,"PROPERTIES",UDim2.new(0,11,0.40,8),
        UDim2.new(1,-22,0,24),Theme.Text)
    self.Properties=mk("ScrollingFrame",main,{
        Name="PropertyGrid",BackgroundTransparency=1,
        BorderSizePixel=0,Position=UDim2.new(0,10,0.40,39),
        Size=UDim2.new(1,-20,0.60,-79),
        ScrollBarThickness=4,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,
        CanvasSize=UDim2.fromOffset(0,0),ZIndex=11,
    })
    list(self.Properties)
    self.Status=label(main,"",UDim2.new(0,11,1,-31),
        UDim2.new(1,-22,0,24),Theme.Muted)
    self.Menu=style(mk("Frame",gui,{
        Name="ContextActions",Visible=false,
        BackgroundColor3=Theme.Window,
        Size=UDim2.fromOffset(215,160),
        ZIndex=30,
    }),Theme.Window)
    self.Tooltip=style(mk("TextLabel",gui,{
        Name="HoverTooltip",Text="",Visible=false,
        BackgroundColor3=Theme.Panel,
        Size=UDim2.fromOffset(268,45),
        TextColor3=Theme.Text,
        TextSize=11,TextWrapped=true,
        Font=Enum.Font.Gotham,
        ZIndex=60,
    }),Theme.Panel)
    self.Menu.Visible=false
    local choice=style(mk("Frame",gui,{
        Name="UnifiedConnectionChoice",Visible=false,
        BackgroundColor3=Theme.Window,Size=UDim2.fromOffset(268,280),
        Position=UDim2.new(1,-636,0,115),ZIndex=40,
    }),Theme.Window)
    self.ConnectionChoice=choice
    self.ConnectionChoiceHeading=label(choice,"CONNECTION",
        UDim2.fromOffset(10,8),UDim2.new(1,-46,0,26))
    self.ConnectionChoiceHeading.ZIndex=41
    self.ConnectionChoices=mk("ScrollingFrame",choice,{
        Name="CompatibleConnections",Position=UDim2.fromOffset(8,40),
        Size=UDim2.new(1,-16,1,-84),
        ScrollBarThickness=3,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,
        CanvasSize=UDim2.fromOffset(0,0),
        BackgroundTransparency=1,ZIndex=41,
    })
    list(self.ConnectionChoices)
    self.ConnectionCancel=button(choice,"CANCEL",
        UDim2.new(0,8,1,-38),UDim2.new(1,-16,0,30),function()
            self:CloseConnectionChoice(true)
        end)
    self.ConnectionCancel.ZIndex=43
    self:Hint(self.ConnectionCancel,"Cancel without changing any authored connection")
    self:Focus(false)
    self:RenderTree()
    self:RenderProperties()
end

function Panel:FindNode(key)
    if not key or not self.Snapshot then return nil end
    if key:sub(1,16)=="whole-component:" then
        local cid=key:sub(17)
        local members={}
        for _,model in ipairs(self.Snapshot.models) do
            if model:GetAttribute("ComponentId")==cid then
                table.insert(members,model)
            end
        end
        if #members>0 then
            return {kind="component",key=key,componentId=cid,
                id=cid,name="Component "..cid:sub(1,8).." (all)",
                members=members,totalMembers=#members,
                partialComponent=false,wholeComponent=true}
        end
        return nil
    end
    for _,a in ipairs(self.Snapshot.assemblies) do
        if a.key==key then return a end
        for _,c in ipairs(a.children) do
            if c.key==key then return c end
            for _,p in ipairs(c.children or {}) do
                if p.key==key then return p end
            end
        end
    end
    for _,r in ipairs(self.Snapshot.relations) do
        if r.key==key then return r end
    end
    return nil
end

function Panel:OnConstructionSelection()
    if self.ApplyingSelection or self.Tools.PrimaryId~="Build" then return end
    local built=self.Build
    local node
    if built.SelectedComponentId then
        local cid=built.SelectedComponentId
        for _,a in ipairs(self.Snapshot and self.Snapshot.assemblies or {}) do
            for _,c in ipairs(a.children) do
                if c.kind=="component" and c.componentId==cid
                    and not c.partialComponent then
                    node=c break
                end
            end
            if node then break end
        end
        if not node then
            -- The world editor selected a FULL component whose primitives
            -- cross assembly boundaries. Do not silently narrow it to the
            -- first assembly's partial component entry.
            node=self:FindNode("whole-component:"..cid)
        end
    elseif built.Selected and own(built.Selected) then
        node=self:NodeForModel(built.Selected)
    elseif #built.SelectedParts>1 then
        node={kind="multi",key="multi",name="Multiple primitives",
            members=table.clone(built.SelectedParts)}
    end
    self:Select(node,false)
end

function Panel:NodeForModel(model)
    if not own(model) then return nil end
    local id=entityId(model)
    local found=self:FindNode("p:"..tostring(id))
    return found or {kind="primitive",key="p:"..tostring(id),
        id=id,name=model.Name,model=model,members={model}}
end

function Panel:Select(node,propagate)
    if node and node.kind=="primitive" and not own(node.model) then return end
    self.Selected=node
    self.SelectedKey=node and node.key or nil
    self.Flags={}
    if self.Feedback then
        self.Feedback:Clear("explorer-selection")
        if node and (self.Tools.PrimaryId~="Build"
            or self.Tools.SubtoolId~="Edit" or node.partialComponent
            or node.kind=="assembly" or node.kind=="relation") then
            local members={}
            local activeRoot
            if simulating() then
                local simulations=workspace:FindFirstChild("OPENWORKS_Simulated")
                activeRoot=simulations and simulations:FindFirstChild(
                    "Simulation_"..tostring(player.UserId))
            end
            local simulatedById={}
            if activeRoot then
                for _,candidate in ipairs(activeRoot:GetChildren()) do
                    local id=entityId(candidate)
                    if type(id)=="string" then simulatedById[id]=candidate end
                end
            end
            for _,m in ipairs(node.members or {}) do
                if own(m) then
                    local visible=if activeRoot then simulatedById[entityId(m)]
                        else m
                    if visible and visible.PrimaryPart then
                        table.insert(members,visible)
                    end
                end
            end
            if #members>0 and node.kind~="unassigned" then
                if node.kind=="relation" or node.kind=="multi" then
                    for i,member in ipairs(members) do
                        self.Feedback:Set("explorer-selection",
                            tostring(i),{member},"selection",false)
                    end
                else
                    if node.kind=="component" and #members>1 then
                        local anchor=ComponentGeometry.CentralPrimitive(members)
                        if anchor then
                            local ordered={anchor}
                            for _,m in ipairs(members) do
                                if m~=anchor then table.insert(ordered,m) end
                            end
                            members=ordered
                        end
                    end
                    self.Feedback:Set("explorer-selection","active",
                        members,if node.kind=="assembly" then "assembly"
                            else "selection",#members>1)
                end
            end
        end
    end
    if propagate and node and self.Tools.PrimaryId=="Build"
        and self.Tools.SubtoolId=="Edit" then
        self.ApplyingSelection=true
        if node.kind=="primitive" then
            self.Build:SetSelection(node.model)
        elseif node.kind=="component" then
            if node.partialComponent then
                -- A partial assembly slice is READ-ONLY as a component
                -- selection. The Build editor's component actions operate
                -- on the entire ComponentId, so do not select a fragment.
                self.Build:SetSelection(nil)
            else
                self.Build:SetComponentSelection(node.componentId,node.members)
            end
        end
        self.ApplyingSelection=false
    elseif propagate and node and node.kind=="primitive"
        and self.Tools.PrimaryId=="Mechanics"
        and self.Tools.SubtoolId=="Connect"
        and not self.ConnectionChoiceOpen then
        -- Explorer and 3D clicks participate in the EXACT same pair draft.
        -- The controller validates ownership before accepting either part.
        self.Mechanics:PickConnectPart(node.model)
    end
    self:RenderProperties()
    self:RenderTree()
end

function Panel:SelectWorldAtCenter()
    local camera=workspace.CurrentCamera
    local root=workspace:FindFirstChild(Config.FolderName)
    local simulationRoot
    if simulating() then
        local simulations=workspace:FindFirstChild("OPENWORKS_Simulated")
        simulationRoot=simulations and simulations:FindFirstChild(
            "Simulation_"..tostring(player.UserId))
    end
    local castRoot=simulationRoot or root
    if not camera or not castRoot then return nil end
    local ray=camera:ViewportPointToRay(
        camera.ViewportSize.X*0.5,camera.ViewportSize.Y*0.5)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={castRoot}
    params.IgnoreWater=true
    local hit=workspace:Raycast(ray.Origin,ray.Direction*Grid.MaxDistance,params)
    if not hit then return nil end
    local model=hit.Instance
    while model and model.Parent~=castRoot do model=model.Parent end
    if not own(model) then return nil end
    if simulationRoot then
        model=self.Snapshot and self.Snapshot.byId[entityId(model)]
        if not own(model) then return nil end
    end
    local node=self:NodeForModel(model)
    self:Select(node,false)
    return node
end

function Panel:CreateTreeRow(node,depth,expandable,force)
    local search=self.Search.Text:lower()
    if not force and search~="" and not node.name:lower():find(search,1,true)
        and not tostring(node.id or ""):lower():find(search,1,true) then
        return
    end
    local line=row(self.Tree,27)
    local x=math.min(depth*13,42)
    local expanded=self.Expanded[node.key]~=false
    if expandable then
        local toggle=button(line,if expanded then "⌄" else "›",
            UDim2.fromOffset(x,0),UDim2.fromOffset(22,25),function()
                self.Expanded[node.key]=not expanded
                self:RenderTree()
            end)
        self:Hint(toggle,if expanded then "Collapse" else "Expand")
    end
    local left=x+(if expandable then 24 else 14)
    local selected=self.SelectedKey==node.key
    local name=if node.kind=="assembly" then "◈  "..node.name
        elseif node.kind=="component" then "▣  "..node.name
        elseif node.kind=="relation" then "⌁  "..node.name
        elseif node.kind=="unassigned" then "◇  "..node.name
        else "□  "..node.name
    local select=button(line,name,UDim2.fromOffset(left,0),
        UDim2.new(1,-left-29,0,25),function()
            self:Select(node,true)
        end)
    select.TextXAlignment=Enum.TextXAlignment.Left
    select.BackgroundColor3=if selected then Theme.Active else Theme.Panel
    self:Hint(select,node.kind=="relation"
        and "Inspect this mechanical connection and its physical endpoints"
        or "Select "..node.name)
    local menu=button(line,"⋯",UDim2.new(1,-27,0,0),
        UDim2.fromOffset(26,25),function()
            self:Select(node,true)
            if self.ConnectionChoiceOpen then return end
            local mouse=UIS:GetMouseLocation()
            self:OpenMenu(node,mouse)
        end)
    self:Hint(menu,"Actions available for this object in the current tool")
end

function Panel:RenderTree()
    if not self.Tree or not self.Snapshot then return end
    if self.Tooltip then self.Tooltip.Visible=false end
    clear(self.Tree)
    local search=self.Search.Text:lower()
    self.TabObjects.BackgroundColor3=if self.View=="Objects" then Theme.Active else Theme.Raised
    self.TabConnections.BackgroundColor3=if self.View=="Connections" then Theme.Active else Theme.Raised
    if self.View=="Connections" then
        for _,relation in ipairs(self.Snapshot.relations) do
            local source=relation.first and relation.first.Name or "?"
            local target=relation.second and relation.second.Name or "?"
            local text=relation.name.." · "..source.." / "..target
            if search=="" or text:lower():find(search,1,true)
                or relation.id:lower():find(search,1,true) then
                local shown=table.clone(relation)
                shown.name=text
                self:CreateTreeRow(shown,0,false)
            end
        end
    else
        for _,a in ipairs(self.Snapshot.assemblies) do
            local parentMatch=search~="" and (
                a.name:lower():find(search,1,true)~=nil
                or a.id:lower():find(search,1,true)~=nil)
            local anyMatch=search=="" or parentMatch
            for _,c in ipairs(a.children) do
                if c.name:lower():find(search,1,true) then anyMatch=true end
                for _,p in ipairs(c.children or {}) do
                    if p.name:lower():find(search,1,true) then anyMatch=true end
                end
                if c.kind=="primitive"
                    and c.name:lower():find(search,1,true) then anyMatch=true end
            end
            if anyMatch then
                local header=table.clone(a)
                if search~="" then
                    -- Temporarily bypass the row's own filter when a child
                    -- matched the search rather than the assembly name.
                    header.name=a.name
                end
                self:CreateTreeRow(header,0,true,true)
                if self.Expanded[a.key]~=false or search~="" then
                    for _,c in ipairs(a.children) do
                        if c.kind=="component" then
                            local contains=search=="" or parentMatch
                                or c.name:lower():find(search,1,true)~=nil
                            for _,p in ipairs(c.children) do
                                if p.name:lower():find(search,1,true) then
                                    contains=true
                                end
                            end
                            if contains then
                                self:CreateTreeRow(c,1,true,true)
                                if self.Expanded[c.key]~=false or search~="" then
                                    for _,p in ipairs(c.children) do
                                        if search=="" or parentMatch
                                            or c.name:lower():find(search,1,true)
                                            or p.name:lower():find(search,1,true) then
                                            self:CreateTreeRow(p,2,false,true)
                                        end
                                    end
                                end
                            end
                        elseif search=="" or parentMatch
                            or c.name:lower():find(search,1,true) then
                            self:CreateTreeRow(c,1,false,true)
                        end
                    end
                end
            end
        end
    end
end

-- One explicit draft transaction in the shared Properties pane. This is
-- client-only until the existing AssemblyTool:Confirm call validates and
-- submits the complete member set. Partial components never imply a weld.
function Panel:ApplyDraftName()
    local draft=self.AssemblyTool
    if draft.Stage~="Selecting" then return true end
    local field=self.Fields["Draft name"]
    local candidate=if field and field.Parent then field.Text else draft.Name
    local name=tostring(candidate or ""):match("^%s*(.-)%s*$")
    if not name or #name==0 or #name>48 or name:find("[%c]") then
        self:Message("Assembly name must contain 1–48 valid characters")
        return false
    end
    draft.Name=name
    return true
end

function Panel:FocusAssemblyName()
    if not self.Properties then return end
    self:RenderProperties()
    local field=self.Fields["Draft name"]
    if field then
        self:Focus(true)
        task.defer(function()
            if field.Parent and self.AssemblyTool.Stage=="Selecting" then
                field:CaptureFocus()
            end
        end)
    end
end

function Panel:OnAssemblyDraftChanged()
    if not self.Properties then return end
    local draft=self.AssemblyTool
    local ids={}
    for id in pairs(draft.Selected or {}) do table.insert(ids,id) end
    table.sort(ids)
    local signature=table.concat({
        tostring(draft.Stage),tostring(draft.EditingId or ""),
        tostring(draft.Name or ""),table.concat(ids,","),
    },"|")
    if signature==self.DraftSignature then return end
    self.DraftSignature=signature
    if not UIS:GetFocusedTextBox() then self:RenderProperties() end
end

function Panel:RenderAssemblyDraft(node)
    local draft=self.AssemblyTool
    self:Section("Assembly editor")
    if draft.Stage~="Selecting" then
        self:ActionButton("Create assembly",
            "Start a named assembly and select its physical members",function()
                draft:BeginNew()
            end)
        return
    end
    local count=0
    for _ in pairs(draft.Selected) do count+=1 end
    self:Value("Mode",if draft.EditingId then "Editing saved assembly"
        else "Creating assembly")
    local nameField=self:Field("Draft name",draft.Name)
    nameField:GetPropertyChangedSignal("Text"):Connect(function()
        -- Preserve in-progress typing if the user selects another object
        -- before committing the assembly draft.
        if draft.Stage=="Selecting" then
            draft.Name=nameField.Text
        end
    end)
    self:Value("Selected primitives",count)
    if node and (node.kind=="primitive" or node.kind=="component")
        and node.members and #node.members>0
        and not node.partialComponent then
        local member=node.members[1]
        local id=entityId(member)
        local selected=id and draft.Selected[id]==true
        self:ActionButton(
            if selected then "Remove from draft" else "Add to draft",
            if node.kind=="primitive" then
                "Toggle this individual primitive only"
            else "Toggle every primitive in the complete editor component",
            function()
                draft:ToggleMember(member,node.kind=="primitive")
                self:OnAssemblyDraftChanged()
            end)
    end
    self:ActionButton(
        if draft.EditingId then "Save assembly changes" else "Create assembly",
        "Confirm exact named membership through the existing server API",function()
            draft:Confirm()
            self:Scan(true)
        end)
    self:ActionButton("Discard draft",
        "Discard uncommitted assembly membership and name",function()
            draft:Cancel()
            self:OnAssemblyDraftChanged()
        end)
end

function Panel:OnSimulationSessionChanged()
    if not self.Properties then return end
    local signature=table.concat({
        tostring(simulating()),
        tostring(player:GetAttribute("OPENWORKS_SimulationPaused")==true),
        tostring(self.Mechanics.SimSeedId or ""),
        tostring(self.Mechanics.SimAssemblyId or ""),
        tostring(self.Tools.PrimaryId or ""),
        tostring(self.Tools.SubtoolId or ""),
    },"|")
    if signature==self.SessionSignature then return end
    self.SessionSignature=signature
    if not UIS:GetFocusedTextBox() then self:RenderProperties() end
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

function Panel:Appearance(node)
    if self.Tools.PrimaryId~="Build"
        or self.Tools.SubtoolId~="Paint" or simulating() then return end
    self:Section("Appearance")
    local model=node.model or node.members[1]
    local scope=if node.kind=="component" then "Component" else "Primitive"
    local id=if scope=="Component" then node.componentId else node.id
    if not model or not id then return end
    self:Cycle("Material",Materials.List(),
        model:GetAttribute("ConstructionMaterial") or "Steel")
    self:ActionButton("Apply material","Update real density, traction and restitution",function()
        self:Send({action="SetMaterial",scope=scope,id=id,
            materialId=self.Flags.Material})
    end)
    self:Cycle("Finish",Paint.List(),
        model:GetAttribute("PaintFinish") or "Factory")
    self:Field("Color HEX",model:GetAttribute("PaintColorHex") or "#D61F2C")
    self:ActionButton("Apply paint","Change surface appearance without changing physical properties",function()
        local finish=self.Flags.Finish
        local hex=Paint.NormalizeHex(self.Fields["Color HEX"].Text)
        if finish~="Factory" and not hex then
            self:Message("Invalid HEX color")
            return
        end
        self:Send({action="SetPaint",scope=scope,id=id,
            paintFinish=finish,paintColorHex=if finish=="Factory" then nil else hex})
    end)
    local swatches=Paint.Palette()
    local r=row(self.Properties,54)
    for i=1,math.min(9,#swatches) do
        local swatch=swatches[i]
        local color=Paint.ToColor(swatch.Hex) or Theme.Accent
        local column=(i-1)%9
        local square=button(r,"",UDim2.new(column/9,2,0,5),
            UDim2.new(1/9,-4,0,36),function()
                self.Fields["Color HEX"].Text="#"..swatch.Hex
            end)
        square.BackgroundColor3=color
        self:Hint(square,swatch.Name.." · #"..swatch.Hex)
    end
    self:ActionButton("Restore factory finish","Remove custom paint and restore the physical material appearance",function()
        self:Send({action="SetPaint",scope=scope,id=id,
            paintFinish="Factory",paintColorHex=nil})
    end)
end

function Panel:Geometry(node)
    local model=node.model or node.members and node.members[1]
    if node.kind=="component" and node.members and #node.members>0 then
        model=ComponentGeometry.CentralPrimitive(node.members) or model
    end
    if not model then return end
    self:Section("Geometry")
    self:Value("Object",node.name)
    self:Value("Members",#(node.members or {}))
    if model.PrimaryPart then
        self:Value("Position (U)",formatVector(model:GetPivot().Position))
        self:Value(if node.kind=="component" then "Anchor size (U)"
            else "Size (U)",formatVector(model.PrimaryPart.Size))
    end
    if node.kind=="component" then
        local total=#self.Build:ComponentMembers(node.componentId)
        if total>#node.members then
            self:Value("Whole component",total)
        end
    end
    self:Value("Material",model:GetAttribute("ConstructionMaterial") or "Steel")
    self:Value("Finish",model:GetAttribute("PaintFinish") or "Factory")
    local assembly=model:GetAttribute("AssemblyName")
    if type(assembly)=="string" and assembly~="" then
        self:Value("Assembly",assembly)
    end
    if node.partialComponent then
        self:Value("Scope","Partial component · select individual primitives to edit")
    else
        self:Appearance(node)
    end
    -- A part can participate in many independent relationships. Show the
    -- actual saved relation endpoints, never inferred parent/child joints.
    local included={}
    for _,member in ipairs(node.members or {}) do
        local id=entityId(member)
        if type(id)=="string" then included[id]=true end
    end
    local connected={}
    for _,relation in ipairs(self.Snapshot and self.Snapshot.relations or {}) do
        local raw=relation.relation
        if included[raw:GetAttribute("SourceId")]
            or included[raw:GetAttribute("TargetId")]
            or included[raw:GetAttribute("SecondTargetId")] then
            table.insert(connected,relation)
        end
    end
    if #connected>0 then
        self:Section("Connections")
        for i,relation in ipairs(connected) do
            if i>12 then break end
            local shown=relation
            self:ActionButton(relation.name,
                "Inspect "..relation.name.." and its real endpoints",function()
                    self.View="Connections"
                    self:Select(shown,false)
                    self:Focus(true)
                end)
        end
        if #connected>12 then
            self:Value("More",#connected-12)
        end
    end
    if self.Tools.PrimaryId=="Mechanics"
        and self.Tools.SubtoolId=="Connect"
        and not simulating() and node.kind=="primitive" then
        self:ActionButton("Connect","Select this as the first mechanical participant",function()
            self:RunAction("connect",node)
        end)
    end
    if self.Tools.PrimaryId=="Build" and not simulating()
        and node.kind=="primitive" then
        self:ActionButton("Resize","Show face handles for this exact primitive [V]",function()
            self:RunAction("resize",node)
        end)
    end
    if self.Tools.PrimaryId=="AssemblySimulation"
        and not simulating() and node.kind=="primitive" then
        self:ActionButton(
            if model:GetAttribute("Grounded")==true then "Release ground" else "Ground",
            "Change whether this authored body is fixed in space",function()
                self:RunAction("ground",node)
            end)
    end
end

function Panel:AssemblyProperties(node)
    self:Section("Assembly")
    self:Value("Members",#node.members)
    local grounded=0
    for _,m in ipairs(node.members) do
        if m:GetAttribute("Grounded")==true then grounded+=1 end
    end
    self:Value("Grounded",grounded)
    if self.Tools.PrimaryId=="AssemblySimulation"
        and self.Tools.SubtoolId=="AssemblyEditor" and not simulating()
        and self.AssemblyTool.Stage~="Selecting" then
        self:Field("Name",node.name)
        self:ActionButton("Save name","Rename without changing the member IDs",function()
            local name=self.Fields.Name.Text:match("^%s*(.-)%s*$")
            if not name or name=="" or #name>48 or name:find("[%c]") then
                self:Message("Invalid assembly name")
                return
            end
            local ids={}
            for _,m in ipairs(node.members) do
                local id=entityId(m)
                if type(id)=="string" then table.insert(ids,id) end
            end
            table.sort(ids)
            self:Send({action="UpdateAssembly",assemblyId=node.id,
                name=name,memberIds=ids},false)
        end)
        self:ActionButton("Edit members","Edit exactly the registered set",function()
            self:RunAction("edit-members",node)
        end)
    end
end

function Panel:RelationshipProperties(node)
    local relation=node.relation
    if not relation or not relation.Parent then return end
    self:Section("Connection")
    local kind=tostring(relation:GetAttribute("Kind") or "Connection")
    self:Value("Type",kind)
    self:Value("Source",node.first and node.first.Name or "Unavailable")
    self:Value("Target",node.second and node.second.Name or "Unavailable")
    local canEdit=self.Tools.PrimaryId=="Mechanics"
        and self.Tools.SubtoolId=="Configure" and not simulating()
    if not canEdit then return end
    if kind=="Spring" then
        self:Field("Stiffness",relation:GetAttribute("Stiffness") or 120)
        self:Field("Damping",relation:GetAttribute("Damping") or 14)
        self:Field("Rest length (U)",
            (relation:GetAttribute("FreeLength") or 0.5)/Grid.Unit)
        self:ActionButton("Apply spring","Set spring stiffness, damping and free length",function()
            local st=tonumber(self.Fields.Stiffness.Text)
            local damping=tonumber(self.Fields.Damping.Text)
            local length=tonumber(self.Fields["Rest length (U)"].Text)
            if not st or not damping or not length then
                self:Message("Invalid spring values") return
            end
            self:Send({action="TuneSpring",relationId=node.id,
                stiffness=st,damping=damping,freeLength=length*Grid.Unit},true)
        end)
    elseif kind=="Bearing" or kind=="Slider" or kind=="Cylindrical" then
        self:Field("Lower limit",relation:GetAttribute("LowerLimit") or -4)
        self:Field("Upper limit",relation:GetAttribute("UpperLimit") or 4)
        self.Flags.Limits=relation:GetAttribute("LimitsEnabled")==true
        local toggle
        toggle=self:ActionButton(
            if self.Flags.Limits then "Limits: enabled" else "Limits: disabled",
            "Toggle mechanical motion limits",function()
                self.Flags.Limits=not self.Flags.Limits
                toggle.Text=if self.Flags.Limits then "Limits: enabled"
                    else "Limits: disabled"
            end)
        self:ActionButton("Apply limits","Commit exact limit settings to the server",function()
            local low=tonumber(self.Fields["Lower limit"].Text)
            local high=tonumber(self.Fields["Upper limit"].Text)
            if not low or not high then
                self:Message("Invalid limits") return
            end
            self:Send({action="AdjustJoint",relationId=node.id,
                lowerLimit=low,upperLimit=high,
                limitsEnabled=self.Flags.Limits},true)
        end)
        if kind=="Bearing" then
            self:Section("Bearing motor")
            self.Flags.Motor=relation:GetAttribute("MotorEnabled")==true
            local motor
            motor=self:ActionButton(
                if self.Flags.Motor then "Motor: enabled" else "Motor: disabled",
                "Configure the powered shaft bearing",function()
                    self.Flags.Motor=not self.Flags.Motor
                    motor.Text=if self.Flags.Motor then "Motor: enabled"
                        else "Motor: disabled"
                end)
            self:Field("Motor key",relation:GetAttribute("MotorKey") or "F")
            self:Field("Speed (rad/s)",relation:GetAttribute("MotorSpeed") or 3)
            self:Field("Max torque",relation:GetAttribute("MotorTorque") or 3000)
            self:Field("Acceleration",relation:GetAttribute("MotorAcceleration") or 40)
            self:ActionButton("Apply motor","Save motor input, speed, torque and acceleration",function()
                local speed=tonumber(self.Fields["Speed (rad/s)"].Text)
                local torque=tonumber(self.Fields["Max torque"].Text)
                local accel=tonumber(self.Fields.Acceleration.Text)
                if not speed or not torque or not accel then
                    self:Message("Invalid motor values") return
                end
                self:Send({action="TuneBearingMotor",relationId=node.id,
                    motorEnabled=self.Flags.Motor,
                    motorKey=self.Fields["Motor key"].Text:gsub("%s+",""),
                    motorSpeed=speed,motorTorque=torque,
                    motorAcceleration=accel},true)
            end)
        end
    end
    self:ActionButton("Remove connection","Delete only this relation, leaving its physical members",function()
        self:RunAction("remove-relation",node)
    end)
end

function Panel:RenderProperties()
    if not self.Properties then return end
    if self.Tooltip then self.Tooltip.Visible=false end
    clear(self.Properties)
    self.Fields={}
    self.Flags={}
    local primary=self.Tools.PrimaryId
    local subtool=self.Tools.SubtoolId
    local editing=primary=="AssemblySimulation"
        and subtool=="AssemblyEditor" and not simulating()
    if self.NewAssemblyButton then
        self.NewAssemblyButton.Visible=editing
            and self.AssemblyTool.Stage~="Selecting"
    end
    local node=self.Selected
    if not node then
        self:Value("Selection","None")
    elseif node.kind=="primitive" or node.kind=="component"
        or node.kind=="multi" then
        self:Geometry(node)
    elseif node.kind=="assembly" then
        self:AssemblyProperties(node)
    elseif node.kind=="relation" then
        self:RelationshipProperties(node)
    elseif node.kind=="unassigned" then
        self:Value("Primitives",#node.members)
    end
    -- Draft authoring is independent of what the user currently inspects.
    -- It must remain visible with zero selected primitives.
    if editing then
        self:RenderAssemblyDraft(node)
    elseif primary=="AssemblySimulation" and subtool=="Simulation"
        or simulating() then
        self:RenderSimulationControls(node)
    end
end

function Panel:ActionsFor(node)
    return Actions.List(node,self.Tools,simulating(),
        self.AssemblyTool.Stage,self.Mechanics.SimAssemblyId)
end

function Panel:OpenMenu(node,position)
    if not node then return end
    local options=self:ActionsFor(node)
    if #options==0 then return end
    self.MenuRestoreFocus=self.Focused
    self.MenuOpen=true
    self:Focus(true)
    clear(self.Menu)
    local height=math.min(440,#options*31+8)
    local viewport=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
        or Vector2.new(1280,720)
    self.Menu.Size=UDim2.fromOffset(225,height)
    self.Menu.Position=UDim2.fromOffset(
        math.clamp(position.X,5,math.max(5,viewport.X-230)),
        math.clamp(position.Y,5,math.max(5,viewport.Y-height-5)))
    self.Menu.Visible=true
    for i,action in ipairs(options) do
        local option=button(self.Menu,action.label,
            UDim2.fromOffset(5,4+(i-1)*31),
            UDim2.new(1,-10,0,29),function()
                local wasFocused=self.MenuRestoreFocus
                self:CloseMenu()
                self:RunAction(action.id,node)
                if action.id=="paint" or action.id=="configure"
                    or action.id=="connections" or action.id=="rename" then
                    self:Focus(true)
                else
                    self:Focus(wasFocused)
                end
            end)
        option.ZIndex=32
        option.TextXAlignment=Enum.TextXAlignment.Left
        self:Hint(option,action.tooltip
            ..(if action.shortcut then " · "..action.shortcut else ""))
    end
end

function Panel:RunAction(action,node)
    if not node then return end
    local allowed=false
    for _,item in ipairs(self:ActionsFor(node)) do
        if item.id==action then allowed=true break end
    end
    if not allowed then
        self:Message("Action unavailable in current tool")
        return
    end
    local model=node.model or node.members and node.members[1]
    if action=="select" then
        self:Select(node,true)
    elseif action=="connect" and own(model) then
        if self.Mechanics:BeginConnect(model) then
            self:Focus(false)
        end
    elseif action=="resize" and own(model) then
        self.Build:SetSelection(model)
        self.Tools:SetSubtool("Resize")
        self:Select(node,false)
    elseif action=="paint" then
        self.Tools:SetSubtool("Paint")
        self:Select(node,false)
        self:Focus(true)
    elseif action=="duplicate" and own(model) then
        if node.kind=="component" then
            self.Build:SetComponentSelection(node.componentId,node.members)
        else self.Build:SetSelection(model) end
        self:Focus(false)
        self.Build:StartMove(true)
    elseif action=="delete" and own(model) then
        if node.kind=="component" then
            self.Build:SetComponentSelection(node.componentId,node.members)
        else self.Build:SetSelection(model) end
        self.Build:Delete()
        self:Select(nil,false)
    elseif action=="ungroup" then
        self.Build:SetComponentSelection(node.componentId,node.members)
        self.Build:UngroupComponent()
        self:Scan(true)
    elseif action=="connections" then
        self.View="Connections"
        self:RenderTree()
        self:Focus(true)
    elseif action=="edit-members" and own(model) then
        self.AssemblyTool:LoadExisting(model)
        self:Scan(true)
    elseif action=="rename" then
        self:Select(node,false)
        self:Focus(true)
        local field=self.Fields.Name
        if field then field:CaptureFocus() end
    elseif action=="ground" and own(model) then
        self:Send({action="SetGrounded",instanceId=entityId(model)},true)
    elseif action=="new-assembly" then
        self.AssemblyTool:BeginNew()
        self:Focus(false)
    elseif action=="membership" and own(model) then
        -- Primitive rows operate on ONE member; component rows operate on
        -- the full group, as in the world editor's ordinary click workflow.
        self.AssemblyTool:ToggleMember(model,node.kind=="primitive")
        self:OnAssemblyDraftChanged()
        self:Scan(true)
    elseif action=="configure" then
        self:Select(node,false)
        self:Focus(true)
    elseif action=="remove-relation" then
        self:Send({action="RemoveRelation",relationId=node.id},true)
        self:Select(nil,false)
    elseif action=="run" or action=="stop" then
        self:RunSimulationAction(action,node)
    end
end

function Panel:Scan(force)
    local now=os.clock()
    if not force and now-self.LastScan<0.48 then return end
    self.LastScan=now
    local snapshot=Data.Snapshot(player)
    local changed=force or self.Signature~=snapshot.signature
    self.Snapshot=snapshot
    if changed then
        self.Signature=snapshot.signature
        if self.SelectedKey and self.SelectedKey~="multi" then
            self.Selected=self:FindNode(self.SelectedKey)
            if not self.Selected then self.SelectedKey=nil end
        end
        if not UIS:GetFocusedTextBox() then self:RenderProperties() end
        self:RenderTree()
    end
    if self.StatusUntil==0 or now>self.StatusUntil then
        self.Status.Text=tostring(#snapshot.models).." objects · "
            ..tostring(#snapshot.relations).." connections"
        self.StatusUntil=0
    end
end

function Panel:Start()
    if self.Started then return end
    self.Started=true
    self.Snapshot=Data.Snapshot(player)
    self.Signature=self.Snapshot.signature
    self:MakeUI()
    table.insert(self.Connections,self.Tools.SubtoolChanged.Event:Connect(function()
        self:CloseConnectionChoice(true)
        self:CloseMenu()
        if self.Tools.PrimaryId=="Build"
            and self.Tools.SubtoolId=="Paint" then
            self:Focus(true)
        else
            self:Focus(false)
        end
        if self.Selected then self:Select(self.Selected,false)
        else self:RenderProperties() end
        self:OnAssemblyDraftChanged()
        self:OnSimulationSessionChanged()
    end))
    table.insert(self.Connections,UIS.InputBegan:Connect(function(input,processed)
        if input.KeyCode==Enum.KeyCode.Tab and not processed
            and not self.ConnectionChoiceOpen
            and not self.Build.SmartMatch
            and not self.Build.LockedAlignment
            and not self.Build.PendingMateChoice
            and not UIS:GetFocusedTextBox()
            and not player:GetAttribute("OPENWORKS_AssemblyNaming")
            and not player:GetAttribute("OPENWORKS_PlotMenuOpen")
            and not player:GetAttribute("OPENWORKS_PropertiesOpen") then
            self:CloseMenu()
            self:Focus(not self.Focused)
            return
        end
        if input.KeyCode==Enum.KeyCode.Escape then
            if self.ConnectionChoiceOpen then
                self:CloseConnectionChoice(true)
                return
            end
            if self.MenuOpen then self:CloseMenu() return end
            if self.Focused and not UIS:GetFocusedTextBox() then
                self:Focus(false)
            end
        end
        if input.UserInputType==Enum.UserInputType.MouseButton2
            and not processed and not self.Focused
            and not simulating()
            and not UIS:GetFocusedTextBox()
            and not player:GetAttribute("OPENWORKS_CursorUIOpen")
            and not player:GetAttribute("OPENWORKS_PropertiesOpen")
            and not player:GetAttribute("OPENWORKS_PlotMenuOpen")
            and not player:GetAttribute("OPENWORKS_AssemblyNaming") then
            local node=self:SelectWorldAtCenter()
            if node then
                local pointer=UIS:GetMouseLocation()
                self:OpenMenu(node,pointer)
            end
        end
    end))
    for _,attribute in ipairs({
        "OPENWORKS_Simulating","OPENWORKS_SimulationPaused",
    }) do
        table.insert(self.Connections,
            player:GetAttributeChangedSignal(attribute):Connect(function()
                if self.Tools.PrimaryId=="AssemblySimulation" or simulating() then
                self:OnSimulationSessionChanged()
                if not UIS:GetFocusedTextBox() then
                    self:RenderProperties()
                end
            end
            end))
    end
    table.insert(self.Connections,RunService.Heartbeat:Connect(function()
        self:Scan(false)
    end))
    self:Scan(true)
    self:OnAssemblyDraftChanged()
    self:OnSimulationSessionChanged()
end

function Panel:Destroy()
    self:CloseConnectionChoice(true)
    self:CloseMenu()
    self:Focus(false)
    for _,conn in ipairs(self.Connections) do conn:Disconnect() end
    table.clear(self.Connections)
    if self.Feedback then self.Feedback:Clear("explorer-selection") end
    if self.Gui then self.Gui:Destroy() end
end

return Panel
