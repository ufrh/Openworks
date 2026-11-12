--!strict
-- Three native Roblox tools; contextual subtools provide compatibility modes
-- for the existing controllers until each UI v2 phase is migrated.
-- Server authority is always the *equipped native tool*, not this client state.
local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local UserInputService=game:GetService("UserInputService")

local player=Players.LocalPlayer
local construction=ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local definitions=require(construction:WaitForChild("ToolDefinitions"))
local subtools=require(construction:WaitForChild("SubtoolDefinitions"))

local validIds={}
for _, definition in ipairs(definitions) do validIds[definition.Id]=true end

local ToolController={}
ToolController.__index=ToolController

function ToolController.new()
    return setmetatable({
        ActiveId=nil, -- compatibility mode, NOT native equipped ID
        PrimaryId=nil,
        SubtoolId=nil,
        ActiveTool=nil,
        LastSubtool={},
        Changed=Instance.new("BindableEvent"),
        SubtoolChanged=Instance.new("BindableEvent"),
        Activated=Instance.new("BindableEvent"),
        Connections={},
        ToolConnections={},
        BackpackConnection=nil,
        CharacterConnection=nil,
        ObservedBackpack=nil,
        ConsumedInput=nil,
        ShortcutGuard=nil,
        Started=false,
    },ToolController)
end

function ToolController:GetDefinition(primary)
    return subtools[primary or self.PrimaryId]
end

function ToolController:GetSubtool(id,primary)
    local definition=self:GetDefinition(primary)
    if not definition then return nil end
    for _, item in ipairs(definition.Items) do
        if item.Id==id then return item end
    end
    return nil
end

function ToolController:WasConsumed(input)
    return input~=nil and self.ConsumedInput==input
end

function ToolController:SetShortcutGuard(callback)
    self.ShortcutGuard=callback
end

function ToolController:Publish(previousMode,previousPrimary,previousSubtool)
    local chosen=self:GetSubtool(self.SubtoolId)
    self.ActiveId=chosen and chosen.LegacyMode or nil
    player:SetAttribute("OPENWORKS_PrimaryTool",self.PrimaryId or "")
    player:SetAttribute("OPENWORKS_ActiveSubtool",self.SubtoolId or "")
    -- Maintain the old HUD attribute only until the UI is fully migrated.
    player:SetAttribute("OPENWORKS_ActiveTool",self.ActiveId or "")
    if self.ActiveId~=previousMode or self.PrimaryId~=previousPrimary then
        self.Changed:Fire(self.ActiveId)
    end
    if self.PrimaryId~=previousPrimary or self.SubtoolId~=previousSubtool then
        self.SubtoolChanged:Fire(self.PrimaryId,self.SubtoolId,previousSubtool)
    end
end

function ToolController:SetSubtool(id)
    if not self.PrimaryId or not self:GetSubtool(id) then return false end
    if id==self.SubtoolId then return false end
    if self.PrimaryId=="AssemblySimulation"
        and id=="AssemblyEditor"
        and player:GetAttribute("OPENWORKS_Simulating")==true then
        return false -- Keep physics controls reachable during simulation.
    end
    local previousMode=self.ActiveId
    local previousPrimary=self.PrimaryId
    local previousSubtool=self.SubtoolId
    self.SubtoolId=id
    self.LastSubtool[self.PrimaryId]=id
    self:Publish(previousMode,previousPrimary,previousSubtool)
    print("[OPENWORKS] "..self.PrimaryId.." / "..id)
    return true
end

function ToolController:SetActive(tool)
    if self.ActiveTool==tool then return end
    local previousMode=self.ActiveId
    local previousPrimary=self.PrimaryId
    local previousSubtool=self.SubtoolId
    self.ActiveTool=tool
    local primary=if tool then tool:GetAttribute("OpenworksToolId") else nil
    self.PrimaryId=if type(primary)=="string" and validIds[primary] then primary else nil
    local definition=self:GetDefinition()
    self.SubtoolId=if definition then
        (self.LastSubtool[self.PrimaryId] or definition.Default) else nil
    self:Publish(previousMode,previousPrimary,previousSubtool)
    if self.PrimaryId then
        print("[OPENWORKS] Equipped "..self.PrimaryId.." / "..tostring(self.SubtoolId))
    end
end

function ToolController:HandleShortcut(input,processed)
    self.ConsumedInput=nil
    if processed or not self.PrimaryId
        or UserInputService:GetFocusedTextBox()
        or player:GetAttribute("OPENWORKS_CursorUIOpen")==true
        or player:GetAttribute("OPENWORKS_PlotMenuOpen")==true
        or player:GetAttribute("OPENWORKS_PropertiesOpen")==true
        or player:GetAttribute("OPENWORKS_ExplorerOpen")==true
        or player:GetAttribute("OPENWORKS_AssemblyNaming")==true then
        return
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        or UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
        or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then return end
    local definition=self:GetDefinition()
    if not definition then return end
    for _, item in ipairs(definition.Items) do
        if input.KeyCode==item.Key and item.Id~=self.SubtoolId then
            if self.ShortcutGuard and not self.ShortcutGuard(
                self.PrimaryId,self.SubtoolId,item.Id,input.KeyCode) then
                return
            end
            self.ConsumedInput=input
            self:SetSubtool(item.Id)
            return
        end
    end
end

function ToolController:BindTool(tool)
    if not tool:IsA("Tool") then return end
    local id=tool:GetAttribute("OpenworksToolId")
    if type(id)~="string" or not validIds[id] or self.ToolConnections[tool] then
        return
    end
    local connections={}
    self.ToolConnections[tool]=connections
    table.insert(connections,tool.Equipped:Connect(function() self:SetActive(tool) end))
    table.insert(connections,tool.Unequipped:Connect(function()
        if self.ActiveTool==tool then self:SetActive(nil) end
    end))
    table.insert(connections,tool.Activated:Connect(function()
        -- A click on docked UI must never also place/delete/select in world.
        -- Roblox Tool.Activated does not include gameProcessedEvent.
        if self.ActiveTool==tool
            and player:GetAttribute("OPENWORKS_ExplorerOpen")~=true then
            self.Activated:Fire(self.ActiveId)
        end
    end))
    table.insert(connections,tool.Destroying:Connect(function()
        if self.ActiveTool==tool then self:SetActive(nil) end
        for _,connection in ipairs(connections) do connection:Disconnect() end
        self.ToolConnections[tool]=nil
    end))
    if tool.Parent==player.Character then self:SetActive(tool) end
end

function ToolController:ObserveBackpack(backpack)
    if self.ObservedBackpack==backpack then return end
    if self.BackpackConnection then self.BackpackConnection:Disconnect() end
    self.ObservedBackpack=backpack
    for _,item in ipairs(backpack:GetChildren()) do self:BindTool(item) end
    self.BackpackConnection=backpack.ChildAdded:Connect(function(item)
        self:BindTool(item)
    end)
end

function ToolController:ObserveCharacter(character)
    if self.CharacterConnection then self.CharacterConnection:Disconnect() end
    self:SetActive(nil)
    for _,item in ipairs(character:GetChildren()) do self:BindTool(item) end
    self.CharacterConnection=character.ChildAdded:Connect(function(item)
        self:BindTool(item)
    end)
end

function ToolController:Start()
    if self.Started then return end
    self.Started=true
    -- Register before domain controllers, so one keystroke cannot both
    -- change subtools and execute its old action.
    table.insert(self.Connections,UserInputService.InputBegan:Connect(function(input,processed)
        self:HandleShortcut(input,processed)
    end))
    table.insert(self.Connections,player.ChildAdded:Connect(function(child)
        if child:IsA("Backpack") then self:ObserveBackpack(child) end
    end))
    table.insert(self.Connections,player.CharacterAdded:Connect(function(character)
        self:ObserveCharacter(character)
    end))
    local backpack=player:FindFirstChildOfClass("Backpack")
        or player:WaitForChild("Backpack",10)
    if backpack then
        self:ObserveBackpack(backpack)
    else
        warn("[OPENWORKS] Native Backpack was not available on client startup.")
    end
    if player.Character then self:ObserveCharacter(player.Character) end
end

function ToolController:Destroy()
    if not self.Started then return end
    self.Started=false
    if self.BackpackConnection then self.BackpackConnection:Disconnect() end
    if self.CharacterConnection then self.CharacterConnection:Disconnect() end
    for _,connection in ipairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    for _,connections in pairs(self.ToolConnections) do
        for _,connection in ipairs(connections) do connection:Disconnect() end
    end
    table.clear(self.ToolConnections)
    self.Changed:Destroy()
    self.SubtoolChanged:Destroy()
    self.Activated:Destroy()
end

return ToolController
