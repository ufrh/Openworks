# OPENWORKS — Redesign reset notes

**2026-11-08.** The current dev implementation was archived intact at `archive/pre-gearblocks-redesign-2026-11-08` before this reset.

## Preserved, unchanged
- FORGE/Reforge 4.4.1: `src/forge-shared/` and `src/forge-server/`
- Rojo project mappings and existing development launch/sync scripts
- Repository and git history

## Removed from active dev
All previous OpenWorks-specific FORM, fabrication/CSG editor, CAD modes, gizmos, camera systems, assembly/simulation/persistence implementation, obsolete architecture documents, tests and manufacturing workflows. Everything remains in the archive branch.

## For the new design document
GearBlocks is the primary gameplay and interaction baseline. The desired expansion includes modular shape fabrication with optional curves/parametric mechanical prefabs, consolidation of rigid components on finalization, clear mechanical relationships, belts/cables/other specialized elements, and electronics. Scale should be broadly comparable to GearBlocks. No implementation decisions are final until the complete user-authored design is reviewed.

## Caution
This commit updates remote `dev`; it does not automatically reset uncommitted local files or an already-open Roblox Studio session. Preserve local work before pulling. Do not use the launcher reset option unless willing to lose local uncommitted files.

## Smoke-test status
The new bootstrap source has not been run in Roblox Studio; FORGE itself is preserved byte-for-byte.
