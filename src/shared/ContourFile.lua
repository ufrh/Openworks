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

local function surfacePass(outline, match, radiusMM, style)
    local perimeter = match.perimeter
    if perimeter <= 0 then return nil end
    local reach = math.min(math.max(radiusMM * 2, 3.5), perimeter * 0.12)
    local depth = math.min(math.max(radiusMM * 0.16, 0.12), reach * 0.12)
    local positions = {}
    local travel = 0

    for i, point in outline do
        positions[#positions + 1] = {at = travel, point = point}
        travel += (outline[i % #outline + 1] - point).Magnitude
    end

    for step = -6, 6 do
        local at = (match.travel + reach * step / 6) % perimeter
        local point = Profile.sample(outline, at)
        if point then
            positions[#positions + 1] = {at = at, point = point}
        end
    end

    table.sort(positions, function(a, b) return a.at < b.at end)
    local unique = {}
    for _, entry in positions do
        if #unique == 0 or entry.at - unique[#unique].at > 0.0001 then
            unique[#unique + 1] = entry
        end
    end

    if #unique > 768 then return nil end
    local result = {}
    for i, entry in unique do
        local previous = unique[(i - 2) % #unique + 1].point
        local following = unique[i % #unique + 1].point
        local tangent = following - previous
        local difference = math.abs(entry.at - match.travel)
        difference = math.min(difference, perimeter - difference)
        local weight = 0
        if difference < reach and tangent.Magnitude > 1e-6 then
            local t = difference / reach
            weight = if style == 'Round'
                then 0.5 * (1 + math.cos(math.pi * t))
                else 1 - t
        end
        local inward = if tangent.Magnitude > 1e-6
            then Vector2.new(-tangent.Y, tangent.X).Unit else Vector2.zero
        result[#result + 1] = entry.point + inward * (depth * weight)
    end
    return result
end

function ContourFile.apply(work, item, localPoint, radiusMM, style)
    if not work or not item or typeof(localPoint) ~= 'Vector3'
        or type(radiusMM) ~= 'number' or radiusMM < 0.5 or radiusMM > 100
        or (style ~= 'Round' and style ~= 'Chamfer') then
        return nil, 'Invalid contour filing parameters'
    end

    local outline, thickness = Profile.extract(item.solid)
    if not outline then return nil, thickness end
    local target = Vector2.new(localPoint.X, localPoint.Z) / Stock.SCALE
    local closest = Profile.closest(outline, target)
    if not closest or closest.distance > math.max(radiusMM * 1.5, 8) then
        return nil, 'Aim the file near the actual contour surface'
    end

    local nearest, selected
    for i, vertex in outline do
        local previous = outline[(i - 2) % #outline + 1]
        local following = outline[i % #outline + 1]
        local incoming = (vertex - previous).Magnitude
        local outgoing = (following - vertex).Magnitude
        if turn(previous, vertex, following) < 0.88
            or math.min(incoming, outgoing) < math.max(1.2, radiusMM * 1.2) then
            continue
        end
        local delta = (vertex - target).Magnitude
        if delta < math.max(radiusMM * 0.4, 1) and (not nearest or delta < nearest) then
            nearest, selected = delta, i
        end
    end

    local modified, replacements = {}, 0
    if selected then
        for i, vertex in outline do
            local previous = outline[(i - 2) % #outline + 1]
            local following = outline[i % #outline + 1]
            local incoming = vertex - previous
            local outgoing = following - vertex
            local firstLength, secondLength = incoming.Magnitude, outgoing.Magnitude
            local near = i == selected
            local convex = turn(previous, vertex, following) > 0.88

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
    else
        modified = surfacePass(outline, closest, radiusMM, style)
        replacements = if modified then 1 else 0
    end

    if not modified or replacements == 0 or #modified > 768 then
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
