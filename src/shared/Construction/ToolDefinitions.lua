--!strict
-- Single source of truth for OPENWORKS native Tool instances and their order.
local definitions = {
    { Id = "Build", Tooltip = "Place primitives and construct geometry" },
    { Id = "Edit", Tooltip = "Build, resize, and edit mechanical relationships" },
    { Id = "Simulate", Tooltip = "Mouse-driven properties and native mechanical simulation" },
    { Id = "Inspect", Tooltip = "Inspect, measure, and select obstructed components" },
    { Id = "Weld", Tooltip = "Choose two touching solids and author an explicit weld" },
}

for _, definition in ipairs(definitions) do
    table.freeze(definition)
end

return table.freeze(definitions)
