local HttpService = game:GetService('HttpService')
local FORM = require(script.Parent.FORM)
local Machine = require(script.Parent.FORM.Machine)

local Workshop = {}
Workshop.__index = Workshop
Workshop.VERSION = 1
Workshop.MAX_OPERATIONS = 24
Workshop.MAX_JSON_BYTES = 24000

local function number(v, name, min, max)
    assert(type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge,
        name .. ' must be a finite number')
    assert(v >= min and v <= max, name .. ' outside allowed range')
    return v
end

local function whole(v, name, min, max)
    number(v, name, min, max)
    assert(v % 1 == 0, name .. ' must be an integer')
    return v
end

local function label(v)
    assert(type(v) == 'string' and #v > 0 and #v <= 48, 'Invalid project name')
    assert(not string.find(v, '[%c]'), 'Project name contains control characters')
    return v
end

local function axis(v)
    assert(v == 'X' or v == 'Y' or v == 'Z', 'Axis must be X, Y or Z')
    return v
end

local function sign(v)
    assert(v == 1 or v == -1, 'Edge sign must be +1 or -1')
    return v
end

local function size(v)
    assert(type(v) == 'table', 'Expected stock dimensions')
    return {
        x = number(v.x, 'Stock X', 10, 250),
        y = number(v.y, 'Stock Y', 10, 250),
        z = number(v.z, 'Stock Z', 10, 250),
    }
end

local function xyz(v, name)
    assert(type(v) == 'table', name .. ' must be a coordinate')
    return {x = number(v.x, name .. '.x', -500, 500),
        y = number(v.y, name .. '.y', -500, 500),
        z = number(v.z, name .. '.z', -500, 500)}
end

local function vec(p)
    return Vector3.new(p.x, p.y, p.z)
end

local function normalize(op)
    assert(type(op) == 'table' and type(op.kind) == 'string', 'Invalid operation')
    local kind = op.kind
    local result = {kind = kind}

    if kind == 'drill' then
        result.center = xyz(op.center, 'Drill center')
        result.radius = number(op.radius, 'Drill radius', 0.25, 75)
        result.height = number(op.height, 'Drill height', 0.25, 350)
        result.segments = whole(op.segments or 12, 'Drill segments', 6, 32)
    elseif kind == 'pocket' then
        result.center = xyz(op.center, 'Pocket center')
        result.size = xyz(op.size, 'Pocket size')
        for _, n in {'x', 'y', 'z'} do
            result.size[n] = number(op.size[n], 'Pocket ' .. n, 0.25, 300)
        end
    elseif kind == 'slot' then
        result.from = xyz(op.from, 'Slot start')
        result.to = xyz(op.to, 'Slot end')
        assert(math.abs(result.from.y - result.to.y) < 1e-5, 'Slot endpoints need equal Y')
        assert((vec(result.from) - vec(result.to)).Magnitude >= 0.1, 'Slot endpoints are identical')
        result.radius = number(op.radius, 'Slot radius', 0.25, 50)
        result.height = number(op.height, 'Slot height', 0.25, 350)
        result.segments = whole(op.segments or 12, 'Slot segments', 6, 32)
    elseif kind == 'profile' then
        assert(type(op.points) == 'table' and #op.points >= 2 and #op.points <= 7,
            'Profile needs 2 to 7 points')
        result.points = {}
        for i, point in op.points do
            result.points[i] = xyz(point, 'Profile point ' .. i)
            if i > 1 then
                assert(math.abs(result.points[i].y - result.points[1].y) < 1e-5,
                    'Profile points must share Y')
                assert((vec(result.points[i]) - vec(result.points[i - 1])).Magnitude >= 0.1,
                    'Consecutive profile points must differ')
            end
        end
        result.radius = number(op.radius, 'Profile radius', 0.25, 50)
        result.height = number(op.height, 'Profile height', 0.25, 350)
        result.segments = whole(op.segments or 12, 'Profile segments', 6, 32)
    elseif kind == 'saw' then
        result.point = xyz(op.point, 'Saw point')
        result.axis = axis(op.axis)
        result.direction = sign(op.direction or 1)
    elseif kind == 'chamfer' or kind == 'fillet' then
        result.axisA = axis(op.axisA)
        result.axisB = axis(op.axisB)
        assert(result.axisA ~= result.axisB, 'Edge axes cannot match')
        result.signA = sign(op.signA)
        result.signB = sign(op.signB)
        if kind == 'chamfer' then
            result.distance = number(op.distance, 'Chamfer width', 0.1, 50)
        else
            result.radius = number(op.radius, 'Fillet radius', 0.1, 50)
            result.segments = whole(op.segments or 6, 'Fillet segments', 2, 12)
        end
    else
        error('Unsupported machining operation: ' .. kind)
    end

    return result
end

function Workshop.compile(op)
    op = normalize(op)
    local kind = op.kind
    if kind == 'drill' then
        return {kind = kind, center = vec(op.center), radius = op.radius,
            height = op.height, segments = op.segments}
    elseif kind == 'pocket' then
        return {kind = kind, center = vec(op.center), size = vec(op.size)}
    elseif kind == 'slot' then
        return {kind = kind, from = vec(op.from), to = vec(op.to), radius = op.radius,
            height = op.height, segments = op.segments}
    elseif kind == 'profile' then
        local points = {}
        for i, p in op.points do points[i] = vec(p) end
        return {kind = kind, points = points, radius = op.radius,
            height = op.height, segments = op.segments}
    elseif kind == 'saw' then
        local direction = if op.axis == 'X' then Vector3.xAxis
            elseif op.axis == 'Y' then Vector3.yAxis else Vector3.zAxis
        return {kind = kind, point = vec(op.point), normal = direction * op.direction}
    end
    return op
end

local function rebuild(stock, operations)
    local machine = Machine.new(FORM.box(Vector3.new(stock.x, stock.y, stock.z)))
    for i, op in operations do
        local ok, removed = machine:apply(Workshop.compile(op))
        if not ok then return nil, string.format('Operation %d (%s): %s', i, op.kind, tostring(removed)) end
    end
    return machine
end

function Workshop.new(stock, name)
    local clean = size(stock or {x = 100, y = 50, z = 40})
    local machine = Machine.new(FORM.box(Vector3.new(clean.x, clean.y, clean.z)))
    return setmetatable({
        stock = clean,
        name = label(name or 'Untitled Workpiece'),
        operations = {},
        cursor = 0,
        machine = machine,
    }, Workshop)
end

function Workshop:replace(operations)
    assert(type(operations) == 'table' and #operations <= Workshop.MAX_OPERATIONS,
        'Operation budget exceeded')
    local clean = {}
    for i, op in operations do clean[i] = normalize(op) end
    local machine, reason = rebuild(self.stock, clean)
    if not machine then return false, reason end
    self.operations = clean
    self.machine = machine
    self.cursor = #clean
    return true
end

function Workshop:insert(op, index)
    index = index or self.cursor + 1
    assert(type(index) == 'number' and index % 1 == 0
        and index >= 1 and index <= self.cursor + 1, 'Invalid insertion index')
    local clean = {}
    for i = 1, self.cursor do clean[i] = self.operations[i] end
    table.insert(clean, index, normalize(op))
    return self:replace(clean)
end

function Workshop:edit(index, op)
    assert(type(index) == 'number' and index >= 1 and index <= self.cursor
        and index % 1 == 0, 'Invalid operation index')
    local clean = {}
    for i = 1, self.cursor do clean[i] = self.operations[i] end
    clean[index] = normalize(op)
    return self:replace(clean)
end

function Workshop:remove(index)
    assert(type(index) == 'number' and index >= 1 and index <= self.cursor
        and index % 1 == 0, 'Invalid operation index')
    local clean = {}
    for i = 1, self.cursor do clean[i] = self.operations[i] end
    table.remove(clean, index)
    return self:replace(clean)
end

function Workshop:move(index, delta)
    assert(type(index) == 'number' and index % 1 == 0 and index >= 1 and index <= self.cursor,
        'Invalid operation index')
    assert(delta == 1 or delta == -1, 'Move direction must be +/-1')
    local target = index + delta
    if target < 1 or target > self.cursor then return false, 'CANNOT_MOVE_FURTHER' end
    local clean = {}
    for i = 1, self.cursor do clean[i] = self.operations[i] end
    clean[index], clean[target] = clean[target], clean[index]
    return self:replace(clean)
end

function Workshop:undo()
    if self.cursor == 0 then return false, 'NOTHING_TO_UNDO' end
    if not self.machine:undo() then return false, 'HISTORY_DESYNC' end
    self.cursor -= 1
    return true
end

function Workshop:redo()
    if self.cursor >= #self.operations then return false, 'NOTHING_TO_REDO' end
    if not self.machine:redo() then return false, 'HISTORY_DESYNC' end
    self.cursor += 1
    return true
end

function Workshop:resetStock(stock)
    local clean = size(stock)
    self.stock = clean
    self.operations = {}
    self.cursor = 0
    self.machine = Machine.new(FORM.box(vec(clean)))
    return true
end

function Workshop:summary()
    local status = self.machine:status()
    return {
        name = self.name,
        operations = self.cursor,
        totalOperations = #self.operations,
        volume = status.volume,
        removed = status.removedTotal,
        pieces = status.pieceCount,
        stockVolume = self.stock.x * self.stock.y * self.stock.z,
    }
end

function Workshop:payload()
    local records = {}
    for i, op in self.operations do records[i] = normalize(op) end
    return {version = Workshop.VERSION, name = self.name, stock = size(self.stock),
        cursor = self.cursor, operations = records}
end

function Workshop:serialize()
    return HttpService:JSONEncode(self:payload())
end

function Workshop.deserialize(json)
    assert(type(json) == 'string' and #json > 0 and #json <= Workshop.MAX_JSON_BYTES,
        'Project JSON length is invalid')
    local ok, payload = pcall(function() return HttpService:JSONDecode(json) end)
    if not ok or type(payload) ~= 'table' or payload.version ~= Workshop.VERSION then
        return nil, 'INVALID_PROJECT_VERSION_OR_JSON'
    end

    local success, jobOrReason, errorReason = pcall(function()
        local job = Workshop.new(payload.stock, payload.name)
        assert(type(payload.operations) == 'table'
            and #payload.operations <= Workshop.MAX_OPERATIONS, 'Invalid project operations')
        local valid, reason = job:replace(payload.operations)
        if not valid then return nil, reason end
        assert(type(payload.cursor) == 'number' and payload.cursor % 1 == 0
            and payload.cursor >= 0 and payload.cursor <= #job.operations,
            'Invalid project cursor')
        while job.cursor > payload.cursor do
            local reverted = job:undo()
            assert(reverted, 'Cannot restore project cursor')
        end
        return job
    end)
    if not success then return nil, tostring(jobOrReason) end
    if not jobOrReason then return nil, errorReason end
    return jobOrReason
end

return Workshop
