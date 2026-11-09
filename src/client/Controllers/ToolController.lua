--!strict
-- Observes native Roblox Tools. No custom equip logic or hotbar UI.
-- Changed and Activated are BindableEvents that Phase 02 can consume.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local definitions = require(
    ReplicatedStorage:WaitForChild("Openworks")
        :WaitForChild("Construction")
        :WaitForChild("ToolDefinitions")
)

local validIds = {}
for _, definition in ipairs(definitions) do
    validIds[definition.Id] = true
end

local ToolController = {}
ToolController.__index = ToolController

function ToolController.new()
    return setmetatable({
        ActiveId = nil,
        ActiveTool = nil,
        Changed = Instance.new("BindableEvent"),
        Activated = Instance.new("BindableEvent"),
        Connections = {},
        ToolConnections = {},
        BackpackConnection = nil,
        CharacterConnection = nil,
        ObservedBackpack = nil,
        Started = false,
    }, ToolController)
end

function ToolController:SetActive(tool)
    if self.ActiveTool == tool then
        return
    end

    self.ActiveTool = tool
    self.ActiveId = if tool then tool:GetAttribute("OpenworksToolId") else nil
    self.Changed:Fire(self.ActiveId)

    if self.ActiveId then
        print("[OPENWORKS] Equipped " .. self.ActiveId)
    end
end

function ToolController:BindTool(tool)
    if not tool:IsA("Tool") then
        return
    end

    local id = tool:GetAttribute("OpenworksToolId")
    if type(id) ~= "string" or not validIds[id] then
        return
    end
    if self.ToolConnections[tool] then
        return
    end

    local connections = {}
    self.ToolConnections[tool] = connections

    table.insert(connections, tool.Equipped:Connect(function()
        self:SetActive(tool)
    end))

    table.insert(connections, tool.Unequipped:Connect(function()
        if self.ActiveTool == tool then
            self:SetActive(nil)
        end
    end))

    table.insert(connections, tool.Activated:Connect(function()
        if self.ActiveTool ~= tool then
            return
        end

        self.Activated:Fire(id)
        print("[OPENWORKS] " .. id .. " activated (interaction pending)")
    end))

    table.insert(connections, tool.Destroying:Connect(function()
        if self.ActiveTool == tool then
            self:SetActive(nil)
        end

        for _, connection in ipairs(connections) do
            connection:Disconnect()
        end
        self.ToolConnections[tool] = nil
    end))

    if tool.Parent == player.Character then
        self:SetActive(tool)
    end
end

function ToolController:ObserveBackpack(backpack)
    if self.ObservedBackpack == backpack then
        return
    end

    if self.BackpackConnection then
        self.BackpackConnection:Disconnect()
    end
    self.ObservedBackpack = backpack

    for _, item in ipairs(backpack:GetChildren()) do
        self:BindTool(item)
    end

    self.BackpackConnection = backpack.ChildAdded:Connect(function(item)
        self:BindTool(item)
    end)
end

function ToolController:ObserveCharacter(character)
    if self.CharacterConnection then
        self.CharacterConnection:Disconnect()
    end
    self:SetActive(nil)

    for _, item in ipairs(character:GetChildren()) do
        self:BindTool(item)
    end

    self.CharacterConnection = character.ChildAdded:Connect(function(item)
        self:BindTool(item)
    end)
end

function ToolController:Start()
    if self.Started then
        return
    end
    self.Started = true

    table.insert(self.Connections, player.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then
            self:ObserveBackpack(child)
        end
    end))

    table.insert(self.Connections, player.CharacterAdded:Connect(function(character)
        self:ObserveCharacter(character)
    end))

    local backpack = player:FindFirstChildOfClass("Backpack")
        or player:WaitForChild("Backpack", 10)

    if backpack then
        self:ObserveBackpack(backpack)
    else
        warn("[OPENWORKS] Native Backpack was not available on client startup.")
    end

    if player.Character then
        self:ObserveCharacter(player.Character)
    end
end

function ToolController:Destroy()
    if not self.Started then
        return
    end
    self.Started = false

    if self.BackpackConnection then
        self.BackpackConnection:Disconnect()
        self.BackpackConnection = nil
    end
    if self.CharacterConnection then
        self.CharacterConnection:Disconnect()
        self.CharacterConnection = nil
    end

    for _, connection in ipairs(self.Connections) do
        connection:Disconnect()
    end
    table.clear(self.Connections)

    for _, connections in pairs(self.ToolConnections) do
        for _, connection in ipairs(connections) do
            connection:Disconnect()
        end
    end
    table.clear(self.ToolConnections)

    self.Changed:Destroy()
    self.Activated:Destroy()
end

return ToolController
