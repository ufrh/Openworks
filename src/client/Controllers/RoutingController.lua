--!strict
-- Scrap Mechanic-style logical wiring: always-on-top adornment dots and
-- lines. Mouse presses and releases select endpoints; server validates
-- ownership and persists routing. NO physical constraint is created.
-- Use Roblox SCREEN space for both GetMouseLocation and hit/ray helpers,
-- so the top-bar GUI inset cannot displace click targets from their dots.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local construction=RS:WaitForChild("Openworks"):WaitForChild("Construction")
local Config=require(construction:WaitForChild("BuildConfig"))
local Route={}
Route.__index=Route
local ORANGE=Color3.fromRGB(245,144,48)
local BLUE=Color3.fromRGB(67,161,238)
local AQUA=Color3.fromRGB(92,224,170)
local WHITE=Color3.fromRGB(229,238,249)
local function modelById()
    local map={}
    local folder=workspace:FindFirstChild(Config.FolderName)
    if folder then
        for _,model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") and model.PrimaryPart
                and model:GetAttribute("OwnerUserId")==player.UserId then
                local id=model:GetAttribute("InstanceId")
                if type(id)=="string" then map[id]=model end
            end
        end
    end
    return map
end
local function jointFolder()
    return workspace:FindFirstChild("OPENWORKS_Relationships")
end
local function operated(relation)
    if relation:GetAttribute("OwnerUserId")~=player.UserId then return false end
    local kind=relation:GetAttribute("Kind")
    return kind=="Rope" or (kind=="Bearing"
        and relation:GetAttribute("MotorEnabled")==true)
end
function Route.new(tools,mechanics,editor)
    local root=Instance.new("Folder")
    root.Name="OPENWORKS_RouteAdornments"
    root.Parent=workspace
    return setmetatable({
        Tools=tools,Mechanics=mechanics,Editor=editor,
        Root=root,Dots={},Lines={},Points={},Drag=nil,
        SelectedSeatId=nil,Connections={},
        LastScan=0,LastActive=false,
    },Route)
end
function Route:Active()
    return self.Tools.PrimaryId=="Mechanics"
        and self.Tools.SubtoolId=="Route"
        and player:GetAttribute("OPENWORKS_Simulating")~=true
end
local function dot(root,color)
    local item=Instance.new("SphereHandleAdornment")
    item.Name="RouteEndpoint"
    item.AlwaysOnTop=true
    item.Transparency=0
    item.Radius=0.15
    item.Color3=color
    item.Parent=root
    return item
end
local function line(root,color)
    local item=Instance.new("LineHandleAdornment")
    item.Name="RouteWire"
    item.AlwaysOnTop=true
    item.Transparency=0
    item.Thickness=3
    item.Color3=color
    item.Parent=root
    return item
end
function Route:DrawDot(key,model,position,color)
    local adorn=self.Dots[key]
    if not adorn then adorn=dot(self.Root,color) self.Dots[key]=adorn end
    local part=model.PrimaryPart
    adorn.Adornee=part
    adorn.CFrame=part.CFrame:ToObjectSpace(CFrame.new(position))
    adorn.Color3=color
    adorn.Visible=true
end
function Route:DrawLine(key,anchor,startPoint,endPoint,color)
    local adorn=self.Lines[key]
    if not adorn then adorn=line(self.Root,color) self.Lines[key]=adorn end
    local delta=endPoint-startPoint
    if delta.Magnitude<0.001 then adorn.Visible=false return end
    adorn.Adornee=anchor
    adorn.CFrame=anchor.CFrame:ToObjectSpace(CFrame.lookAt(startPoint,endPoint))
    adorn.Length=delta.Magnitude
    adorn.Color3=color
    adorn.Visible=true
end
function Route:Refresh()
    if not self:Active() then return end
    local models=modelById()
    local activeDots={}
    local activeLines={}
    local points={}
    for id,model in pairs(models) do
        if model:GetAttribute("TemplateId")=="SeatPlate" then
            local pos=model:GetPivot().Position+
                model:GetPivot().UpVector*(model.PrimaryPart.Size.Y*0.5+0.2)
            local color=if model:GetAttribute("SeatRole")=="Passenger"
                then BLUE else ORANGE
            self:DrawDot("seat:"..id,model,pos,
                if self.SelectedSeatId==id then AQUA else color)
            activeDots["seat:"..id]=true
            points["seat:"..id]={kind="seat",id=id,model=model,
                position=pos}
        end
    end
    local folder=jointFolder()
    if folder then
        local offsets={}
        for _,relation in ipairs(folder:GetChildren()) do
            if not operated(relation) then continue end
            local id=relation:GetAttribute("RelationId")
            local source=models[relation:GetAttribute("SourceId")]
            if type(id)~="string" or not source then continue end
            local sourceId=relation:GetAttribute("SourceId")
            offsets[sourceId]=(offsets[sourceId] or 0)+1
            local n=offsets[sourceId]
            local pos=source:GetPivot().Position+
                source:GetPivot().UpVector*(0.30+n*0.14)
            local seatId=relation:GetAttribute("SeatId")
            local selected=seatId~=nil and seatId==self.SelectedSeatId
            self:DrawDot("control:"..id,source,pos,
                if selected then AQUA else WHITE)
            activeDots["control:"..id]=true
            points["control:"..id]={kind="control",id=id,model=source,
                position=pos,relation=relation}
            if type(seatId)=="string" then
                local seat=points["seat:"..seatId]
                if seat then
                    self:DrawLine("wire:"..id,source.PrimaryPart,
                        pos,seat.position,if selected then AQUA else ORANGE)
                    activeLines["wire:"..id]=true
                end
            end
        end
    end
    if self.Drag then
        local from=points[self.Drag.key]
        local camera=workspace.CurrentCamera
        if from and camera then
            local mouse=UIS:GetMouseLocation()
            local ray=camera:ScreenPointToRay(mouse.X,mouse.Y)
            local finish=ray.Origin+ray.Direction*math.max(8,
                (from.position-ray.Origin).Magnitude)
            local hovered=self:AtMouse(points,mouse)
            if hovered and hovered.key~=self.Drag.key then
                finish=hovered.position
            end
            self:DrawLine("drag",from.model.PrimaryPart,
                from.position,finish,AQUA)
            activeLines.drag=true
        end
    end
    for id,adorn in pairs(self.Dots) do
        if not activeDots[id] then adorn:Destroy() self.Dots[id]=nil end
    end
    for id,adorn in pairs(self.Lines) do
        if not activeLines[id] then adorn:Destroy() self.Lines[id]=nil end
    end
    self.Points=points
end
function Route:AtMouse(points,mouse)
    local camera=workspace.CurrentCamera
    if not camera then return nil end
    local best=nil
    local dist=26
    for key,point in pairs(points or self.Points) do
        local screen,visible=camera:WorldToScreenPoint(point.position)
        if visible and screen.Z>0 then
            local distance=(Vector2.new(screen.X,screen.Y)-mouse).Magnitude
            if distance<dist then
                dist=distance
                best=point
                best.key=key
            end
        end
    end
    return best
end
-- A click anywhere on the actual flat seat plate must work too;
-- the visible always-on-top dot is a handle, not a tiny mandatory hitbox.
function Route:RaySeatAtMouse(mouse)
    local camera=workspace.CurrentCamera
    local folder=workspace:FindFirstChild(Config.FolderName)
    if not camera or not folder then return nil end
    local ray=camera:ScreenPointToRay(mouse.X,mouse.Y)
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances={folder}
    params.IgnoreWater=true
    local hit=workspace:Raycast(ray.Origin,ray.Direction*400,params)
    if not hit then return nil end
    local model=hit.Instance
    while model and model.Parent~=folder do model=model.Parent end
    if not model or model:GetAttribute("TemplateId")~="SeatPlate"
        or model:GetAttribute("OwnerUserId")~=player.UserId then
        return nil
    end
    local id=model:GetAttribute("InstanceId")
    return self.Points["seat:"..tostring(id)]
end

function Route:OpenSeat(point)
    self.SelectedSeatId=point.id
    if not self.Editor then return end
    local node=self.Editor:NodeForModel(point.model,false)
    if node then
        self.Editor:OpenForNode(node,UIS:GetMouseLocation(),"object")
    end
end
function Route:Begin(input,processed)
    if not self:Active() or processed or UIS:GetFocusedTextBox()
        or player:GetAttribute("OPENWORKS_ExplorerOpen")==true
        or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    local mouse=UIS:GetMouseLocation()
    local point=self:AtMouse(self.Points,mouse)
        or self:RaySeatAtMouse(mouse)
    if point then self.Drag={key=point.key,point=point} end
end
function Route:Finish(input)
    if input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    local drag=self.Drag
    self.Drag=nil
    if not drag or not self:Active() then return end
    local mouse=UIS:GetMouseLocation()
    local dest=self:AtMouse(self.Points,mouse)
        or self:RaySeatAtMouse(mouse)
    if dest and dest.key~=drag.key and dest.kind~=drag.point.kind then
        local control=if dest.kind=="control" then dest else drag.point
        local seat=if dest.kind=="seat" then dest else drag.point
        if seat.model:GetAttribute("SeatRole")~="Operator" then
            self.Mechanics:Message("Passenger seats cannot route controls")
            return
        end
        local ok=self.Mechanics:Request({action="RouteControl",
            relationId=control.id,seatId=seat.id})
        if ok then self.SelectedSeatId=seat.id end
        self:Refresh()
    elseif drag.point.kind=="seat" then
        self:OpenSeat(drag.point)
    elseif drag.point.kind=="control" then
        local seatId=drag.point.relation:GetAttribute("SeatId")
        if seatId and self.Points["seat:"..seatId] then
            self:OpenSeat(self.Points["seat:"..seatId])
        end
    end
end
function Route:Start()
    table.insert(self.Connections,UIS.InputBegan:Connect(function(i,p)
        self:Begin(i,p)
    end))
    table.insert(self.Connections,UIS.InputEnded:Connect(function(i)
        self:Finish(i)
    end))
    table.insert(self.Connections,RunService.RenderStepped:Connect(function()
        local active=self:Active()
        if active~=self.LastActive then
            self.LastActive=active
            player:SetAttribute("OPENWORKS_CursorUIOpen",active)
            if not active then
                self.Drag=nil
                self.SelectedSeatId=nil
                for id,dot in pairs(self.Dots) do dot:Destroy() self.Dots[id]=nil end
                for id,wire in pairs(self.Lines) do wire:Destroy() self.Lines[id]=nil end
                self.Points={}
            end
        end
        if not active then return end
        if os.clock()-self.LastScan<1/30 then return end
        self.LastScan=os.clock()
        self:Refresh()
    end))
end
function Route:Destroy()
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    player:SetAttribute("OPENWORKS_CursorUIOpen",false)
    self.Root:Destroy()
end
return Route
