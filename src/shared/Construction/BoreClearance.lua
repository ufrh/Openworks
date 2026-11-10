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

function Bore.ShaftFits(source, target)
    if not Alignment.IsShaft(source) or not source.PrimaryPart then
        return false, "Not a cylindrical shaft"
    end
    local profile = boreProfile(target)
    if not profile then return false, "Opening lacks verifiable bore dimensions" end

    local shaftCF = source:GetPivot()
    local targetCF = target:GetPivot()
    local shaftAxis = shaftCF.RightVector
    local holeAxis = targetCF:VectorToWorldSpace(profile.axis)
    if math.abs(shaftAxis:Dot(holeAxis)) < 0.9999 then
        return false, "Shaft and bore axes do not match"
    end

    local diff = shaftCF.Position - targetCF.Position
    local radial = diff - holeAxis * diff:Dot(holeAxis)
    local alongY = math.abs(radial:Dot(targetCF:VectorToWorldSpace(profile.localY)))
    local alongZ = math.abs(radial:Dot(targetCF:VectorToWorldSpace(profile.localZ)))
    local diameter = math.max(source.PrimaryPart.Size.Y, source.PrimaryPart.Size.Z)
    local radius = diameter/2
    if profile.circular then
        if math.sqrt(alongY^2 + alongZ^2) + radius + TOL > math.min(profile.radiusY,profile.radiusZ) then
            return false, "Shaft exceeds circular bore clearance"
        end
    elseif alongY + radius + TOL > profile.radiusY
        or alongZ + radius + TOL > profile.radiusZ then
        return false, "Shaft exceeds opening clearance"
    end
    return true
end

return table.freeze(Bore)
