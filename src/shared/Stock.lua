local FORM = require(script.Parent.FORM)

local Stock = {}
Stock.__index = Stock

Stock.SCALE = 0.04
Stock.MAX_ITEMS = 40
Stock.MATERIALS = {
    Steel = {density = 7.85, color = Color3.fromRGB(121, 131, 138)},
    Aluminum = {density = 2.70, color = Color3.fromRGB(189, 199, 206)},
}
Stock.SHAPES = {Block = true, Sheet = true, Rod = true, Tube = true}

local function finite(n, minimum, maximum)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
        and n >= minimum and n <= maximum
end

local function positive(n)
    assert(finite(n, 0.5, 250), 'Dimensions must be 0.5-250 mm')
    return n
end

local function makeSolid(shape, dimensions)
    if shape == 'Block' or shape == 'Sheet' then
        local x, y, z = positive(dimensions.x), positive(dimensions.y), positive(dimensions.z)
        if shape == 'Sheet' then
            assert(y <= 12, 'Sheet thickness must be at most 12 mm')
        end
        return FORM.box(Vector3.new(x, y, z)), {x = x, y = y, z = z}
    end

    local radius, length = positive(dimensions.radius), positive(dimensions.length)
    local segments = dimensions.segments or 16
    assert(type(segments) == 'number' and segments % 1 == 0 and segments >= 8 and segments <= 32,
        'Invalid cylinder segments')
    if shape == 'Rod' then
        return FORM.cylinder(radius, length, segments),
            {radius = radius, length = length, segments = segments}
    end

    local inner = dimensions.innerRadius
    assert(finite(inner, 0.25, radius - 0.25), 'Tube bore must be smaller than outer radius')
    local vertices, triangles = {}, {}
    for i = 0, segments - 1 do
        local a = i * 2 * math.pi / segments
        for _, r in {radius, inner} do
            vertices[#vertices + 1] = Vector3.new(r * math.cos(a), -length / 2, r * math.sin(a))
            vertices[#vertices + 1] = Vector3.new(r * math.cos(a), length / 2, r * math.sin(a))
        end
    end
    local function index(i, section)
        return ((i % segments) * 4) + section
    end
    local function quad(a, b, c, d)
        triangles[#triangles + 1] = {a, b, c}
        triangles[#triangles + 1] = {a, c, d}
    end
    for i = 0, segments - 1 do
        local j = i + 1
        quad(index(i, 1), index(i, 2), index(j, 2), index(j, 1))
        quad(index(j, 3), index(j, 4), index(i, 4), index(i, 3))
        quad(index(i, 2), index(i, 4), index(j, 4), index(j, 2))
        quad(index(j, 1), index(j, 3), index(i, 3), index(i, 1))
    end
    return {vertices = vertices, triangles = triangles},
        {radius = radius, innerRadius = inner, length = length, segments = segments}
end

function Stock.create(id, shape, material, dimensions, frame)
    assert(type(id) == 'number' and id % 1 == 0 and id >= 1, 'Invalid stock identity')
    assert(Stock.SHAPES[shape], 'Unknown stock shape')
    assert(Stock.MATERIALS[material], 'Unknown metal')
    frame = frame or CFrame.identity
    assert(typeof(frame) == 'CFrame', 'Stock placement must be a CFrame')
    local solid, clean = makeSolid(shape, dimensions)
    local validation = FORM.validate(solid)
    assert(validation.ok, 'Stock surface failed validation: ' .. tostring(validation.issues[1] and validation.issues[1].code))
    local volume = FORM.signedVolume(solid)
    assert(volume > 0, 'Stock volume must be positive')
    return {
        id = id, shape = shape, material = material, dimensions = clean,
        frame = frame, solid = solid, volume = volume,
        massKg = volume * Stock.MATERIALS[material].density / 1000000,
    }
end

function Stock.move(item, frame)
    assert(typeof(frame) == 'CFrame', 'Expected placement CFrame')
    item.frame = frame
end

function Stock.info(item)
    return {
        id = item.id, shape = item.shape, material = item.material,
        volume = item.volume, massKg = item.massKg, frame = item.frame,
    }
end

return Stock
