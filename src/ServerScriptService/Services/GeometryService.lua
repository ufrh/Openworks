-- Roblox projection of the authoritative block document.
-- Parts are disposable compiled representations, never the saved source.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local FORGE = require(ReplicatedStorage.FORGE)
local Units = require(ReplicatedStorage.OpenWorks.Shared.Units)

local GeometryService = FORGE.Class("Service", {
    Name = "GeometryService",
})

local runtime

function GeometryService:Init()
    runtime = Workspace:FindFirstChild("OpenWorksRuntime")
    if not runtime then
        runtime = Instance.new("Folder")
        runtime.Name = "OpenWorksRuntime"
        runtime.Parent = Workspace
    end

    -- Temporary flat workshop floor for the first vertical slice only.
    if not Workspace:FindFirstChild("Baseplate") and not Workspace:FindFirstChild("OpenWorksFloor") then
        local floor = Instance.new("Part")
        floor.Name = "OpenWorksFloor"
        floor.Anchored = true
        floor.Size = Vector3.new(512, 1, 512)
        floor.Position = Vector3.new(0, -0.5, 0)
        floor.Material = Enum.Material.Concrete
        floor.Color = Color3.fromRGB(118, 125, 132)
        floor.Parent = Workspace
    end
end

local function ownerFolder(userId)
    local name = tostring(userId)
    local folder = runtime:FindFirstChild(name)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = name
        folder.Parent = runtime
    end
    return folder
end

function GeometryService:Sync(player, document)
    local folder = ownerFolder(player.UserId)
    local seen = {}
    for _, block in ipairs(document.blocks) do
        seen[block.id] = true
        local part = folder:FindFirstChild(block.id)
        if not part then
            part = Instance.new("Part")
            part.Name = block.id
            part.Anchored = true
            part.Material = Enum.Material.Metal
            part.Color = Color3.fromRGB(70, 77, 86)
            part.TopSurface = Enum.SurfaceType.Smooth
            part.BottomSurface = Enum.SurfaceType.Smooth
            part:SetAttribute("OpenWorksId", block.id)
            part:SetAttribute("OpenWorksOwner", player.UserId)
            part.Parent = folder
        end
        part.Size = Vector3.new(
            Units.ToStuds(block.sx), Units.ToStuds(block.sy), Units.ToStuds(block.sz)
        )
        part.CFrame = CFrame.new(
            Units.ToStuds(block.x), Units.ToStuds(block.y), Units.ToStuds(block.z)
        )
    end

    for _, instance in ipairs(folder:GetChildren()) do
        if not seen[instance.Name] then
            instance:Destroy()
        end
    end
end

function GeometryService:Release(player)
    if runtime then
        local folder = runtime:FindFirstChild(tostring(player.UserId))
        if folder then folder:Destroy() end
    end
end

return GeometryService
