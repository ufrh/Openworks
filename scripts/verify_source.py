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

    camera=read("src/client/Controllers/CameraController.lua")
    plots_service=read("src/server/Runtime/PlotService.lua")
    check("Default freecam retains native Scriptable camera on respawn",
          'player.CameraMode=Enum.CameraMode.Classic' in camera
          and 'cam.CameraType=Enum.CameraType.Scriptable' in camera
          and 'Enum.RenderPriority.Camera.Value+1' in camera
          and 'player.CharacterAdded:Connect(function()' in camera
          and 'Enum.CameraMode.LockFirstPerson' not in camera)
    check("Mouse movement always looks around without RMB activation",
          'UIS:GetMouseDelta()' in camera
          and 'self.Yaw-=delta.X*LOOK_SENSITIVITY' in camera
          and 'self.Pitch=math.clamp(self.Pitch-delta.Y*LOOK_SENSITIVITY' in camera
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
    check("Revert prior head-start and look smoothing",
          'LOOK_RESPONSE=22' not in camera
          and 'POSITION_RESPONSE=18' not in camera
          and 'OPENWORKS_CameraSpawnReady' not in camera
          and 'OPENWORKS_CameraSpawnReady' not in plots_service)
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
          and 'grounded = false' in read("src/client/Controllers/AssemblyController.lua")
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
          and 'if (payload.scope=="Assembly" and not hasEquippedTool(player,"Assembly"))' in service)
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
          'hasEquippedTool(player,"Assembly")' in service
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
    check("Edit multiselect outlines every actual primitive, not group bounding box",
          'for _,model in ipairs(self.SelectedParts) do' in selection
          and 'Name="OPENWORKS_SelectionOutline"' in selection
          and 'self.ComponentOutline=ComponentOutline.new(' not in selection)
    check("Assembly selection highlights each primitive without phantom bounds",
          'for _,id in ipairs(ids) do' in tool_ui
          and 'Name="AssemblyPrimitive",Adornee=model' in tool_ui
          and 'ComponentOutline.new(' not in tool_ui)
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
          "MAX_HIGHLIGHTS=64" in world
          and "Color3.fromRGB(179,115,255)" in tool_ui)
    handles=read("src/client/Controllers/PhysicalHandles.lua")
    check("Frame-budgeted placement retains per-render ghost smoothing",
          'visualNow-(self.PreviewComputeTime or 0)<1/30' in selection
          and 'self.PreviewVisualPose=WorldMotion.Step(' in selection
          and 'outlineNow-(self.OutlineLastUpdate or 0)>=0.1' in selection
          and 'self.OutlinePreviewing~=previewing' in selection)
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
