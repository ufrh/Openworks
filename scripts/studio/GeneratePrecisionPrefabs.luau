-- OPENWORKS: one-time Studio Edit-mode gallery generation.
-- First sync/pull `dev` into Studio. Paste this file in View > Command Bar.
-- This generates session-static MeshParts in ReplicatedStorage and a 45-item
-- Workspace gallery. Play-mode servers regenerate the mesh content on boot.
local Prefabs = require(game:GetService("ReplicatedStorage")
    :WaitForChild("Openworks"):WaitForChild("Construction")
    :WaitForChild("ProceduralPrefabLibrary"))
Prefabs.BuildGallery(true)
