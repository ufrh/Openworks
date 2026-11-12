--!strict
-- UI v2 primary tools -> contextual subtools. LegacyMode is strictly a
-- client compatibility adapter while existing controllers migrate; it is NOT
-- an authorization token and must never be sent to the server as authority.
local definitions={
    Build={
        Default="Place",
        Items={
            {Id="Place",Key=Enum.KeyCode.B,LegacyMode="Build"},
            {Id="Edit",Key=Enum.KeyCode.E,LegacyMode="Edit"},
            {Id="Resize",Key=Enum.KeyCode.V,LegacyMode="Edit"},
            {Id="Paint",Key=Enum.KeyCode.M,LegacyMode="Edit"},
        },
    },
    Mechanics={
        Default="Connect",
        Items={
            {Id="Connect",Key=Enum.KeyCode.C,LegacyMode="Mechanics"},
            {Id="Configure",Key=Enum.KeyCode.E,LegacyMode="Mechanics"},
        },
    },
    AssemblySimulation={
        Default="AssemblyEditor",
        Items={
            {Id="AssemblyEditor",Key=Enum.KeyCode.E,LegacyMode="Assembly"},
            {Id="Simulation",Key=Enum.KeyCode.Y,LegacyMode="Simulate"},
        },
    },
}
for _, definition in pairs(definitions) do
    for _, item in ipairs(definition.Items) do table.freeze(item) end
    table.freeze(definition.Items)
    table.freeze(definition)
end
return table.freeze(definitions)
