--!strict
-- Read-only view of the primitives generated in Studio.
-- Do not compile CSG or manufacture new primitives at runtime.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LIBRARY_NAME = "OPENWORKS_PrimitiveLibrary_DRAFT"

local Registry = {}

-- Studio's draft tube templates were generated with LengthOnly_1U.
-- The runtime kernel can resize their cross sections without regenerating
-- the library; circular profiles keep Y and Z tied to one diameter.
function Registry.ResolveResizeMode(model)
    local name = string.lower(model.Name)
    if string.find(name, "circulartube", 1, true)
        or string.find(name, "halftube", 1, true) then
        return "LengthAndDiameter_1U"
    elseif string.find(name, "squaretube", 1, true)
        or string.find(name, "rectangulartube", 1, true) then
        return "XYZ_1U"
    end
    return model:GetAttribute("ResizeMode") or "None"
end

function Registry.List()
    local source = ReplicatedStorage:FindFirstChild(LIBRARY_NAME)
    local entries = {}

    if not source then
        return entries
    end

    for _, category in ipairs(source:GetChildren()) do
        if not category:IsA("Folder") then
            continue
        end

        for _, model in ipairs(category:GetChildren()) do
            if not model:IsA("Model") then
                continue
            end

            local geometry = model.PrimaryPart or model:FindFirstChild("Geometry")
            if geometry and geometry:IsA("BasePart") then
                table.insert(entries, {
                    Id = model.Name,
                    Category = category.Name,
                    ResizeMode = Registry.ResolveResizeMode(model),
                    Model = model,
                })
            end
        end
    end

    table.sort(entries, function(a, b)
        return a.Id < b.Id
    end)

    return entries
end

function Registry.Get(id)
    for _, entry in ipairs(Registry.List()) do
        if entry.Id == id then
            return entry
        end
    end
    return nil
end

function Registry.IsAvailable()
    return ReplicatedStorage:FindFirstChild(LIBRARY_NAME) ~= nil
end

return Registry
