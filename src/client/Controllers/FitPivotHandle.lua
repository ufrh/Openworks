--!strict
-- A single contextual gizmo for the logical fitting origin.
-- SphereHandleAdornment is noncolliding and never becomes authored geometry.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Origin=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("FitOrigin"))

local Handle={}
Handle.__index=Handle
function Handle.new()
    local adornment=Instance.new("SphereHandleAdornment")
    adornment.Name="OPENWORKS_FitOrigin"
    adornment.Color3=Color3.fromRGB(83,221,239)
    adornment.Transparency=0.12
    adornment.Radius=0.11
    adornment.AlwaysOnTop=true
    adornment.Visible=false
    adornment.Parent=workspace.CurrentCamera
    return setmetatable({Adornment=adornment},Handle)
end
function Handle:Update(anchor,scope,active)
    local ad=self.Adornment
    if not anchor or not anchor.Parent or not anchor.PrimaryPart or not active then
        ad.Visible=false
        ad.Adornee=nil
        return
    end
    local world=Origin.World(anchor,scope)
    ad.Adornee=anchor.PrimaryPart
    ad.CFrame=CFrame.new(anchor.PrimaryPart.CFrame:PointToObjectSpace(world))
    ad.Visible=true
    ad.Color3=if scope=="Component" then Color3.fromRGB(162,127,242)
        else Color3.fromRGB(83,221,239)
end
function Handle:UpdateCandidate(anchor,world,scope)
    local ad=self.Adornment
    if not anchor or not anchor.Parent or not anchor.PrimaryPart
        or typeof(world)~="Vector3" then
        ad.Adornee=nil
        ad.Visible=false
        return
    end
    local root=anchor.PrimaryPart
    ad.Adornee=root
    ad.CFrame=CFrame.new(root.CFrame:PointToObjectSpace(world))
    ad.Color3=if scope=="Component" then Color3.fromRGB(162,127,242)
        else Color3.fromRGB(83,221,239)
    ad.Visible=true
end

function Handle:UpdatePreview(ghost)
    local ad=self.Adornment
    if not ghost or not ghost.Parent then
        ad.Visible=false
        ad.Adornee=nil
        return
    end
    local offset,custom=Origin.PreviewLocal(ghost)
    if not custom then
        ad.Visible=false
        ad.Adornee=nil
        return
    end
    local root=ghost.PrimaryPart
    if not root then
        for _,desc in ipairs(ghost:GetDescendants()) do
            if desc:IsA("BasePart") and desc:GetAttribute("GearPivotOnly")~=true then
                root=desc
                break
            end
        end
    end
    if not root then ad.Visible=false return end
    local point=ghost:GetPivot():PointToWorldSpace(offset)
    ad.Adornee=root
    ad.CFrame=CFrame.new(root.CFrame:PointToObjectSpace(point))
    ad.Color3=Color3.fromRGB(83,221,239)
    ad.Visible=true
end

function Handle:Destroy()
    self.Adornment:Destroy()
end
return Handle
