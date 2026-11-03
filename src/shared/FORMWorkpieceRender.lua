local AssetService = game:GetService('AssetService')

local FORM = require(script.Parent.FORM)
local Shading = require(script.Parent.FORM.Shading)
local Stock = require(script.Parent.Stock)

local Renderer = {}

function Renderer.create(solid, source, appearance, preciseCollision)
    assert(FORM.validate(solid).ok, 'FORM geometry is invalid')
    appearance = appearance or source

    local low, high = FORM.bounds(solid)
    local center = (low + high) * 0.5
    local display = solid
    local shading = Shading.normals(display, if preciseCollision then 65 else 40)

    local editable = AssetService:CreateEditableMesh()
    assert(editable, 'EditableMesh unavailable; enable Mesh / Image APIs and check memory budget')

    local vertices = {}
    for index, point in display.vertices do
        vertices[index] = editable:AddVertex((point - center) * Stock.SCALE)
    end

    local normals = {}
    local function normalId(vector)
        local key = string.format('%.6f/%.6f/%.6f', vector.X, vector.Y, vector.Z)
        if not normals[key] then normals[key] = editable:AddNormal(vector) end
        return normals[key]
    end

    for i, triangle in display.triangles do
        local face = editable:AddTriangle(
            vertices[triangle[1]], vertices[triangle[2]], vertices[triangle[3]])
        editable:SetFaceNormals(face, {
            normalId(shading[i][1]), normalId(shading[i][2]), normalId(shading[i][3]),
        })
    end

    local bakedResult, bakedContent = AssetService:CreateDataModelContentAsync(
        Content.fromObject(editable))
    editable:Destroy()

    assert(bakedResult == Enum.CreateContentResult.Success,
        'Could not replicate FORM geometry: ' .. tostring(bakedResult))

    local mesh = AssetService:CreateMeshPartAsync(bakedContent, {
        CollisionFidelity = if preciseCollision
            then Enum.CollisionFidelity.PreciseConvexDecomposition
            else Enum.CollisionFidelity.Hull,
    })
    mesh.TextureContent = Content.none

    mesh.Name = 'FORMFiledVisual'
    mesh.Size = (high - low) * Stock.SCALE
    mesh.Anchored = false
    mesh.Massless = true
    mesh.CanCollide = true
    mesh.CanTouch = false
    mesh.CanQuery = true
    mesh.CastShadow = appearance.CastShadow
    mesh.Material = appearance.Material
    mesh.MaterialVariant = appearance.MaterialVariant
    mesh.Color = appearance.Color
    mesh.Transparency = appearance.Transparency
    mesh.Reflectance = appearance.Reflectance
    mesh.CFrame = source.CFrame * CFrame.new(center * Stock.SCALE)

    return mesh
end

return Renderer
