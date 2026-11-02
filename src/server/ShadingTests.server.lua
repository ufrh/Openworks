local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Union = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Union'))
local Shading = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Shading'))

local function checkSurface(mesh, expectedPlane, expectedNormal, label)
    local normals, stats = Shading.normals(mesh, 30)
    local selected = 0

    for i, face in mesh.triangles do
        local flat = true
        for _, vertexId in face do
            local vertex = mesh.vertices[vertexId]
            if math.abs(vertex.Y - expectedPlane) > 0.001 then
                flat = false
                break
            end
        end

        if flat then
            selected += 1
            for _, normal in normals[i] do
                assert(normal:Dot(expectedNormal) > 0.99999,
                    string.format('%s has top-face shading leakage in triangle %d: %s',
                        label, i, tostring(normal)))
            end
        end
    end

    assert(selected > 0, label .. ' has no top-facing triangles')
    print(string.format('[FORM:Shading] %s: %d stable top triangles; %d plane groups, %d protected, %d smoothed edges',
        label, selected, stats.planarGroups, stats.protectedGroups, stats.smoothedEdges))
end

local box = FORM.box(Vector3.new(100, 50, 40))
checkSurface(box, 25, Vector3.yAxis, 'Stock')

local cutter = FORM.cylinder(7, 70, 12)
local drilled, reason = Union.subtractBoundary(box, cutter, 192650)
assert(drilled, 'Drilled shading fixture failed: ' .. tostring(reason))
checkSurface(drilled, 25, Vector3.yAxis, 'Drilled workpiece')

local normals = Shading.normals(drilled, 30)
for i, face in drilled.triangles do
    for corner, normal in normals[i] do
        assert(normal.X == normal.X and normal.Y == normal.Y and normal.Z == normal.Z,
            'Invalid shading normal')
        assert(math.abs(normal.Magnitude - 1) < 1e-4,
            string.format('Non-unit normal in face %d corner %d', i, corner))
    end
end

print('[FORM:Shading] All flat-surface and finite-normal tests passed')
