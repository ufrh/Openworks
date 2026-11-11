--!strict
-- One cohesive, studio-style component boundary: twelve screen-pixel
-- LineHandleAdornments, anchored to an existing selected part.
-- Never creates invisible Parts, physics geometry, shadows or per-member
-- outlines. Uses the entire selected group bounding box as ONE silhouette.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Construction=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Geometry=require(Construction:WaitForChild("ComponentGeometry"))

local Outline={}
Outline.__index=Outline
local BLUE=Color3.fromRGB(0,170,255)

function Outline.new(parent, members, color)
    local folder=Instance.new("Folder")
    folder.Name="OPENWORKS_UnifiedComponentOutline"
    folder.Parent=parent
    local edges={}
    for i=1,12 do
        local line=Instance.new("LineHandleAdornment")
        line.Name="Boundary"..tostring(i)
        line.Color3=color or BLUE
        line.Thickness=2
        line.Transparency=0.08
        line.AlwaysOnTop=false
        line.Visible=false
        line.Parent=folder
        edges[i]=line
    end
    local self=setmetatable({Folder=folder,Edges=edges},Outline)
    self:Update(members)
    return self
end

function Outline:Update(members)
    local anchor
    for _,member in ipairs(members or {}) do
        if member and member.Parent and member.PrimaryPart then
            anchor=member.PrimaryPart
            break
        end
    end
    if not anchor then
        for _,edge in ipairs(self.Edges) do edge.Visible=false end
        return false
    end
    local center,size=Geometry.Bounds(members)
    if not center then return false end
    local half=(size+Vector3.new(0.025,0.025,0.025))*0.5
    local low=center-half
    local high=center+half
    local n=0
    local function segment(a,b)
        n+=1
        local line=self.Edges[n]
        line.Adornee=anchor
        line.CFrame=anchor.CFrame:ToObjectSpace(CFrame.lookAt(a,b))
        line.Length=(b-a).Magnitude
        line.Visible=true
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
    return true
end

function Outline:Destroy()
    if self.Folder then self.Folder:Destroy() end
end

return Outline
