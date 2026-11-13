# UI V2 + shaft-centric mechanical systems integration

## Sources and rules

- **Destination:** `feature/ui-reorganization-v2` at `328a3281cdb339df33facdda704f0a60fb54830b`.
- **Source:** `feature/shaft-centric-gear-transmission` at `f34e29478928dd15d921d6cac32c164bf784b913`.
- **Result:** `integration/ui-v2-shaft-systems`, based on UI V2, not a replacement of its tools.
- Preserve UI V2's **three native tools**, contextual floating inspector, multi-selection, rack-and-pinion fallback, and current rack/guide geometry. The source branch's old 6-tool/legacy UI must **not** be used as the destination.
- Existing shared `ComponentBankService`, `ComponentBankPreview`, `FitOrigin`, `FitSolver`, `GearTransmission`, `BeltTransmission`, `PulleyLibrary`, gear and bore geometry already had mostly matching implementations in UI V2. **They were not fully connected to the active input and server dispatch.** This integration exposes them to players.

## Implemented integrations

| Area | Behavior in integrated source | Location |
|---|---|---|
| Component Bank | Build catalog shows saved components; search, delete (two clicks), register selected component, retrieve blueprint and repeatedly stamp; server validates/places geometry and reconstructs only internal relationships | `ConstructionController`, `ConstructionService`, `ComponentBankService` |
| Build + Edit | One native **Build** tool with **Place** / **Edit** subtools. Enter leaves placement for Edit. No competing native Edit tool | Existing UI V2 tool definitions + modified `ConstructionController` |
| Alignment origins | Set/reset component or primitive origin, choose cursor/face/edge/corner, preview contextual handle, snap to authored target origins and available surfaces, preserve origins through undo/plot save/component bank | `FitOrigin`, `FitSolver`, `SmartPlacement`, `ConstructionController`, `ConstructionService` |
| Gear/pulley mounts | Hubs attach to shafts only as validated rigid Welds; no independent rotating gear hub. Shaft bearings establish freedom of motion | `ConnectionCatalog`, `AssemblyController`, `SmartPlacement`, existing `MechanicalService` |
| Pulley belts | Ensure pulley templates, choose two pulleys with Mechanics > Connect > Belt, validate real shaft mounts, author/remove belt relationships | `ConstructionService`, `AssemblyController`, `ConnectionCatalog`, existing `PulleyLibrary` and `MechanicalService` |
| Gear/belt simulation | Native physics torque transfer through physical shaft-centric `GearTransmission` and `BeltTransmission`, cloned assembly physics; stop restores originals | `PhysicalSimulationService`, `UnifiedSimulationService` |
| Rack preservation | Registered assemblies containing a rack/guide use UI V2's existing `RackSimulationService` kinematic compatibility implementation | `UnifiedSimulationService` + unchanged `RackSimulationService` |
| Safety | A registered assembly containing both rack and friction belt is **rejected explicitly**, rather than simulating only half the transmission. Separate them into distinct named assemblies | `UnifiedSimulationService` |
| Contextual UI | Right-click a selected component to Save to component library; selected construction offers Set/Reset alignment origin | `ContextEditor` |

### Interaction notes

1. Equip Build > Edit and select an existing **grouped component**. Press **Shift+B** or right-click > **Save to component library**, enter a name, and confirm. Build > Place > **B** displays the catalog including **My Components**. Selecting a saved component starts its placement ghost. Click to place; repeat to stamp; **Enter** returns to Edit. Bank uses `OPENWORKS_ComponentBank_v1` per-player DataStore, separate from plot autosaving.
2. In Build > Edit, select a primitive/component and press **O**, then aim/click to set the alignment origin; **Q/E** switches snapping mode; **Shift+O** resets. These operations use server metadata history. Origins are not mechanical constraints and alignment alone never implies a Weld.
3. Create a gear or pulley, create a shaft, attach via the small central bore snap or Mechanics > Connect > Rigid. Both parts must fit physically; the hub is welded to the shaft. To rotate, attach the shaft to a housing with a **Bearing**.
4. Add two mounted pulleys and Mechanics > Connect > **Belt** to create a friction belt; both must be on distinct shafts. Belts can be removed via the existing relationship context UI, or the server action `RemoveBelt`.
5. Register the full mechanism as a named assembly. Use Assembly & Simulation > Simulation to test the transmission. Assemblies containing racks use the UI V2 compatible rack solver; no automatic mixing with native physical belts.

## Static validation

```powershell
python scripts/verify_source.py
git diff --check
```

On the integration commit, static source architecture contracts passed **270/270**. These checks do not compile Luau, run in Studio, perform DataStore calls, or assert native physics stability. Existing CI uses `stylua --verify --syntax luau src` as a Luau parser check; run it when the required CLI is installed.

## Studio acceptance — still required

- [ ] **Boot:** Rojo connects on port 34872; no startup `require`/API errors; exactly three native Tools.
- [ ] **Bank:** Build > Edit, select a grouped component, save it under a name, close/reopen catalog, search, select, place two independent copies, verify transforms and internal relationships; rejoin and confirm it persists.
- [ ] **Origin:** Set origin on primitive and grouped component, verify the visible cue, align two authored origins and a world surface, undo/redo, save plot and reload; confirm the origin is not welded.
- [ ] **Hub:** Fit gear onto shaft using cursor depth; select Rigid; verify a physical weld and the gear rotates with its shaft, not freely around it.
- [ ] **Pulley:** Fit two pulley hubs to separate shafts, create Belt from Mechanics > Connect, validate geometry and belt visual, attempt invalid duplicate, remove from relationship inspector.
- [ ] **Native simulation:** Ground a housing, register gear/shaft/bearing/crank assembly, start simulation, hold crank and check driven gears and belt, stop, verify the original exact geometry is restored.
- [ ] **Racks:** Build separate rack-and-pinion + grounded guide assembly, confirm existing Q/E backdrive and travel limits still function.
- [ ] **Mixed rejection:** Register a rack and belt in *one* named assembly; verify helpful rejection, with no partial simulation clones.
- [ ] **Persistence:** Save/reload a plot with belts, hubs, registered assembly, material finishes and custom origins; no corrupt load or duplicate relationships.
- [ ] **Regression:** `docs/QA_REGRESSION.md` UI V2 contextual selection, paint, freecam, resize, multi-hole fitting, undo, autosave, and stop/reset checks.

## Not included / limitations

- No Roblox Studio runtime or Luau compiler was available in this environment. The static checks alone **do not establish that the new GUI and physics work at runtime**.
- The shaft source branch's older standalone tool UI and replacement WorldVisuals were intentionally not imported; they conflict with the more recent UI V2 architecture.
- Rack and physical belt systems are not numerically coupled within the same assembly; the router rejects this combination rather than giving incorrect results.
- Source-only ZIP and Git bundle are supplied; this integration is **not pushed to GitHub**. Review and test locally before merging into `feature/ui-reorganization-v2` or pushing.
