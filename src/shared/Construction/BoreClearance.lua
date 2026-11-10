--!strict
-- Geometry-aware clearance check using the primitive generator's hole metadata.
-- Never bypasses collisions involving a flange or any other member.
local Alignment = require(script.Parent:WaitForChild("AlignmentMath"))
local Grid = require(script.Parent:WaitForChild("GridMath"))
local Bore = {}
local TOL = 0.001

local function boreProfile(target)
    local id = string.lower(tostring(target:GetAttribute("TemplateId") or target.Name))
    local axis = Alignment.TargetAxis(target)
    if not axis or not target.PrimaryPart then return nil end

    local outer = target.PrimaryPart.Size
    if axis == Vector3.yAxis then
        -- Generated DrilledBlock_D... modules explicitly store hole diameter
        -- in player-facing Units (v4 primitive generator).
        local holeU = target:GetAttribute("HoleDiameterU")
        local holeStuds = target:GetAttribute("HoleDiameterStuds")
        local diameter = if type(holeStuds) == "number" then holeStuds
            elseif type(holeU) == "number" then holeU * Grid.Unit
            else nil
        if not diameter or diameter <= 0 then return nil end
        return {
            axis = axis, radiusY = diameter / 2, radiusZ = diameter / 2,
            circular = true,
            localY = Vector3.xAxis, localZ = Vector3.zAxis,
        }
    end

    if not string.find(id, "tube", 1, true)
        or string.find(id, "halftube", 1, true) then return nil end

    -- Generator v4 writes original inner profile and wall thickness in U.
    -- Resizing an immutable Studio CSG result scales the internal cavity
    -- along with its exterior. Account for that separately on Y and Z.
    local wallU = target:GetAttribute("WallU")
    if type(wallU) ~= "number" then
        wallU = tonumber(string.match(id, "[_%-]w([%d%.]+)"))
    end
    if type(wallU) ~= "number" or wallU <= 0 then return nil end

    local circular = string.find(id, "circulartube", 1, true) ~= nil
    local innerY = target:GetAttribute("InnerDiameterU")
        or target:GetAttribute("InnerWidthU")
    local innerZ = target:GetAttribute("InnerDiameterU")
        or target:GetAttribute("InnerHeightU")
    if type(innerY) ~= "number" or type(innerZ) ~= "number" then return nil end

    local initialOuterY = (innerY + 2 * wallU) * Grid.Unit
    local initialOuterZ = (innerZ + 2 * wallU) * Grid.Unit
    if initialOuterY <= 0 or initialOuterZ <= 0 then return nil end

    local boreY = innerY * Grid.Unit * (outer.Y / initialOuterY)
    local boreZ = innerZ * Grid.Unit * (outer.Z / initialOuterZ)

    return {
        axis = axis,
        radiusY = boreY / 2,
        radiusZ = boreZ / 2,
        circular = circular,
        localY = Vector3.yAxis, localZ = Vector3.zAxis,
    }
end

function Bore.OpeningDiameter(target)
    local profile=boreProfile(target)
    if not profile then return nil end
    return 2*math.min(profile.radiusY,profile.radiusZ)
end

function Bore.MaxShaftDiameter(source, target): (number?, string?)
    if not Alignment.IsShaft(source) or not source.PrimaryPart then
        return nil, "Select a cylindrical shaft"
    end
    local profile = boreProfile(target)
    if not profile then return nil, "Opening has no verifiable bore dimensions" end

    local sourceCF = source:GetPivot()
    local targetCF = target:GetPivot()
    local shaftAxis = sourceCF.RightVector
    local holeAxis = targetCF:VectorToWorldSpace(profile.axis)
    if math.abs(shaftAxis:Dot(holeAxis)) < 0.9999 then
        return nil, "Align the shaft axis before adjusting the fit"
    end

    local delta = sourceCF.Position - targetCF.Position
    local radial = delta - holeAxis * delta:Dot(holeAxis)
    local y = math.abs(radial:Dot(targetCF:VectorToWorldSpace(profile.localY)))
    local z = math.abs(radial:Dot(targetCF:VectorToWorldSpace(profile.localZ)))
    local usableRadius
    if profile.circular then
        usableRadius = math.min(profile.radiusY, profile.radiusZ)
            - math.sqrt(y * y + z * z)
    else
        usableRadius = math.min(profile.radiusY - y, profile.radiusZ - z)
    end
    local diameter = math.max(0, 2 * (usableRadius - TOL))
    if diameter <= 0 then return nil, "Shaft has no available bore clearance" end
    return diameter
end

function Bore.ShaftFits(source, target)
    local maxDiameter, reason = Bore.MaxShaftDiameter(source, target)
    if not maxDiameter then return false, reason end
    local diameter = math.max(source.PrimaryPart.Size.Y, source.PrimaryPart.Size.Z)
    if diameter > maxDiameter + 1e-5 then
        return false, "Shaft diameter exceeds available bore clearance"
    end
    local engaged,reason=Alignment.Engaged(source,target)
    if not engaged then return false,reason end
    return true
end

return table.freeze(Bore)
