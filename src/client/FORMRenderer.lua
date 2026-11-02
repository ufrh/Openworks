local AssetService = game:GetService('AssetService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local FORMMaterial = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORMMaterial'))

local Shading = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Shading'))
local Planarize = require(ReplicatedStorage:WaitForChild('Openworks'):WaitForChild('FORM'):WaitForChild('Planarize'))

local Renderer = {}

function Renderer.create(solid, studsPerMillimeter, smoothAngle)
    assert(type(studsPerMillimeter) == 'number' and studsPerMillimeter > 0, 'Invalid display scale')
    smoothAngle = smoothAngle or 30

    local display, planarStats = Planarize.display(solid)
    local shading, shadingStats = Shading.normals(display, smoothAngle)
    local editable = AssetService:CreateEditableMesh()
    assert(editable, 'EditableMesh could not be allocated. Check mesh permissions and memory limits.')

    local ids = {}
    for i, position in display.vertices do
        ids[i] = editable:AddVertex(position * studsPerMillimeter)
    end

    local normalIds = {}
    local function normalId(normal)
        local signature = string.format('%.6f:%.6f:%.6f', normal.X, normal.Y, normal.Z)
        local id = normalIds[signature]
        if not id then
            id = editable:AddNormal(normal)
            normalIds[signature] = id
        end
        return id
    end

    for i, triangle in display.triangles do
        local faceId = editable:AddTriangle(ids[triangle[1]], ids[triangle[2]], ids[triangle[3]])
        editable:SetFaceNormals(faceId, {
            normalId(shading[i][1]),
            normalId(shading[i][2]),
            normalId(shading[i][3]),
        })
    end

    local part = AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
        CollisionFidelity = Enum.CollisionFidelity.Hull,
    })

    FORMMaterial.mark(part)
    shadingStats.planarization = planarStats
    return part, editable, shadingStats
end

function Renderer.createMany(solids, studsPerMillimeter, smoothAngle)
    local combined = {vertices = {}, triangles = {}}
    for _, solid in solids do
        local offset = #combined.vertices
        for _, vertex in solid.vertices do
            combined.vertices[#combined.vertices + 1] = vertex
        end
        for _, triangle in solid.triangles do
            combined.triangles[#combined.triangles + 1] = {
                triangle[1] + offset, triangle[2] + offset, triangle[3] + offset,
            }
        end
    end
    return Renderer.create(combined, studsPerMillimeter, smoothAngle)
end

return Renderer
