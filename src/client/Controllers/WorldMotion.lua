--!strict
-- OPENWORKS unified visual-motion profile.
-- Every build/edit/assembly preview uses the same responsive damping.
-- Only presentation clones/ghosts are interpolated: placement, collision,
-- constraints, sizes and persistence remain EXACT server-authoritative state.
local RunService=game:GetService("RunService")

local WorldMotion={}
WorldMotion.Profile=table.freeze({
    Placement=30,   -- 95% of target in ~100 ms: crisp, not instant
    Scale=34,       -- grips and actual resizing previews stay synchronized
    TurnSeconds=0.20,
    NudgeSeconds=0.14,
    FrameCap=0.075,
    TeleportDistance=12,
})

local running=setmetatable({}, {__mode="k"})
local MAX_ANIMATED_PARTS=260
local MAX_ANIMATED_MODELS=48

function WorldMotion.Alpha(dt:number,response:number?):number
    return 1-math.exp(
        -math.clamp(dt,0,WorldMotion.Profile.FrameCap)
        *(response or WorldMotion.Profile.Placement))
end

function WorldMotion.Step(current:CFrame?,goal:CFrame,dt:number,response:number?):CFrame
    if not current
        or (current.Position-goal.Position).Magnitude
            >WorldMotion.Profile.TeleportDistance then
        return goal
    end
    local result=current:Lerp(goal,WorldMotion.Alpha(dt,response))
    if (result.Position-goal.Position).Magnitude<0.0002
        and result.LookVector:Dot(goal.LookVector)>0.999999
        and result.UpVector:Dot(goal.UpVector)>0.999999 then
        return goal
    end
    return result
end

function WorldMotion.StepSize(current:Vector3?,goal:Vector3,
    dt:number,response:number?):Vector3
    if not current then return goal end
    local result=current:Lerp(goal,WorldMotion.Alpha(dt,response))
    return if (result-goal).Magnitude<0.0002 then goal else result
end

-- A fast-out turn is much more responsive than a symmetrical ease-in-out:
-- input responds on the FIRST frame, then gently settles in the last frames.
function WorldMotion.Ease(t:number):number
    local x=math.clamp(t,0,1)
    return x*(2-x)
end

function WorldMotion.Cancel(models)
    for _,model in ipairs(models or {}) do
        local stop=running[model]
        if stop then stop() end
    end
end

-- Visual-only transition on changes committed by the server. The actual
-- authored models stay where the server decides; this lightweight ghost
-- merely presents the movement and is noncolliding/nonqueryable.
-- The returned cleanup is also called for rejected operations.
function WorldMotion.AnimateTurn(models,delta:CFrame,seconds:number?)
    WorldMotion.Cancel(models)
    local valid={}
    local partCount=0
    for _,model in ipairs(models or {}) do
        if model and model.Parent and model:IsA("Model") then
            table.insert(valid,model)
            for _,part in ipairs(model:GetDescendants()) do
                if part:IsA("BasePart") then partCount+=1 end
            end
        end
    end
    if #valid==0 or #valid>MAX_ANIMATED_MODELS
        or partCount>MAX_ANIMATED_PARTS then
        -- Huge assemblies favor responsiveness over hundreds of clones.
        return function() end
    end

    local ghosts={}
    local originals={}
    local connection
    local finished=false
    local function cleanup()
        if finished then return end
        finished=true
        if connection then connection:Disconnect() connection=nil end
        for _,entry in ipairs(ghosts) do
            if entry.copy.Parent then entry.copy:Destroy() end
        end
        for _,item in ipairs(originals) do
            if item.part.Parent then
                item.part.LocalTransparencyModifier=item.previous
            end
        end
        for _,model in ipairs(valid) do
            if running[model]==cleanup then running[model]=nil end
        end
    end

    for _,model in ipairs(valid) do
        local clone=model:Clone()
        clone.Name="OPENWORKS_MotionVisual"
        clone:SetAttribute("OPENWORKS_PresentationOnly",true)
        local from=model:GetPivot()
        for _,part in ipairs(clone:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide=false
                part.CanTouch=false
                part.CanQuery=false
                part.Anchored=true
                part.LocalTransparencyModifier=0
                part.CastShadow=false
            elseif part:IsA("Highlight") or part:IsA("SelectionBox")
                or part:IsA("BillboardGui") then
                part:Destroy()
            end
        end
        clone.Parent=workspace
        table.insert(ghosts,{copy=clone,from=from})
        for _,part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                table.insert(originals,{
                    part=part,previous=part.LocalTransparencyModifier,
                })
                part.LocalTransparencyModifier=1
            end
        end
    end
    for _,model in ipairs(valid) do running[model]=cleanup end

    local start=os.clock()
    local duration=math.max(0.035,seconds or WorldMotion.Profile.TurnSeconds)
    connection=RunService.RenderStepped:Connect(function()
        local t=math.clamp((os.clock()-start)/duration,0,1)
        local eased=WorldMotion.Ease(t)
        for _,entry in ipairs(ghosts) do
            if entry.copy.Parent then
                entry.copy:PivotTo(entry.from:Lerp(delta*entry.from,eased))
            end
        end
        if t>=1 then cleanup() end
    end)
    return cleanup
end

function WorldMotion.AnimateMove(models,direction:Vector3,seconds:number?)
    if direction.Magnitude<0.00001 then return function() end end
    return WorldMotion.AnimateTurn(models,CFrame.new(direction),
        seconds or WorldMotion.Profile.NudgeSeconds)
end

return table.freeze(WorldMotion)
