local FORM = require(script.Parent.FORM)

local SawTube = {}

local function clone(values)
    return table.clone(values)
end

local function fromStock(item)
    if item.tubeProfile then return item.tubeProfile end
    if item.shape ~= 'Tube' or not item.dimensions then return nil end
    local d = item.dimensions
    local lower, upper = {}, {}
    for i = 1, d.segments do
        lower[i] = -d.length / 2
        upper[i] = d.length / 2
    end
    return {
        radius = d.radius,
        innerRadius = d.innerRadius,
        segments = d.segments,
        outerLow = clone(lower), outerHigh = clone(upper),
        innerLow = clone(lower), innerHigh = clone(upper),
    }
end

local function vertex(radius, y, index, segments)
    local angle = (index - 1) * 2 * math.pi / segments
    return Vector3.new(radius * math.cos(angle), y, radius * math.sin(angle))
end

local function calculate(profile, point, normal, offset)
    if normal.Y <= 0.05 then return nil, 'Saw must cross the tube axis' end
    local outer, inner = {}, {}
    for i = 1, profile.segments do
        local a = vertex(profile.radius, 0, i, profile.segments)
        local b = vertex(profile.innerRadius, 0, i, profile.segments)
        outer[i] = point.Y + (offset - (a.X - point.X) * normal.X
            - (a.Z - point.Z) * normal.Z) / normal.Y
        inner[i] = point.Y + (offset - (b.X - point.X) * normal.X
            - (b.Z - point.Z) * normal.Z) / normal.Y
        if outer[i] <= profile.outerLow[i] + 0.1
            or outer[i] >= profile.outerHigh[i] - 0.1
            or inner[i] <= profile.innerLow[i] + 0.1
            or inner[i] >= profile.innerHigh[i] - 0.1 then
            return nil, 'Cut crosses a tube end; move toward its middle or straighten the saw'
        end
    end
    return {outer = outer, inner = inner}
end

local function mesh(p)
    local vertices, triangles = {}, {}
    for i = 1, p.segments do
        vertices[#vertices + 1] = vertex(p.radius, p.outerLow[i], i, p.segments)
        vertices[#vertices + 1] = vertex(p.radius, p.outerHigh[i], i, p.segments)
        vertices[#vertices + 1] = vertex(p.innerRadius, p.innerLow[i], i, p.segments)
        vertices[#vertices + 1] = vertex(p.innerRadius, p.innerHigh[i], i, p.segments)
    end
    local function index(i, k)
        return ((i - 1) % p.segments) * 4 + k
    end
    local function quad(a, b, c, d)
        triangles[#triangles + 1] = {a, b, c}
        triangles[#triangles + 1] = {a, c, d}
    end
    for i = 1, p.segments do
        local j = i % p.segments + 1
        quad(index(i, 1), index(i, 2), index(j, 2), index(j, 1))
        quad(index(j, 3), index(j, 4), index(i, 4), index(i, 3))
        quad(index(i, 2), index(i, 4), index(j, 4), index(j, 2))
        quad(index(j, 1), index(j, 3), index(i, 3), index(i, 1))
    end
    return {vertices = vertices, triangles = triangles}
end

function SawTube.preview(item, point, normal, kerf)
    local profile = fromStock(item)
    if not profile then return nil, 'No tube profile available' end
    if math.abs(normal.Y) <= 0.05 then return nil, 'Rotate the saw across the tube axis' end
    if normal.Y < 0 then normal = -normal end
    local middle, reason = calculate(profile, point, normal, 0)
    if not middle then return nil, reason end
    local minus, minusReason = calculate(profile, point, normal, -kerf / 2)
    if not minus then return nil, minusReason end
    local plus, plusReason = calculate(profile, point, normal, kerf / 2)
    if not plus then return nil, plusReason end

    local outer, inner = {}, {}
    for i = 1, profile.segments do
        outer[i] = vertex(profile.radius, middle.outer[i], i, profile.segments)
        inner[i] = vertex(profile.innerRadius, middle.inner[i], i, profile.segments)
    end
    return {profile = profile, low = minus, high = plus, rings = {outer, inner}}
end

function SawTube.split(item, point, normal, kerf)
    local info, reason = SawTube.preview(item, point, normal, kerf)
    if not info then return nil, reason end
    local p = info.profile
    local lower = {
        radius = p.radius, innerRadius = p.innerRadius, segments = p.segments,
        outerLow = clone(p.outerLow), innerLow = clone(p.innerLow),
        outerHigh = clone(info.low.outer), innerHigh = clone(info.low.inner),
    }
    local upper = {
        radius = p.radius, innerRadius = p.innerRadius, segments = p.segments,
        outerLow = clone(info.high.outer), innerLow = clone(info.high.inner),
        outerHigh = clone(p.outerHigh), innerHigh = clone(p.innerHigh),
    }
    local a, b = mesh(upper), mesh(lower)
    if not FORM.validate(a).ok or not FORM.validate(b).ok then
        return nil, 'Tube split generated invalid surface geometry'
    end
    local originalVolume = FORM.signedVolume(item.solid)
    local kept = FORM.signedVolume(a) + FORM.signedVolume(b)
    local removed = originalVolume - kept
    if removed <= 0 then return nil, 'Invalid tube kerf volume' end
    return {a, b}, {removed = removed, retained = kept, tubeProfiles = {upper, lower}}
end

function SawTube.offsetProfile(profile, displacement)
    local p = {
        radius = profile.radius,
        innerRadius = profile.innerRadius,
        segments = profile.segments,
    }
    for _, key in {'outerLow', 'outerHigh', 'innerLow', 'innerHigh'} do
        p[key] = {}
        for i, y in profile[key] do p[key][i] = y - displacement.Y end
    end
    return p
end

function SawTube.isTube(item)
    return item.shape == 'Tube' or item.tubeProfile ~= nil
end

return SawTube
