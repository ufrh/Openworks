--!strict
-- Player-owned rope/winch controls during the ACTIVE assembly simulation.
-- The server resolves the saved Rope relationship and binding: no client
-- supplied force, rope length, winch target, or physics body is trusted.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer

local Controller={}
Controller.__index=Controller

function Controller.new(assembly)
    return setmetatable({
        Assembly=assembly,Remote=RS:WaitForChild("OPENWORKS_RopeControl"),
        Held={},Connections={},Elapsed=0,
    },Controller)
end

function Controller:Active()
    return (self.Assembly.Mode=="Simulate"
            or player:GetAttribute("OPENWORKS_SimulationHasSeat")==true)
        and self.Assembly:IsSimulating()
        and player:GetAttribute("OPENWORKS_SimulationPaused")~=true
        and player:GetAttribute("OPENWORKS_PropertiesOpen")~=true
        and player:GetAttribute("OPENWORKS_ExplorerOpen")~=true
        and not UIS:GetFocusedTextBox()
end

function Controller:HasRopeKey(key)
    local folder=workspace:FindFirstChild("OPENWORKS_Relationships")
    if not folder then return false end
    for _,joint in ipairs(folder:GetChildren()) do
        if joint:GetAttribute("OwnerUserId")==player.UserId
            and joint:GetAttribute("Kind")=="Rope"
            and (joint:GetAttribute("RopeInKey")==key
                or joint:GetAttribute("RopeOutKey")==key) then
            return true
        end
    end
    return false
end

function Controller:Release()
    for key in pairs(self.Held) do
        self.Remote:FireServer(key,false)
    end
    table.clear(self.Held)
end

function Controller:Start()
    table.insert(self.Connections,UIS.InputBegan:Connect(function(input,processed)
        if not self:Active() then return end
        local key=input.KeyCode.Name
        -- Roblox's character movement can mark A/D handled even during
        -- engineering simulation. Honor explicitly bound steering cables
        -- while still respecting text entry and open property dialogs.
        if processed and key~="A" and key~="D" then return end
        if self:HasRopeKey(key) then
            self.Held[key]=true
            self.Remote:FireServer(key,true)
        end
    end))
    table.insert(self.Connections,UIS.InputEnded:Connect(function(input)
        local key=input.KeyCode.Name
        if self.Held[key] then
            self.Held[key]=nil
            self.Remote:FireServer(key,false)
        end
    end))
    table.insert(self.Connections,RunService.Heartbeat:Connect(function(dt)
        if not next(self.Held) then return end
        if not self:Active() then self:Release() return end
        self.Elapsed+=dt
        if self.Elapsed<0.1 then return end
        self.Elapsed=0
        for key in pairs(self.Held) do
            local enum=Enum.KeyCode[key]
            if not enum or not UIS:IsKeyDown(enum) then
                self.Held[key]=nil
                self.Remote:FireServer(key,false)
            else
                self.Remote:FireServer(key,true)
            end
        end
    end))
end

function Controller:Destroy()
    self:Release()
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
end

return Controller
