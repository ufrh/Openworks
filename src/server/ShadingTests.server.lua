local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORM = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'))
local Union = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Union'))
local Shading = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Shading'))
local Planarize = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Planarize'))

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


local warped = FORM.box(Vector3.new(100, 50, 40))
warped.vertices[3] = warped.vertices[3] + Vector3.new(0, 0.008, 0)
local original = warped.vertices[3]
local display, planarStats = Planarize.display(warped)

assert(warped.vertices[3] == original, 'Display planarization mutated canonical geometry')
assert(planarStats.snappedVertices > 0, 'Warpage fixture did not trigger planarization')
assert(planarStats.maxAxisShift > 0 and planarStats.maxAxisShift <= 0.03,
    'Unexpected CAD display geometry correction')

local topY = display.vertices[3].Y
for _, index in {3, 4, 7, 8} do
    assert(math.abs(display.vertices[index].Y - topY) < 1e-5,
        string.format('Display top not planar after correction at vertex %d', index))
end
print(string.format('[FORM:Shading] Warped-plate planarization: %d vertices corrected; max %.6f mm',
    planarStats.snappedVertices, planarStats.maxAxisShift))

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
