--!strict
-- Dedicated Assembly TOOL. Name a set, select any combination of standalone
-- primitives and whole editor components, and explicitly confirm membership.
-- Alt+click selects only one primitive even when it has a ComponentId.
-- No automatic mechanical traversal, hidden welds, or arbitrary scope.
-- Simulate previews the entire aimed registered assembly in PURPLE.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local Config=require(RS:WaitForChild("Openworks"):WaitForChild("Construction")
    :WaitForChild("BuildConfig"))
local Theme=require(script.Parent:WaitForChild("StudioTheme"))
local ComponentOutline=require(script.Parent:WaitForChild("ComponentOutline"))

local player=Players.LocalPlayer
local PURPLE=Color3.fromRGB(179,115,255)
local MAX_SELECTION=128
local Tool={}
Tool.__index=Tool

local function make(class,parent,props)
    local obj=Instance.new(class)
    for key,value in pairs(props or {}) do obj[key]=value end
    obj.Parent=parent
    return obj
end

local function constructed()
    return workspace:FindFirstChild(Config.FolderName)
end

local function ownedModels()
    local folder=constructed()
    local result={}
    if folder then
        for _,model in ipairs(folder:GetChildren()) do
            if model:IsA("Model")
                and model.PrimaryPart
                and model:GetAttribute("OwnerUserId")==player.UserId then
                table.insert(result,model)
            end
        end
    end
    return result
end

local function instanceId(model)
    local id=model and model:GetAttribute("InstanceId")
    return if type(id)=="string" and id~="" then id else nil
end

function Tool.new(tools)
    return setmetatable({
        Tools=tools,Mode=nil,Stage="Idle",Name="",EditingId=nil,
        Selected={},Busy=false,LastMessage=nil,MessageUntil=0,
        PreviewRoot=nil,PreviewCache="",PreviewOutlines={},
        LastTick=0,Connections={},
    },Tool)
end

function Tool:Pick()
    local folder=constructed()
    local camera=workspace.CurrentCamera
    if not folder or not camera then return nil end
    local ray=camera:ViewportPointToRay(
        camera.ViewportSize.X*0.5,camera.ViewportSize.Y*0.5)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={folder}
    params.IgnoreWater=true
    local hit=workspace:Raycast(ray.Origin,
        ray.Direction*Config.PlotSize,params)
    if not hit then return nil end
    local model=hit.Instance:FindFirstAncestorOfClass("Model")
    if model and model.Parent==folder and model.PrimaryPart
        and model:GetAttribute("OwnerUserId")==player.UserId then
        return model
    end
    return nil
end

function Tool:OwnedAssembly(id)
    local members={}
    for _,model in ipairs(ownedModels()) do
        if model:GetAttribute("AssemblyId")==id then
            table.insert(members,model)
        end
    end
    return members
end

function Tool:Tell(message)
    self.LastMessage=tostring(message)
    self.MessageUntil=os.clock()+3.2
    self:Refresh()
end

function Tool:Draw()
    local gui=make("ScreenGui",player:WaitForChild("PlayerGui"),{
        Name="OPENWORKS_AssemblyTool",ResetOnSpawn=false,
        IgnoreGuiInset=true,DisplayOrder=45,
        ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    })
    self.Gui=gui
    local panel=Theme.Chrome(make("Frame",gui,{
        Name="AssemblyAuthoringPanel",
        Size=UDim2.fromOffset(328,151),
        Position=UDim2.fromOffset(16,64),
        BackgroundColor3=Theme.Window,BorderSizePixel=0,
        Visible=false,
    }),Theme.Window)
    self.Panel=panel
    self.Title=make("TextLabel",panel,{
        Name="AssemblyTitle",Text="ASSEMBLY / EDITOR",
        BackgroundTransparency=1,
        Position=UDim2.fromOffset(12,9),
        Size=UDim2.new(1,-24,0,23),
        Font=Enum.Font.GothamBold,TextSize=13,
        TextColor3=Theme.Text,TextXAlignment=Enum.TextXAlignment.Left,
    })
    self.Status=make("TextLabel",panel,{
        Name="AssemblyStage",
        Text="N  /  Create named assembly",
        BackgroundTransparency=1,
        Position=UDim2.fromOffset(12,39),
        Size=UDim2.new(1,-24,0,44),
        Font=Enum.Font.Gotham,TextSize=12,TextWrapped=true,
        TextColor3=Theme.Muted,TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Top,
    })
    self.Instruction=make("TextLabel",panel,{
        Name="AssemblyInstructions",
        Text="Click an existing assembly to edit it",
        BackgroundTransparency=1,
        Position=UDim2.fromOffset(12,87),
        Size=UDim2.new(1,-24,0,21),
        Font=Enum.Font.Gotham,TextSize=11,TextWrapped=true,
        TextColor3=Theme.Muted,TextXAlignment=Enum.TextXAlignment.Left,
    })
    local newButton=Theme.Button(make("TextButton",panel,{
        Name="NewAssembly",Text="NEW   [N]",TextSize=12,
        Position=UDim2.fromOffset(12,116),
        Size=UDim2.fromOffset(143,27),BorderSizePixel=0,
        BackgroundColor3=Theme.Raised,
    }),false)
    local confirmButton=Theme.Button(make("TextButton",panel,{
        Name="ConfirmAssembly",Text="CONFIRM   [Enter]",TextSize=12,
        Position=UDim2.fromOffset(165,116),
        Size=UDim2.fromOffset(151,27),BorderSizePixel=0,
        BackgroundColor3=Theme.Raised,
    }),false)
    self.ConfirmButton=confirmButton
    table.insert(self.Connections,newButton.Activated:Connect(function()
        self:OpenName(false)
    end))
    table.insert(self.Connections,confirmButton.Activated:Connect(function()
        self:Confirm()
    end))

    local overlay=make("TextButton",gui,{
        Name="AssemblyNameModal",
        Size=UDim2.fromScale(1,1),Text="",Modal=true,
        BackgroundTransparency=1,Visible=false,ZIndex=60,
    })
    self.Modal=overlay
    local dialog=Theme.Chrome(make("Frame",overlay,{
        Name="AssemblyNameDialog",
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.4),
        Size=UDim2.fromOffset(356,154),
        BackgroundColor3=Theme.Window,ZIndex=61,
    }),Theme.Window)
    make("TextLabel",dialog,{
        Name="AssemblyNameTitle",Text="ASSEMBLY / NAME",
        BackgroundTransparency=1,
        Position=UDim2.fromOffset(14,12),
        Size=UDim2.new(1,-28,0,25),ZIndex=62,
        TextColor3=Theme.Text,TextSize=13,
        Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left,
    })
    local input=Theme.Chrome(make("TextBox",dialog,{
        Name="AssemblyName",Size=UDim2.new(1,-28,0,32),
        Position=UDim2.fromOffset(14,47),
        BackgroundColor3=Theme.Input,BorderSizePixel=0,
        PlaceholderText="Assembly name",Text="",
        ClearTextOnFocus=false,TextSize=13,
        Font=Enum.Font.Gotham,TextColor3=Theme.Text,ZIndex=62,
    }),Theme.Input)
    self.NameInput=input
    local accept=Theme.Button(make("TextButton",dialog,{
        Name="Continue",Position=UDim2.fromOffset(14,93),
        Size=UDim2.fromOffset(159,32),Text="CONTINUE",
        BackgroundColor3=Theme.Raised,ZIndex=62,
    }),false)
    local cancel=Theme.Button(make("TextButton",dialog,{
        Name="Cancel",Position=UDim2.fromOffset(185,93),
        Size=UDim2.fromOffset(157,32),Text="CANCEL",
        BackgroundColor3=Theme.Raised,ZIndex=62,
    }),false)
    table.insert(self.Connections,accept.Activated:Connect(function()
        self:AcceptName()
    end))
    table.insert(self.Connections,cancel.Activated:Connect(function()
        self:CloseName(true)
    end))
    table.insert(self.Connections,input.FocusLost:Connect(function(enter)
        if enter and self.Modal.Visible then self:AcceptName() end
    end))
    self.ChromeConnection=Theme.Attach(gui)
end

function Tool:Refresh()
    if not self.Panel then return end
    self.Panel.Visible=self.Mode=="Assembly"
    if self.Mode~="Assembly" then return end
    local count=0
    for _ in pairs(self.Selected) do count+=1 end
    self.ConfirmButton.Active=self.Stage=="Selecting" and not self.Busy
    self.ConfirmButton.AutoButtonColor=self.ConfirmButton.Active
    self.ConfirmButton.BackgroundColor3=if self.ConfirmButton.Active
        then Theme.Active else Theme.Panel
    if self.Stage=="Selecting" then
        self.Title.Text="ASSEMBLY / "..self.Name
        self.Status.Text=tostring(count).." primitives selected"
            ..(if self.EditingId then "  /  EDITING" else "  /  NEW")
        self.Instruction.Text="Click component / primitive • Alt+click: single"
    elseif self.Stage=="Naming" then
        self.Title.Text="ASSEMBLY / NAME"
        self.Status.Text="Enter the name to begin selecting"
        self.Instruction.Text="Enter to continue • Esc cancels"
    else
        self.Title.Text="ASSEMBLY / EDITOR"
        self.Status.Text="N  /  Create named assembly"
        self.Instruction.Text="Aim and click an existing assembly to edit"
    end
    if self.LastMessage and os.clock()<self.MessageUntil then
        self.Instruction.Text=self.LastMessage
    end
end

function Tool:OpenName(rename)
    if self.Mode~="Assembly" or self.Busy then return end
    if rename and not self.EditingId then return end
    self.Stage="Naming"
    self.NameInput.Text=if rename then self.Name else ""
    self.Modal.Visible=true
    player:SetAttribute("OPENWORKS_AssemblyNaming",true)
    UIS.MouseBehavior=Enum.MouseBehavior.Default
    UIS.MouseIconEnabled=true
    self:Refresh()
    task.defer(function()
        if self.Modal.Visible then self.NameInput:CaptureFocus() end
    end)
end

function Tool:CloseName(cancel)
    self.Modal.Visible=false
    player:SetAttribute("OPENWORKS_AssemblyNaming",false)
    if not player:GetAttribute("OPENWORKS_PropertiesOpen")
        and not player:GetAttribute("OPENWORKS_PlotMenuOpen") then
        UIS.MouseBehavior=Enum.MouseBehavior.LockCenter
        UIS.MouseIconEnabled=false
    end
    if cancel then
        self.Stage=if self.EditingId then "Selecting" else "Idle"
    end
    self:Refresh()
end

function Tool:AcceptName()
    if not self.Modal.Visible then return end
    local name=self.NameInput.Text:match("^%s*(.-)%s*$")
    if not name or #name==0 or #name>48 or name:find("[%c]") then
        self:Tell("Enter a name between 1 and 48 characters")
        return
    end
    self.Name=name
    self.Stage="Selecting"
    self:CloseName(false)
    self:Refresh()
end

function Tool:BeginNew()
    self.Selected={}
    self.EditingId=nil
    self.Name=""
    self:OpenName(false)
end

function Tool:LoadExisting(model)
    local id=model:GetAttribute("AssemblyId")
    if type(id)~="string" or id=="" then
        self:Tell("Press N to create a named assembly")
        return
    end
    self.EditingId=id
    self.Name=model:GetAttribute("AssemblyName") or "Assembly"
    self.Selected={}
    for _,member in ipairs(self:OwnedAssembly(id)) do
        local memberId=instanceId(member)
        if memberId then self.Selected[memberId]=true end
    end
    self.Stage="Selecting"
    self:Refresh()
end

function Tool:Click()
    if self.Mode~="Assembly" or self.Busy
        or self.Stage=="Naming" then return end
    local model=self:Pick()
    if not model then
        self:Tell("Aim at a constructed primitive or editor component")
        return
    end
    if self.Stage~="Selecting" then
        self:LoadExisting(model)
        return
    end
    local alt=UIS:IsKeyDown(Enum.KeyCode.LeftAlt)
        or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
    local targets={model}
    local group=not alt and model:GetAttribute("ComponentId")
    if type(group)=="string" and group~="" then
        targets={}
        for _,member in ipairs(ownedModels()) do
            if member:GetAttribute("ComponentId")==group then
                table.insert(targets,member)
            end
        end
    end
    -- Clicking a component selects its ENTIRE primitive membership; Alt
    -- lets authors select only one member from inside the editor component.
    local allSelected=true
    for _,item in ipairs(targets) do
        if not self.Selected[instanceId(item)] then
            allSelected=false break
        end
    end
    if not allSelected then
        for _,item in ipairs(targets) do
            local existing=item:GetAttribute("AssemblyId")
            if type(existing)=="string" and existing~=""
                and existing~=self.EditingId then
                self:Tell("Already belongs to another assembly: "
                    ..tostring(item:GetAttribute("AssemblyName") or "Assembly"))
                return
            end
        end
    end
    local current=0
    for _ in pairs(self.Selected) do current+=1 end
    local added=0
    for _,item in ipairs(targets) do
        if not self.Selected[instanceId(item)] then added+=1 end
    end
    if not allSelected and current+added>MAX_SELECTION then
        self:Tell("Assemblies support up to 128 primitives")
        return
    end
    for _,item in ipairs(targets) do
        local id=instanceId(item)
        if id then self.Selected[id]=if allSelected then nil else true end
    end
    self.PreviewCache=""
    self:Refresh()
end

function Tool:Confirm()
    if self.Mode~="Assembly" or self.Stage~="Selecting"
        or self.Busy then return end
    local ids={}
    for id in pairs(self.Selected) do table.insert(ids,id) end
    table.sort(ids)
    if #ids==0 then
        self:Tell("Select at least one primitive or component")
        return
    end
    self.Busy=true
    self:Refresh()
    local payload={
        action=if self.EditingId then "UpdateAssembly" else "CreateAssembly",
        assemblyId=self.EditingId,name=self.Name,memberIds=ids,
    }
    local remote=RS:WaitForChild(Config.RequestName)
    local ok,answer=pcall(function()return remote:InvokeServer(payload)end)
    self.Busy=false
    if not ok or type(answer)~="table" or answer.ok~=true then
        self:Tell(if ok and type(answer)=="table"
            then tostring(answer.message) else "Could not save assembly")
        return
    end
    self.Stage="Idle"
    self.EditingId=nil
    self.Selected={}
    self.PreviewCache=""
    self:Tell(answer.message or "Assembly saved")
end

function Tool:Cancel()
    self:CloseName(false)
    self.Stage="Idle"
    self.Selected={}
    self.EditingId=nil
    self.PreviewCache=""
    self:Refresh()
end

function Tool:ClearVisuals()
    if self.PreviewRoot then self.PreviewRoot:Destroy() end
    self.PreviewRoot=nil
    self.PreviewCache=""
    self.PreviewOutlines={}
    player:SetAttribute("OPENWORKS_HoverAssemblyId","")
end

function Tool:ShowVisuals(members,color)
    local byId={}
    for _,member in ipairs(members) do
        local id=instanceId(member)
        if id then byId[id]=member end
    end
    local ids={}
    for id in pairs(byId) do table.insert(ids,id) end
    table.sort(ids)
    local signature=table.concat(ids,";")
    if signature==self.PreviewCache and self.PreviewRoot then return end
    self:ClearVisuals()
    if #ids==0 then return end
    self.PreviewCache=signature
    local root=make("Folder",self.Gui,{
        Name="OPENWORKS_AssemblySelectionPreview",
    })
    self.PreviewRoot=root
    local groups={}
    local singles={}
    for _,id in ipairs(ids) do
        local model=byId[id]
        local group=model:GetAttribute("ComponentId")
        if type(group)=="string" and group~="" then
            groups[group]=groups[group] or {}
            table.insert(groups[group],model)
        else
            table.insert(singles,model)
        end
    end
    for _,membersOfGroup in pairs(groups) do
        if #membersOfGroup>1 then
            local outer=ComponentOutline.new(root,membersOfGroup,color)
            table.insert(self.PreviewOutlines,outer)
            for _,member in ipairs(membersOfGroup) do
                make("Highlight",root,{
                    Name="AssemblyGroupFill",Adornee=member,
                    FillColor=color,FillTransparency=0.84,
                    OutlineTransparency=1,
                    DepthMode=Enum.HighlightDepthMode.Occluded,
                })
            end
        else
            table.insert(singles,membersOfGroup[1])
        end
    end
    for _,model in ipairs(singles) do
        make("Highlight",root,{
            Name="AssemblyPrimitive",Adornee=model,
            FillColor=color,FillTransparency=0.88,
            OutlineColor=color,OutlineTransparency=0.06,
            DepthMode=Enum.HighlightDepthMode.Occluded,
        })
    end
end

function Tool:Tick()
    local mode=self.Tools.ActiveId
    if mode~=self.Mode then
        self.Mode=mode
        self:ClearVisuals()
        if mode~="Assembly" then
            if self.Modal and self.Modal.Visible then self:CloseName(true) end
            self.Stage="Idle"
            self.Selected={}
            self.EditingId=nil
        end
        self:Refresh()
    end
    local id=""
    local members={}
    if mode=="Assembly" and self.Stage=="Selecting" then
        for _,model in ipairs(ownedModels()) do
            if self.Selected[instanceId(model)] then
                table.insert(members,model)
            end
        end
    elseif mode=="Simulate"
        and player:GetAttribute("OPENWORKS_Simulating")~=true then
        local aim=self:Pick()
        local chosen=aim and aim:GetAttribute("AssemblyId")
        if type(chosen)=="string" and chosen~="" then
            id=chosen
            members=self:OwnedAssembly(chosen)
        end
    elseif mode=="Assembly" and self.Stage=="Idle" then
        local aim=self:Pick()
        local chosen=aim and aim:GetAttribute("AssemblyId")
        if type(chosen)=="string" and chosen~="" then
            id=chosen
            members=self:OwnedAssembly(chosen)
        end
    end

    -- Hover preview belongs to the registered assembly, not the moving
    -- individual seed primitive. In Simulate, fill suppression prevents
    -- purple from fighting green/orange grounding Highlights.
    self:ShowVisuals(members,PURPLE)
    player:SetAttribute("OPENWORKS_HoverAssemblyId",id)
end

function Tool:Start()
    self:Draw()
    self.Mode=self.Tools.ActiveId
    self:Refresh()
    table.insert(self.Connections,self.Tools.Activated.Event:Connect(
        function(mode)
            if mode=="Assembly" then self:Click() end
        end))
    table.insert(self.Connections,UIS.InputBegan:Connect(function(input,processed)
        if self.Tools.ActiveId~="Assembly" or self.Busy then return end
        if self.Stage=="Naming" then
            if input.KeyCode==Enum.KeyCode.Escape then
                self:CloseName(true)
            end
            return
        end
        if processed or UIS:GetFocusedTextBox() then return end
        local key=input.KeyCode
        if key==Enum.KeyCode.N then
            self:BeginNew()
        elseif key==Enum.KeyCode.R and self.Stage=="Selecting"
            and self.EditingId then
            self:OpenName(true)
        elseif key==Enum.KeyCode.Return
            or key==Enum.KeyCode.KeypadEnter then
            self:Confirm()
        elseif key==Enum.KeyCode.Escape then
            self:Cancel()
        end
    end))
    table.insert(self.Connections,RunService.RenderStepped:Connect(function()
        if os.clock()-self.LastTick<0.09 then return end
        self.LastTick=os.clock()
        self:Tick()
    end))
end

function Tool:Destroy()
    self:ClearVisuals()
    if self.ChromeConnection then self.ChromeConnection:Disconnect() end
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
    player:SetAttribute("OPENWORKS_AssemblyNaming",false)
end

return Tool
