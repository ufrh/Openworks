--!strict
-- Visual reference using the LOCAL PLAYER'S actual current avatar at its
-- real Roblox scale. This is never authored or networked construction.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local CameraAimRay=require(script.Parent:WaitForChild("CameraAimRay"))

local player=Players.LocalPlayer
local ScaleGhost={}
ScaleGhost.__index=ScaleGhost

local function cloneAvatar(character:Model):Model?
    -- Roblox characters can be non-Archivable. Restore the original flag
    -- after cloning so we never mutate the real avatar's runtime behavior.
    local archived=character.Archivable
    character.Archivable=true
    local ok,copy=pcall(function() return character:Clone() end)
    character.Archivable=archived
    if not ok or not copy then return nil end

    copy.Name="OPENWORKS_CharacterScaleGhost"
    copy:SetAttribute("OPENWORKS_VisualOnly",true)
    -- Preserve exact body scale, skin, avatar colors, clothing, faces, hair,
    -- accessories, packages and mesh textures. Only remove interactive
    -- behavior and physics; never touch the live player character.
    for _,item in ipairs(copy:GetDescendants()) do
        if item:IsA("LuaSourceContainer") or item:IsA("Humanoid")
            or item:IsA("Animator") or item:IsA("Tool") then
            item:Destroy()
        elseif item:IsA("BasePart") then
            item.Anchored=true
            item.Massless=true
            item.CanCollide=false
            item.CanTouch=false
            item.CanQuery=false
            item.CastShadow=false
            if item.Name=="HumanoidRootPart" then
                item.Transparency=1
            else
                item.Transparency=math.max(item.Transparency,0.30)
            end
            item:SetAttribute("OPENWORKS_VisualOnly",true)
        elseif item:IsA("Decal") or item:IsA("Texture") then
            item.Transparency=math.max(item.Transparency,0.30)
        end
    end
    return copy
end

function ScaleGhost.new()
    return setmetatable({
        Model=nil,Visible=false,Moving=false,
        Source=nil,FootOffset=Vector3.zero,
        LastFeet=nil,CurrentFeet=nil,Connections={},
    },ScaleGhost)
end

function ScaleGhost:Make()
    local character=player.Character
    if not character then return nil end
    if self.Model and self.Source==character then return self.Model end
    local model=cloneAvatar(character)
    if not model then return nil end
    local old=self.Model
    self.Model=model
    self.Source=character
    -- The avatar's feet, NOT its HumanoidRootPart, are the placement origin.
    -- Use the actual cloned rig's bounds so tall/short avatar scales work.
    local boundsCF,boundsSize=model:GetBoundingBox()
    local bottom=Vector3.new(boundsCF.Position.X,
        boundsCF.Position.Y-boundsSize.Y*0.5,boundsCF.Position.Z)
    self.FootOffset=model:GetPivot():PointToObjectSpace(bottom)
    if old then old:Destroy() end
    return model
end

function ScaleGhost:FeetPose()
    if self.LastFeet then return self.LastFeet end
    local plot=player:GetAttribute("OPENWORKS_PlotOrigin")
    local position=if typeof(plot)=="Vector3"
        then plot+Vector3.new(0,0.025,0)
        else Vector3.new(0,0.025,0)
    self.LastFeet=CFrame.new(position)
    return self.LastFeet
end

function ScaleGhost:MoveToFeet(pose:CFrame)
    if self.Model then
        self.Model:PivotTo(pose*CFrame.new(-self.FootOffset))
    end
end

function ScaleGhost:Show(value)
    self.Visible=value
    self.Moving=false
    self.CurrentFeet=nil
    if value then
        local model=self:Make()
        if not model then
            self.Visible=false
            warn("[OPENWORKS] Character scale reference unavailable: player avatar not loaded")
            return
        end
        model.Parent=workspace
        self:MoveToFeet(self:FeetPose())
    elseif self.Model then
        self.Model.Parent=nil
    end
end

function ScaleGhost:Toggle()
    self:Show(not self.Visible)
    return self.Visible
end

function ScaleGhost:BeginMove()
    if not self.Visible then self:Show(true) end
    self.Moving=self.Visible and self.Model~=nil
end

function ScaleGhost:CancelMove()
    self.Moving=false
    self.CurrentFeet=nil
    self:MoveToFeet(self:FeetPose())
end

function ScaleGhost:Place()
    if not self.Moving then return false end
    self.Moving=false
    self.LastFeet=self.CurrentFeet or self.LastFeet
    self.CurrentFeet=nil
    self:MoveToFeet(self:FeetPose())
    return true
end

function ScaleGhost:Update()
    if not self.Moving or not self.Model then return end
    local camera=workspace.CurrentCamera
    if not camera then return end
    local ray=CameraAimRay.Ray(camera)
    if not ray then return end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances={self.Model,player.Character}
    params.IgnoreWater=true
    local hit=workspace:Raycast(ray.Origin,ray.Direction,params)
    local location=hit and hit.Position
    if not location then
        local dir=ray.Direction.Unit
        if dir.Y< -0.001 then
            local distance=-ray.Origin.Y/dir.Y
            if distance>=0 and distance<=256 then
                location=ray.Origin+dir*distance
            end
        end
    end
    if location then
        self.CurrentFeet=CFrame.new(location+Vector3.new(0,0.025,0))
        self:MoveToFeet(self.CurrentFeet)
    end
end

function ScaleGhost:Start()
    if #self.Connections>0 then return end
    table.insert(self.Connections,RunService.RenderStepped:Connect(function()
        self:Update()
    end))
    table.insert(self.Connections,player.CharacterAppearanceLoaded:Connect(function(character)
        -- Refresh after avatar accessories/clothes/scale load or respawn.
        -- Keep the previously placed feet position unchanged.
        if not self.Visible or self.Moving or character~=player.Character then
            return
        end
        local model=self:Make()
        if model then
            model.Parent=workspace
            self:MoveToFeet(self:FeetPose())
        end
    end))
end

function ScaleGhost:Destroy()
    for _,connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    table.clear(self.Connections)
    if self.Model then self.Model:Destroy() end
    self.Model=nil
end

return ScaleGhost
