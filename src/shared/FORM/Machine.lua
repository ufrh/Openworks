local FORM = require(script.Parent)
local Boolean = require(script.Parent.Boolean)
local Cut = require(script.Parent.Cut)
local Union = require(script.Parent.Union)

local Machine = {}
Machine.__index = Machine

local MAX_PIECES = 192
local MAX_OPERATIONS = 64
local MAX_CUTTERS = 24
local EPSILON = 1e-5

local function assertVector(value, name)
    assert(typeof(value) == 'Vector3', name .. ' must be a Vector3')
end

local function cloneSolid(solid)
    local vertices = table.clone(solid.vertices)
    local triangles = {}
    for i, face in solid.triangles do triangles[i] = table.clone(face) end
    return {vertices = vertices, triangles = triangles}
end

local function volume(pieces)
    local total = 0
    for _, piece in pieces do total += FORM.signedVolume(piece) end
    return total
end

local function transform(solid, frame)
    assert(typeof(frame) == 'CFrame', 'Expected a CFrame')
    local result = cloneSolid(solid)
    for i, vertex in result.vertices do result.vertices[i] = frame:PointToWorldSpace(vertex) end
    return result
end

local function subtract(pieces, cutter)
    assert(FORM.validate(cutter).ok, 'Invalid cutter geometry')
    local output = {}
    local removed = 0

    for _, piece in pieces do
        local rest, amount = Boolean.subtract(piece, cutter)
        if not rest then return nil, tostring(amount) end
        for _, fragment in rest do
            output[#output + 1] = fragment
            if #output > MAX_PIECES then return nil, 'PIECE_LIMIT_EXCEEDED' end
        end
        removed += amount
    end

    return output, removed
end

local function keepNegative(pieces, point, normal)
    assertVector(point, 'Plane point')
    assertVector(normal, 'Plane normal')
    assert(normal.Magnitude > 0, 'Plane normal cannot be zero')
    normal = normal.Unit
    local output = {}
    local removed = 0

    for _, piece in pieces do
        local minimum, maximum = math.huge, -math.huge
        for _, vertex in piece.vertices do
            local distance = (vertex - point):Dot(normal)
            minimum = math.min(minimum, distance)
            maximum = math.max(maximum, distance)
        end

        if maximum <= EPSILON then
            output[#output + 1] = piece
        elseif minimum >= -EPSILON then
            removed += FORM.signedVolume(piece)
        else
            local outside, inside = Cut.split(piece, point, normal)
            if not outside then return nil, 'PLANE_CUT_FAILED_' .. tostring(inside) end
            removed += FORM.signedVolume(outside)
            output[#output + 1] = inside
        end
        if #output > MAX_PIECES then return nil, 'PIECE_LIMIT_EXCEEDED' end
    end

    return output, removed
end

local function axisValue(vector, axis)
    if axis == 'X' then return vector.X end
    if axis == 'Y' then return vector.Y end
    if axis == 'Z' then return vector.Z end
    error('Axis must be X, Y or Z')
end

local function axisVector(axis)
    if axis == 'X' then return Vector3.xAxis end
    if axis == 'Y' then return Vector3.yAxis end
    if axis == 'Z' then return Vector3.zAxis end
    error('Axis must be X, Y or Z')
end

local function corner(pieces, axisA, signA, axisB, signB)
    assert(axisA ~= axisB, 'Edge axes must be different')
    assert(signA == 1 or signA == -1, 'Edge sign A must be +/-1')
    assert(signB == 1 or signB == -1, 'Edge sign B must be +/-1')

    local lower = Vector3.new(math.huge, math.huge, math.huge)
    local upper = Vector3.new(-math.huge, -math.huge, -math.huge)

    for _, piece in pieces do
        local low, high = FORM.bounds(piece)
        lower = Vector3.new(math.min(lower.X, low.X), math.min(lower.Y, low.Y), math.min(lower.Z, low.Z))
        upper = Vector3.new(math.max(upper.X, high.X), math.max(upper.Y, high.Y), math.max(upper.Z, high.Z))
    end

    local limitA = axisValue(if signA == 1 then upper else lower, axisA)
    local limitB = axisValue(if signB == 1 then upper else lower, axisB)
    return limitA, limitB, lower, upper
end

local function operationCutters(spec)
    if spec.kind == 'drill' then
        assertVector(spec.center, 'Drill center')
        local radius = spec.radius
        local height = spec.height
        assert(type(radius) == 'number' and radius > 0 and type(height) == 'number' and height > 0,
            'Invalid drill dimensions')
        local frame = spec.frame or CFrame.new(spec.center)
        assert(typeof(frame) == 'CFrame', 'Invalid drill frame')
        return {transform(FORM.cylinder(radius, height, spec.segments or 12), frame)}
    end

    if spec.kind == 'pocket' then
        assertVector(spec.size, 'Pocket size')
        assertVector(spec.center, 'Pocket center')
        return {transform(FORM.box(spec.size), spec.frame or CFrame.new(spec.center))}
    end

    if spec.kind == 'slot' then
        assertVector(spec.from, 'Slot start')
        assertVector(spec.to, 'Slot end')
        assert(math.abs(spec.from.Y - spec.to.Y) < EPSILON, 'Slot endpoints must have matching Y')
        assert(type(spec.radius) == 'number' and spec.radius > 0, 'Invalid slot radius')
        assert(type(spec.height) == 'number' and spec.height > 0, 'Invalid slot cutter height')

        local direction = spec.to - spec.from
        assert(direction.Magnitude > EPSILON, 'Slot endpoints must differ')
        local center = (spec.from + spec.to) / 2
        local frame = CFrame.lookAt(center, center + direction)
        local diameter = spec.radius * 2
        return {
            transform(FORM.box(Vector3.new(diameter, spec.height, direction.Magnitude)), frame),
            transform(FORM.cylinder(spec.radius, spec.height, spec.segments or 12), CFrame.new(spec.from)),
            transform(FORM.cylinder(spec.radius, spec.height, spec.segments or 12), CFrame.new(spec.to)),
        }
    end

    if spec.kind == 'profile' then
        assert(type(spec.points) == 'table' and #spec.points >= 2 and #spec.points <= 9,
            'Profile requires 2-9 path points')
        local cutters = {}
        for i = 1, #spec.points - 1 do
            local step = operationCutters({
                kind = 'slot',
                from = spec.points[i],
                to = spec.points[i + 1],
                radius = spec.radius,
                height = spec.height,
                segments = spec.segments or 12,
            })
            for _, cutter in step do cutters[#cutters + 1] = cutter end
        end
        assert(#cutters <= MAX_CUTTERS, 'Tool path exceeds cutter budget')
        return cutters
    end

    error('Unknown cutting operation: ' .. tostring(spec.kind))
end

local function planeCutter(point, normal, stock)
    assertVector(point, 'Plane point')
    assertVector(normal, 'Plane normal')
    assert(normal.Magnitude > 0, 'Invalid machining plane')

    local lower, upper = FORM.bounds(stock)
    local size = (upper - lower).Magnitude * 8 + 100
    local unit = normal.Unit
    local center = point + unit * (size / 2)
    local frame = CFrame.lookAt(center, center + unit)
    return transform(FORM.box(Vector3.new(size * 2, size * 2, size)), frame)
end

local function execute(pieces, spec)
    assert(type(spec) == 'table' and type(spec.kind) == 'string', 'Invalid machining operation')

    if spec.kind == 'drill' or spec.kind == 'pocket' or spec.kind == 'slot' or spec.kind == 'profile' then
        local cutters = operationCutters(spec)
        assert(#cutters <= MAX_CUTTERS, 'Too many cutters per operation')
        local current = pieces
        local removed = 0
        for _, cutter in cutters do
            local nextPieces, amount = subtract(current, cutter)
            if not nextPieces then return nil, amount end
            current = nextPieces
            removed += amount
        end
        return current, removed, cutters
    end

    if spec.kind == 'saw' then
        local output, removed = keepNegative(pieces, spec.point, spec.normal)
        if not output then return nil, removed end
        return output, removed, {planeCutter(spec.point, spec.normal, pieces[1])}
    end

    if spec.kind == 'chamfer' or spec.kind == 'fillet' then
        local axisA, axisB = spec.axisA, spec.axisB
        local signA, signB = spec.signA, spec.signB
        local distance = if spec.kind == 'chamfer' then spec.distance else spec.radius
        assert(type(distance) == 'number' and distance > 0, 'Invalid edge finishing radius/distance')

        local boundA, boundB, lower, upper = corner(pieces, axisA, signA, axisB, signB)
        local spanA = axisValue(upper - lower, axisA)
        local spanB = axisValue(upper - lower, axisB)
        assert(distance < math.min(spanA, spanB) / 2, 'Edge finishing exceeds half of stock span')

        local vectorA, vectorB = axisVector(axisA) * signA, axisVector(axisB) * signB
        local cornerPosition = axisVector(axisA) * boundA + axisVector(axisB) * boundB
        local center = cornerPosition - (vectorA + vectorB) * distance

        local planes = {}
        if spec.kind == 'chamfer' then
            planes[1] = {point = cornerPosition - vectorA * distance, normal = vectorA + vectorB}
        else
            local segments = spec.segments or 6
            assert(type(segments) == 'number' and segments % 1 == 0 and segments >= 2 and segments <= 24,
                'Fillet segments must be between 2 and 24')
            for i = 1, segments - 1 do
                local angle = i * math.pi / (2 * segments)
                local normal = vectorA * math.cos(angle) + vectorB * math.sin(angle)
                planes[#planes + 1] = {point = center + normal * distance, normal = normal}
            end
        end

        local current = pieces
        local removed = 0
        local cutters = {}
        for _, plane in planes do
            local nextPieces, amount = keepNegative(current, plane.point, plane.normal)
            if not nextPieces then return nil, amount end
            current = nextPieces
            removed += amount
            cutters[#cutters + 1] = planeCutter(plane.point, plane.normal, pieces[1])
        end
        return current, removed, cutters
    end

    return nil, 'UNKNOWN_OPERATION_' .. spec.kind
end

function Machine.new(stock)
    assert(FORM.validate(stock).ok, 'Invalid initial workpiece')
    local first = {cloneSolid(stock)}
    return setmetatable({
        stock = cloneSolid(stock),
        history = {},
        cursor = 0,
        states = {{pieces = first, volume = FORM.signedVolume(stock), removed = 0}},
    }, Machine)
end

function Machine:pieces()
    return self.states[self.cursor + 1].pieces
end

function Machine:volume()
    return self.states[self.cursor + 1].volume
end

function Machine:apply(spec)
    if self.cursor >= MAX_OPERATIONS then return nil, 'OPERATION_LIMIT_EXCEEDED' end

    local old = self.states[self.cursor + 1]
    if #old.pieces == 0 then return nil, 'WORKPIECE_EMPTY' end

    local ok, pieces, removed, cutters = pcall(execute, old.pieces, spec)
    if not ok then return nil, tostring(pieces) end
    if not pieces then return nil, removed end
    if #pieces == 0 then return nil, 'OPERATION_REMOVES_ENTIRE_WORKPIECE' end
    if removed <= 1e-5 then return nil, 'NO_MATERIAL_REMOVED' end

    local currentVolume = volume(pieces)
    if not FORM.volumeClose(currentVolume + removed, old.volume) then
        return nil, string.format('VOLUME_MISMATCH %.8f', currentVolume + removed - old.volume)
    end
    for _, piece in pieces do
        if not FORM.validate(piece).ok then return nil, 'INVALID_RESULT_PIECE' end
    end

    while #self.history > self.cursor do table.remove(self.history) end
    while #self.states > self.cursor + 1 do table.remove(self.states) end

    self.cursor += 1
    self.history[self.cursor] = {spec = table.clone(spec), removed = removed, cutters = cutters}
    self.states[self.cursor + 1] = {
        pieces = pieces,
        volume = currentVolume,
        removed = removed,
    }

    return true, removed
end

function Machine:undo()
    if self.cursor == 0 then return false end
    self.cursor -= 1
    return true
end

function Machine:redo()
    if self.cursor >= #self.history then return false end
    self.cursor += 1
    return true
end

function Machine:reset()
    self.cursor = 0
    table.clear(self.history)
    while #self.states > 1 do table.remove(self.states) end
end

function Machine:mesh()
    if self.cursor == 0 then
        local solid = cloneSolid(self.stock)
        return solid, nil, {weld = {connectedComponents = 1, eulerCharacteristic = 2,
            trianglesAfter = #solid.triangles}, surface = {outputTriangles = #solid.triangles}}
    end

    local cutters = {}
    for i = 1, self.cursor do
        for _, cutter in self.history[i].cutters or {} do
            cutters[#cutters + 1] = cutter
        end
    end

    if #cutters > 48 then return nil, 'CUTTER_HISTORY_BUDGET_EXCEEDED' end
    return Union.fromStockAndCutters(self.stock, cutters, self:volume())
end

function Machine:status()
    return {
        operations = self.cursor,
        redo = #self.history - self.cursor,
        pieceCount = #self:pieces(),
        volume = self:volume(),
        removedTotal = FORM.signedVolume(self.stock) - self:volume(),
    }
end

return Machine
