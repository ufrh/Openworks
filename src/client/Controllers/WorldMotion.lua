--!strict
-- Visual-only damped motion. This never writes the server-authored placement.
-- Snap/commit/physics use exact CFrames; only previews and turn animations
-- are interpolated for a premium, weighty mechanical feel.
local RunService = game:GetService("RunService")
local WorldMotion = {}

function WorldMotion.Step(current: CFrame?, goal: CFrame, dt: number, response: number)
    if not current then return goal end
    return current:Lerp(goal, 1 - math.exp(-math.clamp(dt,0,0.1) * (response or 16)))
end

function WorldMotion.AnimateTurn(models, delta: CFrame, seconds: number)
    local ghosts = {}
    local original = {}
    local start = os.clock()
    for _, model in ipairs(models) do
        if not model or not model.Parent then continue end
        local clone = model:Clone()
        clone.Name = "OPENWORKS_TurnMotion"
        local from = model:GetPivot()
        for _, part in ipairs(clone:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
                part.CanTouch = false
                part.CanQuery = false
                part.Anchored = true
                part.LocalTransparencyModifier = 0
                part.CastShadow = false
            end
        end
        clone.Parent = workspace
        table.insert(ghosts,{copy=clone,from=from})
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                table.insert(original,{part=part,previous=part.LocalTransparencyModifier})
                part.LocalTransparencyModifier = 1
            end
        end
    end

    local connection
    local function cleanup()
        if connection then connection:Disconnect() connection = nil end
        for _, entry in ipairs(ghosts) do
            if entry.copy.Parent then entry.copy:Destroy() end
        end
        for _, item in ipairs(original) do
            if item.part.Parent then
                item.part.LocalTransparencyModifier = item.previous
            end
        end
    end

    connection = RunService.RenderStepped:Connect(function()
        local t = math.clamp((os.clock()-start)/math.max(seconds,0.01),0,1)
        local eased = t*t*(3-2*t)
        for _, entry in ipairs(ghosts) do
            if entry.copy.Parent then
                entry.copy:PivotTo(entry.from:Lerp(delta * entry.from,eased))
            end
        end
        if t >= 1 then cleanup() end
    end)
    return cleanup
end

return table.freeze(WorldMotion)
