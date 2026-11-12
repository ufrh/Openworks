--!strict
-- Single source of truth for OPENWORKS native Tool instances and their order.
local definitions = {
    { Id = "Build", Tooltip = "Place primitives and construct geometry" },
    { Id = "Edit", Tooltip = "Move, group, resize and author mechanical connections" },
    { Id = "Assembly", Tooltip = "Name assemblies and explicitly choose primitives or components" },
    { Id = "Simulate", Tooltip = "Simulate an authored assembly with native mechanical physics" },
    { Id = "Inspect", Tooltip = "Inspect, measure, and select obstructed components" },
    { Id = "Weld", Tooltip = "Weld touching solids or a fitted drilled block and shaft rigidly" },
    { Id = "Belt", Tooltip = "Connect two shaft-mounted pulleys with a tensioned friction belt" },
}

for _, definition in ipairs(definitions) do
    table.freeze(definition)
end

return table.freeze(definitions)
