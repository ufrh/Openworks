# OPENWORKS — Q4 / Replicated Physics, Actuation and Persistence

## Server-manufactured world

`OpenWorksWorld` is a real FORGE Service. On Free Mode entry it
publishes source documents from `OpenWorksDocuments`, compiling every
component using server-side FORM and the original GeometryService pipeline.
No client mesh or caller-selected Part is accepted as source geometry.

Published physics is placed under
`Workspace.OPENWORKS_Published/<UserId>/Component_<Id>` with original
world placement. A CSG recompile preserves the body's current physical
CFrame displacement and velocity, subject to geometry validity.
The published part is unanchored, colliding, owner-locked by the
DragDetector permission policy and server-owned for network simulation.
Clients retire their old local Free clones when the replicated part arrives.

The server checks compiled material volume before publication and retains
the previous body on compile failure. Exact mesh collision is not claimed:
PreciseConvexDecomposition is the finest practical Roblox approximation.

## Joint and actuator compilation

Joint records and local hole features are held in server-side graph/data.
The server builds physics constraints only for explicit installed
relationships and recreates them after replacing a manufactured body.
Installed relative poses are restored only for a new relationship or
when its physical body is replaced; unrelated recompiles must not
re-teleport a working assembly.

Revolute joints support server-capped HingeConstraint motor angular
velocity and torque. Motor state is saved with the relationship graph.

## Persistence

- DataStore name: `OPENWORKS_MANUFACTURING_V1`.
- Payload version: 1, keyed by player UserId.
- Contents: source FORM component snapshots, joint graph, actuation,
  and published physical CFrame poses.
- JSON codec: tagged Vector2, Vector3 and CFrame; 1 MiB limit and
  explicit nesting/table bounds. Roblox Instances/meshes are never saved.
- Autosave: 120 seconds for loaded players; also PlayerRemoving and
  server BindToClose; manual Save Workshop buttons are available.
- DataStore writes use UpdateAsync with bounded retries and explicit
  failure messages. Production needs published experience data access.
- Studio writes are **off by default** to protect live player data.
  To opt in for controlled Studio tests, set the DataModel attribute
  `OpenworksEnableStudioDataStore=true` before starting Play, and
  enable the experience's Studio API access in Studio settings.

The FORGE transport caps messages at 32 KiB: client startup fetches
components in four-item pages. Very large individual component histories
may still exceed this limit and need a future streaming/chunking codec.

## Diagnostics and acceptance

- `OpenWorksWorld:GetStats()` returns published bodies, installed joints,
  build-in-progress state, last server compile error.
- FORGE metrics include publication count, CSG/volume rejects and
  save success/failures.
- `scripts/VERIFY_Q4_PERSISTENCE.lua` checks codec safety without
  writing to DataStore.
- `scripts/VERIFY_Q4_WORLD.lua` tests the actual FORGE server CSG
  publisher, replicated DragDetector, ownership metadata and cleanup.
- `scripts/VERIFY_Q3_ASSEMBLY.lua` checks graph/axis behavior.
- Manual Studio multi-client tests must verify object ownership, dragging,
  two component joints, motors, repeated edit/publish, reconnect and save.

## Outstanding production work

Real-world-correct friction and thread engagement, fine-bearing collision
proxies, wiring/Arduino-like logic, permission policies for shared
assemblies, high-load performance tuning, failure-injection testing,
recovery from invalid saved histories and full DataStore integration tests
remain outside the current verified implementation. **GitHub commits do
not substitute for Roblox Studio runtime results.**
