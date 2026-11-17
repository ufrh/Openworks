--!strict
-- Search the actual available shaft insertion depth, not just the first
-- depth selected by cursor. A solid behind a through-hole is a hard stop.
-- Shared construction geometry: this never authorizes an intersection.
local Alignment=require(script.Parent:WaitForChild("AlignmentMath"))
local MultiFit=require(script.Parent:WaitForChild("MultiFitMath"))
local Bore=require(script.Parent:WaitForChild("BoreClearance"))
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

local function authorizedBoreContact(moving,other)
    if not moving or not other then return false end
    -- A gear may be traversed during a multi-hole insertion, but only if
    -- it is actually CONCENTRIC and has sufficient positive bore clearance.
    -- Generic MultiFit.Check uses looser guide tolerances, which could
    -- show a green ghost for a gear the server then refuses to weld.
    local movingHub=type(moving:GetAttribute("GearTeeth"))=="number"
        or moving:GetAttribute("PrimitiveFamily")=="Pulley"
    local otherHub=type(other:GetAttribute("GearTeeth"))=="number"
        or other:GetAttribute("PrimitiveFamily")=="Pulley"
    if movingHub or otherHub then
        local shaft=if Alignment.IsShaft(moving) then moving
            elseif Alignment.IsShaft(other) then other else nil
        local hub=if movingHub then moving else if otherHub then other else nil
        if not shaft or not hub then return false end
        local cf=shaft:GetPivot()
        local offset=hub:GetPivot().Position-cf.Position
        local axis=cf.RightVector.Unit
        if (offset-axis*offset:Dot(axis)).Magnitude>0.012 then
            return false
        end
        return Bore.ShaftFits(shaft,hub)==true
    end
    return MultiFit.Check(moving,other)~=nil
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
                if not authorizedBoreContact(moving,other) then
                    return false,"Shaft insertion stops before "..other.Name
                end
            end
        end
    end
    return true
end

-- For multiple coaxial guides, preserve the exact geometry midpoint.
-- Single-hole fits may search nearby 0.5 U increments around the cursor
-- if obstructed. Multi-hole fits fail instead of shifting off center.
-- Both directions supported: shaft->hole and hole->shaft.
function Insertion.Resolve(ghost:Model,source:Model,target:Model,
    movingShaft:boolean,previewCF:CFrame,preferredU:number,ignored,
    requiredHoles,requiredMovingHoles):
    (CFrame?,number?,string?)
    local shaft=if movingShaft then source else target
    local hole=if movingShaft then target else source
    local low,high=Alignment.InsertionBounds(shaft,hole)
    if not low then return nil,nil,"No valid insertion range" end
    local lowStep=math.ceil(low*2-1e-6)
    local highStep=math.floor(high*2+1e-6)
    local centered=(requiredHoles and #requiredHoles>1)
        or (requiredMovingHoles and #requiredMovingHoles>1)
    if not centered and lowStep>highStep then
        return nil,nil,"No allowable insertion depth"
    end

    local original=ghost:GetPivot()
    -- Preserve the EXACT solved center for multi-guide fits. The old
    -- round(preferredU*2) silently moved odd-spaced patterns off center.
    local anchorU=if centered then preferredU else
        math.clamp(math.round(preferredU*2)*0.5,low,high)
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
    local function attempt(units:number):boolean
        if units<low-0.00001 or units>high+0.00001 then
            return false
        end
        local candidate=CFrame.new(axis*((units-preferredU)*Grid.Unit))*previewCF
        ghost:PivotTo(candidate)
        local actualSource=source
        local actualTarget=target
        local shaftModel=if movingShaft then actualSource else actualTarget
        local holeModel=if movingShaft then actualTarget else actualSource
        local fits=MultiFit.Check(
            if movingShaft then shaftModel else holeModel,
            if movingShaft then holeModel else shaftModel)
        if fits and movingShaft and requiredHoles then
            -- A clear fit at the first hole is NOT enough when the same
            -- shaft is expected to span several independent lugs.
            for _,otherHole in ipairs(requiredHoles) do
                if not MultiFit.Check(shaftModel,otherHole) then
                    fits=nil
                    failure="Shaft must pass through every aligned guide hole"
                    break
                end
            end
        end
        if fits and not movingShaft and requiredMovingHoles then
            -- Every coaxial moving lug must remain engaged on the
            -- stationary shaft after the reverse insertion is resolved.
            for _,otherHole in ipairs(requiredMovingHoles) do
                if not MultiFit.Check(otherHole,shaftModel) then
                    fits=nil
                    failure="Every moving guide hole must remain on the shaft"
                    break
                end
            end
        end
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
    if not found and not centered then
        -- Ordinary single-hole fitting can still seek a nearby unblocked
        -- depth on the familiar 0.5 U adjustment lattice.
        local anchorStep=math.round(anchorU*2)
        local limit=math.min(Insertion.MaxSearchSteps,
            math.max(anchorStep-lowStep,highStep-anchorStep))
        for radius=1,limit do
            local inwardFirst=if preferredU<0 then -1 else 1
            if attempt((anchorStep+inwardFirst*radius)*0.5)
                or attempt((anchorStep-inwardFirst*radius)*0.5) then
                found=true
                break
            end
        end
    end
    -- If the exact midpoint is blocked or cannot engage EVERY guide,
    -- reject the preview; do not "resolve" it by shifting to one hole.
    ghost:PivotTo(original)
    return bestCF,bestU,if found then nil else failure
end

return table.freeze(Insertion)
