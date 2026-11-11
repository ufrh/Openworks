--!strict
-- Isolated, player-owned construction plots. Plots are ephemeral workspace
-- geometry; ONLY explicit saves in PlotPersistence touch DataStoreService.
local Players=game:GetService("Players")

local Plots={}
Plots.__index=Plots

local HALF=62
local SPACING=168
local MAX_PLOTS=20
local FLOOR_TOP=-0.08

local function primitive(parent,name,size,cf,color,material,collidable)
    local part=Instance.new("Part")
    part.Name=name
    part.Size=size
    part.CFrame=cf
    part.Anchored=true
    part.CanCollide=collidable
    part.CanTouch=false
    part.CanQuery=collidable
    part.CastShadow=false
    part.Material=material
    part.Color=color
    part.Parent=parent
    return part
end

function Plots.new()
    local folder=workspace:FindFirstChild("OPENWORKS_PlayerPlots")
    if not folder then
        folder=Instance.new("Folder")
        folder.Name="OPENWORKS_PlayerPlots"
        folder.Parent=workspace
    end
    return setmetatable({Folder=folder,Owned={},Slots={}},Plots)
end

function Plots:Origin(index)
    -- Slot 1 retains the legacy workshop at world origin. Remaining plots
    -- are fully separate; saved coordinates are LOCAL to each slot.
    local column=(index-1)%5
    local row=math.floor((index-1)/5)
    return Vector3.new(column*SPACING,0,row*SPACING)
end

function Plots:Assign(player)
    if self.Owned[player] then return self.Owned[player] end
    local slot
    for i=1,MAX_PLOTS do
        if not self.Slots[i] then slot=i break end
    end
    if not slot then return nil,"No free plots in this server" end
    local origin=self:Origin(slot)
    local plot=Instance.new("Model")
    plot.Name="OPENWORKS_Plot_"..slot
    plot:SetAttribute("OwnerUserId",player.UserId)
    plot:SetAttribute("PlotIndex",slot)
    plot.Parent=self.Folder
    local floor=primitive(plot,"PlotFloor",Vector3.new(HALF*2,0.16,HALF*2),
        CFrame.new(origin+Vector3.new(0,FLOOR_TOP-0.08,0)),
        Color3.fromRGB(41,48,57),Enum.Material.SmoothPlastic,true)
    floor.Transparency=0.06
    local edgeColor=Color3.fromRGB(72,165,178)
    for _,side in ipairs({-1,1}) do
        primitive(plot,"BorderX",Vector3.new(0.18,0.09,HALF*2),
            CFrame.new(origin+Vector3.new(side*HALF,FLOOR_TOP+0.01,0)),
            edgeColor,Enum.Material.Metal,false).Transparency=0.16
        primitive(plot,"BorderZ",Vector3.new(HALF*2,0.09,0.18),
            CFrame.new(origin+Vector3.new(0,FLOOR_TOP+0.01,side*HALF)),
            edgeColor,Enum.Material.Metal,false).Transparency=0.16
    end
    local info={index=slot,origin=origin,model=plot}
    self.Slots[slot]=player
    self.Owned[player]=info
    player:SetAttribute("OPENWORKS_PlotIndex",slot)
    player:SetAttribute("OPENWORKS_PlotOrigin",origin)
    player:SetAttribute("OPENWORKS_PlotHalfSize",HALF)
    return info
end

function Plots:Get(player)
    return self.Owned[player]
end

function Plots:Contains(player,position,size)
    local info=self.Owned[player]
    if not info or typeof(position)~="Vector3" then return false end
    local half=if typeof(size)=="Vector3" then size*0.5 else Vector3.zero
    local rel=position-info.origin
    return math.abs(rel.X)+half.X <= HALF-0.3
        and math.abs(rel.Z)+half.Z <= HALF-0.3
        and rel.Y>=-0.5
        and rel.Y<=90
end

function Plots:Spawn(player,character)
    local info=self.Owned[player]
    if not info then return end
    task.spawn(function()
        local root=character:WaitForChild("HumanoidRootPart",12)
        if not root or not character.Parent or not player.Parent then return end
        character:PivotTo(CFrame.new(info.origin+Vector3.new(0,5,0)))
    end)
end

function Plots:Release(player)
    local info=self.Owned[player]
    if not info then return end
    self.Owned[player]=nil
    self.Slots[info.index]=nil
    if info.model then info.model:Destroy() end
end

return Plots
