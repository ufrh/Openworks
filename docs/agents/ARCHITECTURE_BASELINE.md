# OpenWorks 2.0 — Roblox Rebuild Architecture Baseline

**Status:** LOCKED design baseline, 2026-11-21  
**Target:** Roblox + Luau + FORGE services/controllers + Rojo/Git  
**Scope:** Architecture and implementation contracts; not a claim of implemented code.  
**Principle:** Preserve the engineering design from standalone OpenWorks while implementing it using Roblox-specific backends. Gameplay interactions remain open to refinement through testing.

## 1. Decisions locked

1. **Project structure:** OpenWorks is a folder-based Rojo project, not one master ModuleScript. FORGE manages application services/controllers and lifecycle; ordinary ModuleScripts implement pure algorithms and internal helpers.
2. **Framework reuse:** Use FORGE rather than recreating dependency resolution, service/controller registration, RPC, signals, logging, cleanup, or bootstrapping. Extend FORGE only when an observed limitation requires it.
3. **Single authority:** A versioned, structured `ConstructionDocument` is the only authoritative representation of an authored machine. Instances, EditableMeshes, CSG results, collision proxies, and physics constraints are derived representations.
4. **Service boundaries:** A small number of authoritative services own construction, geometry compilation, mechanical definitions, simulation, persistence, and eventual Harmonics. No service exists merely to wrap a small math helper.
5. **Command-only mutation:** Authored changes occur through validated, revisioned, transactional commands, with per-document undo/redo and server permission checks. Clients may predict *previews* but not commit authoritative edits.
6. **Geometry source model:** Exactly five primitives (Block, Cylinder, Sphere, Wedge, Rounded Wedge) and three editing tool families (Drill/Cut, Pattern, Fillet/Chamfer). Components retain source primitives and nondestructive modifier histories.
7. **Geometry compilation:** Geometry service compiles authoritative source into visible geometry, collision geometry, and mechanically meaningful features from one feature graph; backends are replaceable and expensive work is cached/invalidated incrementally.
8. **Mechanical model:** SmartFit uses recognized features with stable identities; mating alignment and the chosen joint/rigid behavior remain separate. Auto/Never/Force welding policies are resolved into rigid groups, not blindly converted into thousands of constraints.
9. **Simulation:** Machines are independently Stabilized or Active; grounding is independent. Authored build pose, current stabilized pose, and active physical state are distinct. A player may edit a stabilized machine while other machines run.
10. **Networking:** FORGE handles endpoint transport. OpenWorks defines command schemas, validation, per-document revision numbers, snapshots, incremental changes, and client resynchronization. The server is authoritative.
11. **Persistence:** Saves are versioned documents with migration and recovery rules; saving never depends on reading the current workspace hierarchy as its primary source.
12. **Testing and diagnostics:** Pure logic tests, Roblox-integration tests, and repeatable mechanical/geometry regression scenes. Tests gate risky changes and preserve construction invariants.
13. **Development approach:** Build complete vertical slices, beginning with one Block's placement, resizing, selection, delete, undo/redo, save and reload. Do not implement an entire collection of disconnected systems before testing the full path.
14. **Security:** Server modules and private data live under ServerScriptService, never ReplicatedStorage. Shared code contains only safe definitions and deterministic helpers; all client payloads are untrusted.
15. **Future systems:** Harmonics maintains an interface boundary, but remains unimplemented until geometry, mechanical graphs, and machine simulation are usable.

## 2. FORGE integration — verified against Ruckus FORGE 3.2.0

The verified FORGE configuration uses `Config.Paths.ServerServices = 'Services'` and `Config.Paths.ClientControllers = 'Controllers'`. Its default server bootstrap scans `ServerScriptService.Services`; its client bootstrap scans `PlayerScripts.Controllers`. The loader recursively **requires every ModuleScript beneath configured application roots**. Modules must therefore be safe to require at load time: no unsolicited Instances, physics changes, or initialization side effects at module top level.

FORGE exposes `FORGE.Class('Service', { Name = ... })` and `FORGE.Class('Controller', { Name = ... })`, `Dependencies`/`Requires`, lifecycle `Init` / `Start` / `Stop` / `Destroy`, `Server` and `Client` endpoint namespaces, endpoint configuration via `:Secure(...)`, and remote signals via `:CreateSignal(...)` / `:FireClient(...)`. Use the actual FORGE APIs; don't invent a second lifecycle. Its `DependencyGraph.Resolve` rejects circular dependencies.

Proposed Studio/Rojo hierarchy (folder names represent organizational structure; ModuleScripts are explicit files or Rojo `init.lua` modules):

```text
ReplicatedStorage
├── FORGE/                                 existing framework
└── OpenWorks/
    └── Shared/
        ├── Foundation/                    units, IDs, schemas, deterministic data math
        ├── Geometry/                      five primitives, modifier definitions, features, math
        ├── Mechanics/                     relationship schemas, transmissions and graph math
        ├── Commands/                      typed command schemas and pure validators
        └── Config/

ServerScriptService
├── FORGE/                                 existing FORGE runtime/bootstrap
└── Services/                              FORGE-discovered root
    └── OpenWorks/
        ├── ConstructionService/
        │   ├── init.lua                    FORGE Service registration
        │   ├── Documents.lua
        │   ├── Transactions.lua
        │   ├── Revisions.lua
        │   └── Permissions.lua
        ├── GeometryService/
        │   ├── init.lua
        │   ├── Compiler.lua
        │   ├── Cache.lua
        │   └── Features.lua
        ├── MechanicsService/
        │   ├── init.lua
        │   ├── Contacts.lua
        │   ├── Welding.lua
        │   └── Graph.lua
        ├── SimulationService/
        │   ├── init.lua
        │   ├── Discovery.lua
        │   ├── States.lua
        │   ├── PhysicsAdapter.lua
        │   └── Controls.lua
        ├── PersistenceService/
        │   ├── init.lua
        │   ├── Serializer.lua
        │   └── Migrations.lua
        └── HarmonicsService/              placeholder only, not registered until built

StarterPlayer
└── StarterPlayerScripts
    ├── FORGE/                              existing FORGE client bootstrap
    └── Controllers/                        FORGE-discovered root
        └── OpenWorks/
            ├── ToolController.lua         owns input arbitration and active tool
            ├── BuildController.lua
            ├── EditController.lua
            ├── SelectionController.lua
            ├── SimulationController.lua
            └── VisualController.lua
```

**Naming:** Each registered service/controller has a globally unique FORGE component name. Services expose operations through a public domain API; helpers remain private. Folders are not themselves services.

**Loading:** The existing FORGE bootstraps should be reused. We may add project-specific roots *only if needed*, rather than modifying its internal loader. A helper module should not register itself as a service.

## 3. System ownership

| Owner | Responsible for | Explicitly not responsible for |
|---|---|---|
| Shared Foundation | Units, IDs, schemas, pure validation helpers | Workspace / service state |
| Shared Geometry & GeometryService | Source geometry, modifiers, feature extraction, compiled meshes/colliders, caches | Player input or machine activation |
| ConstructionService | Authoritative documents, edit commands, permissions, revisions, components and undo/redo | Physical simulation implementation |
| MechanicsService | Contacts, welding rules, joint definitions, gear ratio graphs, actuator definitions | Deciding when a machine is Active |
| SimulationService | Connected machine discovery, stabilization, activation, physics tick integration and controls | Mutating authored geometry without commands |
| PersistenceService | Snapshots, schema migration, saving/recovery | Workspace-to-save scraping |
| Controllers | Input, preview, selection, visuals, tool UI | Security, persistent authoring or simulated physics authority |
| HarmonicsService (later) | Harmonic field, quartz physical network and computing | Implementing initial construction functionality |

**Dependency contract:** Shared pure modules have no application-service dependencies. Services depend on shared modules and other services only via declared FORGE dependencies; no cycles. Controllers use shared math and FORGE's client-facing service proxies. Cross-domain mutations use an owning service's public API; events notify changes without establishing hidden authoritative side effects.

## 4. Data and precision contract

`ConstructionDocument` fields (initial baseline):

```lua
{
    SchemaVersion = 1,
    Id = "document-id",
    Revision = 0,
    OwnerId = 0,
    Primitives = {},       -- stable ID -> shape type, local transforms, dimensions, materials
    Components = {},       -- stable ID -> child IDs, nested editable structure
    Modifiers = {},        -- ordered nondestructive operations with stable IDs
    Features = {},         -- stable holes/axes/slots/face interfaces; generated/indexed as needed
    ContactPolicies = {}, -- Auto, Never, Force
    Relationships = {},    -- stable feature-ID references and mechanical parameters
    BuildPoses = {},       -- separate original authored poses
    Metadata = {},
}
```

Preserve **1u = 10 cm** as the logical engineering convention from the standalone foundation, with authored translational positions/dimensions stored as integer ticks (**1000 ticks/u**, default manipulation step **0.25u**, optional fine step **0.01u**). Use Roblox-scale presentation at an initial **0.25 studs/u**, subject to physical-scale validation. This implies **2.5 studs/m**; forces, mass, player controller speeds, and gravity must consistently respect that conversion. In particular, do not mix default Roblox `196.2 studs/s²` with a claim that gravity represents `9.81m/s²` at this scale: equivalent gravity would be approximately **24.525 studs/s²**. Physics feel and player movement need test-based tuning before final numbers become gameplay commitments.

All authoritative references use IDs and local-coordinate feature frames, not long-lived pointers to Workspace Instances. Duplication produces independent new IDs for the entire owned hierarchy and rewires internal references; external relationships are not silently copied. Source data is not discarded when compiling optimized meshes.

## 5. Commands and replication

Typical command envelope:

```lua
{
    DocumentId = "...",
    BaseRevision = 18,
    ClientOperationId = "...", -- deduplication / acknowledgment only
    Kind = "Primitive.Resize",
    Arguments = { PrimitiveId = "...", Dimensions = {x = 2, y = 3, z = 4} },
}
```

The server validates identity/ownership, payload limits, expected revision, target IDs, constraints, and geometry feasibility. It computes changes on a draft, atomically commits the new document revision, then produces a delta and accepted/rejected acknowledgment. On revision mismatch, clients receive a resync instruction or fresh snapshot; no blind overwrite or duplicated edits. Undo/redo is a new validated transaction against the *current* revision, not a client command to set arbitrary old state. Rate limiting and payload bounds use FORGE endpoint security options but do not replace domain validation.

Initial multiplayer coordination: one authoritative document, serialized per-document edits on the server; ownership and permissions checked for every command. Concurrent collaborator editing, collaboration locks and merge policy come later, without changing command formats.

## 6. Geometry feasibility gate (required)

The geometry architecture is fixed; the **choice of native Roblox geometry API is not prematurely fixed**. Prove all of the following before assuming production-ready booleans/fillets:

1. A basic shape renders, collides and round-trips its source definition.
2. A drilled circular bore produces a *real opening* in both render and collision; no invisible blocking convex hull.
3. Drill history can be edited without destroying the original source primitives.
4. A regenerated component produces stable feature IDs/frames for SmartFit.
5. Compiler caching avoids rebuilding unrelated components, with performance measured on nontrivial assemblies.
6. A graceful unsupported-geometry path reports a clear error; it does not silently lose accuracy or save invalid parts.

Candidate backends may use GeometryService CSG, EditableMesh and/or prebuilt meshes subject to permissions, server/client availability, and measured performance. A fallback may approximate visuals only when honestly indicated; physical holes and fit interfaces must remain correct for functional geometry.

## 7. Mechanics and simulation invariants

- **Geometric fit does not imply a particular joint.** Shafts/holes permit different relations; a gear fitted on its shaft is rigid by default.
- **Auto-Weld** defaults to structurally contacting compatible rigid geometry; Never and Force override contact policy. Moving joints exclude rigid welding across their interface.
- **Logical rigid groups** merge ordinary weld-connected geometry conceptually. Roblox constraints or union/collision proxies are emitted only when required by backend physics, not one per source primitive as a default.
- **Machine membership** is connected through rigid and mechanical graph links, not incidental collision.
- **Stabilized** means precise editable pose, including midair; **Active** means physically running. **Grounded** fixes a rigid group anywhere regardless of machine state.
- **Stabilize Here** preserves current physical pose; **Reset to Build Position** restores authored original configuration.
- **Structural edits** of active machines require stabilization; nonstructural control adjustments can be live.
- **Transmissions** are shaft-centric, permit multiple gears per shaft, support compound ratios and backdriving; net torque and constraint conflicts must be resolved by a single consistent solver strategy, not repeated velocity teleports.
- **Simulation source** is always an authoritative construction+mechanics definition, never reconstructed by reverse-engineering Instances.
- **Roblox network ownership** and server authority for active physics must be evaluated and enforced intentionally, not assumed to confer edit permissions.

## 8. Diagnostics, tests and performance

- Pure tests: stable ID duplication, integer unit round trips, deterministic geometry math, command validation/undo, graph connectivity, gear ratio propagation and feature lifetime.
- Roblox tests: rendered/collision drilled openings, nondestructive rebuilding, network request rejection, chunked replication and save/load.
- Visual tests: hover/selection, feature snap dots, gizmos, thin line arcs, grounded/moving coloring and server/client correction behavior.
- Performance baselines: hundreds of rigid source primitives in one machine, many discrete mechanical joints, moving vehicles, large source-document updates and save/load limits.
- Compile dirtiness at component/feature dependency level. Never recompile or resend entire machines for isolated local edits when a coherent partial update is sufficient.
- Profile before adopting Actors/Parallel Luau or aggressive native geometry caches; avoid hidden cross-Actor shared-state assumptions.

## 9. First milestone: one complete Block lifecycle

**This is the release gate for Architecture Slice 1:**

1. FORGE initializes the registered OpenWorks services/controllers in dependency order.
2. A client requests a Block and shows a responsive local translucent placement preview.
3. A typed, revisioned command arrives at the server over a configured FORGE endpoint.
4. The server validates and commits the Block to a construction document.
5. GeometryService compiles it to a Roblox visible/collidable representation.
6. The client receives acknowledgment/revision and authoritative placement.
7. The Block can be selected, moved, rotated, resized, deleted, undone and redone.
8. Storing and reloading the document restores the same IDs, dimensions and transforms.
9. A separate minimal machine-state test confirms Stabilized vs Active/grounded behavior without conflating authored state.
10. Diagnostic tests cover tampered commands, stale revisions and interrupted persistence.

Pass these before broadening the primitive catalog or implementing complex machining.

## 10. Deferred, not forgotten

- Exact UI layout and final input/keybind map; keep the established first-person workflow and thin technical visual language.
- Final physics constants and large-assembly performance limits, subject to calibrated Roblox tests.
- Specific backend implementation for Fillet/Chamfer and hard cases of large-scale Boolean geometry.
- Advanced mechanism implementations: springs, gear loops, bevels, universal/vector couplings, ropes/belts and fine torque/friction behavior.
- Harmonics equations, quartz pipes, propulsion, devices and computing, after core mechanics work.
- Multiplayer collaborative editing policies beyond initial ownership and server authority.
- Large terrain/world systems, planets, aviation and other long-term gameplay.

Deferred items have module ownership defined above; they are not permission to reintroduce a monolithic or Instance-authoritative architecture.

## 11. Architectural acceptance statement

**Locked:** FORGE-backed folder organization; source-document authority; service/controller ownership; shared pure engineering definitions; command-only mutation; independent machine state; adapter-based geometry/physics; staged validation; and the one-Block vertical slice.

**Not yet implemented:** This document specifies a plan. It does not modify or claim a working Roblox Studio place. Before code migration, choose the new Roblox 2.0 repository/branch and check the exact FORGE dependency version against this baseline. Existing Roblox and Godot repositories remain untouched by writing this file.

**Reference basis:** `ufrh/Ruckus` FORGE 3.2.0 loader, class API, lifecycle, dependency graph, and bootstrap paths inspected on 2026-11-21; prior OpenWorks standalone design and engineering foundation; the approved OpenWorks 2.0 rebuild decisions in conversation.