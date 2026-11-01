local AssetService = game:GetService('AssetService')

local Renderer = {}

function Renderer.create(solid, studsPerMillimeter)
    assert(type(studsPerMillimeter) == 'number' and studsPerMillimeter > 0, 'Invalid display scale')

    local editable = AssetService:CreateEditableMesh()
    assert(editable, 'EditableMesh could not be allocated. Check mesh permissions and memory limits.')

    local ids = {}
    for i, position in solid.vertices do
        ids[i] = editable:AddVertex(position * studsPerMillimeter)
    end

    for _, triangle in solid.triangles do
        editable:AddTriangle(ids[triangle[1]], ids[triangle[2]], ids[triangle[3]])
    end

    local part = AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
        CollisionFidelity = Enum.CollisionFidelity.Hull,
    })
    return part, editable
end

return Renderer
