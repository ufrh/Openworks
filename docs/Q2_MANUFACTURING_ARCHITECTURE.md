# OPENWORKS — Q2 manufacturing architecture

## Runtime ownership

- **FORGE 4.4.1** owns service/controller lifecycle, transport and security.
- **OpenWorksDocuments** is the per-player server-authoritative source of
  component/operation history, revision numbers and notes.
- **DocumentBridge** is the client boundary. It forwards edits to FORGE
  endpoints and adopts validated snapshots without replacing component tables.
- **FORM Document** validates operations, dimensions and history and can
  rebuild source documents from snapshots.
- **FORM Fabricator** compiles generated geometry from ordered operation
  histories. Clients keep the last accepted material visible while CSG runs.
- **FORM Features** derives stable hole mating candidates from enabled
  Drill / DrillFace operations. The IDs are "hole:<operationId>", anchored
  to the local workpiece frame, not to disposable Roblox Parts.

## Snap policy

The client-only `Tools/Snapping/SnapSettings` module owns the interactive
increment. Default: 0.05 studs (14 mm); configurable 1–560 mm in the Edit
panel, with 14/28/70/140 mm quick presets. It drives:
- Component-sized construction grid spacing/visibility redraw
- Sketch points and face-local drill placement
- Transform gizmo **Move** increments
- Surface point snapping and saw selection picks

Authoring snap is distinct from dimensional tolerance: typed positions,
scales, drill diameters, stock dimensions and fabrication source history are
stored at 1 mm resolution as FORM permits. Rotation remains 15° snap.
Construction grid is always enabled **on entering Edit**, including after
Boolean compilation. Explicit manual hiding and model-only Preview override
that default temporarily. The grid never resizes the fixed chamber.

## Authoritative transaction flow

1. User authors an operation locally but does not mutate the server.
2. DocumentBridge invokes a FORGE service endpoint with component ID and
   expected revision.
3. The server validates ownership, shape, bounds, operation count and
   revision, then applies the FORM operation.
4. The client adopts the returned validated snapshot (same component
   identity) and starts/updates local CSG preview.
5. CSG failure restores the latest previously issued server snapshot;
   failure of the very first solid discards the invalid server draft.
6. Transform gizmo updates remain smooth and local during dragging; the
   server receives a single absolute final transform on release.
7. Component notes commit once on focus loss, not per keystroke.

The service currently stores session-scoped component documents in memory.
**Durable persistence and replication of physical world bodies are Q4**
responsibilities. CSG compilation and final collision material remain
client-derived; full server verification of generated solids is not yet in
place. Q3 must verify the final compiled opening/clearance before treating
a hole metadata candidate as an actual mechanical mating interface.

## Source geometry frame

Sketch points from SketchEditor are component-centered Vector2 values.
Document preserves that centered frame, with 1 mm authored-value precision,
and Extrusion consumes it directly. Adding/subtracting `node.size/2` at a
second stage is an invalid double transform and must not be reintroduced.

## Acceptance testing

Run in Roblox Studio Play:
1. `scripts/VERIFY_Q2_MANUFACTURING.lua` on CLIENT.
2. `scripts/VERIFY_Q2_FORGE_DOCUMENTS.lua` on CLIENT (real server RPC).
3. `scripts/VERIFY_FORM_SKETCH_REMOVAL.lua` on CLIENT (actual Boolean).
4. `scripts/VERIFY_SKETCH_GRID_ALIGNMENT.lua` on CLIENT.
5. Manually sketch a stock body, drill, saw, undo, toggle feature history,
   type a non-default 21 mm snap, move the component and re-enter Free.
6. Inspect FORGE boot and network diagnostics for failures.

These checks are committed but **not executable through the GitHub-only
workflow**. Do not mark all Q2 acceptance criteria passed until Studio Play
runs confirm actual source-to-solid correctness and the server round trip.
