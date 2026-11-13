--!strict
-- Hotbar 1 Build places; hotbar 2 Edit manipulates existing authored parts.
-- Mechanics and Assembly/Simulation retain their contextual subtools.
-- LegacyMode is an internal compatibility adapter, never server authority.
local definitions={
    Build={
        Default="Build",
        Items={{Id="Build",Key=Enum.KeyCode.B,LegacyMode="Build"}},
    },
    Edit={
        Default="Edit",
        Items={{Id="Edit",Key=Enum.KeyCode.E,LegacyMode="Edit"}},
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
