--!strict
-- Switch from the edit-only invisible freecam avatar to a real walking /
-- seated character ONLY when the simulated graph contains a seat plate.
-- Seat control authorization is always checked server-side.
local Runtime={}
local function humanoidFor(player)
    local character=player.Character
    return character,character and character:FindFirstChildOfClass("Humanoid")
end
function Runtime.OperatorSeatId(player,session)
    if not session or not session.Seats then return nil end
    local _,humanoid=humanoidFor(player)
    local sitting=humanoid and humanoid.SeatPart
    if not sitting or not sitting:IsA("Seat") then return nil end
    local model=sitting:FindFirstAncestorOfClass("Model")
    if not model or model:GetAttribute("OwnerUserId")~=player.UserId
        or model:GetAttribute("SeatRole")~="Operator" then return nil end
    local id=model:GetAttribute("InstanceId")
    if type(id)=="string" and session.Seats[id]==sitting then
        return id
    end
    return nil
end
function Runtime.CanControl(player,session,seatId)
    if type(seatId)~="string" or seatId=="" then return true end
    -- When the active mechanism has NO seat, freecam/manual bindings
    -- remain compatible even if a motor was routed elsewhere on the plot.
    if not session or not session.Seats then return true end
    return Runtime.OperatorSeatId(player,session)==seatId
end
function Runtime.Start(player,graph,copies,session)
    local candidates={}
    for _,original in ipairs(graph.models or {}) do
        if original:GetAttribute("TemplateId")=="SeatPlate" then
            local id=original:GetAttribute("InstanceId")
            local clone=copies[id]
            local seat=clone and clone.PrimaryPart
            if seat and seat:IsA("Seat") then
                seat.Disabled=false
                seat.CanTouch=true
                table.insert(candidates,{id=id,seat=seat,
                    role=original:GetAttribute("SeatRole") or "Operator"})
            end
        end
    end
    if #candidates==0 then
        player:SetAttribute("OPENWORKS_SimulationHasSeat",false)
        return
    end
    table.sort(candidates,function(a,b)
        if a.role~=b.role then return a.role=="Operator" end
        return a.id<b.id
    end)
    session.Seats={}
    for _,entry in ipairs(candidates) do session.Seats[entry.id]=entry.seat end
    player:SetAttribute("OPENWORKS_SimulationHasSeat",true)
    local char,hum=humanoidFor(player)
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if not char or not hum or not root then return end
    root.Anchored=false
    hum.WalkSpeed=16
    hum.JumpPower=50
    hum.JumpHeight=7.2
    hum.AutoRotate=true
    for _,desc in ipairs(char:GetDescendants()) do
        if desc:IsA("BasePart") and not desc:FindFirstAncestorOfClass("Tool") then
            desc.Transparency=if desc.Name=="HumanoidRootPart" then 1 else 0
            desc.CanCollide=desc.Name~="HumanoidRootPart"
            desc.CanTouch=true
        elseif desc:IsA("Decal") then
            desc.Transparency=0
        end
    end
    local initial=candidates[1].seat
    char:PivotTo(initial.CFrame*CFrame.new(0,3,0))
    task.defer(function()
        if player.Parent and session.World and session.World.Parent
            and initial.Parent and hum.Parent then
            initial:Sit(hum)
        end
    end)
end
function Runtime.Stop(player,session)
    if not session or not session.Seats then
        player:SetAttribute("OPENWORKS_SimulationHasSeat",false)
        return
    end
    local char,hum=humanoidFor(player)
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if hum then hum.Sit=false end
    if root then
        local origin=player:GetAttribute("OPENWORKS_PlotOrigin")
        if typeof(origin)=="Vector3" and char then
            char:PivotTo(CFrame.new(origin+Vector3.new(0,5,0)))
        end
        root.Anchored=true
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
    end
    if hum then
        hum.WalkSpeed=0
        hum.JumpPower=0
        hum.JumpHeight=0
        hum.AutoRotate=false
    end
    if char then
        for _,desc in ipairs(char:GetDescendants()) do
            if desc:IsA("BasePart")
                and not desc:FindFirstAncestorOfClass("Tool") then
                desc.Transparency=1
                desc.CanCollide=false
                desc.CanTouch=false
            elseif desc:IsA("Decal") then desc.Transparency=1 end
        end
    end
    session.Seats=nil
    player:SetAttribute("OPENWORKS_SimulationHasSeat",false)
    -- Seating may have unequipped the native Simulate Tool. Return it
    -- to the character so P and the normal build UI keep working.
    if hum and char and char.Parent then
        local backpack=player:FindFirstChildOfClass("Backpack")
        if backpack then
            for _,tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool")
                    and tool:GetAttribute("OpenworksToolId")=="AssemblySimulation" then
                    hum:EquipTool(tool)
                    break
                end
            end
        end
    end
end
return table.freeze(Runtime)
