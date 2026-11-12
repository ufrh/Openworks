--!strict
-- Creates actual Roblox Tool instances in StarterPack.
-- No Handles and no custom hotbar. Roblox provides equipment and hotkeys.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")
local StarterPlayer = game:GetService("StarterPlayer")

local definitions = require(
    ReplicatedStorage:WaitForChild("Openworks")
        :WaitForChild("Construction")
        :WaitForChild("ToolDefinitions")
)

local Provisioner = {}

local function createTemplate(definition)
    local displayName=definition.Name or definition.Id
    -- Tool names may differ from internal IDs (Assembly & Simulation).
    -- Always replace by the immutable OpenworksToolId, not by display name.
    for _, existing in ipairs(StarterPack:GetChildren()) do
        if existing:IsA("Tool")
            and existing:GetAttribute("OpenworksToolId")==definition.Id then
            existing:Destroy()
        elseif existing.Name==displayName then
            warn("[OPENWORKS] StarterPack name conflict: "..displayName)
            return nil
        end
    end

    local tool = Instance.new("Tool")
    tool.Name = definition.Name or definition.Id
    tool.ToolTip = definition.Tooltip
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    tool.ManualActivationOnly = false
    tool:SetAttribute("OpenworksToolId", definition.Id)
    tool.Parent = StarterPack

    return tool
end

local function alreadyOwned(player, id)
    local backpack = player:FindFirstChildOfClass("Backpack")
    local character = player.Character

    for _, container in ipairs({ backpack, character }) do
        if container then
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("Tool") and item:GetAttribute("OpenworksToolId") == id then
                    return true
                end
            end
        end
    end

    return false
end

function Provisioner.Start()
    StarterPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
    -- Clean up legacy Assemble tool copies from the pre-named-Assembly
    -- workflow; native Assembly now occupies its own hotbar slot.
    local legacyIds = {
        Assemble=true,Edit=true,Assembly=true,
        Simulate=true,Inspect=true,Weld=true,
    }
    local function removeLegacy(container)
        if not container then return end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local id=tool:GetAttribute("OpenworksToolId")
                if legacyIds[id] or (id==nil and legacyIds[tool.Name]) then
                    tool:Destroy()
                end
            end
        end
    end
    removeLegacy(StarterPack)
    for _, player in ipairs(Players:GetPlayers()) do
        removeLegacy(player:FindFirstChildOfClass("Backpack"))
        removeLegacy(player.Character)
    end

    local templates = {}
    for _, definition in ipairs(definitions) do
        local template = createTemplate(definition)
        if template then
            templates[definition.Id] = template
        end
    end

    -- StarterPack automatically handles fresh spawns and respawns.
    -- Cover players who were already present during a Studio script reload.
    for _, player in ipairs(Players:GetPlayers()) do
        task.defer(function()
            local backpack = player:FindFirstChildOfClass("Backpack")
                or player:WaitForChild("Backpack", 10)
            if not backpack then
                return
            end

            for _, definition in ipairs(definitions) do
                local template = templates[definition.Id]
                if template and not alreadyOwned(player, definition.Id) then
                    template:Clone().Parent = backpack
                end
            end
        end)
    end

    print("[OPENWORKS] StarterPack native tools provisioned: Build, Mechanics, Assembly & Simulation")
end

return Provisioner
