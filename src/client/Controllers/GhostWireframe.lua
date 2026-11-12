--!strict
-- Geometry-following ghost strokes for editable primitive Parts.
-- Cuboids, cylinders and balls use their actual primitive surface edges.
-- Roblox PartOperation CSG mesh edges are not exposed as a safe synchronous
-- API: those fall back to oriented extents, NOT fabricated fake cut edges.
-- No helper Parts or physics changes. Parent is shared VisualFeedback root.
local Ghost={}
Ghost.__index=Ghost

local CYAN=Color3.fromRGB(67,207,224)
local RED=Color3.fromRGB(246,79,86)
local ORANGE=Color3.fromRGB(255,157,54)
local MAX_EDGES=384
local STEPS=16

local function add(edges,part,a,b)
    if #edges>=MAX_EDGES then return end
    table.insert(edges,{part=part,a=a,b=b})
end

local function block(edges,part)
    local h=part.Size*0.5
    for _,y in ipairs({-h.Y,h.Y}) do
        for _,z in ipairs({-h.Z,h.Z}) do
            add(edges,part,Vector3.new(-h.X,y,z),Vector3.new(h.X,y,z))
        end
    end
    for _,x in ipairs({-h.X,h.X}) do
        for _,z in ipairs({-h.Z,h.Z}) do
            add(edges,part,Vector3.new(x,-h.Y,z),Vector3.new(x,h.Y,z))
        end
    end
    for _,x in ipairs({-h.X,h.X}) do
        for _,y in ipairs({-h.Y,h.Y}) do
            add(edges,part,Vector3.new(x,y,-h.Z),Vector3.new(x,y,h.Z))
        end
    end
end

local function cylinder(edges,part)
    local half=part.Size*0.5
    local radiusY=half.Y
    local radiusZ=half.Z
    local function rim(x,theta)
        return Vector3.new(x,math.cos(theta)*radiusY,
            math.sin(theta)*radiusZ)
    end
    for _,x in ipairs({-half.X,half.X}) do
        for i=0,STEPS-1 do
            add(edges,part,rim(x,i*math.pi*2/STEPS),
                rim(x,(i+1)*math.pi*2/STEPS))
        end
    end
    for i=0,3 do
        local angle=i*math.pi*0.5
        add(edges,part,rim(-half.X,angle),rim(half.X,angle))
    end
end

local function ball(edges,part)
    local half=part.Size*0.5
    for plane=1,3 do
        local function p(angle)
            local a=math.cos(angle)
            local b=math.sin(angle)
            if plane==1 then return Vector3.new(half.X*a,half.Y*b,0) end
            if plane==2 then return Vector3.new(half.X*a,0,half.Z*b) end
            return Vector3.new(0,half.Y*a,half.Z*b)
        end
        for i=0,STEPS-1 do
            add(edges,part,p(i*math.pi*2/STEPS),
                p((i+1)*math.pi*2/STEPS))
        end
    end
end

function Ghost.new(parent)
    local folder=Instance.new("Folder")
    folder.Name="OPENWORKS_GeometryGhostEdges"
    folder.Parent=parent
    return setmetatable({
        Folder=folder,Edges={},Model=nil,Valid=true,Pending=false,
        LastRender=0,
    },Ghost)
end

function Ghost:Bind(model)
    if self.Model==model then return end
    self.Model=model
    self.LastRender=0
    if not model then
        for _,line in ipairs(self.Edges) do line.Visible=false end
    end
end

function Ghost:SetValid(valid)
    self.Valid=valid~=false
end

function Ghost:SetPending(pending)
    self.Pending=pending==true
end

function Ghost:Update()
    if not self.Model or not self.Model.Parent then
        -- A normal placement preview is temporarily unparented while the
        -- center ray has no hit. Retain it so edges recover on the next hit.
        for _,line in ipairs(self.Edges) do line.Visible=false end
        return
    end
    if os.clock()-self.LastRender<0.08 then return end
    self.LastRender=os.clock()
    local edgeData={}
    for _,part in ipairs(self.Model:GetDescendants()) do
        if #edgeData>=MAX_EDGES then break end
        if not part:IsA("BasePart")
            or part:GetAttribute("GearPivotOnly")==true
            or part:GetAttribute("OPENWORKS_VisualOnly")==true
            or part.Transparency>=0.98 then continue end
        if part:IsA("Part") and part.Shape==Enum.PartType.Cylinder then
            cylinder(edgeData,part)
        elseif part:IsA("Part") and part.Shape==Enum.PartType.Ball then
            ball(edgeData,part)
        else
            block(edgeData,part)
        end
    end
    local color=if not self.Valid then RED
        elseif self.Pending then ORANGE else CYAN
    for i,data in ipairs(edgeData) do
        local line=self.Edges[i]
        if not line then
            line=Instance.new("LineHandleAdornment")
            line.Name="GeometryEdge_"..i
            line.Thickness=2
            line.Transparency=0
            line.AlwaysOnTop=false
            line.Parent=self.Folder
            self.Edges[i]=line
        end
        line.Adornee=data.part
        line.CFrame=CFrame.lookAt(data.a,data.b)
        line.Length=(data.b-data.a).Magnitude
        line.Color3=color
        line.Visible=true
    end
    for i=#edgeData+1,#self.Edges do self.Edges[i].Visible=false end
end

function Ghost:Destroy()
    self.Folder:Destroy()
end

return Ghost
