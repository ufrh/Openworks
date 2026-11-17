--!strict
-- Auto-connected mechanism router. Shaft-centric transmissions use native
-- physics; real rack/guide connections select the rack kinematics engine.
-- Each engine owns ONLY its active player's session. No authored graph is
-- mutated in order to decide which simulation implementation should run.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local GearMath=require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GearMath"))
local RackSimulationService=require(script.Parent:WaitForChild("RackSimulationService"))
local PhysicalSimulationService=require(script.Parent:WaitForChild("PhysicalSimulationService"))

local Unified={}
Unified.__index=Unified

function Unified.new(deps)
    local self=setmetatable({
        D=deps,
        Rack=RackSimulationService.new(deps),
        Physical=PhysicalSimulationService.new(deps),
        Active={},
    },Unified)
    return self
end

function Unified:Engine(player)
    return self.Active[player]
end

function Unified:IsRunning(player)
    return self.Rack:IsRunning(player) or self.Physical:IsRunning(player)
end

function Unified:Choose(player,payload)
    if type(payload)~="table" or type(payload.seedId)~="string" then
        return self.Physical
    end
    local seed=self.D.findOwned(player,payload.seedId)
    if not seed then return self.Physical end
    local ok,reason,ids=self.D.assemblies:DetectConnected(player,{
        seedId=payload.seedId,
    })
    if not ok then return nil,reason end
    local rack=false
    local memberIds={}
    for _,id in ipairs(ids) do memberIds[id]=true end
    for _,model in ipairs(self.D.folder:GetChildren()) do
        if model:IsA("Model")
            and model:GetAttribute("OwnerUserId")==player.UserId
            and memberIds[model:GetAttribute("InstanceId")] then
            local kind=GearMath.Kind(model)
            if kind=="Rack" or kind=="RackGuide" then rack=true end
        end
    end
    local hasBelt=false
    local hasVectorJoint=false
    for _,relation in ipairs(self.D.mechanical.Folder:GetChildren()) do
        if relation:GetAttribute("OwnerUserId")==player.UserId
            and memberIds[relation:GetAttribute("SourceId")]
            and memberIds[relation:GetAttribute("TargetId")] then
            local kind=relation:GetAttribute("Kind")
            if kind=="Rack" or kind=="Guide" then rack=true end
            if kind=="Belt" then hasBelt=true end
            if kind=="VectorJoint" then hasVectorJoint=true end
        end
    end
    if rack and hasVectorJoint then
        return nil,"Vector Joint with rack/guide assemblies is not yet supported by the rack engine; separate those connections into independent mechanisms"
    end
    if rack and hasBelt then
        return nil,"Rack + friction belt assemblies cannot simulate together yet; separate those connections into independent mechanisms"
    end
    return if rack then self.Rack else self.Physical
end

function Unified:Start(player,payload)
    if self:IsRunning(player) then
        return false,"Stop the current simulation first"
    end
    local engine,reason=self:Choose(player,payload)
    if not engine then return false,reason end
    local selected=if engine==self.Rack then "RackSimulationService"
        else "PhysicalSimulationService"
    print("[OPENWORKS][SIM ROUTER] "..selected..
        " selected for "..player.Name)
    local ok,message=engine:Start(player,payload)
    if ok then self.Active[player]=engine end
    return ok,message
end

function Unified:Stop(player)
    local engine=self:Engine(player)
    if not engine then
        if self.Rack:IsRunning(player) then engine=self.Rack
        elseif self.Physical:IsRunning(player) then engine=self.Physical end
    end
    if not engine then
        return false,"No simulation running"
    end
    local ok,message=engine:Stop(player)
    if ok then self.Active[player]=nil end
    return ok,message
end

function Unified:SetStatus(player,running,grounded)
    -- The physical engine writes the same attributes as the rack engine.
    self.Physical:SetStatus(player,running,grounded)
end

function Unified:InputCrank(player,id,speed,holding,release)
    local engine=self:Engine(player)
    if engine then engine:InputCrank(player,id,speed,holding,release) end
end
function Unified:InputMotor(player,key,holding)
    local engine=self:Engine(player)
    if engine then engine:InputMotor(player,key,holding) end
end
function Unified:InputRope(player,key,holding)
    local engine=self:Engine(player)
    if engine then engine:InputRope(player,key,holding) end
end
function Unified:InputRack(player,id,direction,holding,release)
    if self:Engine(player)==self.Rack then
        self.Rack:InputRack(player,id,direction,holding,release)
    end
end
function Unified:BeginRack(player,request)
    if self:Engine(player)~=self.Rack then
        return false,"This assembly does not have a rack drive"
    end
    return self.Rack:BeginRack(player,request)
end
function Unified:BeginCrank(player,request)
    local engine=self:Engine(player)
    if not engine then return false,"Start an assembly simulation first" end
    return engine:BeginCrank(player,request)
end
function Unified:Pause(player)
    local engine=self:Engine(player)
    if not engine then return false,"Start simulation first" end
    return engine:Pause(player)
end
function Unified:Reset(player)
    local engine=self:Engine(player)
    if not engine then return false,"Start simulation first" end
    local ok,message=engine:Reset(player)
    if not engine:IsRunning(player) then self.Active[player]=nil end
    return ok,message
end
function Unified:Info(player,payload)
    local engine=self:Engine(player)
    if not engine then
        engine=self:Choose(player,payload)
        if not engine then return false,"Assembly mode is incompatible" end
    end
    return engine:Info(player,payload)
end
function Unified:SyncRelationship(player,relation)
    local engine=self:Engine(player)
    if not engine then return true end
    return engine:SyncRelationship(player,relation)
end
function Unified:ClearPlayer(player)
    self.Active[player]=nil
    self.Rack:ClearPlayer(player)
    self.Physical:ClearPlayer(player)
end

return table.freeze(Unified)
