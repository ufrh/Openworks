# OPENWORKS — Machining Workshop phase

## Scope

The Workshop phase converts FORM from a preset-driven machining demonstration to a parametric project editor. The geometry kernel remains at `src/shared/FORM`; `src/shared/Workshop.lua` owns stock/project data and operation replay. Neither FORM nor Workshop stores GUI instances, mesh IDs or DataStore references.

### Client workflow

1. Start Play. The workbench boots with a 100 × 50 × 40 mm workpiece and one example through-hole.
2. On the **left**, select one of seven operation types: drill, pocket, slot, profile, saw, chamfer, or faceted fillet.
3. Edit the operation parameters in **millimeters**. For a profile, enter semicolon-separated `x,y,z` path points at the same Y.
4. **Refresh Tool Path** displays the current proposed operation. **Add Operation** applies it to the machining project.
5. On the **right**, select an existing timeline operation to edit, move up/down or delete it. An edit replays the entire applicable operation sequence atomically; failure preserves the previous project.
6. Undo/redo affect the active history cursor. Inserting after undo intentionally discards the redo branch.
7. **New Stock** accepts dimensions between 10 and 250 mm, resets operations and keeps the current project name.
8. **Save Project / Load Project** use a single per-player DataStore slot. Studio often needs **Game Settings → Security → Enable Studio Access to API Services**; failures are explicitly reported instead of silently claiming persistence.
9. **Export Project JSON** opens the serialized project for manual select-all/copy; **Import Project JSON** accepts a pasted project even when DataStore access is disabled.
10. Toggle tool-path overlay, normals and material. Existing visual refinements (planarization, protected normals, metal/plastic/neon) remain in the EditableMesh render adapter.

## Modules

- `src/shared/Workshop.lua`: operation normalization, typed compilation, bounded replay, atomic insert/edit/delete/reorder, undo/redo, named stock and versioned JSON.
- `src/client/WorkbenchUI.lua`: working two-panel client editor with operation timeline, parameters, project import/export and live rendering.
- `src/client/Toolpath.lua`: non-colliding Neon geometry to indicate drilling, stock removal, slots, multi-point paths and saw planes.
- `src/server/WorkshopStorage.server.lua`: rate-limited and validated remote project save/load, keyed by user ID. The server replays project operations before saving; never trusts supplied triangles or total volume.
- `src/server/WorkshopTests.server.lua`: project operation replay, volume checks, atomic rejection, undo/redo and JSON round-trip.
- `src/client/init.client.lua`: starts the new editor.

## Project file protocol

Version 1 JSON contains `version`, `name`, `stock={x,y,z}`, `cursor`, and `operations`. Positions, cutter sizes, angles, signs, and profile points are plain bounded numeric values. No Roblox Instances, arbitrary Luau, remote payload objects, or untrusted mesh triangles are accepted as records.

A project has at most 24 committed operations and a 24 KB JSON limit, as well as the existing FORM operation budgets. Replay generates the same `Machine` convex fragments and uses the original stock/cutter history to produce a unified surface; a failed unification preserves the fragment preview. Invalid edits never overwrite the previous workpiece.

All dimensions are in mm until the renderer converts at the current 0.04 studs/mm preview scale.

## Engineering limits

This phase is a **prototype workshop**, not a physically simulated CNC. Tool paths are visualization of cutter sweeps, not G-code, feed rates, physical tool collisions, fixture/stock constraints, material cutting forces, or actual machine motion. The slot and profile follow the existing horizontal-Y machining convention. Fillets are faceted. Only one server-side save slot per player is provided in this phase; the portable JSON export allows manual project interchange.

Server-side persistence is best-effort when DataStore is enabled, and client preview geometry is not an authoritative multiplayer model. Multi-user shared builds and inventory/tool progression remain later product layers.

## Runtime acceptance

Run Play and inspect `[WORKSHOP]` together with `[FORM]` logs. The project test must report:

```text
[WORKSHOP] Project replay, editing, reorder, atomic rejection, undo/redo and JSON tests passed
```

Then use the GUI to test: add a drill, edit its radius, undo/redo, move independent pocket/drill operations, export/import JSON, and save/load when Studio API access is available. Verify the workpiece still renders as a unified mesh or an explicit fallback after each operation.

**Verification:** source committed to `dev`, source files scanned for obvious unclosed strings. The newly added Workshop UI, remote storage and project tests have not been executed in Roblox Studio in this session; their runtime success is not claimed.
