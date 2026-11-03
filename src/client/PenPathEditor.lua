local ReplicatedStorage = game:GetService('ReplicatedStorage')

local PenPath = require(ReplicatedStorage:WaitForChild('Openworks')
    :WaitForChild('PenPath'))
local ScorePath = require(ReplicatedStorage:WaitForChild('Openworks')
    :WaitForChild('ScorePath'))

local Editor = {}
Editor.__index = Editor

local function mark(parent, name)
    local part = Instance.new('Part')
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Transparency = 0.06
    part.Parent = parent
    return part
end

function Editor.new()
    local self = setmetatable({}, Editor)
    self.work = nil
    self.nodes = {}
    self.drag = nil
    self.cursor = nil
    self.dirty = true
    self.parts = {}
    self.used = 0
    self.folder = Instance.new('Folder')
    self.folder.Name = 'OpenworksPenTool'
    self.folder.Parent = workspace
    return self
end

function Editor:attach(work)
    if self.work == work then return end
    self:clear()
    self.work = work
    self.dirty = true
end

function Editor:clear()
    table.clear(self.nodes)
    self.drag = nil
    self.cursor = nil
    self.dirty = true
    self:render()
end

function Editor:close()
    self.work = nil
    self:clear()
end

function Editor:hasPath()
    return #self.nodes > 0
end

function Editor:undo()
    if #self.nodes > 0 then
        table.remove(self.nodes)
        self.drag = nil
        self.dirty = true
    end
    return #self.nodes
end

function Editor:payload()
    local result = {}
    for i, node in self.nodes do
        result[i] = {
            point = node.point,
            inHandle = node.inHandle,
            outHandle = node.outHandle,
        }
    end
    return result
end

function Editor:world(point)
    if not self.work then return nil end
    local axis, sign = ScorePath.face(self.work)
    local normal = self.work.CFrame:VectorToWorldSpace(
        ScorePath.normal(axis, sign))
    return self.work.CFrame:PointToWorldSpace(point) + normal * 0.025
end

function Editor:pick(camera, screen)
    local selected, nearest
    for i, node in self.nodes do
        for _, name in {'inHandle', 'outHandle', 'point'} do
            if name ~= 'point' and (node[name] - node.point).Magnitude < 0.012 then
                continue
            end
            local world = self:world(node[name])
            local projected, visible = camera:WorldToViewportPoint(world)
            if visible then
                local distance = (Vector2.new(projected.X, projected.Y) - screen).Magnitude
                if distance < 15 and (not nearest or distance < nearest) then
                    selected, nearest = {index = i, kind = name}, distance
                end
            end
        end
    end
    return selected
end

function Editor:press(point, camera, screen, alternate)
    if not self.work or not point then return false end
    local picked = self:pick(camera, screen)
    if picked then
        self.drag = picked
        self.drag.alternate = alternate
        return true
    end

    if #self.nodes >= PenPath.MAX_ANCHORS then return false end
    self.nodes[#self.nodes + 1] = {
        point = point, inHandle = point, outHandle = point,
    }
    self.drag = {index = #self.nodes, kind = 'new'}
    self.dirty = true
    return true
end

function Editor:move(point, alternate)
    if not self.drag or not point then return end
    local drag = self.drag
    local node = self.nodes[drag.index]
    if not node then return end
    if drag.kind == 'point' then
        local delta = point - node.point
        node.point = point
        node.inHandle += delta
        node.outHandle += delta
    elseif drag.kind == 'new' or drag.kind == 'outHandle' then
        node.outHandle = point
        if drag.kind == 'new' or not alternate then
            node.inHandle = node.point * 2 - point
        end
    elseif drag.kind == 'inHandle' then
        node.inHandle = point
        if not alternate then node.outHandle = node.point * 2 - point end
    end
    self.dirty = true
end

function Editor:release()
    self.drag = nil
end

function Editor:hover(point)
    if (self.cursor == nil) ~= (point == nil)
        or (point and self.cursor and (point - self.cursor).Magnitude > 0.005) then
        self.cursor = point
        self.dirty = true
    end
end

function Editor:part(kind, from, to, color, diameter)
    if not self.work then return end
    self.used += 1
    local part = self.parts[self.used]
    if not part then
        part = mark(self.folder, 'PenVisual_' .. self.used)
        self.parts[self.used] = part
    end
    local a = self:world(from)
    local b = to and self:world(to) or nil
    part.Color = color
    part.Shape = if kind == 'Dot' then Enum.PartType.Ball else Enum.PartType.Block
    if kind == 'Dot' then
        part.Size = Vector3.new(diameter, diameter, diameter)
        part.CFrame = CFrame.new(a)
    else
        local length = (b - a).Magnitude
        part.Size = Vector3.new(diameter, diameter, math.max(0.002, length))
        part.CFrame = CFrame.lookAt((a + b) * 0.5, b)
    end
    part.Parent = self.folder
end

function Editor:render()
    if not self.dirty then return end
    self.dirty = false
    self.used = 0

    if self.work and self.work.Parent then
        local gold = Color3.fromRGB(246, 188, 82)
        local cyan = Color3.fromRGB(95, 225, 211)
        local dim = Color3.fromRGB(123, 161, 173)
        local active = Color3.fromRGB(255, 228, 155)
        local samples = PenPath.sample(self.work, self.nodes, true)

        if samples then
            for i = 2, #samples do
                self:part('Line', samples[i - 1], samples[i], gold, 0.020)
            end
        end

        for i, node in self.nodes do
            if (node.inHandle - node.point).Magnitude > 0.012 then
                self:part('Line', node.point, node.inHandle, dim, 0.008)
                self:part('Dot', node.inHandle, nil, cyan, 0.034)
            end
            if (node.outHandle - node.point).Magnitude > 0.012 then
                self:part('Line', node.point, node.outHandle, dim, 0.008)
                self:part('Dot', node.outHandle, nil, cyan, 0.034)
            end
            self:part('Dot', node.point, nil,
                if i == #self.nodes then active else cyan, 0.052)
        end

        if self.cursor and #self.nodes > 0 and not self.drag then
            local last = self.nodes[#self.nodes]
            local start = last.point
            if (self.cursor - start).Magnitude > 0.03 then
                local prior = start
                for i = 1, 12 do
                    local point = PenPath.cubic(start, last.outHandle,
                        self.cursor, self.cursor, i / 12)
                    self:part('Line', prior, point, dim, 0.010)
                    prior = point
                end
            end
        end
    end

    for i = self.used + 1, #self.parts do
        self.parts[i].Parent = nil
    end
end

return Editor
