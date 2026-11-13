#!/usr/bin/env python3
"""Static contracts for the publish-once / load-forever mesh workflow.

The actual upload MUST be run from a locally loaded Roblox Studio plugin.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
mod = (ROOT / 'src/shared/Construction/ProceduralPrefabLibrary.lua').read_text()
plugin = (ROOT / 'scripts/studio/OpenworksPermanentMeshPublisher.plugin.lua').read_text()
doc = (ROOT / 'docs/PERMANENT_MESH_PUBLISHING.md').read_text()

def check(description, predicate):
    assert predicate, description
    print('PASS', description)

check('Dedicated manifest outside auto-regenerated draft library',
    'PUBLISHED_MANIFEST_NAME = "OPENWORKS_PublishedMeshAssets"' in mod and
    'MANIFEST_NAME = "OPENWORKS_PublishedMeshAssets"' in plugin and
    'LIBRARY_NAME = "OPENWORKS_PrimitiveLibrary_DRAFT"' in mod)
check('Names exactly eight gears plus one bolt',
    'COUNTS = {8, 12, 20, 32}' in mod and
    'for _, kind in ipairs({"Spur", "Bevel90"})' in mod and
    'BOLT_BASE_KEY = "Bolt_SharpThread"' in mod)
check('Permanent assets loaded directly without EditableMesh creation',
    'AssetService:CreateMeshPartAsync(Content.fromAssetId(assetId)' in mod and
    'base = publishedPart(published[key], key)' in mod and
    'boltBase = publishedPart(published[BOLT_BASE_KEY], BOLT_BASE_KEY)' in mod)
check('Asset manifest is read only when Ready=true',
    'if manifest:GetAttribute("Ready") ~= true then' in mod and
    'manifest:GetAttribute("SchemaVersion") == PUBLISHED_SCHEMA' in mod)
check('Legacy temporary preview path retained for unconverted places',
    'CreateDataModelContentAsync(Content.fromObject(mesh))' in mod and
    'base, details = buildGearMesh(teeth, bevel)' in mod and
    'boltBase, boltDetails = buildBoltMesh()' in mod)
check('Published gear metadata matches runtime gear math',
    'local function publishedGearDetails(teeth)' in mod and
    'triangles = #samples * 8' in mod and
    'model:SetAttribute("GearModuleStuds", math.pi * CAD_MODULE * scale)' in mod)
check('Published bolt metadata matches existing fitting geometry',
    'local function publishedBoltDetails()' in mod and
    'headLength = 0.17' in mod and
    'model.PrimaryPart = pivot' in mod and
    'ringCollision(model,scale,details.root,details.pitch,bevel)' in mod)
check('Publisher requires an installed plugin and uses real mesh assets',
    'assert(plugin, "Install this Script as a LOCAL STUDIO PLUGIN first' in plugin and
    'AssetService:CreateAssetAsync(editableMesh,' in plugin and
    'Enum.AssetType.Mesh' in plugin and
    'CreateAssetVersionAsync(editableMesh,' in plugin)
check('Publisher stores IDs as durable StringValues and supports resume',
    'Instance.new("StringValue")' in plugin and
    'entry.Value = tostring(id)' in plugin and
    'previousId and not updateVersion' in plugin)
check('Publisher supports group-owned experiences',
    'Enum.CreatorType.Group' in plugin and 'Enum.AssetCreatorType.Group' in plugin)
check('Publisher marks complete only after upload and refreshes prefab gallery',
    plugin.index('assert(progress == 9') < plugin.index('manifest:SetAttribute("Ready", true)') and
    'generator.Ensure(true)' in plugin and 'generator.BuildGallery(false)' in plugin)
check('Shared module destroys EditableMesh after plugin callback',
    len(re.findall(r'local ok, result = pcall\(onEditable, mesh\)\s+mesh:Destroy\(\)', mod)) == 2)
check('Plugin install / save requirements documented',
    all(s in doc for s in ['Save as Local Plugin', 'Save/Publish the Roblox place', 'Sync latest `dev`']))
print('PASS: published mesh workflow source contracts')
