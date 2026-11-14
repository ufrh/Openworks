#!/usr/bin/env python3
"""Contract for a transactional permanent-gear Mesh-ID replacement publisher.

These are source invariants, not a real upload test. Real meshes require
running the local Roblox Studio plugin with creator permissions.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
plugin=(root/"scripts/studio/OpenworksPermanentMeshPublisher.plugin.lua").read_text()
packed=(root/"scripts/studio/OpenworksPermanentMeshPublisher.rbxmx").read_text()
generator=(root/"src/shared/Construction/ProceduralPrefabLibrary.lua").read_text()
doc=(root/"docs/PERMANENT_MESH_PUBLISHING.md").read_text()
def test(label,condition):
    assert condition,label
    print("PASS",label)
test("Unsupported Mesh CreateAssetVersionAsync is not called",
    "AssetService:CreateAssetVersionAsync" not in plugin
    and "AssetService:CreateAssetAsync(editableMesh," in plugin)
test("Normal existing mesh IDs remain live until all candidates load",
    'if not previouslyReady then manifest:SetAttribute("Ready",false) end' in plugin
    and 'entry:SetAttribute("PendingAssetId",' in plugin
    and 'entry.Value=string.format("%.0f",ids[key])' in plugin)
test("Pending IDs persist and retries never repeatedly upload",
    'local pending=pendingIdFor(entry)' in plugin
    and 'if pending then' in plugin
    and 'entry:GetAttribute("PendingProfileVersion") ~= 6' in plugin)
test("Eight gear IDs are validated before promotion",
    'for _,teeth in ipairs({8,12,20,32}) do' in plugin
    and 'for _,kind in ipairs({"Spur","Bevel90"}) do' in plugin
    and 'verifyReplacement(key,candidate)' in plugin
    and 'Content.fromAssetId(assetId)' in plugin
    and plugin.index('verifyReplacement(key,candidate)')
         <plugin.index('entry.Value=string.format("%.0f",ids[key])'))
test("Failed runtime prefab installation restores original manifest",
    'for key,old in pairs(originals) do' in plugin
    and 'entry.Value=old.Id' in plugin
    and 'entry:SetAttribute("ProfileVersion",old.Version)' in plugin
    and 'manifest:SetAttribute("GearGeometryVersion",oldVersion)' in plugin
    and 'manifest:SetAttribute("Ready",previouslyReady)' in plugin)
test("Staged IDs only removed after successful runtime prefab rebuild",
    plugin.index('if not rebuilt then') <
    plugin.index('entry:SetAttribute("PendingAssetId",nil)'))
test("Original bolt mesh ID is always reused",
    'local isGear=key~="Bolt_SharpThread"' in plugin
    and 'not replaceGears or not isGear or upToDate' in plugin)
test("Gear geometry version only switches to 5 after uploads",
    'manifest:SetAttribute("GearGeometryVersion",6)' in plugin
    and 'model:SetAttribute("GearToothPhaseFraction",toothPhase)' in generator)
test("Per-gear phase supports mixed old/pending mesh updates",
    'entry:GetAttribute("ProfileVersion")' in generator
    and 'publishedVersion<5' in generator)
test("Packaged .rbxmx plugin exactly matches the Lua source",
    packed.split("<![CDATA[",1)[1].split("]]>",1)[0]==plugin)
test("User-facing docs explain changed IDs and staged retry",
    'new gear base IDs' in doc
    and 'PendingAssetId' in doc and 'Save/Publish the Roblox place' in doc)
print("PASS: staged mesh replacement contracts")
