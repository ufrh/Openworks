--!strict
-- Native tool hotbar: Build=1, Edit=2, Mechanics=3, Assembly/Sim=4.
-- Editor and placement have separate equipped-tool authority.
local definitions = {
    { Id = "Build", Name = "Build", Tooltip = "Place primitives and saved components" },
    { Id = "Edit", Name = "Edit", Tooltip = "Select, reshape, transform, paint and fit authored geometry" },
    { Id = "Mechanics", Name = "Mechanics", Tooltip = "Connect and configure mechanical relationships" },
    { Id = "AssemblySimulation", Name = "Assembly & Simulation", Tooltip = "Manage assemblies and simulate machines" },
}
for _, definition in ipairs(definitions) do
    table.freeze(definition)
end
return table.freeze(definitions)
