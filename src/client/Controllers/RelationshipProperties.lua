--!strict
-- Mouse-driven relationship inspection and editing inside Simulate.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local construction=RS:WaitForChild("Openworks"):WaitForChild("Construction")
local Grid=require(construction:WaitForChild("GridMath"))
local Config=require(construction:WaitForChild("BuildConfig"))
local Properties={}
Properties.__index=Properties
local BG=Color3.fromRGB(21,28,37)
local SURFACE=Color3.fromRGB(37,47,59)
local WHITE=Color3.fromRGB(235,242,248)
local MUTED=Color3.fromRGB(158,179,195)
local function create(class,parent,props)
    local item=Instance.new(class)
    for k,v in pairs(props) do item[k]=v end
    if item:IsA("GuiObject") and parent
        and parent:FindFirstChildOfClass("UIListLayout")
        and props.LayoutOrder==nil then
        item.LayoutOrder=#parent:GetChildren()
    end
    item.Parent=parent
    return item
end
local function rounded(item)
    create("UICorner",item,{CornerRadius=UDim.new(0,8)})
    return item
end
local function label(parent,text,h)
    return create("TextLabel",parent,{
        BackgroundTransparency=1,Size=UDim2.new(1,-10,0,h or 22),
        Font=Enum.Font.GothamMedium,TextSize=13,Text=text,
        TextColor3=MUTED,TextXAlignment=Enum.TextXAlignment.Left,
        TextWrapped=true,ZIndex=5,
    })
end
local function button(parent,text,h)
    return rounded(create("TextButton",parent,{
        Size=UDim2.new(1,-10,0,h or 30),
        BackgroundColor3=SURFACE,BorderSizePixel=0,
        Text=text,TextColor3=WHITE,TextSize=13,
        Font=Enum.Font.GothamMedium,AutoButtonColor=true,ZIndex=5,
    }))
end
local function clear(frame)
    for _,child in ipairs(frame:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
end
function Properties.new(controller)
    return setmetatable({Controller=controller,Open=false,
        SelectedId=nil,SelectedName=nil,SelectedRelation=nil,
        Fields={},LimitsOn=false,Looking=false,Connections={}},Properties)
end
function Properties:Relations()
    local root=workspace:FindFirstChild("OPENWORKS_Relationships")
    if not root or not self.SelectedId then return {} end
    local included={[self.SelectedId]=true}
    local built=workspace:FindFirstChild(Config.FolderName)
    if built then
        local group
        for _,m in ipairs(built:GetChildren()) do
            if m:GetAttribute("OwnerUserId")==player.UserId
                and m:GetAttribute("InstanceId")==self.SelectedId then
                group=m:GetAttribute("ComponentId")
                break
            end
        end
        if group then
            for _,m in ipairs(built:GetChildren()) do
                if m:GetAttribute("OwnerUserId")==player.UserId
                    and m:GetAttribute("ComponentId")==group then
                    included[m:GetAttribute("InstanceId")]=true
                end
            end
        end
    end
    local relations={}
    for _,r in ipairs(root:GetChildren()) do
        if r:GetAttribute("OwnerUserId")==player.UserId
            and (included[r:GetAttribute("SourceId")]
                or included[r:GetAttribute("TargetId")]
                or included[r:GetAttribute("SecondTargetId")]) then
            table.insert(relations,r)
        end
    end
    table.sort(relations,function(a,b)
        return tostring(a:GetAttribute("RelationId"))<
            tostring(b:GetAttribute("RelationId"))
    end)
    return relations
end
function Properties:SelectWorld()
    local camera=workspace.CurrentCamera
    if not camera then return end
    local roots={}
    local authored=workspace:FindFirstChild(Config.FolderName)
    local simulated=workspace:FindFirstChild("OPENWORKS_Simulated")
    if authored then table.insert(roots,authored) end
    if simulated then table.insert(roots,simulated) end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances=roots
    params.IgnoreWater=true
    local mouse=UIS:GetMouseLocation()
    local ray=camera:ViewportPointToRay(mouse.X,mouse.Y)
    local hit=workspace:Raycast(ray.Origin,ray.Direction*Grid.MaxDistance,params)
    local instance=hit and hit.Instance
    while instance and instance~=workspace do
        if instance:IsA("Model")
            and instance:GetAttribute("OwnerUserId")==player.UserId
            and type(instance:GetAttribute("InstanceId"))=="string" then
            self.SelectedId=instance:GetAttribute("InstanceId")
            self.SelectedName=instance.Name:gsub("^Sim_","")
            self.SelectedRelation=nil
            self:Refresh()
            return
        end
        instance=instance.Parent
    end
    self.Status.Text="Click one of your constructed or simulated parts"
end
function Properties:Field(name,value)
    label(self.Editor,name,19)
    local edit=rounded(create("TextBox",self.Editor,{
        Size=UDim2.new(1,-10,0,31),BackgroundColor3=SURFACE,
        BorderSizePixel=0,Text=tostring(value),ClearTextOnFocus=false,
        Font=Enum.Font.GothamMedium,TextSize=14,TextColor3=WHITE,
        TextXAlignment=Enum.TextXAlignment.Center,ZIndex=5,
    }))
    self.Fields[name]=edit
end
function Properties:Apply()
    local r=self.SelectedRelation
    if not r or not r.Parent then return end
    local kind=r:GetAttribute("Kind")
    local id=r:GetAttribute("RelationId")
    local function val(key)
        return self.Fields[key] and tonumber(self.Fields[key].Text)
    end
    local payload
    if kind=="Spring" then
        local strength,damp,rest=val("Stiffness"),val("Damping"),val("Rest length (U)")
        if not strength or not damp or not rest then
            self.Status.Text="Enter valid spring numbers"
            return
        end
        payload={action="TuneSpring",relationId=id,
            stiffness=strength,damping=damp,freeLength=rest*Grid.Unit}
    elseif kind=="Bearing" or kind=="Slider" or kind=="Cylindrical" then
        local low,high=val("Lower limit"),val("Upper limit")
        if not low or not high then
            self.Status.Text="Enter valid limits"
            return
        end
        payload={action="AdjustJoint",relationId=id,
            lowerLimit=low,upperLimit=high,limitsEnabled=self.LimitsOn}
    else
        self.Status.Text="This connection has no tunable settings"
        return
    end
    local ok,result=self.Controller:Request(payload)
    self.Status.Text=result and tostring(result.message) or "Request failed"
    -- Preserve typed values until attribute replication catches up. Immediate
    -- rebuild could display stale pre-request values after a successful edit.
end
function Properties:Refresh()
    if not self.Gui then return end
    clear(self.RelationList)
    clear(self.Editor)
    self.Fields={}
    self.Heading.Text=if self.SelectedId
        then "PART  /  "..tostring(self.SelectedName)
        else "CLICK A PART IN THE WORLD"
    local list=self:Relations()
    if #list==0 then
        label(self.RelationList,if self.SelectedId
            then "No mechanical relationships" else "Select a part to inspect",35)
    end
    for _,r in ipairs(list) do
        local guides=r:GetAttribute("FitPointCount")
        local name=tostring(r:GetAttribute("Kind"))
        if type(guides)=="number" and guides>1 then
            name..="  •  "..tostring(guides).." fitted guides"
        end
        local item=button(self.RelationList,
            (if self.SelectedRelation==r then "●  " else "○  ")..name)
        if self.SelectedRelation==r then
            item.BackgroundColor3=Color3.fromRGB(34,99,114)
        end
        item.Activated:Connect(function()
            self.SelectedRelation=r
            self:Refresh()
        end)
    end
    local r=self.SelectedRelation
    if not r or not r.Parent then return end
    local kind=r:GetAttribute("Kind")
    label(self.Editor,string.upper(tostring(kind)).."  /  SETTINGS",26)
    if kind=="Spring" then
        self:Field("Stiffness",r:GetAttribute("Stiffness") or 120)
        self:Field("Damping",r:GetAttribute("Damping") or 14)
        self:Field("Rest length (U)",string.format("%.2f",
            (r:GetAttribute("FreeLength") or 0.5)/Grid.Unit))
    elseif kind=="Bearing" or kind=="Slider" or kind=="Cylindrical" then
        self:Field("Lower limit",r:GetAttribute("LowerLimit") or -4)
        self:Field("Upper limit",r:GetAttribute("UpperLimit") or 4)
        self.LimitsOn=r:GetAttribute("LimitsEnabled")==true
        local toggle=button(self.Editor,
            "LIMITS  /  "..(if self.LimitsOn then "ON" else "OFF"))
        toggle.Activated:Connect(function()
            self.LimitsOn=not self.LimitsOn
            toggle.Text="LIMITS  /  "..(if self.LimitsOn then "ON" else "OFF")
        end)
    else
        label(self.Editor,"Structural relationship • no editable parameters",50)
        return
    end
    local apply=button(self.Editor,"APPLY SETTINGS",38)
    apply.BackgroundColor3=Color3.fromRGB(32,102,115)
    apply.Activated:Connect(function() self:Apply() end)
end
function Properties:Show(open)
    self.Open=open
    if not self.Gui then return end
    self.Gui.Enabled=open
    if self.WorldSurface then
        self.WorldSurface.Visible=true
        self.WorldSurface.Modal=true
    end
    player:SetAttribute("OPENWORKS_PropertiesOpen",open)
    if not open then
        self.Looking=false
        player:SetAttribute("OPENWORKS_PropertiesLooking",false)
    end
    if open then
        UIS.MouseBehavior=Enum.MouseBehavior.Default
        UIS.MouseIconEnabled=true
        self:Refresh()
    end
end
function Properties:Start()
    local gui=create("ScreenGui",player:WaitForChild("PlayerGui"),{
        Name="OPENWORKS_RelationshipProperties",Enabled=false,
        ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=83,
    })
    self.Gui=gui
    local surface=create("TextButton",gui,{
        Name="SelectWorldPart",Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,BorderSizePixel=0,Text="",
        Modal=true,Active=true,ZIndex=1,
    })
    self.WorldSurface=surface
    surface.Activated:Connect(function()
        if not self.Looking then self:SelectWorld() end
    end)
    table.insert(self.Connections,UIS.InputBegan:Connect(function(input,_processed)
        if not self.Open then return end
        if input.UserInputType==Enum.UserInputType.MouseButton2 then
            self.Looking=true
            surface.Visible=false
            surface.Modal=false
            player:SetAttribute("OPENWORKS_PropertiesLooking",true)
        end
    end))
    table.insert(self.Connections,UIS.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton2 and self.Looking then
            self.Looking=false
            surface.Visible=true
            surface.Modal=true
            player:SetAttribute("OPENWORKS_PropertiesLooking",false)
        end
    end))
    local panel=rounded(create("Frame",gui,{
        Name="PropertiesPanel",Position=UDim2.fromOffset(16,55),
        Size=UDim2.fromOffset(320,565),
        BackgroundColor3=BG,BorderSizePixel=0,ZIndex=3,
    }))
    create("UIPadding",panel,{
        PaddingTop=UDim.new(0,12),PaddingLeft=UDim.new(0,12),
        PaddingRight=UDim.new(0,12),
    })
    create("UIListLayout",panel,{Padding=UDim.new(0,8)})
    local title=label(panel,"OPENWORKS  /  SIMULATE PROPERTIES",25)
    title.TextColor3=WHITE
    self.Heading=label(panel,"CLICK A PART IN THE WORLD",40)
    self.RelationList=create("ScrollingFrame",panel,{
        Size=UDim2.new(1,0,0,130),BackgroundTransparency=1,
        BorderSizePixel=0,ScrollBarThickness=3,
        CanvasSize=UDim2.fromOffset(0,0),
        AutomaticCanvasSize=Enum.AutomaticSize.Y,ZIndex=4,
    })
    create("UIListLayout",self.RelationList,{Padding=UDim.new(0,5)})
    self.Editor=create("ScrollingFrame",panel,{
        Size=UDim2.new(1,0,0,235),BackgroundTransparency=1,
        BorderSizePixel=0,ScrollBarThickness=3,
        CanvasSize=UDim2.fromOffset(0,0),
        AutomaticCanvasSize=Enum.AutomaticSize.Y,ZIndex=4,
    })
    create("UIListLayout",self.Editor,{Padding=UDim.new(0,5)})
    self.Status=label(panel,"Select a part and its relationship to change settings.",39)
    local actions=create("Frame",panel,{
        Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,ZIndex=4,
    })
    create("UIListLayout",actions,{
        FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,8),
    })
    local run=button(actions,"RUN / STOP",35)
    run.Size=UDim2.fromOffset(172,35)
    run.Activated:Connect(function()
        if self.Controller:IsSimulating() then
            self.Controller:Request({action="StopSimulation"})
        elseif self.SelectedId then
            self.Controller.SimSeedId=self.SelectedId
            self.Controller:Request({action="StartSimulation",
                seedId=self.SelectedId,grounded=true})
        else self.Status.Text="Choose a part before running simulation" end
    end)
    local ground=button(actions,"GROUND",35)
    ground.Size=UDim2.fromOffset(111,35)
    ground.Activated:Connect(function()
        if self.SelectedId and not self.Controller:IsSimulating() then
            self.Controller:Request({action="SetGrounded",
                instanceId=self.SelectedId})
        else self.Status.Text="Select a stopped body to change grounding" end
    end)
end
function Properties:Destroy()
    self:Show(false)
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    if self.Gui then self.Gui:Destroy() end
end
return Properties
