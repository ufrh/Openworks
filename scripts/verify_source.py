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
    check("No mechanical relationship powered by hidden motor",
          "Enum.ActuatorType.None" in simulation
          and "HandCrank_PlayerTorque" in simulation)
    check("Manual input has distance and stale-packet limits",
          "INPUT_EXPIRES" in simulation and "playerRoot.Position-root.Position" in simulation)

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
