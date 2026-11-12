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
        tool_ids == ["Build", "Mechanics", "AssemblySimulation"],
        str(tool_ids),
    )

    subtool_definitions = read("src/shared/Construction/SubtoolDefinitions.lua")
    native_tool_controller = read("src/client/Controllers/ToolController.lua")
    check(
        "UI v2 exactly eight subtools across three primary tools",
        all(name in subtool_definitions for name in (
            'Default="Place"', 'Default="Connect"', 'Default="AssemblyEditor"',
            'Id="Place"', 'Id="Edit"', 'Id="Resize"', 'Id="Paint"',
            'Id="Connect"', 'Id="Configure"',
            'Id="AssemblyEditor"', 'Id="Simulation"',
        ))
        and len(re.findall(r'\{Id="(?:Place|Edit|Resize|Paint|Connect|Configure|AssemblyEditor|Simulation)"',
                           subtool_definitions)) == 8,
    )
    check(
        "UI v2 subtool state and shortcut guards are active",
        'SubtoolChanged' in native_tool_controller
        and 'SetSubtool' in native_tool_controller
        and 'WasConsumed' in native_tool_controller
        and 'SetShortcutGuard' in read("src/client/init.client.lua"),
    )
    check(
        "UI v2 server native tool access migrated",
        all(t in read("src/server/Runtime/ConstructionService.lua") for t in (
            'hasEquippedTool(player,"Build")',
            'hasEquippedTool(player,"Mechanics")',
            'hasEquippedTool(player,"AssemblySimulation")',
        ))
        and 'hasEquippedTool(player,"Weld")' not in read("src/server/Runtime/ConstructionService.lua")
        and 'hasEquippedTool(player,"Simulate")' not in read("src/server/Runtime/ConstructionService.lua"),
    )

    explorer_data = read("src/client/Controllers/ExplorerData.lua")
    unified_panel = read("src/client/Controllers/UnifiedExplorer.lua")
    context_actions = read("src/client/Controllers/ContextActionRegistry.lua")
    client_entry = read("src/client/init.client.lua")
    construction_ui = read("src/client/Controllers/ConstructionController.lua")
    mechanical_ui = read("src/client/Controllers/AssemblyController.lua")
    assembly_ui = read("src/client/Controllers/AssemblyToolController.lua")
    camera_ui = read("src/client/Controllers/CameraController.lua")
    check("UI v2 Phase 3 has a single docked Explorer/Properties owner",
          'UnifiedExplorer.new(tools,' in client_entry
          and 'unifiedExplorer:Start()' in client_entry
          and 'Name="OPENWORKS_UnifiedExplorerProperties"' in unified_panel
          and 'function Panel:RenderTree()' in unified_panel
          and 'function Panel:RenderProperties()' in unified_panel)
    check("Explorer reflects actual named assemblies and partial components",
          'model:GetAttribute("AssemblyId")' in explorer_data
          and 'model:GetAttribute("ComponentId")' in explorer_data
          and 'group.components[cid]' in explorer_data
          and 'relation:GetAttribute("SourceId")' in explorer_data
          and 'model:GetAttribute("OwnerUserId")==player.UserId' in explorer_data)
    check("Partial component entries cannot issue whole-component destructive actions",
          'comp.partialComponent=#comp.members<comp.totalMembers' in explorer_data
          and 'and not node.partialComponent' in context_actions
          and 'if node.partialComponent then' in unified_panel
          and 'self.Build:SetSelection(nil)' in unified_panel
          and 'whole-component:' in unified_panel)
    check("Explorer refreshes replicated mechanical and appearance properties",
          all(token in explorer_data for token in (
              'tostring(m:GetAttribute("PaintFinish") or "")',
              'tostring(m:GetAttribute("ConstructionMaterial") or "")',
              'tostring(m:GetAttribute("Grounded") or "")',
              'tostring(relation:GetAttribute("LowerLimit") or "")',
              'tostring(relation:GetAttribute("MotorEnabled") or "")',
              'tostring(relation:GetAttribute("Stiffness") or "")',
          ))
          and 'not UIS:GetFocusedTextBox()' in unified_panel)

    check("Unified selection synchronizes World and Explorer, including simulation",
          'function Panel:SelectWorldAtCenter()' in unified_panel
          and 'function Panel:OnConstructionSelection()' in unified_panel
          and 'self.UnifiedExplorer:OnConstructionSelection()' in construction_ui
          and 'self.UnifiedExplorer:SelectWorldAtCenter()' in mechanical_ui
          and 'self.UnifiedExplorer:NodeForModel(model)' in assembly_ui
          and 'Simulation_' in unified_panel)
    check("Inline Properties reuse validated mechanical and paint APIs",
          all(key in unified_panel for key in (
              'action="SetPaint"', 'action="SetMaterial"',
              'action="TuneSpring"', 'action="AdjustJoint"',
              'action="TuneBearingMotor"', 'action="UpdateAssembly"',
              'action="SetGrounded"', 'action="RemoveRelation"',
          )))
    check("Context actions are filtered by equipped tool and simulation state",
          'function Actions.List(node,tools,simulating,assemblyStage,runningAssemblyId)' in context_actions
          and 'function Panel:OpenMenu(node,position)' in unified_panel
          and 'function Panel:RunAction(action,node)' in unified_panel
          and 'if not allowed then' in unified_panel
          and 'OPENWORKS_ExplorerOpen' in native_tool_controller)
    check("Explorer pointer focus blocks unintended native world actions",
          'OPENWORKS_ExplorerOpen' in camera_ui
          and 'OPENWORKS_ExplorerOpen' in construction_ui
          and 'OPENWORKS_ExplorerOpen' in mechanical_ui
          and 'OPENWORKS_ExplorerOpen' in assembly_ui
          and 'and player:GetAttribute("OPENWORKS_ExplorerOpen")~=true' in native_tool_controller)
    check("Legacy instructional keybind HUD is not started in Phase 3",
          'contextKeybinds:Start()' not in client_entry
          and 'self.StatusFrame.Visible=self.UnifiedExplorer==nil' in construction_ui
          and 'self.Panel.Visible=self.Mode=="Assembly" and self.UnifiedExplorer==nil' in assembly_ui
          and 'self.Gui.Enabled = self.Active and self.UnifiedExplorer==nil' in mechanical_ui)

    connection_catalog = read("src/client/Controllers/ConnectionCatalog.lua")
    mechanics_connect = read("src/client/Controllers/AssemblyController.lua")
    build_connect = read("src/client/Controllers/ConstructionController.lua")
    mechanic_authority = read("src/server/Runtime/ConstructionService.lua")
    check("UI v2 Phase 4 owns one typed relationship choice catalog",
          'function Catalog.Fit(kind)' in connection_catalog
          and 'function Catalog.Pair(first,second)' in connection_catalog
          and 'function Catalog.Roles(first,second)' in connection_catalog
          and all(('id="'+kind+'"') in connection_catalog or
                  ('add("'+kind+'")') in connection_catalog for kind in (
                     'Cylindrical','Slider','Bearing','FreeFit','Weld',
                     'Spring','Bolt','CrankCoupling','Rotation','Rigid'))
          and 'if not hub then add("Weld") end' in connection_catalog)
    check("Build auto fit and Mechanics pairs use the SAME contextual picker",
          'self.UnifiedExplorer:ChooseFit(' in build_connect
          and 'function Panel:ChooseFit(kind,callback,count)' in unified_panel
          and 'function Panel:ChoosePair(first,second,callback)' in unified_panel
          and 'return self:ChooseConnection(options,callback' in unified_panel
          and 'self.UnifiedExplorer:ChoosePair(first,second' in mechanics_connect)
    check("Connect pair controls share validated requests and endpoint feedback",
          all(token in mechanics_connect for token in (
              'function Controller:StartConnect(seed)',
              'function Controller:PickConnectPart(part)',
              'function Controller:CommitConnect(kind,first,second)',
              'self.Feedback:FlashSuccess({first,second})',
              'self.ConnectInvalid=true',
              'action="SmartMate",mateKind="Bore",relationKind="FreeFit"',
              'action="SmartMate",mateKind="Hub",relationKind=kind',
              'action="CreateSpring"',
              'action="CoupleHandCrank"',
              'action=if kind=="Weld" then "CreateWeld" else "CreateBolt"',
          ))
          and 'self.Mechanics:PickConnectPart(node.model)' in unified_panel)
    check("Mechanics does not reintroduce F/H/Shift+J standalone connect modes",
          'if key==Enum.KeyCode.F' not in mechanics_connect
          and 'if key==Enum.KeyCode.H' not in mechanics_connect
          and 'self:StartPair("Spring")' not in mechanics_connect
          and 'self:ConnectClick()' in mechanics_connect
          and 'self:StartConnect()' in mechanics_connect)
    check("Mechanics SmartMate authorization narrowly allows only bore fit and hub",
          'local approved=(mode=="Bore" and kind=="FreeFit")' in mechanic_authority
          and '(mode=="Hub" and (kind=="Rotation" or kind=="Rigid"))' in mechanic_authority
          and 'not approved or not hasEquippedTool(player,"Mechanics")' in mechanic_authority
          and 'mechanical:SmartMate(player,payload,false)' in mechanic_authority)

    assembly_tool_v2 = read("src/client/Controllers/AssemblyToolController.lua")
    simulate_ui_v2 = read("src/client/Controllers/AssemblyController.lua")
    explorer_v2 = read("src/client/Controllers/UnifiedExplorer.lua")
    crank_ui_v2 = read("src/client/Controllers/HandCrankController.lua")
    rack_ui_v2 = read("src/client/Controllers/RackControlController.lua")
    motor_ui_v2 = read("src/client/Controllers/MotorControlController.lua")
    context_v2 = read("src/client/Controllers/ContextActionRegistry.lua")
    check("UI v2 Phase 5 drafts are usable without an inspected object",
          'function Panel:RenderAssemblyDraft(node)' in explorer_v2
          and 'function Panel:ApplyDraftName()' in explorer_v2
          and 'function Panel:FocusAssemblyName()' in explorer_v2
          and 'self:RenderAssemblyDraft(node)' in explorer_v2
          and 'self:Value("Selection","None")' in explorer_v2
          and 'self:OnAssemblyDraftChanged()' in assembly_tool_v2
          and 'self.NewAssemblyButton.Visible=editing' in explorer_v2)
    check("UI v2 Phase 5 assembly names and exact members commit through original service",
          'draft.Name=name' in explorer_v2
          and 'self.UnifiedExplorer:ApplyDraftName()' in assembly_tool_v2
          and 'action=if self.EditingId then "UpdateAssembly" else "CreateAssembly"' in assembly_tool_v2
          and 'memberIds=ids' in assembly_tool_v2
          and 'self:ToggleMember(model)' in assembly_tool_v2
          and 'function Tool:ToggleMember(model,forceSingle)' in assembly_tool_v2)
    check("UI v2 Phase 5 simulation start stop share a registered-assembly lifecycle",
          'function Controller:StartRegisteredAssembly(seed)' in simulate_ui_v2
          and 'function Controller:StopRegisteredAssembly()' in simulate_ui_v2
          and 'self:StartRegisteredAssembly(seed or self:Pick())' in simulate_ui_v2
          and 'self.Mechanics:StartRegisteredAssembly(seed)' in explorer_v2
          and 'self.Mechanics:StopRegisteredAssembly()' in explorer_v2
          and 'grounded=false' in simulate_ui_v2)
    check("UI v2 Phase 5 run pause reset telemetry are unified in Properties",
          'function Panel:RenderSimulationControls(node)' in explorer_v2
          and 'function Panel:RunSimulationAction(action,node)' in explorer_v2
          and 'action="GetMechanismInfo",seedId=id' in explorer_v2
          and '"PauseSimulation"' in explorer_v2
          and '"ResetSimulation"' in explorer_v2
          and 'self.UnifiedExplorer:RunSimulationAction("pause"' in simulate_ui_v2
          and 'self.UnifiedExplorer:RunSimulationAction("reset"' in simulate_ui_v2
          and 'self.UnifiedExplorer:RunSimulationAction("telemetry"' in simulate_ui_v2)
    check("UI v2 Phase 5 actuator holds release on Explorer focus",
          all('OPENWORKS_ExplorerOpen' in controller for controller in (
              crank_ui_v2,rack_ui_v2,motor_ui_v2))
          and 'self:Release()' in crank_ui_v2
          and 'self:Release()' in rack_ui_v2
          and 'self:Release()' in motor_ui_v2)
    check("UI v2 Phase 5 editing blocked during simulation while Stop remains available",
          'and id=="AssemblyEditor"' in native_tool_controller
          and 'OPENWORKS_Simulating' in native_tool_controller
          and 'OPENWORKS_Simulating' in assembly_tool_v2
          and 'if action~="stop"' in explorer_v2
          and 'elseif simulation and simulation:IsRunning(player) then' in
            read("src/server/Runtime/ConstructionService.lua")
          and 'node.id==runningAssemblyId' in context_v2)

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

    camera=read("src/client/Controllers/CameraController.lua")
    plots_service=read("src/server/Runtime/PlotService.lua")
    check("Default freecam retains native Scriptable camera on respawn",
          'player.CameraMode=Enum.CameraMode.Classic' in camera
          and 'cam.CameraType=Enum.CameraType.Scriptable' in camera
          and 'Enum.RenderPriority.Camera.Value+1' in camera
          and 'player.CharacterAdded:Connect(function()' in camera
          and 'Enum.CameraMode.LockFirstPerson' not in camera)
    check("Mouse movement always looks around with responsive smoothed aiming",
          'UIS:GetMouseDelta()' in camera
          and 'self.TargetYaw-=delta.X*LOOK_SENSITIVITY' in camera
          and 'self.TargetPitch=math.clamp(' in camera
          and 'self.Yaw+=shortestAngle(self.Yaw,self.TargetYaw)*turn' in camera
          and 'self.Pitch+=(self.TargetPitch-self.Pitch)*turn' in camera
          and 'self.Rotating=true' not in camera
          and 'self.Panning=true' not in camera)
    check("Mouse stays center-locked except for UI modals",
          'UIS.MouseBehavior=Enum.MouseBehavior.LockCenter' in camera
          and 'UIS.MouseBehavior=Enum.MouseBehavior.Default' in camera
          and 'OPENWORKS_CursorUIOpen' in camera
          and 'player:SetAttribute("OPENWORKS_CursorUIOpen",open)' in
              read("src/client/Controllers/ConstructionController.lua"))
    aiming=read("src/client/Controllers/CameraAimRay.lua")
    construction_ui=read("src/client/Controllers/ConstructionController.lua")
    assembly_ui=read("src/client/Controllers/AssemblyController.lua")
    assembly_tool=read("src/client/Controllers/AssemblyToolController.lua")
    crank_ui=read("src/client/Controllers/HandCrankController.lua")
    rack_ui=read("src/client/Controllers/RackControlController.lua")
    check("Build/Edit/Assembly/Crank/Rack selection always uses center ray",
          'camera:ViewportPointToRay(center.X,center.Y)' in aiming
          and 'ScreenPointToRay' not in aiming
          and all('CameraAimRay.Ray(camera)' in doc for doc in (
              construction_ui,assembly_ui,assembly_tool,crank_ui,rack_ui)))
    check("Freecam smooths movement, braking and FOV without spring drift",
          'local ACCEL_RESPONSE=15' in camera
          and 'local BRAKE_RESPONSE=27' in camera
          and 'local LOOK_RESPONSE=26' in camera
          and 'local ZOOM_RESPONSE=17' in camera
          and '1-math.exp(-rate*dt)' in camera
          and 'self.Velocity=self.Velocity:Lerp(desired,response(rate,step))' in camera
          and 'camera.FieldOfView=self.CurrentFov' in camera
          and 'self.CurrentFov+=(self.TargetFov-self.CurrentFov)' in camera
          and 'if desired.Magnitude==0 and self.Velocity.Magnitude<0.04 then' in camera)
    check("Freecam pauses cleanly in modals and stays inside plot limits",
          'if inputBlocked then' in camera
          and 'self.Velocity=Vector3.zero' in camera
          and 'self.TargetYaw=self.Yaw' in camera
          and 'self.TargetPitch=self.Pitch' in camera
          and 'local clamped=clampToPlot(proposed)' in camera
          and 'if math.abs(clamped.X-proposed.X)>0.00001' in camera
          and 'self.TargetYaw=self.Yaw+shortestAngle(self.Yaw,self.TargetYaw)' in camera
          and 'OPENWORKS_CameraSpawnReady' not in camera)
    check("Character remains invisible, anchored and immobile with native tools",
          'root.Anchored=true' in plots_service
          and 'humanoid.WalkSpeed=0' in plots_service
          and 'humanoid.JumpPower=0' in plots_service
          and 'descendant.Transparency=1' in plots_service
          and 'FindFirstAncestorOfClass("Tool")' in plots_service)
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

    check("Construction and simulated crank range use owned plot, not frozen head",
          'return plots~=nil and plots:Contains(player,position)' in service
          and 'not self.D.nearPlayer(player,crank.Root.Position)' in simulation
          and 'not self.D.nearPlayer(owner,root.Position)' in simulation)
    check("Simulation starts ungrounded by default but honors authored supports",
          'Grounded = payload.grounded == true' in simulation
          and 'if member:GetAttribute("Grounded") == true then' in simulation
          and 'if not hasExplicitGround and session.Grounded then' in simulation
          and 'action="StartSimulation",seedId=id,grounded=false' in read("src/client/Controllers/AssemblyController.lua")
          and 'Shift+P free' not in read("src/client/Controllers/AssemblyController.lua"))
    check("Assembly only accepts explicit owned primitive ID lists",
          "payload.memberIds" in assembly
          and "self.D.findOwned(player,id)" in assembly
          and "function Service:Connected(" not in assembly)
    check("Assembly supports named create/update", all(
        s in assembly for s in ("function Service:Create(", "function Service:Update(",
                               "MAX_NAME=48", "MAX_MEMBERS=128")))
    assembly_tool=read("src/client/Controllers/AssemblyToolController.lua")
    check("Cardinal X/Y/Z nudge is scoped to owned registered members",
          'local function verticalMove(player,payload)' in service
          and 'selected=components:Members(player,id)' in service
          and 'selected=assemblies:Members(player,id)' in service
          and 'local model=findOwned(player,id)' in service
          and 'if axis~="X" and axis~="Y" and axis~="Z" then' in service
          and 'local delta=(if axis=="X" then Vector3.xAxis' in service
          and 'if model and not model:GetAttribute("ComponentId") then' in service)
    check("Vertical move is one validated atomic undoable transaction",
          'local ok,reason=validState(player,entry,nextState)' in service
          and 'intersectsConstructed(model,ignored)' in service
          and 'applyState(model,before[i])' in service
          and 'commitBatch(player,before,after)' in service
          and 'if (payload.scope=="Assembly" and not hasEquippedTool(player,"AssemblySimulation"))' in service)
    check("Alt+Up/Down always moves world Y and Left/Right uses camera right",
          'function Controller:VerticalNudge(key)' in selection
          and 'if key==Enum.KeyCode.Up or key==Enum.KeyCode.Down then' in selection
          and 'axis,direction="Y",(if key==Enum.KeyCode.Up then 1 else -1)' in selection
          and 'local v=camera.CFrame.RightVector' in selection
          and 'if key==Enum.KeyCode.Left then direction=-direction end' in selection
          and 'self:VerticalNudge(key)' in selection
          and 'if fine then 0.05 else 0.25' in service)
    check("Assembly arrows share world Y and camera-relative horizontal motion",
          'function Tool:VerticalNudge(key)' in assembly_tool
          and 'if key==Enum.KeyCode.Up or key==Enum.KeyCode.Down then' in assembly_tool
          and 'axis,direction="Y",(if key==Enum.KeyCode.Up then 1 else -1)' in assembly_tool
          and 'local v=camera.CFrame.RightVector' in assembly_tool
          and 'self:VerticalNudge(key)' in assembly_tool
          and 'axis=axis,direction=direction,fine=fine' in assembly_tool
          and 'action="VerticalMove",scope="Assembly"' in assembly_tool
          and 'Enum.KeyCode.PageUp' not in assembly_tool)
    paint=read("src/shared/Construction/PaintCatalog.lua")
    materials=read("src/shared/Construction/MaterialCatalog.lua")
    material_ui=read("src/client/Controllers/MaterialPickerController.lua")
    assembly_client=read("src/client/Controllers/AssemblyController.lua")
    mechanical=read("src/server/Runtime/MechanicalService.lua")
    check("No free-floating joint editor or arbitrary-joint server actions",
          'AngularJointController' not in assembly_client
          and 'CreateAxisJoint' not in service
          and 'EditAxisJoint' not in service
          and 'TuneAxisMotor' not in service
          and 'function Mechanical:CreateAxisJoint(' not in mechanical
          and 'JointFrameMath' not in mechanical
          and 'kind=="AxisHinge"' not in simulation)
    motor_client=read("src/client/Controllers/MotorControlController.lua")
    properties=read("src/client/Controllers/RelationshipProperties.lua")
    check("Key-driven motor requires a real shaft-in-hole Bearing",
          'function Mechanical:TuneBearingMotor(' in mechanical
          and 'joint:GetAttribute("Kind")~="Bearing"' in mechanical
          and 'constraint:IsA("HingeConstraint") and spec.motorEnabled==true' in mechanical
          and 'and edge.kind=="Bearing"' in simulation
          and 'and edge.relation:GetAttribute("MotorEnabled")==true' in simulation
          and 'joint:GetAttribute("Kind")=="Bearing"' in motor_client
          and 'joint:GetAttribute("MotorEnabled")==true' in motor_client
          and 'action="TuneBearingMotor"' in properties
          and 'action=="TuneBearingMotor"' in service)
    check("Bearing motor is saved, undoable, live-editable and fail-safe",
          'motorEnabled=relation:GetAttribute("MotorEnabled")==true' in mechanical
          and 'relation:SetAttribute("MotorEnabled",spec.motorEnabled==true)' in mechanical
          and 'RelationId=edge.relation:GetAttribute("RelationId")' in simulation
          and 'if motor.RelationId==id then found=motor break end' in simulation
          and 'motor.Constraint.AngularVelocity=0' in simulation
          and 'os.clock()-motor.LastInput>0.45' in simulation
          and 'propertyAction and simulation:IsRunning(player)' in service)
    check("Shaft-hole bearing still drives native hinge physics",
          'kind == "Bearing"' in mechanical
          and 'Instance.new("HingeConstraint")' in mechanical
          and 'edge.kind == "Bearing"' in simulation
          and 'JointFrames.ForOpening(edge.target)' in simulation)
    check("Retired joints skipped in old plot saves",
          'skipped+=1' in persistence
          and 'retired arbitrary-axis joint(s)' in persistence)
    check("Motor settings are edited only on physical bearings",
          'function Properties:ApplyMotor()' in
              read("src/client/Controllers/RelationshipProperties.lua")
          and 'action="TuneBearingMotor"' in
              read("src/client/Controllers/RelationshipProperties.lua")
          and 'motorEnabled=self.MotorOn' in
              read("src/client/Controllers/RelationshipProperties.lua")
          and 'function Mechanical:TuneBearingMotor(' in mechanical
          and 'MotorEnabled' in mechanical
          and 'kind=="Bearing"' in simulation
          and 'function Simulation:InputMotor(player,key,holding)' in simulation)
    check("Vehicle paint has custom HEX, real matte/metallic/chrome finishes",
          'function Paint.NormalizeHex(value:any)' in paint
          and 'Factory={Name="Original material"' in paint
          and 'Matte={Name="Matte"' in paint
          and 'Gloss={Name="High Gloss"' in paint
          and 'Chrome={Name="Chrome"' in paint
          and 'Pearl={Name="Pearlescent"' in paint
          and 'part.Reflectance=finish.Reflectance' in paint
          and 'if paintColor then part.Color=paintColor end' in paint)
    check("Painting is server-authorized, supports components and is undoable",
          'action=="SetPaint"' in service
          and 'local function setPaint(player,payload)' in service
          and 'PaintCatalog.IsValidFinish(payload.paintFinish)' in service
          and 'PaintCatalog.NormalizeHex(payload.paintColorHex)' in service
          and 'members=components:Members(player,id)' in service
          and 'commitBatch(player,before,after)' in service
          and 'action="SetPaint"' in material_ui)
    check("Paint and engineering materials have separate physics and appearance",
          'MaterialCatalog.Apply(model,if MaterialCatalog.IsValid' in service
          and 'PaintCatalog.Apply(model,if PaintCatalog.IsValidFinish' in service
          and 'CustomPhysicalProperties=PhysicalProperties.new(' in materials
          and 'part.Material=finish.Material' in paint
          and 'part.CustomPhysicalProperties=' not in paint)
    check("Paint stays on copies, transforms, history, and manual plots",
          'paintFinish=model:GetAttribute("PaintFinish") or "Factory"' in service
          and 'paintColorHex=model:GetAttribute("PaintColorHex")' in service
          and 'then self.Selected:GetAttribute("PaintFinish")' in selection
          and 'paintFinish=record.paintFinish or "Factory"' in persistence
          and 'paintHex=snap.paintColorHex' in persistence
          and 'result.steps = table.clone(data.steps)' in component)
    check("Paint studio supports custom hexadecimal, swatches and factory reset",
          'Name="OPENWORKS_Materials"' in material_ui
          and 'function Picker:ApplyPaint(reset)' in material_ui
          and 'self.HexBox.Text="#"..self.ColorHex' in material_ui
          and 'Paint.Palette()' in material_ui
          and 'action="SetMaterial"' in material_ui
          and 'paintFinish=finish' in material_ui
          and 'self:ApplyPaint(true)' in material_ui)
    check("Assembly server authorization",
          'hasEquippedTool(player,"AssemblySimulation")' in service
          and 'action=="CreateAssembly"' in service
          and 'action=="UpdateAssembly"' in service)
    check("Removed old automatic registration API",
          'action=="RegisterAssembly"' not in service
          and 'action=="AddAssemblyMember"' not in service)
    check("Component grouping and ungrouping receive metadata history callback",
          'self.D.commitMetadata(player, before, after)' in component
          and 'commitMetadata = commitMetadata,' in service[
              service.index('components = ComponentService.new({'):
              service.index('alignmentService = AlignmentService.new({')])
    feedback = read("src/client/Controllers/VisualFeedback.lua")
    ghost_edges = read("src/client/Controllers/GhostWireframe.lua")
    alignment_editor = read("src/client/Controllers/AssemblyController.lua")
    check("UI v2 uses one oriented twelve-edge selection renderer",
          'for i=1,12 do' in feedback
          and 'LineHandleAdornment' in feedback
          and 'self.Feedback:Set("selection","component",ordered,"selection",true)' in selection
          and 'if self.GroupAnchor then table.insert(ordered,self.GroupAnchor) end' in selection
          and 'self.Feedback:Set("selection",tostring(i),{model},"selection",false)' in selection
          and 'Instance.new("Highlight")' not in feedback)
    check("UI v2 assembly boxes use whole-selection and member semantics",
          'self.Feedback:Set("assembly",id,{byId[id]},"assembly",false)' in tool_ui
          and 'self.Feedback:Set("assembly","outer",ordered,"assembly",true)' in tool_ui
          and 'Name="AssemblyPrimitive",Adornee=model' not in tool_ui)
    check("UI v2 orange/red/green connection feedback is server-confirmed",
          'self.Feedback:Set("connection","first",{first},"pending",false)' in alignment_editor
          and 'if valid then "pending" else "invalid"' in alignment_editor
          and 'if self:Request(request) then' in alignment_editor
          and 'self.Feedback:FlashSuccess({first,second})' in alignment_editor
          and 'self.Feedback:FlashSuccess({self.WeldFirst,picked})' in alignment_editor)
    check("UI v2 automatic smart fits use orange pending and real committed models",
          'self.Feedback:SetGhostPending(mechanical)' in selection
          and 'if mechanical then "pending" else "snap"' in selection
          and 'self.Feedback:FlashSuccess(participants)' in selection
          and 'and model:GetAttribute("InstanceId")==newId' in selection
          and 'if ok then' in selection)
    check("UI v2 geometry ghost edges are client-only with CSG fallback",
          'Instance.new("LineHandleAdornment")' in ghost_edges
          and 'MAX_EDGES=384' in ghost_edges
          and 'part:IsA("Part") and part.Shape==Enum.PartType.Cylinder' in ghost_edges
          and 'self.Feedback:SetGhost(ghost,true)' in selection)
    check("Components are selection groups, not implicit welds",
          'return "p:" .. tostring(model:GetAttribute("InstanceId"))' in simulation
          and "PrefabInternalPart" in simulation)
    check("Simulation builds from registered member IDs",
          'model:GetAttribute("AssemblyId")==assemblyId' in simulation
          and "if left~=right then" in simulation)
    check("No per-component completeness requirement",
          "An editor component has members outside this assembly" not in simulation)
    gears=read("src/server/Runtime/GearKinematics.lua")
    gear_math=read("src/shared/Construction/GearMath.lua")
    check("Kinematic gears no longer receive native bearings or prefab joints",
          'session.Gears=GearKinematics.new(graph,copies)' in simulation
          and 'not session.Gears:IsKinematic(id)' in simulation
          and 'session.Gears:IsKinematic(edge.source:GetAttribute("InstanceId"))' in simulation
          and 'session.Gears:IsKinematic(edge.target:GetAttribute("InstanceId"))' in simulation
          and 'part.Anchored=true' in simulation
          and 'part.CanCollide=false' in simulation
          and 'motor.Name="AuthoredGearRatioDrive"' not in simulation)
    check("Automatic gear meshes are independent of K authoring",
          'GearMath.AutoMeshable(left.Model,right.Model)' in gears
          and 'if left.Group==right.Group then continue end' in gears
          and 'function GearMath.AutoMeshable(' in gear_math
          and 'if edge.kind~="Gear" then continue end' not in gears
          and 'function Controller:ToggleGearMode()' in read(
              "src/client/Controllers/AssemblyController.lua")
          and 'Gears auto-mesh in simulation' in read(
              "src/client/Controllers/AssemblyController.lua"))
    check("Runtime gear engagement matches real face overlap, not editor center-plane limit",
          'function GearMath.AutoMeshStatus(' in gear_math
          and 'MESH_PITCH_TOLERANCE=0.09' in gear_math
          and 'math.min(a.PrimaryPart.Size.X,b.PrimaryPart.Size.X)*0.07' in gear_math
          and 'if axial>=faceLimit then' in gear_math
          and 'if not GearMath.Meshable(a,b)' not in gear_math)
    check("Third gear diagnostics expose failed pitch or axial overlap",
          'self.Unmeshed={}' in gears
          and 'GearMath.AutoMeshStatus(' in gears
          and 'function Kinematics:Explain(id)' in gears
          and 'session.Gears.Unmeshed[1].Reason' in simulation
          and 'session.Gears:Explain(id)' in simulation)
    check("New unregistered gear cannot silently vanish from simulation",
          'local function countNearbyUnregisteredGears(' in simulation
          and 'countNearbyUnregisteredGears(' in simulation
          and 'session.UnregisteredGears' in simulation
          and 'NOT in assembly' in simulation)
    check("Obsolete explicit K edge does not force registered assembly expansion",
          'or kind == "Fixed" or kind == "Gear"' not in simulation
          and 'or kind == "Cylindrical" or kind == "Fixed"' in simulation
          and 'if edge.kind == "Gear" then' in simulation)
    check("Kinematic gear train respects tooth ratios and rigid grouping",
          'edge.kind=="Weld" or edge.kind=="Fixed" or edge.kind=="Bolt"' in gears
          and 'ratio=-left.Teeth/right.Teeth*orientation' in gears
          and 'ratio=-left.Teeth/right.Teeth*signA*signB' in gears
          and 'model:PivotTo(delta*model:GetPivot())' in gears
          and 'local stalled=false' in gears
          and 'if group.Grounded then stalled=true end' in gears)
    check("Gear bodies are physics-free but remain selectable",
          'model:SetAttribute("OPENWORKS_GearKinematic",true)' in gears
          and 'part.CanQuery=part:GetAttribute("GearPivotOnly")~=true' in simulation
          and 'session.Gears:ConfigureSupport(graph,copies,session.GroundKeys,' in simulation
          and 'not session.Gears:IsKinematic(id)' in simulation)
    check("Crank powers kinematic gears without native motors",
          'local kinematic=session.Gears:IsKinematic(drivenId)' in simulation
          and 'if not kinematic then' in simulation
          and 'session.Gears:Step(dt,' in simulation
          and 'if crank.Drive then crank.Drive.Enabled=false end' in simulation
          and 'crank.NativeSpeed+=(HandCrankMath.FixedAngularSpeed' in simulation)
    check("Gear and rigid shaft fall as one kinematic body, no native gear forces",
          'function Kinematics:Translate(dt)' in gears
          and 'group.FallVelocity-workspace.Gravity*maxStep' in gears
          and 'shiftGroup(group,Vector3.new(0,offset,0))' in gears
          and 'part.Anchored=true' in simulation
          and 'part.CanCollide=false' in simulation
          and 'not session.Gears:IsKinematic(id)' in simulation)
    check("Grounded bearing housing supports axle without native hinge forces",
          'function Kinematics:ConfigureSupport(' in gears
          and 'sg.Supported=true' in gears
          and 'tg.Supported=true' in gears
          and 'group.Supported then' in gears
          and 'session.Gears:ConfigureSupport(graph,copies,session.GroundKeys,' in simulation)
    check("Free-spinning gear follows falling shaft position and tilt",
          'tg.Followers' in gears
          and 'shiftGroup(group,center-group.Center)' in gears
          and 'local desiredAxis=shaft.RightVector.Unit*follower.AxisSign' in gears
          and 'CFrame.fromAxisAngle(axis,math.acos(dot))' in gears)
    check("Branched and reverse gear influence use one bidirectional graph",
          'table.insert(a.Links,{Group=b,Ratio=ratio})' in gears
          and 'table.insert(b.Links,{Group=a,Ratio=1/ratio})' in gears
          and 'for _,edge in ipairs(group.Links) do' in gears
          and 'for group,velocity in pairs(speed) do' in gears)
    check("Scripted crank ramps up and coasts down while gears stay physics-free",
          'CRANK_ACCEL_RESPONSE=9' in gears
          and 'CRANK_RELEASE_RESPONSE=6' in gears
          and 'self.CurrentSpeed+=(target-self.CurrentSpeed)*alpha' in gears
          and 'local ROTATION_PERIOD=1/60' in gears
          and 'crank.NativeSpeed+=(HandCrankMath.FixedAngularSpeed' in simulation)
    check("Crank selectable through obstructing shaft / gear in single-crank assembly",
          'if Crank.IsCrank(node) then return node end' in crank
          and 'if only then return nil end' in crank
          and 'node:GetAttribute("OwnerUserId")~=player.UserId' in crank)
    check("Controlled rotation targets the coupled physical shaft",
          'copies[coupledShaft:GetAttribute("InstanceId")]' in simulation
          and 'DrivenId=drivenId' in simulation
          and 'if crank.Drive then' in simulation
          and 'crank.Torque' not in simulation
          and 'VelocityGain' not in simulation)
    check("Held-LMB crank is fixed-speed, range-limited, torque-capped",
          "HandCrankMath.FixedAngularSpeed" in simulation
          and "self:StopCrank(session,id)" in simulation
          and "self.D.nearPlayer(owner,root.Position)" in simulation
          and "self.D.nearPlayer(player,crank.Root.Position)" in simulation
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
    check("Gear-to-gear acquisition targets teeth and true pitch circle",
          'Smart.GearPitchCapture = 0.7' in smart_placement
          and 'Smart.GearFaceCapture = 0.55' in smart_placement
          and 'math.abs(radial.Magnitude-pitch)>Smart.GearPitchCapture' in smart_placement
          and 'aimedPart:IsDescendantOf(model)' in smart_placement
          and 'local directAim=aimedModel==target' in smart_placement
          and 'score=if directAim then -0.15' in smart_placement)
    check("One moving gear can align to two other gear pitch circles",
          'function Smart.MultiGearPose(' in smart_placement
          and 'local along=(r1*r1-r2*r2+distance*distance)/(2*distance)' in smart_placement
          and 'local height=math.sqrt(math.max(0,height2))' in smart_placement
          and 'local pose,dist,meshes=Smart.MultiGearPose(' in smart_placement
          and 'math.max(0,meshes-1)*0.5' in smart_placement)
    transmission=read("src/server/Runtime/GearLibrary.lua")
    rack_client=read("src/client/Controllers/RackControlController.lua")
    check("45/90-degree bevel catalog contains actual tapered tooth-ring geometry",
          'function bevelTemplate(' in transmission
          and 'local halfCone=math.rad(shaftAngleDeg*0.5)' in transmission
          and 'model:SetAttribute("BevelShaftAngleDeg",shaftAngleDeg)' in transmission
          and 'for _,angle in ipairs({45,90}) do' in transmission
          and 'bevelTemplate(transmission,count,angle)' in transmission)
    check("45/90-degree bevels are ONE precompiled tapered CSG solid",
          'local GeometryService=game:GetService("GeometryService")' in transmission
          and 'GeometryService:UnionAsync(hub,additions,options)' in transmission
          and 'GeometryService:SubtractAsync(union,{cutter},options)' in transmission
          and 'SplitApart=false' in transmission
          and 'model:SetAttribute("GeometryVersion",3)' in transmission
          and 'model:SetAttribute("UnifiedBevelSolid",true)' in transmission
          and 'geometry.Name="BevelSolid"' in transmission
          and 'geometry.Parent=model' in transmission
          and 'scratch:Destroy()' in transmission
          and 'model.PrimaryPart=pivot' in transmission
          and 'pivot:SetAttribute("GearPivotOnly",true)' in transmission
          and 'TaperRim_' not in transmission
          and 'BevelTooth_' not in transmission)
    check("Bevel root and teeth share one uninterrupted inclined cone",
          'local axis=(Vector3.xAxis+radial*tanCone).Unit' in transmission
          and 'local normal=(radial-Vector3.xAxis*tanCone).Unit' in transmission
          and 'local widestRootRadius=rootRadius+' in transmission
          and 'rootRadius-TOOTH_EMBED-0.012' in transmission
          and 'ConicalRoot_' in transmission
          and 'ConicalTooth_' in transmission
          and 'for _,angle in ipairs({45,90}) do' in transmission)
    check("Bevel CSG failure never creates a fake solid with filled-in bore",
          'if not ok or type(unions)~="table" or #unions~=1' in transmission
          and 'if not drilled or type(solids)~="table" or #solids~=1' in transmission
          and 'model:Destroy()' in transmission
          and 'if old then old:Destroy() end' in transmission)
    check("Bevel 45 and 90 geometry requires intersecting pitch-cone apexes",
          'function GearMath.AutoBevelStatus(' in gear_math
          and 'na~=nb' in gear_math
          and 'math.cos(math.rad(shaftAngle))' in gear_math
          and 'GearMath.BevelApex(a)-GearMath.BevelApex(b)' in gear_math
          and 'function Smart.BevelPose(' in smart_placement
          and 'GearMath.Kind(target)==bevelKind' in smart_placement
          and 'kind=="Bevel45" or kind=="Bevel90"' in gears
          and 'BevelConeDeg") or 22.5' in gear_math)
    check("Rack and guide parts are available as generated templates",
          'function rackTemplate(' in transmission
          and 'function rackGuideTemplate(' in transmission
          and 'model:SetAttribute("RackPitchStuds",MODULE)' in transmission
          and 'model:SetAttribute("RackGuideLengthStuds",length)' in transmission)
    check("Rack and guide placement uses physical contact, no implicit joint",
          'function Smart.RackPose(' in smart_placement
          and 'function Smart.GuidePose(' in smart_placement
          and 'GearMath.AutoGuideStatus(' in gear_math
          and 'mode=="Rack" or mode=="Guide"' in mechanical
          and 'd.commitAssembly(player,before,after,nil,false)' in mechanical)
    check("Rack pinion graph conserves reciprocal angular-linear ratio",
          'for _,rack in ipairs(self.Racks) do' in gears
          and 'GearMath.PitchRadius(pinion.Model)*signed' in gears
          and 'table.insert(b.Links,{Group=a,Ratio=1/ratio})' in gears
          and 'shiftGroup(group,group.TravelAxis*velocity*step)' in gears)
    check("Rack translation requires physical grounded guide and end limits",
          'groundKeys["p:"..tostring(id)]' in gears
          and 'group.Guide={' in gears
          and 'nextPosition=travel+velocity*step' in gears
          and 'if math.abs(nextPosition)>maxTravel+0.001 then' in gears)
    check("Held Q/E backdrives rack without arbitrary client speed or torque",
          'action="BeginRack"' in rack_client
          and 'Enum.KeyCode.Q' in rack_client
          and 'Enum.KeyCode.E' in rack_client
          and 'function Simulation:BeginRack(' in simulation
          and 'function Simulation:InputRack(' in simulation
          and 'local RACK_MANUAL_SPEED = 1.5' in simulation
          and 'OPENWORKS_RackControl' in service)
    check("Component duplication gives new IDs and preserves internal alignments",
          'idMap[part.instanceId] = HttpService:GenerateGUID(false)' in component
          and 'newState.instanceId = idMap[desired.instanceId]' in component
          and 'newState.componentId = componentId' in component
          and 'newState.componentAnchorId = idMap[anchorOldId]' in component
          and 'newState.assemblyId = nil' in component
          and 'newState.assemblyName = nil' in component
          and 'newState.grounded = false' in component
          and 'idMap[desired.alignedOpeningId]' in component)
    check("Component duplication remaps ONLY wholly internal mechanical links",
          'not idMap[original.sourceId] or not idMap[original.targetId]' in component
          and 'original.boltId and not idMap[original.boltId]' in component
          and 'original.secondTargetId' in component
          and 'spec.relationId=HttpService:GenerateGUID(false)' in component
          and 'spec.sourceId=idMap[original.sourceId]' in component
          and 'spec.targetId=idMap[original.targetId]' in component
          and 'spec.componentId=componentId' in component
          and 'fitSetMap[original.fitSetId]' in component
          and 'mapped.movingId=idMap[point.movingId]' in component
          and 'mapped.stationaryId=idMap[point.stationaryId]' in component)
    check("Copied relationships restore atomically with geometry/undo",
          'local ok,detail=d.mechanical:Restore(player,spec)' in component
          and 'd.mechanical:DestroyRelation(rel)' in component
          and 'd.commitAssembly(player,{},after,relationships,false)' in component
          and 'components.D.mechanical=mechanical' in service
          and 'commitAssembly = commitAssembly,' in service)
    surface=read("src/shared/Construction/SurfacePlacement.lua")
    check("Neighbor face snap uses target local coordinates and exact contact",
          'function SurfacePlacement.SnapToNearbyFace(' in surface
          and 'math.abs(n:Dot(axis))<0.6' in surface
          and 'SurfacePlacement.SnapToSurface(ghost,desired,' in surface
          and 'local FACE_LATTICE=0.0625' in surface
          and 'local bestEdge=EDGE_CAPTURE' in surface
          and 'SurfacePlacement.SnapToNearbyFace(' in selection)
    check("Single primitive copies get new ids and author no physical links",
          'model:SetAttribute("InstanceId", instanceId or HttpService:GenerateGUID(false))' in service
          and 'self.Pending~="Copy"' in selection
          and 'self.SmartMatch.kind=="Gear"' in selection
          and 'self.SmartMatch.kind=="Rack"' in selection
          and 'self.SmartMatch.kind=="Guide"' in selection)
    check("Oversized cylinders and wheel-like rollers never auto-snap into holes",
          'function Bore.CanInsert(source,target)' in gear_clearance
          and 'shaftDiameter>=openingDiameter-2*TOL' in gear_clearance
          and 'local housingLength=' in gear_clearance
          and 'if not Bore.CanInsert(shaft,target) then return nil end' in smart_placement
          and 'if not Bore.CanInsert(shaft,opening) then return nil end' in smart_placement)
    check("Gear-to-gear snap retains tight separate shaft bore hitbox",
          'Smart.HubSnapRadius = 0.34' in smart_placement
          and 'Smart.HubAimRadius = 0.24' in smart_placement
          and 'if hubAimed then boreAim*0.25+0.015' in smart_placement)
    check("Gear selection retargets by tooth hit without old target lock",
          'local switchedGear=movingGear and aimedModel' in selection
          and 'local fullScan=switchedGear' in selection
          and 'preview,hit and hit.Instance' in selection
          and 'ray,allTargets,aimedModel' in selection
          and 'if kind=="Gear" or kind=="Rack"' in smart_placement)
    check("Gear placement authors geometry, not legacy mechanical mesh joints",
          'if mode=="Gear" or mode=="Rack" or mode=="Guide" then' in mechanical
          and 'd.commitAssembly(player,before,after,nil,false)' in mechanical
          and 'mode~="Gear" and mode~="Rack" and mode~="Guide"' in mechanical
          and 'GearMath.AutoMeshStatus(source,target)' in mechanical)
    check("Preview, server and simulation agree on physical gear engagement",
          'GearMath.AutoMeshable(movingModel,target)' in preview
          and 'GearMath.AutoMeshable(candidate,target)' in service
          and 'GearMath.AutoMeshStatus(source,target)' in mechanical
          and 'GearMath.AutoMeshable(left.Model,right.Model)' in gears)
    gear_templates=read("src/server/Runtime/GearLibrary.lua")
    check("Gear snap uses tiny bore/axis-specific target, not gear bounding radius",
          'Smart.HubSnapRadius = 0.34' in smart_placement
          and 'Smart.HubAimRadius = 0.24' in smart_placement
          and 'hubAimDistance(aimRay,target)' in smart_placement
          and 'local range=if isGear then Smart.HubSnapRadius' in smart_placement
          and 'local aimThreshold=if isGear then Smart.HubAimRadius' in smart_placement
          and 'if hubAimed then boreAim*0.25+0.015' in smart_placement)
    check("All stock gear bores accept standard minimum shaft",
          'math.max(0.215, bodyRadius * 0.33)' in gear_templates
          and 'existing:Destroy()' in gear_templates
          and 'oldRadius>=boreRadius-0.0001' in gear_templates)
    check("Build/Edit gear shaft fits validated by preview and server",
          'Smart.HubFits(movingModel,target)' in preview
          and 'Smart.HubFits(candidate,target)' in service
          and 'local opening=if mode=="Hub" then' in mechanical
          and 'local fitted,why=Smart.HubFits(source,target)' in mechanical)
    check("Manual L gear alignment chooses real Rotation or Rigid",
          'local isGear=type(align.Target:GetAttribute("GearTeeth"))=="number"' in layered
          and 'mateKind="Hub"' in layered
          and 'relationKind=choice' in layered
          and 'end,selected.FittedCount or 1,isGear)' in layered)
    check("Simulation uses gear center axis for physical hinge",
          'JointFrames.ForOpening(edge.target)' in simulation
          and 'local explicit = axisOverride(model)' in read("src/shared/Construction/AlignmentMath.lua")
          and 'model:SetAttribute("AxialAxis", "X")' in read("src/server/Runtime/GearLibrary.lua"))
    alignment_math=read("src/shared/Construction/AlignmentMath.lua")
    check("Slider and cylindrical hard stops use only tube faces",
          'housingLength*0.5-endInset' in alignment_math
          and '(shaftLength+housingLength)*0.5-engagement'
              not in alignment_math
          and 'function Alignment.RelativeTravelBounds(' in alignment_math
          and 'return low-authored,high-authored' in alignment_math)
    multi_fit=read("src/shared/Construction/MultiFitMath.lua")
    smart_place=read("src/shared/Construction/SmartPlacement.lua")
    align_service=read("src/server/Runtime/AlignmentService.lua")
    check("Moving drilled bores follow crosshair depth along finite shafts",
          'local function shaftCursorDepth(ray,shaft)' in smart_place
          and 'local denominator=1-parallel*parallel' in smart_place
          and 'depth=math.clamp(depth,-halfLength,halfLength)' in smart_place
          and 'rayT<=0 or rayT>Grid.MaxDistance' in smart_place
          and 'axial=mouseDepth*shaftAxis:Dot(axis)' in smart_place
          and 'shaftMouseDepth,shaftMouseError=shaftCursorDepth(aimRay,target)' in smart_place
          and 'members,source,target,aimed,' in smart_place
          and 'shaftMouseDepth,shaftMouseError' in smart_place
          and 'score=-3+shaftMouseError*0.05' in smart_place
          and 'Alignment.ReversePlan(members,opening,shaft,units,roll)' in smart_place
          and 'local units=math.clamp(snapped,loSnap,hiSnap)' in smart_place)
    check("Gear-on-shaft placement also preserves real cursor depth",
          'if isGear and Alignment.IsShaft(target) then' in smart_place
          and 'local cursorDepth=shaftCursorDepth(aimRay,target)' in smart_place
          and 'near=stationary.Position' in smart_place
          and 'Smart.HubPose(source,target,near)' in smart_place
          and 'local _,distance=shaftCursorDepth(ray,target)' in smart_place)
    check("Long hinge shafts use real segment overlap, not center-only bounds",
          'function Alignment.InsertionBounds(shaft,opening)' in alignment_math
          and 'local requiredOverlap=' in alignment_math
          and 'Alignment.InsertionBounds(shaft,target)' in alignment_math
          and 'Alignment.InsertionBounds(fixedShaft,opening)' in alignment_math
          and 'Alignment.InsertionBounds(shaft,hole)' in multi_fit
          and 'Alignment.InsertionBounds(shaft,opening)' in smart_place)
    check("One shaft can pierce several ungrouped owned bore models",
          'function Fit.StationarySet(movingMembers,primary,all,delta,ignored)' in multi_fit
          and 'and Fit.Check(shafts[1],candidate,delta)' in multi_fit
          and 'and not usedStationary[pair.stationaryId]' in multi_fit
          and 'and not usedMoving[pair.movingId]' in multi_fit
          and 'MultiFit.StationarySet(members,target,' in mechanical
          and 'MultiFit.StationarySet(\n                    members,target,' in smart_place)
    check("Manual L selects empty bore centers and validates all penetrations",
          'function Layered:AimedOpening(excluded)' in layered
          and 'target=self:AimedOpening(excluded) or target' in layered
          and 'MultiFit.StationarySet(' in layered
          and 'MultiFit.AllowMap(fitted)' in layered
          and 'mateKind="Bore"' in layered
          and 'selected.FittedCount or 1' in layered)
    check("Preview and server share individual physical clearance exemptions",
          'MultiFit.AllowMap(matches)' in selection
          and 'MultiFit.AllowMap(fitPairs)' in mechanical
          and 'MultiFit.StationarySet(moving,match.target,' in selection
          and 'MultiFit.StationarySet(members,target,' in mechanical
          and 'MultiFit.AllowMap(selected)' in align_service)
    check("Snug fit, pose and length edits preserve all engaged holes",
          'Shaft must fit every connected opening' in mechanical
          and 'MultiFit.Check(source,pair.hole)' in mechanical
          and 'MultiFit.Check(source,hole)' in mechanical
          and 'MultiFit.StationarySet({model},opening,all)' in service
          and 'Alignment.InsertionBounds(source,target)' in mechanical)
    check("Linear guide stop remains strict for multi-hole fit",
          'if typeName=="Slider" or typeName=="Cylindrical" then' in mechanical
          and 'Alignment.OffsetBounds(pair.shaft,pair.hole)' in mechanical
          and 'Choose Rotation Only for a long hinge pin' in mechanical)
    check("Simulation constrains legacy out-of-bounds shafts without aborting",
          'Alignment.RelativeTravelBounds(' in simulation
          and 'local legacyOutside=lower>0 or upper<0' in simulation
          and 'constraint:SetAttribute("LegacyOutOfBounds",true)' in simulation
          and 'lower,upper=0,0' in simulation
          and 'constraint.LimitsEnabled=true' in simulation
          and 'constraint.LowerLimit=lower*Grid.Unit' in simulation
          and 'constraint.UpperLimit=upper*Grid.Unit' in simulation)
    check("Plot restores old joint positions rather than rejecting older saves",
          'folder:SetAttribute("LegacyOutOfBounds",true)' in mechanical
          and 'low,high=0,0' in mechanical
          and 'Shaft center must start between the tube end faces' not in mechanical
          and 'local ok,message=d.mechanical:Restore(player,spec)' in persistence)
    check("Saved and tuned joints share physical tube-relative stops",
          mechanical.count('Alignment.RelativeTravelBounds(source,target)')>=3
          and 'min=math.max(min,-fittedTravel)' in mechanical
          and 'max=math.min(max,fittedTravel)' in mechanical)
    check("Placement shaft offsets quantize within tube faces",
          smart_placement.count('local loSnap=math.ceil(low*2-1e-6)*0.5')>=2
          and smart_placement.count('local hiSnap=math.floor(high*2+1e-6)*0.5')>=2)
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
          and 'action="SmartMate"' in layered
          and 'mateKind="Bore"' in layered
          and 'position=exact.Position' in layered
          and 'orientation=exact.Rotation' in layered)
    check("Relationship modal cannot duplicate world clicks",
          'if self.PendingMateChoice or (self.Numeric and self.Numeric.Active) then return end' in selection
          and 'self.IgnoreClickUntil=os.clock()+0.22' in selection
          and 'self:RefreshPointer()' in selection)

    check("Metadata undo is in place",
          'kind="Metadata"' in service
          and "local function restoreMetadata" in service
          and 'if record.kind == "Metadata" then' in service)
    check("Assembly tool can directly undo and redo",
          'hasEquippedTool(player,"AssemblySimulation")' in service
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
        if ":SetAsync(" in text or ":UpdateAsync(" in text:
            save_writes.append(file.relative_to(ROOT).as_posix())
    check("Exactly one DataStore write location",
          save_writes == ["src/server/Runtime/PlotPersistence.lua"],
          str(save_writes))
    plot_ui=read("src/client/Controllers/PlotSaveController.lua")
    config=read("src/shared/Construction/BuildConfig.lua")
    check("Autosave and manual SavePlot use one revision-protected write path",
          'if action=="SavePlot" or action=="LoadPlot"' in service
          and "self.Store:UpdateAsync(" in persistence
          and 'AutoSaveEnabled = true' in config
          and 'AutoSaveIntervalSeconds = 120' in config
          and 'function Persistence:Save(player,mode)' in persistence
          and 'sameCloudRevision(cloud,expected,document,uncertain)' in persistence
          and 'self.KnownCloudRevision[player]=if document==nil then false' in persistence)
    check("Autosave only follows successful building edits, never failed load",
          'persistence:MarkDirty(player)' in service
          and 'if result and persistence and not simulationAction' in service
          and 'if not Config.AutoSaveEnabled or not self.Ready[player]' in persistence
          and 'self.Dirty[player]=false' in persistence
          and 'now-(self.DirtySince[player] or now)' in persistence
          and 'self:ShouldAutoSave(player)' in persistence
          and 'persistence:StartAutoSave()' in service)
    check("Save on exit and shutdown happens before deleting authored plot",
          'pcall(persistence.Flush,' in service
          and 'persistence,player,"Exit"' in service
          and 'persistence,player,"Shutdown"' in service
          and 'game:BindToClose(function()' in service
          and service.index('persistence,player,"Exit"')
              <service.index('if simulation then simulation:ClearPlayer(player) end')
          and 'self:Save(player,mode or "Exit")' in persistence)
    check("F6 plot panel shows autosave status and unsaved edits",
          'SAVE UNAVAILABLE' in plot_ui
          and 'if failed then message else "Autosave pending"' in plot_ui
          and 'OPENWORKS_LastSaveMode' in plot_ui
          and 'OPENWORKS_AutoSavePending' in plot_ui
          and 'LAST SAVED  /' in plot_ui
          and 'Autosave pending' in plot_ui)
    check("Unknown DataStore write outcomes retain safe same-session lineage",
          'self.UncertainWriteIds[player]=possible' in persistence
          and 'uncertain[cloud.writeId]' in persistence
          and 'self.UncertainWriteIds[player]=nil' in persistence
          and 'self:MarkSaved(player,document,mode)' in persistence)
    check("Cloud conflict blocks overwrite; failures retain dirty state",
          'if conflict or saved==nil then' in persistence
          and 'self.Ready[player]=false' in persistence
          and 'self:MarkSaved(player,document,mode)' in persistence
          and 'DataStore write failed; unsaved work' in persistence
          and 'if expected==false then return cloud==nil end' in persistence)
    check("Both loading and saving clear Busy after failure",
          "pcall(self.Apply,self,player,target)" in persistence
          and "pcall(self.Encode,self,player)" in persistence
          and "self.Busy[player]=nil" in persistence)
    check("Retired assembly number counter is not accessed",
          "assemblies.NextNumber" not in persistence)

    check("UI v2 assembly feedback is owned by one shared manager",
          'self.Feedback:Clear("assembly")' in tool_ui
          and 'Name="OPENWORKS_UIV2_Feedback"' in feedback
          and 'function Feedback:Destroy()' in feedback)
    check("Selection and inspector visuals are client Workspace-owned",
          'Name="OPENWORKS_LocalSelectionVisuals"' in selection
          and 'Name="OPENWORKS_LocalInspectorSelection"' in inspector)
    check("UI v2 mechanical guides use line/sphere adornments, not Parts",
          'Instance.new("Part")' not in world
          and '"LineHandleAdornment"' in world
          and '"SphereHandleAdornment"' in world
          and 'if kind~="Bearing" and kind~="Slider"' in world)
    check("Ground and assembly feedback avoid the Highlight budget",
          'MAX_BODIES=64' in world
          and 'self.Feedback:Set("ground",id,{model}' in world
          and 'Color3.fromRGB(162,102,237)' in feedback
          and 'Instance.new("Highlight")' not in world)
    handles=read("src/client/Controllers/PhysicalHandles.lua")
    motion=read("src/client/Controllers/WorldMotion.lua")
    gizmo=read("src/client/Controllers/ResizeGizmo.lua")
    layered=read("src/client/Controllers/LayeredEditingController.lua")
    alignment_editor=read("src/client/Controllers/AssemblyController.lua")
    assembly_tool=read("src/client/Controllers/AssemblyToolController.lua")
    check("All authoring previews inherit ONE fast, framerate independent motion profile",
          'WorldMotion.Profile=table.freeze({' in motion
          and 'Placement=30' in motion
          and 'Scale=34' in motion
          and 'function WorldMotion.Alpha(' in motion
          and '1-math.exp(' in motion
          and 'WorldMotion.Profile.Placement' in selection
          and 'WorldMotion.Profile.Placement' in layered
          and 'WorldMotion.Profile.Placement' in alignment_editor
          and 'self.PreviewVisualPose=WorldMotion.Step(' in selection
          and 'align.VisualPose=WorldMotion.Step(' in layered
          and 'self.VisualPose=WorldMotion.Step(' in alignment_editor)
    check("Visual resizing eases block center and dimensions together with grips",
          'function WorldMotion.StepSize(' in motion
          and 'function Controller:AdvanceScalePreview(dt)' in selection
          and 'self.ScaleVisualCF=WorldMotion.Step(' in selection
          and 'self.ScaleVisualSize=WorldMotion.StepSize(' in selection
          and 'ghost.PrimaryPart.Size=self.ScaleVisualSize' in selection
          and 'self:AdvanceScalePreview(dt)' in selection
          and 'self.VisualCF=WorldMotion.Step(' in gizmo
          and 'self.VisualSize=WorldMotion.StepSize(' in gizmo
          and 'self.Visual:Update(self.VisualCF or self.CFrame,' in gizmo)
    check("Server commits keep exact geometry rather than eased visual poses",
          'position=self.PreviewCF.Position' in selection
          and 'position=self.PreviewCF.Position,' in selection
          and 'size=self.CurrentSize' in selection
          and 'self.ScaleCF' in selection
          and 'position = cf.Position' in selection
          and 'WorldMotion.SettlePreview(snapshot,goal,models)' in selection
          and 'function WorldMotion.SettlePreview(' in motion
          and 'item.CanQuery=false' in motion
          and 'part.CanQuery=false' in motion)
    check("Primitive, component, assembly nudges and world turns are visually damped",
          'function WorldMotion.AnimateMove(' in motion
          and 'function WorldMotion.AnimateTurn(' in motion
          and 'local stop=WorldMotion.AnimateMove(affected,displacement)' in selection
          and 'local stop=WorldMotion.AnimateMove(members,displacement)' in assembly_tool
          and 'WorldMotion.Profile.TurnSeconds' in selection
          and 'if not succeeded then stop() end' in selection
          and 'if not ok or type(answer)~="table" or not answer.ok then stop() end' in assembly_tool
          and 'function WorldMotion.Cancel(models)' in motion
          and 'local function stillWaitingForReplication()' in motion
          and 'elapsed>=duration+MAX_REPLICATION_HOLD' in motion)
    check("Post-fit shaft depth and roll inherit exact same visual-only motion",
          'function WorldMotion.AnimateShaftPose(' in motion
          and 'local oldOffset=shaft:GetAttribute("AlignedOffsetU") or 0' in motion
          and 'local oldRoll=shaft:GetAttribute("ShaftRollDegrees") or 0' in motion
          and 'CFrame.fromAxisAngle(axis,math.rad(roll-oldRoll))' in motion
          and 'WorldMotion.Profile.NudgeSeconds' in motion
          and 'WorldMotion.AnimateShaftPose(align.Members,align.Shaft,' in layered
          and 'WorldMotion.AnimateShaftPose(self.Members,self.Source,' in alignment_editor
          and 'if ok then' in layered
          and 'stop()' in layered
          and 'stop()' in alignment_editor)
    check("Drag commit handoffs never leave persistent hidden or colliding ghosts",
          'local handoff,goal,models=self:CapturePendingHandoff()' in selection
          and 'self:FinishPendingHandoff(handoff,goal,models,success)' in selection
          and 'self:FinishPendingHandoff(handoff,goal,models,ok)' in selection
          and 'function WorldMotion.SettlePreview(' in motion
          and 'function WorldMotion.NeedsHandoff(' in motion
          and 'WorldMotion.NeedsHandoff(self.Preview,self.PreviewCF)' in selection
          and 'if count>MAX_ANIMATED_PARTS then return false end' in motion
          and 'snapshot:SetAttribute("OPENWORKS_PresentationOnly",true)' in motion
          and 'snapshot:Destroy()' in motion
          and 'part.LocalTransparencyModifier=item.previous' in motion
          and 'partCount>MAX_ANIMATED_PARTS' in motion
          and 'or distance>WorldMotion.Profile.TeleportDistance' in motion)
    check("Frame-budgeted placement retains easing and ghost feedback",
          'visualNow-(self.PreviewComputeTime or 0)<1/30' in selection
          and 'self.PreviewVisualPose=WorldMotion.Step(' in selection
          and 'self.LastPreviewing=previewing' in selection
          and 'if previewing then self.Feedback:Clear("selection")' in selection
          and 'if os.clock()-self.LastRender<0.08 then return end' in ghost_edges)
    check("Snapping scans moving geometry once per nearby-target pass",
          'local movingGearMembers={}' in smart_placement
          and 'for _,member in ipairs(Smart.Members(moving)) do' in smart_placement
          and 'for _,member in ipairs(movingGearMembers) do' in smart_placement
          and 'local hasMovingGear=#movingGearMembers>0' in smart_placement)
    check("Handles avoid per-frame descendant and unchanged visual writes",
          'grip.Parts=if mode=="Move"' in handles
          and 'grip.LastVisible~=grip.Visible' in handles
          and 'grip.Model:GetDescendants()' not in handles)
    check("Gear physics caches solids and slows only idle scans",
          'group.BottomParts=parts' in gears
          and 'IDLE_SCAN_PERIOD=0.25' in gears
          and 'if moving then SCAN_PERIOD else IDLE_SCAN_PERIOD' in gears)
    compact_hole=read("src/server/Runtime/CompactHoleLibrary.lua")
    check("Compact 1U drilled block is a true 0.98U CSG bore",
          'OUTER_U=1' in compact_hole
          and 'HOLE_U=0.98' in compact_hole
          and 'Shape=Enum.PartType.Cylinder' in compact_hole
          and 'GeometryService:SubtractAsync(base,{cutter}' in compact_hole
          and 'model:SetAttribute("HoleDiameterU",HOLE_U)' in compact_hole
          and 'model:SetAttribute("OpeningAxis","Y")' in compact_hole
          and 'CompactHoleLibrary.Ensure()' in service
          and 'SplitApart=false' in compact_hole)
    check("Compact bored block does not misrepresent CSG errors as valid geometry",
          'if not ok or type(solids)~="table" or #solids~=1' in compact_hole
          and 'template discarded' in compact_hole
          and 'model.Parent=category' in compact_hole)
    shaft_library=read("src/server/Runtime/ShaftLibrary.lua")
    check("Default Shaft is a separate 0.95U diameter x 2U cylinder",
          'model.Name="Shaft"' in shaft_library
          and '0.95*Grid.Unit,0.95*Grid.Unit' in shaft_library
          and '2*Grid.Unit' in shaft_library
          and 'Enum.PartType.Cylinder' in shaft_library
          and 'ShaftLibrary.Ensure()' in service
          and 'payload.templateId=="Shaft"' in service)
    check("Shaft uses native hole/shaft fitting with precision",
          'PrimitiveFamily","CylinderShaft"' in shaft_library
          and 'id=="shaft"' in service
          and 'TemplateId") or model.Name))=="shaft"' in read("src/shared/Construction/AlignmentMath.lua"))
    check("Independent transforms disconnect every non-spring relationship",
          'function Mechanical:DisconnectMoved(' in mechanical
          and 'relation:GetAttribute("Kind")=="Spring"' in mechanical
          and 'local changed=false' in mechanical
          and 'if changed and not keep then' in mechanical
          and 'self:DestroyRelation(relation)' in mechanical
          and 'mechanical:DisconnectMoved(player,prior,nextStates)' in service
          and 'mechanical:DisconnectMoved(player,before,after)' in service)
    check("Rigid joint batches preserve common motion and undo disconnections",
          'motion.delta' in mechanical
          and 'common and not matching(common,motion.delta)' in mechanical
          and 'relations=disconnected,removed=true' in service
          and 'disconnected=disconnected' in service
          and 'local detached=record.disconnected or {}' in mechanical
          and 'local remove=if undo then specs else detached' in mechanical
          and 'local restore=if undo then detached else specs' in mechanical)
    check("Moving a coupled shaft no longer blocks independent detachment",
          'local crankDetaching=false' in service
          and 'not crankDetaching' in service
          and 'model:SetAttribute("AlignedOpeningId",nil)' in service)
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
