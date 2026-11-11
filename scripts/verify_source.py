#!/usr/bin/env python3
"""Static architecture invariants for OPENWORKS.

Run: python scripts/verify_source.py
This does NOT parse/compile Luau or run Roblox physics. Playtesting is
still required; it checks cross-file contracts and dangerous regressions.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
RESULTS: list[tuple[str, bool, str]] = []


def read(path: str) -> str:
    p = ROOT / path
    if not p.is_file():
        raise FileNotFoundError(f"Required source is missing: {path}")
    return p.read_text(encoding="utf-8")


def check(name: str, condition: bool, detail: str = "") -> None:
    RESULTS.append((name, bool(condition), detail))


def check_local_requires(parent: Path) -> None:
    # All explicit requires rooted at script.Parent:WaitForChild("Name")
    # must resolve to a current module in the same Rojo-mapped directory.
    for path in parent.glob("*.lua"):
        content = path.read_text(encoding="utf-8")
        for module in re.findall(
            r'script\.Parent:WaitForChild\(["\']([\w-]+)["\']\)',
            content,
        ):
            target = parent / f"{module}.lua"
            check(
                f"require {path.relative_to(ROOT)} -> {module}",
                target.is_file(),
                f"expected {target.relative_to(ROOT)}",
            )


def main() -> int:
    definitions = read("src/shared/Construction/ToolDefinitions.lua")
    tool_ids = re.findall(r'\{\s*Id\s*=\s*"([^"]+)"', definitions)
    check(
        "Native tool inventory and order",
        tool_ids == ["Build", "Edit", "Assembly", "Simulate", "Inspect", "Weld"],
        str(tool_ids),
    )

    rokit = read("rokit.toml")
    aftman = read("aftman.toml")
    for name in ("rojo", "stylua", "selene"):
        match = r'^' + name + r'\s*=\s*"([^"]+)"'
        versions = [
            re.search(match, doc, flags=re.MULTILINE)
            for doc in (rokit, aftman)
        ]
        check(
            f"{name}: identical toolchain pins",
            all(versions) and versions[0].group(1) == versions[1].group(1),
        )
    check("Single StyLua config", (ROOT / "stylua.toml").is_file()
          and not (ROOT / ".stylua.toml").exists())

    project = read("default.project.json")
    for path in (
        "src/shared", "src/client", "src/server",
        "src/forge-shared", "src/forge-server",
    ):
        check(f"Rojo source path {path}", (ROOT / path).is_dir() and path in project)

    for folder in (
        SRC / "client" / "Controllers",
        SRC / "server" / "Runtime",
        SRC / "shared" / "Construction",
    ):
        check_local_requires(folder)

    assembly = read("src/server/Runtime/AssemblyService.lua")
    service = read("src/server/Runtime/ConstructionService.lua")
    component = read("src/server/Runtime/ComponentService.lua")
    simulation = read("src/server/Runtime/SimulationService.lua")
    persistence = read("src/server/Runtime/PlotPersistence.lua")
    tool_ui = read("src/client/Controllers/AssemblyToolController.lua")
    ctx = read("src/client/Controllers/ContextKeybinds.lua")
    world = read("src/client/Controllers/WorldVisuals.lua")
    selection = read("src/client/Controllers/ConstructionController.lua")
    inspector = read("src/client/Controllers/RelationshipProperties.lua")
    crank = read("src/client/Controllers/HandCrankController.lua")
    client_entry = read("src/client/init.client.lua")

    check("Assembly only accepts explicit owned primitive ID lists",
          "payload.memberIds" in assembly
          and "self.D.findOwned(player,id)" in assembly
          and "function Service:Connected(" not in assembly)
    check("Assembly supports named create/update", all(
        s in assembly for s in ("function Service:Create(", "function Service:Update(",
                               "MAX_NAME=48", "MAX_MEMBERS=128")))
    check("Assembly server authorization",
          'hasEquippedTool(player,"Assembly")' in service
          and 'action=="CreateAssembly"' in service
          and 'action=="UpdateAssembly"' in service)
    check("Removed old automatic registration API",
          'action=="RegisterAssembly"' not in service
          and 'action=="AddAssemblyMember"' not in service)
    check("Components are selection groups, not implicit welds",
          'return "p:" .. tostring(model:GetAttribute("InstanceId"))' in simulation
          and "PrefabInternalPart" in simulation)
    check("Simulation builds from registered member IDs",
          'model:GetAttribute("AssemblyId")==assemblyId' in simulation
          and "if left~=right then" in simulation)
    check("No per-component completeness requirement",
          "An editor component has members outside this assembly" not in simulation)
    check("Passive relationships remain unpowered; only crank gets a drive",
          "Enum.ActuatorType.None" in simulation
          and 'Instance.new("AngularVelocity")' in simulation
          and 'drive.Name="HandCrank_ControlledRotation"' in simulation
          and "HandCrank_PlayerTorque" not in simulation)
    check("Controlled rotation targets the coupled physical shaft",
          'copies[coupledShaft:GetAttribute("InstanceId")]' in simulation
          and 'crank.Drive.AngularVelocity=crank.Axis*HandCrankMath.FixedAngularSpeed' in simulation
          and 'crank.Drive.Enabled=true' in simulation
          and 'crank.Drive.Enabled=false' in simulation
          and 'crank.Torque' not in simulation
          and 'VelocityGain' not in simulation)
    check("Held-LMB crank is fixed-speed, range-limited, torque-capped",
          "HandCrankMath.FixedAngularSpeed" in simulation
          and "self:StopCrank(session,id)" in simulation
          and "playerRoot.Position-root.Position" in simulation
          and "HandCrankMath.MaxTorque" in simulation
          and 'action="BeginCrank"' in crank
          and "GetMouseDelta" not in crank
          and "UserInputService.InputEnded" in crank
          and "self.Remote:FireServer(id,0,false,true)" in crank)
    check("Crank requires live held-input pulse and fails closed",
          "CRANK_HOLD_TIMEOUT = 0.5" in simulation
          and 'crank.LastInput=os.clock()' in simulation
          and "function Simulation:InputCrank(player,id,_desired,holding,release)" in simulation
          and "if release==true or holding~=true then" in simulation
          and "self.Remote:FireServer(self.ActiveId,0,true,false)" in crank
          and "UserInputService:IsMouseButtonPressed(" in crank)
    crank_math=read("src/shared/Construction/HandCrankMath.lua")
    mechanical=read("src/server/Runtime/MechanicalService.lua")
    mates=read("src/client/Controllers/MateChoicePanel.lua")
    check("Hand crank fitted size survives undo/load",
          "HandCrankMath.ApplySize(model,data.size)" in service
          and "HandCrankMath.ValidSize" in persistence
          and "HandCrankMath.ShaftSize(source,target)" in mechanical)
    check("Gear hub choice creates only physical hinge or weld",
          'local HUB_TYPES={"Rotation","Rigid"}' in mates
          and 'request.relationKind=="Rotation" then "Bearing" else "Weld"' in mechanical
          and 'kind=="Hub" then "Rotation"' in read("src/shared/Construction/SmartPlacement.lua"))
    gear_clearance=read("src/shared/Construction/BoreClearance.lua")
    smart_placement=read("src/shared/Construction/SmartPlacement.lua")
    preview=read("src/shared/Construction/PreviewFeedback.lua")
    layered=read("src/client/Controllers/LayeredEditingController.lua")
    check("Gear bore clearance uses circular physical opening metadata",
          'target:GetAttribute("BoreRadiusStuds")' in gear_clearance
          and 'type(target:GetAttribute("GearTeeth"))=="number"' in gear_clearance
          and 'localY=Vector3.yAxis,localZ=Vector3.zAxis' in gear_clearance)
    check("Gear hub mount concentric and genuinely engaged",
          'eccentricity>0.012' in smart_placement
          and 'return Bore.ShaftFits(shaft,gearBody)' in smart_placement
          and 'function Smart.HubPose(' in smart_placement)
    check("Build/Edit gear shaft fits validated by preview and server",
          'Smart.HubFits(movingModel,target)' in preview
          and 'Smart.HubFits(candidate,target)' in service
          and 'if mode=="Hub" then target' in mechanical)
    check("Manual L gear alignment chooses real Rotation or Rigid",
          'local isGear=type(align.Target:GetAttribute("GearTeeth"))=="number"' in layered
          and 'mateKind="Hub"' in layered
          and 'relationKind=choice' in layered
          and 'end,1,isGear)' in layered)
    check("Simulation uses gear center axis for physical hinge",
          'JointFrames.ForOpening(edge.target)' in simulation
          and 'local explicit = axisOverride(model)' in read("src/shared/Construction/AlignmentMath.lua")
          and 'model:SetAttribute("AxialAxis", "X")' in read("src/server/Runtime/GearLibrary.lua"))
    check("Clearance weld requires real drilled bore fit",
          'Bore.ShaftFits(shaft,hole)' in mechanical
          and 'string.find(name,"drilledblock",1,true)' in mechanical)
    layered=read("src/client/Controllers/LayeredEditingController.lua")
    check("Relationship picker uses clickable modal, never numeric choices",
          'Name="OPENWORKS_RelationshipPicker"' in mates
          and 'Modal=true' in mates
          and 'button.Activated:Connect' in mates
          and 'Enum.KeyCode.Escape' in mates
          and 'self:Choose((index-1)%4+1)' not in mates
          and 'BLOCKED_KEYS' in mates)
    check("Build/Edit plus manual L align all use same popup",
          'self:OpenMateChoice("Build")' in selection
          and 'self:OpenMateChoice("Edit")' in selection
          and 'parent.MateChoice:Show' in layered
          and 'action=if choice=="FreeFit" then "Align" else "CreateRelation"' in layered)
    check("Relationship modal cannot duplicate world clicks",
          'if self.PendingMateChoice or (self.Numeric and self.Numeric.Active) then return end' in selection
          and 'self.IgnoreClickUntil=os.clock()+0.22' in selection
          and 'self:RefreshPointer()' in selection)

    check("Metadata undo is in place",
          'kind="Metadata"' in service
          and "local function restoreMetadata" in service
          and 'if record.kind == "Metadata" then' in service)
    check("Assembly tool can directly undo and redo",
          'hasEquippedTool(player,"Assembly")' in service
          and "self:History(false)" in tool_ui
          and "self:History(true)" in tool_ui)
    check("Assembly metadata history does not recreate geometry",
          "commitMetadata(player,before,after)" in assembly
          and "commitBatch(player,before,after)" not in assembly)
    check("Component grouping/grounding uses metadata history",
          component.count("commitMetadata(player, before, after)") >= 3)

    save_writes = []
    for file in SRC.rglob("*.lua"):
        if "forge-" in file.as_posix():
            continue
        text = file.read_text(encoding="utf-8")
        if ":SetAsync(" in text:
            save_writes.append(file.relative_to(ROOT).as_posix())
    check("Exactly one DataStore write location",
          save_writes == ["src/server/Runtime/PlotPersistence.lua"],
          str(save_writes))
    check("Explicit SavePlot is the write gate",
          'if action=="SavePlot" or action=="LoadPlot"' in service
          and "self.Store:SetAsync(" in persistence
          and 'ManualSaveOnly = true' in read("src/shared/Construction/BuildConfig.lua"))
    check("Both loading and saving clear Busy after failure",
          "pcall(self.Apply,self,player,target)" in persistence
          and "pcall(self.Encode,self,player)" in persistence
          and "self.Busy[player]=nil" in persistence)
    check("Retired assembly number counter is not accessed",
          "assemblies.NextNumber" not in persistence)

    check("Single local 3D assembly-preview owner",
          'Name="OPENWORKS_LocalAssemblyPreview"' in tool_ui
          and 'make("Folder",workspace,' in tool_ui)
    check("Selection and inspector visuals are client Workspace-owned",
          'Name="OPENWORKS_LocalSelectionVisuals"' in selection
          and 'Name="OPENWORKS_LocalInspectorSelection"' in inspector)
    check("World mechanical guides use adornments, not helper Parts",
          'Instance.new("Part")' not in world
          and "CylinderHandleAdornment" in world
          and "SphereHandleAdornment" in world)
    check("Highlight budget reserves purple preview",
          "MAX_HIGHLIGHTS=96" in world
          and "Color3.fromRGB(179,115,255)" in tool_ui)
    check("Assembly preview available before P",
          'mode=="Simulate"' in tool_ui
          and "self:OwnedAssembly(chosen)" in tool_ui)
    check("Manual crank uses the same shared range as Simulate",
          "Grid.MaxDistance" in crank and "Grid.MaxDistance" in tool_ui)
    check("Client entry starts Assembly controller",
          "AssemblyToolController.new(tools)" in client_entry
          and "assemblyToolController:Start()" in client_entry)
    check("Current Assembly keybinds (no retired Ctrl+G)",
          'elseif tool=="Assembly" then' in ctx
          and "Register whole connected assembly" not in ctx)
    check("Current docs and regressions documented",
          (ROOT / "docs/ARCHITECTURE.md").is_file()
          and (ROOT / "docs/QA_REGRESSION.md").is_file()
          and (ROOT / "docs/ARCHIVED_IMPLEMENTATION_LOG.md").is_file())

    failed = [(name, detail) for name, ok, detail in RESULTS if not ok]
    for name, ok, detail in RESULTS:
        print(("[ OK ] " if ok else "[FAIL] ") + name
              + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nOPENWORKS static contracts: {len(RESULTS)-len(failed)}/{len(RESULTS)} passed")
    if failed:
        print("This is a static architecture check, NOT a Studio runtime test.")
        return 1
    print("Luau compile, network behavior, physics and Studio GUI still require testing.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[FAIL] Static source verification could not complete: {exc}",
              file=sys.stderr)
        sys.exit(2)
