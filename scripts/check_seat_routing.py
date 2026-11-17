#!/usr/bin/env python3
"""Seat/route integration contracts. These do not replace a Studio playtest."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
def read(p): return (root/p).read_text(encoding="utf-8")
seat=read("src/server/Runtime/SeatLibrary.lua")
server=read("src/server/Runtime/SeatControlService.lua")
service=read("src/server/Runtime/ConstructionService.lua")
routes=read("src/client/Controllers/RoutingController.lua")
panel=read("src/client/Controllers/ContextEditor.lua")
tools=read("src/shared/Construction/SubtoolDefinitions.lua")
physical=read("src/server/Runtime/PhysicalSimulationService.lua")
rack=read("src/server/Runtime/RackSimulationService.lua")
runtime=read("src/server/Runtime/SeatRuntime.lua")
plot=read("src/server/Runtime/PlotService.lua")
motor=read("src/client/Controllers/MotorControlController.lua")
rope=read("src/shared/Construction/RopeMath.lua")
camera=read("src/client/Controllers/CameraController.lua")
persist=read("src/server/Runtime/PlotPersistence.lua")
mech=read("src/server/Runtime/MechanicalService.lua")
startup=read("src/client/init.client.lua")
checks={
 "One native resizable flat plate with both color-coded roles":
    'Library.TemplateId="SeatPlate"' in seat
    and 'Instance.new("Seat")' in seat
    and 'model:SetAttribute("ResizeMode","XYZ_1U")' in seat
    and '"Operator"' in seat and '"Passenger"' in seat,
 "Seat template is registered before existing primitive registry starts":
    "SeatLibrary.Ensure()" in service and 'SeatLibrary.Apply(model,data.seatRole)' in service,
 "Role and logical motor controls are persisted without schema migration":
    "seatRole=snap.seatRole" in persist
    and "seatRole=record.seatRole" in persist
    and 'seatId=relation:GetAttribute("SeatId")' in mech
    and 'folder:SetAttribute("SeatId",spec.seatId)' in mech,
 "Server verifies all route endpoints and role choices":
    'd.findOwned(player,payload.seatId)' in server
    and 'self.D.mechanical:OwnedRelation(player,id)' in server
    and 'SeatLibrary.ValidRole(payload.role)' in server
    and 'seat:GetAttribute("SeatRole")~="Operator"' in server,
 "Route changes are metadata-only, never new physics edges":
    'or seatAction' in service
    and 'relation:SetAttribute("SeatId",if seat then payload.seatId else nil)' in server
    and 'd.commitJointEdit(player,previous,d.mechanical:Snapshot(relation))' in server,
 "Mechanics exposes both Connect and Route":
    'Id="Route"' in tools and 'LegacyMode="Mechanics"' in tools,
 "Always-on-top dots and lines have a drag-to-seat transaction":
    'Instance.new("SphereHandleAdornment")' in routes
    and 'Instance.new("LineHandleAdornment")' in routes
    and 'item.AlwaysOnTop=true' in routes
    and 'action="RouteControl"' in routes
    and 'self.Editor:OpenForNode(node' in routes,
 "Seat click gives centralized route names and keybinds":
    'function Panel:RenderSeatControls(member)' in panel
    and 'action="ConfigureRoutedControl"' in panel
    and 'action="SetSeatRole"' in panel
    and 'action="RouteControl"' in panel,
 "Operator seating and walking happen only with a seat in graph":
    'if #candidates==0 then' in runtime
    and 'root.Anchored=false' in runtime
    and 'initial:Sit(hum)' in runtime
    and 'player:SetAttribute("OPENWORKS_SimulationHasSeat",true)' in runtime,
 "Both active simulation engines transition into/out of seat state":
    all('SeatRuntime.Start(player,graph,copies,session)' in s
        and 'SeatRuntime.Stop(player,session)' in s for s in (physical,rack)),
 "Authoring seat cannot snag hidden builder avatar":
    "part.Disabled=true" in seat
    and "part.CanTouch=false" in seat
    and "seat.Disabled=false" in runtime
    and "seat.CanTouch=true" in runtime,
 "Vehicle handoff preserves avatar physics and detaches SeatWeld":
    'OPENWORKS_OriginalCollision' in plot
    and 'OPENWORKS_OriginalTransparency' in plot
    and 'desc:GetAttribute("OPENWORKS_OriginalCollision")' in runtime
    and 'local weld=seat:FindFirstChild("SeatWeld")' in runtime
    and 'if weld and weld:IsA("Weld") then weld:Destroy() end' in runtime,
 "Routed motors and winches require server-verified operator occupancy":
    'local operatorId=Runtime.OperatorSeatId(player,session)' in runtime
    and 'return operatorId==seatId' in runtime
    and all('SeatRuntime.CanControl(owner,session,motor.SeatId)' in engine
        and 'SeatRuntime.CanControl(player,session,motor.SeatId)' in engine
        and 'SeatRuntime.CanControl(owner,session,rope.SeatId)' in engine
        and 'SeatRuntime.CanControl(player,session,rope.SeatId)' in engine
        for engine in (physical,rack)),
 "No-seat freecam controls and seated tool-unequip remain valid":
    'if not session or not session.Seats then return true end' in runtime
    and 'or player:GetAttribute("OPENWORKS_SimulationHasSeat")==true' in motor
    and 'simulation:IsRunning(player)' in service,
 "Camera switches to normal character mode only when seat present":
    'camera.CameraType=Enum.CameraType.Custom' in camera
    and 'player:GetAttribute("OPENWORKS_SimulationHasSeat")==true' in camera
    and 'camera.CameraType=Enum.CameraType.Scriptable' in camera,
 "Seat-routed ropes can identify their active operator":
    'SeatId=relation:GetAttribute("SeatId")' in rope,
 "Client boot starts route controller":
    'RoutingController.new(tools,assemblyController,unifiedExplorer)' in startup,
}
for name,passed in checks.items():
    print(("PASS" if passed else "FAIL")+": "+name)
if not all(checks.values()): raise SystemExit("Seat routing integration failed")
print(f"PASS: {len(checks)} seat/routing contracts; Studio runtime test still required")
