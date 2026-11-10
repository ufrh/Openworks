--!strict
-- Immediate local construction feedback. A red preview is not submitted:
-- the server still authoritatively rechecks on placement/finalization.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("BuildConfig"))
local Bore = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("BoreClearance"))

local Feedback = {}
Feedback.ValidColor = Color3.fromRGB(83, 176, 241)
Feedback.InvalidColor = Color3.fromRGB(241, 83, 93)

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.RespectCanCollide = false
overlap.MaxParts = 0

function Feedback.Check(ghost: Model, ignored: { [Instance]: boolean }?,
    sourceId: string?, opening: Model?): (boolean, string?)
    local built = workspace:FindFirstChild(Config.FolderName)
    if not built then return true end
    overlap.FilterDescendantsInstances = { built }

    for _, part in ipairs(ghost:GetDescendants()) do
        if not part:IsA("BasePart") then continue end
        local probe = part:Clone()
        -- Actual precompiled CSG geometry, not a bounding-box-only check.
        probe.Name = "OPENWORKS_LocalPreviewProbe"
        probe.Size = Vector3.new(
            math.max(0.015, part.Size.X - 0.006),
            math.max(0.015, part.Size.Y - 0.006),
            math.max(0.015, part.Size.Z - 0.006)
        )
        probe.CFrame = part.CFrame
        probe.Transparency = 1
        probe.CanQuery = true
        probe.CanCollide = false
        probe.CanTouch = false
        probe.Parent = workspace

        local ok, touching = pcall(function()
            return workspace:GetPartsInPart(probe, overlap)
        end)
        probe:Destroy()
        if not ok then return false, "Collision query unavailable" end

        for _, object in ipairs(touching) do
            local target = object:FindFirstAncestorOfClass("Model")
            if target and target.Parent == built
                and not (ignored and ignored[target]) then
                local movingModel = part:FindFirstAncestorOfClass("Model")
                local eligible = target == opening and sourceId
                    and movingModel
                    and movingModel:GetAttribute("InstanceId") == sourceId
                local fits = false
                if eligible then fits = Bore.ShaftFits(movingModel, target) end
                if not fits then
                    return false, tostring(movingModel and movingModel.Name or part.Name)
                        .. " interferes with " .. tostring(target.Name)
                end
            end
        end
    end
    return true
end

function Feedback.IsClear(ghost: Model, ignored: { [Instance]: boolean }?): boolean
    return Feedback.Check(ghost, ignored)
end

function Feedback.Paint(ghost: Model?, valid: boolean)
    if not ghost then return end
    local color = if valid then Feedback.ValidColor else Feedback.InvalidColor
    for _, object in ipairs(ghost:GetDescendants()) do
        if object:IsA("BasePart") then
            object.Color = color
            if object:IsA("PartOperation") then object.UsePartColor = true end
        elseif object:IsA("Highlight") then
            object.FillColor = color
            object.OutlineColor = color
        end
    end
end

return table.freeze(Feedback)
