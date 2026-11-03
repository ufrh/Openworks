local FORM = require(script.Parent.FORM)
local Stock = require(script.Parent.Stock)
local Profile = require(script.Parent.PrismProfile)
local PathCut = require(script.Parent.PathCut)

local ContourFile = {}

local function turn(previous, vertex, following)
    local a, b = vertex - previous, following - vertex
    local scale = a.Magnitude * b.Magnitude
    if scale < 1e-8 then return 0 end
    return (a.X * b.Y - a.Y * b.X) / scale
end

function ContourFile.apply(work, item, localPoint, radiusMM, style)
    if not work or not item or typeof(localPoint) ~= 'Vector3'
        or type(radiusMM) ~= 'number' or radiusMM < 0.5 or radiusMM > 12
        or (style ~= 'Round' and style ~= 'Chamfer') then
        return nil, 'Invalid contour filing parameters'
    end

    local outline, thickness = Profile.extract(item.solid)
    if not outline then return nil, thickness end
    local target = Vector2.new(localPoint.X, localPoint.Z) / Stock.SCALE
    local nearest, selected
    for i, vertex in outline do
        local prev = outline[(i - 2) % #outline + 1]
        local nextPoint = outline[i % #outline + 1]
        if turn(prev, vertex, nextPoint) < 0.007 then continue end
        local delta = (vertex - target).Magnitude
        if not nearest or delta < nearest then
            nearest, selected = delta, i
        end
    end
    if not selected or nearest > math.max(radiusMM * 4, 9) then
        return nil, 'Aim the file near a real convex contour edge'
    end

    local center = outline[selected]
    local influence = math.max(radiusMM * 2.5, 4)
    local modified, replacements = {}, 0
    for i, vertex in outline do
        local previous = outline[(i - 2) % #outline + 1]
        local following = outline[i % #outline + 1]
        local incoming = vertex - previous
        local outgoing = following - vertex
        local firstLength, secondLength = incoming.Magnitude, outgoing.Magnitude
        local near = (vertex - center).Magnitude <= influence
        local convex = turn(previous, vertex, following) > 0.007

        if not near or not convex or firstLength < 0.05 or secondLength < 0.05 then
            modified[#modified + 1] = vertex
            continue
        end

        local reach = math.min(radiusMM * 0.8, firstLength * 0.3,
            secondLength * 0.3)
        if reach < 0.015 then
            modified[#modified + 1] = vertex
            continue
        end

        local a = vertex - incoming.Unit * reach
        local b = vertex + outgoing.Unit * reach
        modified[#modified + 1] = a
        if style == 'Round' then
            local angle = math.acos(math.clamp(incoming.Unit:Dot(outgoing.Unit), -1, 1))
            local segments = math.clamp(math.ceil(angle / 0.14), 6, 16)
            for k = 1, segments - 1 do
                local t = k / segments
                modified[#modified + 1] = a * (1 - t) ^ 2
                    + vertex * (2 * t * (1 - t))
                    + b * t ^ 2
            end
        end
        modified[#modified + 1] = b
        replacements += 1
    end

    if replacements == 0 or #modified > 768 then
        return nil, 'Contour has no safe area for this file size'
    end
    local before = Profile.area(outline)
    local after = Profile.area(modified)
    if after <= 0 or before - after < 1e-5 then
        return nil, 'Filing did not remove enough material'
    end

    local outlineStuds = {}
    for _, v in modified do
        outlineStuds[#outlineStuds + 1] = v * Stock.SCALE
    end
    local solid, reason = PathCut.extrudePolygon(outlineStuds, thickness * Stock.SCALE)
    if not solid then return nil, reason end
    local original = FORM.signedVolume(item.solid)
    local remaining = FORM.signedVolume(solid)
    if remaining <= 0 or remaining >= original
        or original - remaining > original * 0.25 then
        return nil, 'Contour file result is outside the material budget'
    end
    return solid, {
        removed = original - remaining,
        retained = remaining,
        segments = replacements,
        profile = style,
    }
end

return ContourFile
