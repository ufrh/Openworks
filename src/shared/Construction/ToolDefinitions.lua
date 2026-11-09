--!strict
-- Single source of truth for OPENWORKS native Tool instances and their order.
local definitions = {
    { Id = "Build", Tooltip = "Place primitives and construct geometry" },
    { Id = "Edit", Tooltip = "Select, transform, and resize primitives" },
    { Id = "Assemble", Tooltip = "Create rigid components and mechanical relationships" },
    { Id = "Inspect", Tooltip = "Inspect, measure, and select obstructed components" },
}

for _, definition in ipairs(definitions) do
    table.freeze(definition)
end

return table.freeze(definitions)
