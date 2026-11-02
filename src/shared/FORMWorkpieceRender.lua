local AssetService = game:GetService('AssetService')

local FORM = require(script.Parent.FORM)
local Shading = require(script.Parent.FORM.Shading)
local Planarize = require(script.Parent.FORM.Planarize)
local Stock = require(script.Parent.Stock)

local Renderer = {}

function Renderer.create(solid, source)
    assert(FORM.validate(solid).ok, 'Filed geometry is invalid')

    local low, high = FORM.bounds(solid)
    local center = (low + high) * 0.5
    local display = Planarize.display(solid)
    local shading = Shading.normals(display, 35)

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

    local mesh = AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
        CollisionFidelity = Enum.CollisionFidelity.Hull,
    })

    mesh.Name = 'FORMFiledVisual'
    mesh.Size = (high - low) * Stock.SCALE
    mesh.Anchored = false
    mesh.Massless = true
    mesh.CanCollide = false
    mesh.CanTouch = false
    mesh.CanQuery = false
    mesh.CastShadow = source.CastShadow
    mesh.Material = source.Material
    mesh.MaterialVariant = source.MaterialVariant
    mesh.Color = source.Color
    mesh.Transparency = source.Transparency
    mesh.Reflectance = source.Reflectance
    mesh.CFrame = source.CFrame * CFrame.new(center * Stock.SCALE)

    return mesh
end

return Renderer
