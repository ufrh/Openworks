--!strict
-- Search the actual available shaft insertion depth, not just the first
-- depth selected by cursor. A solid behind a through-hole is a hard stop.
-- Shared construction geometry: this never authorizes an intersection.
local Alignment=require(script.Parent:WaitForChild("AlignmentMath"))
local MultiFit=require(script.Parent:WaitForChild("MultiFitMath"))
local Grid=require(script.Parent:WaitForChild("GridMath"))
local Config=require(script.Parent:WaitForChild("BuildConfig"))

local Insertion={}
Insertion.MaxSearchSteps=28 -- 14U of surrounding depth, both directions

local overlap=OverlapParams.new()
overlap.FilterType=Enum.RaycastFilterType.Include
overlap.RespectCanCollide=false
overlap.MaxParts=0

local function contactSolid(part:BasePart):boolean
    -- Preview construction intentionally sets CanCollide=false on ALL
    -- its ghosts. Determine physical intent from metadata instead, so a
    -- component's non-Geometry named solid cannot slip through a wall.
    return part:GetAttribute("GearPivotOnly")~=true
        and part:GetAttribute("OpenworksCollisionMode")~="VisualOnly"
        and part:GetAttribute("OpenworksCollisionMode")~="PivotOnly"
end

-- Evaluate the EXACT candidate pose using genuine Roblox collision geometry.
-- Broadphase contacts with the CSG wall of an aligned bore are permitted
-- only after the shared precise shaft-to-hole fit predicate has passed.
-- Every OTHER colliding component, plate or backstop remains a hard blocker.
function Insertion.Clear(ghost:Model,ignored): (boolean,string?)
    local built=workspace:FindFirstChild(Config.FolderName)
    if not built then return true end
    overlap.FilterDescendantsInstances={built}
    for _,solid in ipairs(ghost:GetDescendants()) do
        if not solid:IsA("BasePart") or not contactSolid(solid) then continue end
        local moving=solid:FindFirstAncestorOfClass("Model")
        local probe=solid:Clone()
        probe.Name="OPENWORKS_BoreDepthProbe"
        probe.Size=Vector3.new(
            math.max(0.015,solid.Size.X-0.006),
            math.max(0.015,solid.Size.Y-0.006),
            math.max(0.015,solid.Size.Z-0.006))
        probe.CFrame=solid.CFrame
        probe.Transparency=1
        probe.CanCollide=false
        probe.CanTouch=false
        probe.CanQuery=true
        probe.Anchored=true
        probe.Parent=workspace
        local ok,hits=pcall(function()
            return workspace:GetPartsInPart(probe,overlap)
        end)
        probe:Destroy()
        if not ok then return false,"Collision query unavailable" end
        for _,part in ipairs(hits) do
            if not part:IsA("BasePart") or not part.CanCollide
                or part:GetAttribute("GearPivotOnly")==true
                or part:GetAttribute("OpenworksCollisionMode")=="VisualOnly"
                then continue end
            local other=part:FindFirstAncestorOfClass("Model")
            if other and other.Parent==built
                and not (ignored and ignored[other]) then
                if not (moving and MultiFit.Check(moving,other)) then
                    return false,"Shaft insertion stops before "..other.Name
                end
            end
        end
    end
    return true
end

-- Snap to existing 0.5U insertion lattice. Keep the cursor's chosen depth
-- when clear. If obstructed, try each shallower/deeper candidate in order
-- of distance from the intended position, without modifying dimensions.
-- Both directions supported: shaft->hole and hole->shaft.
function Insertion.Resolve(ghost:Model,source:Model,target:Model,
    movingShaft:boolean,previewCF:CFrame,preferredU:number,ignored):
    (CFrame?,number?,string?)
    local shaft=if movingShaft then source else target
    local hole=if movingShaft then target else source
    local low,high=Alignment.InsertionBounds(shaft,hole)
    if not low then return nil,nil,"No valid insertion range" end
    local lowStep=math.ceil(low*2-1e-6)
    local highStep=math.floor(high*2+1e-6)
    if lowStep>highStep then return nil,nil,"No allowable insertion depth" end

    local original=ghost:GetPivot()
    local anchorU=math.clamp(math.round(preferredU*2),lowStep,highStep)
    -- Compute the movement axis from the ALREADY SOLVED aligned pose.
    -- In reverse mode the hole moves opposite to positive shaft offset.
    ghost:PivotTo(previewCF)
    local holeCF=if movingShaft then target:GetPivot()
        else source:GetPivot()
    local localAxis=Alignment.TargetAxis(hole)
    if not localAxis then
        ghost:PivotTo(original)
        return nil,nil,"Target has no valid bore axis"
    end
    local axis=holeCF:VectorToWorldSpace(localAxis).Unit
    if not movingShaft then axis=-axis end

    local bestCF,bestU=nil,nil
    local failure="No unobstructed shaft insertion depth"
    local function attempt(step:number):boolean
        if step<lowStep or step>highStep then return false end
        local units=step*0.5
        local candidate=CFrame.new(axis*((units-preferredU)*Grid.Unit))*previewCF
        ghost:PivotTo(candidate)
        local actualSource=source
        local actualTarget=target
        local shaftModel=if movingShaft then actualSource else actualTarget
        local holeModel=if movingShaft then actualTarget else actualSource
        local fits=MultiFit.Check(
            if movingShaft then shaftModel else holeModel,
            if movingShaft then holeModel else shaftModel)
        if fits then
            local clear,reason=Insertion.Clear(ghost,ignored)
            if clear then
                bestCF,bestU=candidate,units
                return true
            end
            failure=reason or failure
        end
        return false
    end

    local found=attempt(anchorU)
    if not found then
        local limit=math.min(Insertion.MaxSearchSteps,
            math.max(anchorU-lowStep,highStep-anchorU))
        for radius=1,limit do
            -- Bias toward the entry side the player was already using,
            -- but allow the opposite side if that is the only clear path.
            local inwardFirst=if preferredU<0 then -1 else 1
            if attempt(anchorU+inwardFirst*radius)
                or attempt(anchorU-inwardFirst*radius) then
                found=true
                break
            end
        end
    end
    ghost:PivotTo(original)
    return bestCF,bestU,if found then nil else failure
end

return table.freeze(Insertion)
