--!strict
-- Seat role / logical control routing only. These links NEVER become welds,
-- physical joints or implicit mechanical assembly edges.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local construction=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local Rope=require(construction:WaitForChild("RopeMath"))
local SeatLibrary=require(script.Parent:WaitForChild("SeatLibrary"))
local SeatControl={}
SeatControl.__index=SeatControl
local MOTOR_KEYS={
    F=true,R=true,T=true,Y=true,H=true,J=true,K=true,L=true,
    B=true,N=true,M=true,V=true,Z=true,X=true,C=true,
    One=true,Two=true,Three=true,Four=true,
}
local function safeName(value)
    return type(value)=="string" and #value>0 and #value<=40
        and value:match("%S")~=nil and not value:find("[%c]")
end
function SeatControl.new(deps)
    return setmetatable({D=deps},SeatControl)
end
function SeatControl:Control(player,id)
    local relation=self.D.mechanical:OwnedRelation(player,id)
    if not relation then return nil end
    local kind=relation:GetAttribute("Kind")
    if kind=="Rope" or (kind=="Bearing"
        and relation:GetAttribute("MotorEnabled")==true) then
        return relation
    end
    return nil
end
function SeatControl:Handle(player,action,payload)
    local d=self.D
    if action=="SetSeatRole" then
        local model=d.findOwned(player,payload.seatId)
        if not SeatLibrary.IsSeat(model)
            or not SeatLibrary.ValidRole(payload.role) then
            return false,"Select your seat plate and an operator/passenger role"
        end
        local before=d.snapshot(model)
        SeatLibrary.Apply(model,payload.role)
        -- A seat converted to Passenger must not retain operating routes.
        if payload.role=="Passenger" then
            for _,relation in ipairs(d.mechanical.Folder:GetChildren()) do
                if relation:GetAttribute("OwnerUserId")==player.UserId
                    and relation:GetAttribute("SeatId")==payload.seatId then
                    local old=d.mechanical:Snapshot(relation)
                    relation:SetAttribute("SeatId",nil)
                    d.commitJointEdit(player,old,d.mechanical:Snapshot(relation))
                end
            end
        end
        d.commitRecord(player,before,d.snapshot(model),true)
        return true,"Seat changed to "..payload.role
    end
    local relation=self:Control(player,payload.relationId)
    if not relation then return false,"Select an operable motor or rope" end
    if action=="RouteControl" then
        local seat=nil
        if payload.seatId~=nil then
            seat=d.findOwned(player,payload.seatId)
            if not SeatLibrary.IsSeat(seat)
                or seat:GetAttribute("SeatRole")~="Operator" then
                return false,"Route controls only to your operator seats"
            end
        end
        local previous=d.mechanical:Snapshot(relation)
        relation:SetAttribute("SeatId",if seat then payload.seatId else nil)
        d.commitJointEdit(player,previous,d.mechanical:Snapshot(relation))
        return true,if seat then "Control routed to operator seat"
            else "Control unlinked; freecam keys remain available"
    end
    if action=="ConfigureRoutedControl" then
        local name=payload.name
        if not safeName(name) then return false,"Use a name of 1–40 characters" end
        local kind=relation:GetAttribute("Kind")
        local first=payload.key
        local second=payload.secondKey
        if kind=="Bearing" then
            if not MOTOR_KEYS[first] then
                return false,"Choose a supported motor key"
            end
        else
            if type(first)~="string" or type(second)~="string"
                or first==second then
                return false,"Select two different winch keys"
            end
            local request=Rope.Attributes(relation)
            request.ropeInKey=first
            request.ropeOutKey=second
            local source=d.findOwned(player,relation:GetAttribute("SourceId"))
            local target=d.findOwned(player,relation:GetAttribute("TargetId"))
            if not source or not target then return false,"Rope is missing a body" end
            local a,b=Rope.Frames(source,target)
            if not Rope.Settings(request,(a-b).Magnitude) then
                return false,"Invalid winch key pair"
            end
        end
        local previous=d.mechanical:Snapshot(relation)
        relation:SetAttribute("ControlName",name)
        if kind=="Bearing" then
            relation:SetAttribute("MotorKey",first)
        else
            relation:SetAttribute("RopeInKey",first)
            relation:SetAttribute("RopeOutKey",second)
        end
        d.commitJointEdit(player,previous,d.mechanical:Snapshot(relation))
        return true,"Saved "..name.." and keybinds"
    end
    return false,"Unsupported seat action"
end
return SeatControl
