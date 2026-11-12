--!strict
-- UI v2 shared line-only selection/operation visualizer.
-- All boxes are twelve LineHandleAdornments attached to existing authored
-- primitives. No helper Parts, Highlights, fill, shadows or world text.
local RunService=game:GetService("RunService")
local GhostWireframe=require(script.Parent:WaitForChild("GhostWireframe"))

local Feedback={}
Feedback.__index=Feedback

local PALETTE={
    selection=Color3.fromRGB(67,207,224),
    snap=Color3.fromRGB(67,207,224),
    assembly=Color3.fromRGB(162,102,237),
    pending=Color3.fromRGB(255,157,54),
    success=Color3.fromRGB(76,222,124),
    invalid=Color3.fromRGB(246,79,86),
    grounded=Color3.fromRGB(76,222,124),
    free=Color3.fromRGB(83,161,238),
}
local PRIORITY={
    success=100,invalid=90,pending=80,assembly=70,
    selection=60,snap=50,grounded=20,free=20,
}

local function valid(model)
    return model and model:IsA("Model") and model.Parent~=nil
        and model.PrimaryPart~=nil and model.PrimaryPart.Parent~=nil
end

local function sameMembers(old,new)
    if #old~=#new then return false end
    for i,model in ipairs(old) do
        if model~=new[i] then return false end
    end
    return true
end

local function newLines(root)
    local edges={}
    for i=1,12 do
        local edge=Instance.new("LineHandleAdornment")
        edge.Name="Edge"..i
        edge.Thickness=2
        edge.Transparency=0
        edge.AlwaysOnTop=false
        edge.Visible=false
        edge.Parent=root
        edges[i]=edge
    end
    return edges
end

local function corners(part,pivot)
    local cf=pivot:ToObjectSpace(part.CFrame)
    local half=part.Size*0.5
    local low=Vector3.new(math.huge,math.huge,math.huge)
    local high=Vector3.new(-math.huge,-math.huge,-math.huge)
    for _,x in ipairs({-1,1}) do
        for _,y in ipairs({-1,1}) do
            for _,z in ipairs({-1,1}) do
                local point=cf:PointToWorldSpace(Vector3.new(
                    half.X*x,half.Y*y,half.Z*z))
                low=low:Min(point)
                high=high:Max(point)
            end
        end
    end
    return low,high
end

local function bounds(members,anchor)
    local pivot=anchor.CFrame
    local low=Vector3.new(math.huge,math.huge,math.huge)
    local high=Vector3.new(-math.huge,-math.huge,-math.huge)
    local found=false
    for _,model in ipairs(members) do
        if valid(model) then
            for _,part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart")
                    and part:GetAttribute("GearPivotOnly")~=true
                    and part:GetAttribute("OPENWORKS_VisualOnly")~=true then
                    local a,b=corners(part,pivot)
                    low=low:Min(a)
                    high=high:Max(b)
                    found=true
                end
            end
        end
    end
    return if found then low else nil, if found then high else nil
end

function Feedback.new()
    local root=Instance.new("Folder")
    root.Name="OPENWORKS_UIV2_Feedback"
    root.Parent=workspace
    return setmetatable({
        Root=root,Layers={},Connections={},LastUpdate=0,
        Ghost=GhostWireframe.new(root),
    },Feedback)
end

function Feedback:Set(owner,key,members,role,whole)
    assert(PALETTE[role]~=nil,"Invalid visual feedback role")
    local layer=self.Layers[owner]
    if not layer then
        layer={}
        self.Layers[owner]=layer
    end
    local list={}
    for _,model in ipairs(members or {}) do
        if valid(model) then table.insert(list,model) end
    end
    if #list==0 then self:Remove(owner,key) return end
    local entry=layer[key]
    if entry and entry.Role==role and entry.Whole==(whole==true)
        and sameMembers(entry.Members,list) then return end
    self:Remove(owner,key)
    local folder=Instance.new("Folder")
    folder.Name=tostring(owner).."_"..tostring(key)
    folder.Parent=self.Root
    entry={
        Folder=folder,Edges=newLines(folder),Members=list,Role=role,
        Whole=whole==true,Expires=nil,
    }
    layer[key]=entry
    self:Draw(entry,true)
end

function Feedback:Remove(owner,key)
    local layer=self.Layers[owner]
    local entry=layer and layer[key]
    if not entry then return end
    entry.Folder:Destroy()
    layer[key]=nil
end

function Feedback:Clear(owner)
    local layer=self.Layers[owner]
    if not layer then return end
    for key in pairs(layer) do self:Remove(owner,key) end
end

function Feedback:SetGhost(model,valid)
    self.Ghost:Bind(model)
    self.Ghost:SetValid(valid)
end

function Feedback:SetGhostValid(valid)
    self.Ghost:SetValid(valid)
end

function Feedback:FlashSuccess(models)
    self:Clear("confirmation")
    for i,model in ipairs(models or {}) do
        if valid(model) then
            self:Set("confirmation",tostring(i),{model},"success",false)
            local entry=self.Layers.confirmation[tostring(i)]
            if entry then entry.Expires=os.clock()+0.42 end
        end
    end
end

function Feedback:Draw(entry,ignorePriority)
    local members=entry.Members
    local anchorModel=members[1]
    local anchor=if valid(anchorModel) then anchorModel.PrimaryPart else nil
    if not anchor then
        for _,edge in ipairs(entry.Edges) do edge.Visible=false end
        return
    end
    local priority=PRIORITY[entry.Role] or 0
    local visible=ignorePriority==true
    if not visible then
        visible=true
        for _,layer in pairs(self.Layers) do
            for _,other in pairs(layer) do
                if other~=entry and (PRIORITY[other.Role] or 0)>priority then
                    for _,subject in ipairs(members) do
                        if table.find(other.Members,subject) then
                            visible=false
                            break
                        end
                    end
                    if not visible then break end
                end
            end
            if not visible then break end
        end
    end
    if not visible then
        for _,edge in ipairs(entry.Edges) do edge.Visible=false end
        return
    end
    local low,high=bounds(members,anchor)
    if not low or not high then
        for _,edge in ipairs(entry.Edges) do edge.Visible=false end
        return
    end
    local n=0
    local function segment(a,b)
        n+=1
        local edge=entry.Edges[n]
        local worldA=anchor.CFrame:PointToWorldSpace(a)
        local worldB=anchor.CFrame:PointToWorldSpace(b)
        edge.Adornee=anchor
        edge.CFrame=anchor.CFrame:ToObjectSpace(CFrame.lookAt(worldA,worldB))
        edge.Length=(b-a).Magnitude
        edge.Color3=PALETTE[entry.Role]
        edge.Visible=true
    end
    for _,y in ipairs({low.Y,high.Y}) do
        for _,z in ipairs({low.Z,high.Z}) do
            segment(Vector3.new(low.X,y,z),Vector3.new(high.X,y,z))
        end
    end
    for _,x in ipairs({low.X,high.X}) do
        for _,z in ipairs({low.Z,high.Z}) do
            segment(Vector3.new(x,low.Y,z),Vector3.new(x,high.Y,z))
        end
    end
    for _,x in ipairs({low.X,high.X}) do
        for _,y in ipairs({low.Y,high.Y}) do
            segment(Vector3.new(x,y,low.Z),Vector3.new(x,y,high.Z))
        end
    end
end

function Feedback:Update()
    local now=os.clock()
    if now-self.LastUpdate<0.08 then return end
    self.LastUpdate=now
    self.Ghost:Update()
    for owner,layer in pairs(self.Layers) do
        for key,entry in pairs(layer) do
            if (entry.Expires and now>=entry.Expires)
                or not valid(entry.Members[1]) then
                self:Remove(owner,key)
            else
                self:Draw(entry,false)
            end
        end
    end
end

function Feedback:Start()
    table.insert(self.Connections,RunService.RenderStepped:Connect(
        function() self:Update() end))
end

function Feedback:Destroy()
    for _,connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    for owner in pairs(self.Layers) do self:Clear(owner) end
    self.Ghost:Destroy()
    self.Root:Destroy()
end

return Feedback
