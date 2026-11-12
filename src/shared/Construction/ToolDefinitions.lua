--!strict
-- UI v2: the only provisioned Roblox Tools. Subtools are contextual client
-- states, not extra Tools or inventory items.
local definitions = {
    { Id = "Build", Name = "Build", Tooltip = "Place, edit, resize and paint geometry" },
    { Id = "Mechanics", Name = "Mechanics", Tooltip = "Connect and configure mechanical relationships" },
    { Id = "AssemblySimulation", Name = "Assembly & Simulation", Tooltip = "Manage assemblies and simulate machines" },
}
for _, definition in ipairs(definitions) do
    table.freeze(definition)
end
return table.freeze(definitions)
