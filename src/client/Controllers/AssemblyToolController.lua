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
local CameraAimRay=require(script.Parent:WaitForChild("CameraAimRay"))
local Construction=RS:WaitForChild("Openworks"):WaitForChild("Construction")
local Config=require(Construction:WaitForChild("BuildConfig"))
local Grid=require(Construction:WaitForChild("GridMath"))
local Theme=require(script.Parent:WaitForChild("StudioTheme"))

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
        PreviewModels=nil,IgnoreConfirmUntil=0,
        LastTick=0,Connections={},
        VerticalHeld=nil,VerticalElapsed=0,
    },Tool)
end

function Tool:Pick()
    local folder=constructed()
    local camera=workspace.CurrentCamera
    if not folder or not camera then return nil end
    local ray=CameraAimRay.Ray(camera)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={folder}
    params.IgnoreWater=true
    -- Use the SAME center ray reach as Simulate/P: purple should never
    -- advertise an assembly outside the actual simulating interaction range.
    local hit=workspace:Raycast(ray.Origin,
        ray.Direction*Grid.MaxDistance,params)
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
    -- Assembly is a native first-person tool; Build/Edit's crosshair isn't
    -- available here, so supply the same aiming reference.
    self.Crosshair=make("TextLabel",gui,{
        Name="AssemblyToolCrosshair",Text="+",
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(20,20),BackgroundTransparency=1,
        Font=Enum.Font.GothamMedium,TextSize=21,
        TextColor3=Theme.Text,
        TextXAlignment=Enum.TextXAlignment.Center,
        TextYAlignment=Enum.TextYAlignment.Center,
        Visible=false,ZIndex=5,
    })
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
    -- This tool retains the locked first-person pointer. Display actual
    -- keyboard hints, not mouse buttons that cannot be clicked.
    self.Shortcuts=make("TextLabel",panel,{
        Name="AssemblyToolShortcutStrip",
        Text="N  NEW               Enter  CONFIRM          Esc  CANCEL",
        Position=UDim2.fromOffset(12,116),
        Size=UDim2.new(1,-24,0,27),
        BackgroundColor3=Theme.Panel,BorderSizePixel=0,
        Font=Enum.Font.GothamMedium,TextSize=11,
        TextColor3=Theme.Text,
        TextXAlignment=Enum.TextXAlignment.Center,
    })

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
    self.Crosshair.Visible=self.Mode=="Assembly" and self.Stage~="Naming"
    if self.Mode~="Assembly" then return end
    local count=0
    for _ in pairs(self.Selected) do count+=1 end
    self.Shortcuts.Text=if self.Stage=="Selecting"
        then "Alt+Up/Down  HEIGHT    Alt+Left/Right  SIDE"
        else "Alt+Up/Down  HEIGHT    Alt+Left/Right  SIDE"
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
    if self.Tools.ActiveId~="Assembly" or self.Busy then return end
    self.Mode="Assembly"
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
    self.IgnoreConfirmUntil=os.clock()+0.25
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
        or self.Busy or os.clock()<(self.IgnoreConfirmUntil or 0) then return end
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

-- Move only a SAVED named assembly, never an uncommitted draft
-- selection. Moving all its authored members together preserves internal
-- alignment. Server rejects out-of-bounds/colliding positions atomically.
function Tool:VerticalNudge(key)
    local alt=UIS:IsKeyDown(Enum.KeyCode.LeftAlt)
        or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
    if not alt then return end
    local axis,direction
    if key==Enum.KeyCode.Up or key==Enum.KeyCode.Down then
        axis,direction="Y",(if key==Enum.KeyCode.Up then 1 else -1)
    else
        local camera=workspace.CurrentCamera
        if not camera then return end
        local v=camera.CFrame.RightVector
        if math.abs(v.X)>=math.abs(v.Z) then
            axis,direction="X",(if v.X>=0 then 1 else -1)
        else
            axis,direction="Z",(if v.Z>=0 then 1 else -1)
        end
        if key==Enum.KeyCode.Left then direction=-direction end
    end
    if self.Tools.ActiveId~="Assembly" or self.Busy
        or self.Stage=="Naming" then return end
    local id=self.EditingId
    if not id then
        local aimed=self:Pick()
        id=aimed and aimed:GetAttribute("AssemblyId")
    end
    if type(id)~="string" or id=="" then
        self:Tell("Select a saved assembly to nudge")
        return
    end
    local fine=UIS:IsKeyDown(Enum.KeyCode.LeftShift)
        or UIS:IsKeyDown(Enum.KeyCode.RightShift)
    self.Busy=true
    local remote=RS:WaitForChild(Config.RequestName)
    local ok,answer=pcall(function()
        return remote:InvokeServer({action="VerticalMove",scope="Assembly",
            id=id,axis=axis,direction=direction,fine=fine})
    end)
    self.Busy=false
    self.PreviewCache=""
    if not ok or type(answer)~="table" or not answer.ok then
        self:Tell(if ok and type(answer)=="table"
            then tostring(answer.message) else "Vertical move failed")
    else
        self:Tell(tostring(answer.message))
    end
end

function Tool:History(redo)
    if self.Tools.ActiveId~="Assembly" or self.Busy
        or self.Stage=="Naming" then return end
    self.Busy=true
    local remote=RS:WaitForChild(Config.RequestName)
    local ok,result=pcall(function()
        return remote:InvokeServer({action=if redo then "Redo" else "Undo"})
    end)
    self.Busy=false
    if ok and type(result)=="table" and result.ok then
        -- Metadata history changes replica attributes in place; UI previews
        -- refresh by AssemblyId as soon as replication reaches the client.
        self.PreviewCache=""
        if self.EditingId and self.Stage=="Selecting" then
            local members=self:OwnedAssembly(self.EditingId)
            self.Selected={}
            for _,member in ipairs(members) do
                local id=instanceId(member)
                if id then self.Selected[id]=true end
            end
        end
        self:Tell(if redo then "Redone" else "Undone")
    else
        self:Tell(if ok and type(result)=="table"
            then tostring(result.message) else "History request failed")
    end
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
    self.PreviewModels=nil
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
    local signatureParts={}
    local sameModels=self.PreviewModels~=nil
    for _,id in ipairs(ids) do
        local model=byId[id]
        table.insert(signatureParts,id..":"..
            tostring(model:GetAttribute("ComponentId") or ""))
        if not self.PreviewModels or self.PreviewModels[id]~=model
            or not model.Parent then
            sameModels=false
        end
    end
    local signature=table.concat(signatureParts,";")
    if #ids==0 then
        if self.PreviewRoot then self:ClearVisuals() end
        return
    end
    if signature==self.PreviewCache and self.PreviewRoot
        and sameModels then return end
    self:ClearVisuals()
    if #ids==0 then return end
    self.PreviewCache=signature
    -- Native Highlights/HandleAdornments render as 3D world feedback.
    -- Their lifetime is still owned by this client controller, not the
    -- server's authored constructions.
    local root=make("Folder",workspace,{
        Name="OPENWORKS_LocalAssemblyPreview",
    })
    self.PreviewRoot=root
    self.PreviewModels=byId
    -- Each selected assembly primitive gets its OWN silhouette, even
    -- when it belongs to the same editor component. The former unified
    -- component bounding-box outline enclosed unwanted empty space.
    for _,id in ipairs(ids) do
        local model=byId[id]
        make("Highlight",root,{
            Name="AssemblyPrimitive",Adornee=model,
            FillColor=color,FillTransparency=0.88,
            OutlineColor=color,OutlineTransparency=0.06,
            DepthMode=Enum.HighlightDepthMode.Occluded,
        })
    end
end

function Tool:OnModeChanged(mode)
    if mode==self.Mode then return end
    self.Mode=mode
    self:ClearVisuals()
    if mode~="Assembly" then
        if self.Modal and self.Modal.Visible then self:CloseName(true) end
        self.Stage="Idle"
        self.Selected={}
        self.EditingId=nil
        self.VerticalHeld=nil
    end
    self:Refresh()
end

function Tool:Tick()
    self:OnModeChanged(self.Tools.ActiveId)
    if self.LastMessage and os.clock()>self.MessageUntil then
        self.LastMessage=nil
        self:Refresh()
    end
    local mode=self.Mode
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
    table.insert(self.Connections,self.Tools.Changed.Event:Connect(function(mode)
        self:OnModeChanged(mode)
    end))
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
        local control=UIS:IsKeyDown(Enum.KeyCode.LeftControl)
            or UIS:IsKeyDown(Enum.KeyCode.RightControl)
        if (UIS:IsKeyDown(Enum.KeyCode.LeftAlt)
                or UIS:IsKeyDown(Enum.KeyCode.RightAlt))
            and (key==Enum.KeyCode.Left or key==Enum.KeyCode.Right
                or key==Enum.KeyCode.Up or key==Enum.KeyCode.Down) then
            self:VerticalNudge(key)
            self.VerticalHeld=key
            self.VerticalElapsed=0
            return
        end
        if control and key==Enum.KeyCode.Z then
            self:History(false)
            return
        elseif control and key==Enum.KeyCode.Y then
            self:History(true)
            return
        end
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
    table.insert(self.Connections,UIS.InputEnded:Connect(function(input)
        if input.KeyCode==self.VerticalHeld then self.VerticalHeld=nil end
    end))
    table.insert(self.Connections,RunService.Heartbeat:Connect(function(dt)
        local key=self.VerticalHeld
        if not key then return end
        if self.Tools.ActiveId~="Assembly" or self.Stage=="Naming"
            or UIS:GetFocusedTextBox()
            or not (UIS:IsKeyDown(Enum.KeyCode.LeftAlt)
                or UIS:IsKeyDown(Enum.KeyCode.RightAlt))
            or not UIS:IsKeyDown(key) then
            self.VerticalHeld=nil
            return
        end
        self.VerticalElapsed+=dt
        if self.VerticalElapsed<0.24 then return end
        self.VerticalElapsed=0.09
        task.spawn(function()
            self:VerticalNudge(key)
        end)
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
