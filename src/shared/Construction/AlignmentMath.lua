--!strict
-- Shared, deterministic phase-04 coaxial placement math.
-- This positions geometry ONLY. It does not create a bearing/revolute joint.
-- A shaft is a full Cylinder primitive (local X axis).
-- A target is a circular/square tube (local X) or drilled block (local Y).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Grid = require(ReplicatedStorage:WaitForChild("Openworks")
    :WaitForChild("Construction"):WaitForChild("GridMath"))

local Alignment = {}
Alignment.MaxOffsetUnits = 64

local function family(model)
    -- Look at BOTH fields: a broad family attribute should not conceal the
    -- more descriptive template ID (e.g. "DrilledBlock_050").
    local id = tostring(model:GetAttribute("TemplateId") or model.Name)
    local category = tostring(model:GetAttribute("PrimitiveFamily") or "")
    return string.lower(id .. category):gsub("[%s_%-]", "")
end

local function axisOverride(model)
    local axis = model:GetAttribute("AxialAxis") or model:GetAttribute("OpeningAxis")
    if axis == "X" then return Vector3.xAxis end
    if axis == "Y" then return Vector3.yAxis end
    if axis == "Z" then return Vector3.zAxis end
    return nil
end

function Alignment.IsShaft(model)
    if not model or not model:IsA("Model") or not model.PrimaryPart then return false end
    local name = family(model)
    if string.find(name, "halfcylinder", 1, true) then return false end
    return string.find(name, "cylinder", 1, true) ~= nil
        or string.lower(tostring(model:GetAttribute("TemplateId") or model.Name))=="shaft"
end

function Alignment.TargetAxis(model)
    if not model or not model:IsA("Model") or not model.PrimaryPart then return nil end
    local name = family(model)
    if string.find(name, "halftube", 1, true) then return nil end
    local explicit = axisOverride(model)
    if explicit then return explicit end
    if string.find(name, "circulartube", 1, true)
        or string.find(name, "squaretube", 1, true)
        or string.find(name, "rectangulartube", 1, true)
        or string.find(name, "recttube", 1, true) then
        return Vector3.xAxis
    end
    if string.find(name, "drilledblock", 1, true)
        or string.find(name, "holeblock", 1, true) then
        -- Studio primitive generator subtracts a Y_AXIS cylinder.
        return Vector3.yAxis
    end
    return nil
end

function Alignment.ShaftIn(members)
    local best = nil
    local bestLength = -1
    for _, model in ipairs(members) do
        if Alignment.IsShaft(model) then
            local length = model.PrimaryPart.Size.X
            if length > bestLength then
                best = model
                bestLength = length
            end
        end
    end
    return best
end

function Alignment.IsOffsetValid(units)
    return type(units) == "number" and units == units
        and math.abs(units * 2 - math.round(units * 2)) < 0.0001
        and math.abs(units) <= Alignment.MaxOffsetUnits
end

-- Physical translational stops are the TWO END FACES OF THE HOUSING,
-- not the combined shaft/housing length. The reference for motion is
-- the shaft's axial CENTER. A long shaft may protrude on both sides,
-- but its center must never slide beyond either tube face.
-- Returns absolute center offset in construction U, relative to the
-- housing center; simulation converts it to its joint's initial frame.
function Alignment.OffsetBounds(shaft, opening)
    if not Alignment.IsShaft(shaft) or not Alignment.TargetAxis(opening)
        or not shaft.PrimaryPart or not opening.PrimaryPart then
        return nil,nil,"An opening and cylindrical shaft are required"
    end
    local axis=Alignment.TargetAxis(opening)
    local size=opening.PrimaryPart.Size
    local housingLength=math.abs(axis.X)*size.X
        +math.abs(axis.Y)*size.Y+math.abs(axis.Z)*size.Z
    local shaftLength=shaft.PrimaryPart.Size.X
    if housingLength<=0 or shaftLength<=0 then
        return nil,nil,"Tube and shaft must have nonzero length"
    end
    -- The center stays just INSIDE the two tube end planes. This small
    -- clearance prevents native Prismatic/Cylindrical constraints from
    -- pushing the center outside the housing due to solver tolerance.
    local endInset=math.min(0.012,housingLength*0.1)
    local bound=math.max(0,housingLength*0.5-endInset)/Grid.Unit
    return -bound,bound
end

-- Native Prismatic/Cylindrical constraints measure translation from
-- their initial common attachment frame (0 studs), not from the
-- construction plot's housing center. Compute that offset ONCE and
-- reuse the same bound conversion in authoring, simulation and tuning.
function Alignment.RelativeTravelBounds(shaft,opening)
    local low,high,reason=Alignment.OffsetBounds(shaft,opening)
    if not low then return nil,nil,reason end
    local axis=opening:GetPivot():VectorToWorldSpace(
        Alignment.TargetAxis(opening)).Unit
    local authored=(shaft:GetPivot().Position-opening:GetPivot().Position)
        :Dot(axis)/Grid.Unit
    return low-authored,high-authored
end

function Alignment.Engaged(shaft,opening)
    local lo,hi=Alignment.OffsetBounds(shaft,opening)
    if not lo then return false,hi end
    local axis=opening:GetPivot():VectorToWorldSpace(
        Alignment.TargetAxis(opening)
    ).Unit
    local separation=(shaft:GetPivot().Position-opening:GetPivot().Position)
        :Dot(axis)/Grid.Unit
    if separation<lo-0.005 or separation>hi+0.005 then
        return false,"Shaft must remain inside the opening"
    end
    return true
end

function Alignment.MatchSteps(orientation)
    for x = 0, 3 do
        for y = 0, 3 do
            for z = 0, 3 do
                local steps = { x = x, y = y, z = z }
                local candidate = Grid.Rotation(steps)
                if candidate.RightVector:Dot(orientation.RightVector) > 0.99999
                    and candidate.UpVector:Dot(orientation.UpVector) > 0.99999 then
                    return steps
                end
            end
        end
    end
    return nil
end

local function continuousShaftRotation(shaft,direction)
    local current=shaft:GetPivot().Rotation
    local currentAxis=current.RightVector
    local desired=if currentAxis:Dot(direction)>=0 then direction else -direction
    local cosine=math.clamp(currentAxis:Dot(desired),-1,1)
    local cross=currentAxis:Cross(desired)
    local transform
    if cross.Magnitude>0.00001 then
        transform=CFrame.fromAxisAngle(cross.Unit,math.acos(cosine))
    elseif cosine<0 then
        transform=CFrame.fromAxisAngle(current.UpVector,math.pi)
    else
        transform=CFrame.identity
    end
    -- Align with the true local bore orientation, not an arbitrary
    -- quarter-turn lookup which flips one side of rotated hole blocks.
    return transform*current
end

function Alignment.Plan(members, shaft, target, offsetUnits, rollDegrees)
    rollDegrees = rollDegrees or 0
    if type(rollDegrees) ~= "number" or rollDegrees ~= rollDegrees
        or math.abs(rollDegrees) > 360 then
        return nil, "Shaft roll must be between -360 and 360 degrees"
    end
    if not Alignment.IsOffsetValid(offsetUnits) then
        return nil, "Insertion offset must be in 0.5-U increments within +/-64 U"
    end
    if not Alignment.IsShaft(shaft) then
        return nil, "Select a Cylinder shaft or a component containing one"
    end

    local axisLocal = Alignment.TargetAxis(target)
    if not axisLocal then
        return nil, "Select a circular/square tube or a drilled-block opening"
    end

    local direction = target:GetPivot():VectorToWorldSpace(axisLocal).Unit
    local lo,hi,why=Alignment.OffsetBounds(shaft,target)
    if not lo then return nil,why end
    if offsetUnits<lo or offsetUnits>hi then
        return nil,string.format("Insertion must stay between %.1f and %.1f U",lo,hi)
    end

    -- Keep the authored shaft's free-angle orientation and choose the
    -- nearest aligned direction, avoiding a mirrored or flipped housing.
    local rotation=continuousShaftRotation(shaft,direction)
    local center=target:GetPivot().Position+direction*(offsetUnits*Grid.Unit)
    local desiredShaft=CFrame.new(center)*rotation
    local delta = desiredShaft * shaft:GetPivot():Inverse()
    local roll = CFrame.new(center)
        * CFrame.fromAxisAngle(rotation.RightVector,math.rad(rollDegrees))
        * CFrame.new(-center)
    local items = {}

    for _, member in ipairs(members) do
        if not member.PrimaryPart then return nil, "Component geometry is incomplete" end
        local base = delta * member:GetPivot()
        local partSteps = Alignment.MatchSteps(base.Rotation)
        if not partSteps then
            -- Existing shafts may already have a free-angle authored roll.
            -- Preserve the original valid 90-degree metadata as fallback.
            partSteps = {
                x = member:GetAttribute("RotX") or 0,
                y = member:GetAttribute("RotY") or 0,
                z = member:GetAttribute("RotZ") or 0,
            }
        end
        local world = roll * base
        table.insert(items, {
            model = member,
            position = world.Position,
            steps = partSteps,
            orientation = world.Rotation,
            size = member.PrimaryPart.Size,
        })
    end

    return {
        delta = roll * delta,
        center = center,
        items = items,
        targetAxis = direction,
        rollDegrees = rollDegrees,
    }
end

-- Inverted alignment: the shaft stays fixed, and a housing (possibly
-- one primitive within a larger rigid component) is moved onto its axis.
-- Reusing the forward alignment math keeps both drag directions exactly
-- consistent in clearance, handedness, offset and roll.
function Alignment.ReversePlan(members, opening, fixedShaft, offsetUnits, rollDegrees)
    if not Alignment.TargetAxis(opening) or not Alignment.IsShaft(fixedShaft) then
        return nil,"Choose a hole-bearing body and a fixed Cylinder shaft"
    end
    if not Alignment.IsOffsetValid(offsetUnits) then
        return nil,"Insertion depth uses 0.5 U increments"
    end
    local lo,hi,why=Alignment.OffsetBounds(fixedShaft,opening)
    if not lo then return nil,why end
    if offsetUnits<lo or offsetUnits>hi then
        return nil,string.format("Insertion must stay between %.1f and %.1f U",lo,hi)
    end
    rollDegrees=rollDegrees or 0
    if type(rollDegrees)~="number" or rollDegrees~=rollDegrees
        or math.abs(rollDegrees)>360 then
        return nil,"Invalid shaft roll"
    end

    local shaftCF=fixedShaft:GetPivot()
    local holeCF=opening:GetPivot()
    local currentAxis=holeCF:VectorToWorldSpace(
        Alignment.TargetAxis(opening)
    ).Unit
    local shaftAxis=shaftCF.RightVector.Unit
    -- Preserve whichever direction the user approached the existing hole
    -- from, avoiding a sudden 180° body flip.
    local targetAxis=if currentAxis:Dot(shaftAxis)>=0
        then shaftAxis else -shaftAxis
    local cross=currentAxis:Cross(targetAxis)
    local angle=math.acos(math.clamp(currentAxis:Dot(targetAxis),-1,1))
    local alignedRotation=if cross.Magnitude>1e-6
        then CFrame.fromAxisAngle(cross.Unit,angle)
        else CFrame.identity
    local axialRoll=CFrame.fromAxisAngle(targetAxis,math.rad(rollDegrees))
    local desiredCenter=shaftCF.Position
        -targetAxis*(offsetUnits*Grid.Unit)
    local destination=CFrame.new(desiredCenter)
        *axialRoll*alignedRotation*holeCF.Rotation
    local delta=destination*holeCF:Inverse()
    local items={}
    for _,member in ipairs(members) do
        if not member.PrimaryPart then
            return nil,"Moving component geometry is incomplete"
        end
        local world=delta*member:GetPivot()
        table.insert(items,{
            model=member,
            position=world.Position,
            orientation=world.Rotation,
            steps=Alignment.MatchSteps(world.Rotation) or {
                x=member:GetAttribute("RotX") or 0,
                y=member:GetAttribute("RotY") or 0,
                z=member:GetAttribute("RotZ") or 0,
            },
            size=member.PrimaryPart.Size,
        })
    end
    return {
        delta=delta,
        items=items,
        center=desiredCenter,
        targetAxis=targetAxis,
        rollDegrees=rollDegrees,
    }
end

return table.freeze(Alignment)
