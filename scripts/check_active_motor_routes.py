#!/usr/bin/env python3
"""Prevent changing a retired motor engine while the live router still uses another.

Run: python scripts/check_active_motor_routes.py
Pure source inspection: does not replace a Roblox Studio integration playtest.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

construction = source("src/server/Runtime/ConstructionService.lua")
router = source("src/server/Runtime/UnifiedSimulationService.lua")
physical = source("src/server/Runtime/PhysicalSimulationService.lua")
rack = source("src/server/Runtime/RackSimulationService.lua")
transmission = source("src/server/Runtime/GearTransmission.lua")
kinematics = source("src/server/Runtime/GearKinematics.lua")
bearings = source("src/server/Runtime/BearingSupport.lua")
assembly = source("src/server/Runtime/AssemblyService.lua")
assembly_tool = source("src/client/Controllers/AssemblyToolController.lua")
mechanics = source("src/server/Runtime/MechanicalService.lua")

checks = {
    "ConstructionService boots Unified": 'require(script.Parent:WaitForChild("UnifiedSimulationService"))' in construction,
    "Unified dispatches Physical/Rack": "return if rack then self.Rack else self.Physical" in router,
    "Physical shaft-only actuator": 'drive.Name="PoweredMotor_ShaftOnlyDrive"' in physical,
    "Physical bearing is passive": "constraint.ActuatorType=Enum.ActuatorType.None" in physical,
    "Physical motor transmits to mounted gears": "session.Gears:SetDrive(motor.ShaftId,motor.NativeSpeed" in physical,
    "Physical resolves actual rigid bearing supports": "BearingSupport.Resolve(" in physical,
    "Physical honors authored grounds only":
        "session.GroundKeys=explicitGround" in physical
        and "session.GroundKeys[edge.b]=true" not in physical
        and 'session.GroundKeys["p:"..tostring(id)]=nil' not in physical,
    "Physical servo/hold/toggle": all(x in physical for x in (
        'motor.DriveType=="Servo"', 'motor.InputMode=="Toggle"',
        "motor.Constraint.CurrentAngle")),
    "Rack motors register before kinematic skip": 'makeMotor(edge,nil,p1,runtime,true)' in rack,
    "Rack motors use actual kinematic solver": "if motorDrive then motorDrive.Speed" in rack
        and "session.Gears:Step(dt," in rack,
    "Rack resolves actual rigid bearing supports": "BearingSupport.Resolve(" in rack,
    "Rack servo/hold/toggle": all(x in rack for x in (
        'motor.DriveType=="Servo"', 'motor.InputMode=="Toggle"',
        "motor.ShaftId")),
    "Gear transmission accepts shaft commands": "function Transmission:SetDrive(id,speed,budget,worldAxis)" in transmission,
    "Kinematic solver accepts servo goals": "function Kinematics:Step(dt,drivenId,shaftAxis,inputSpeed,servoGoal)" in kinematics,
    "Runtime path is visible in Studio Output": "[OPENWORKS][SIM ROUTER]" in router,
    "Physical isolated bearings": "BearingSupport.Resolve(" in physical,
    "Rack isolated bearings": "BearingSupport.Resolve(" in rack,
    "Bearing support is validation only, NEVER automatic anchoring":
        "groundKeys is read-only here" in bearings
        and "groundKeys[key]=true" not in bearings
        and "grouped" not in bearings.lower(),
    "Physical motor angular limits do not torque housing":
        'and edge.relation:GetAttribute("MotorEnabled")~=true' in physical,
    "Rack motor angular limits do not torque housing":
        'and edge.relation:GetAttribute("MotorEnabled")~=true' in rack,
    "Rack honors authored grounds only":
        "session.GroundKeys=explicitGround" in rack
        and "session.GroundKeys[edge.b]=true" not in rack
        and 'session.GroundKeys["p:"..tostring(id)]=nil' not in rack,
    "Motor spin uses exact bearing hinge axis":
        "motor.Constraint.Attachment1.WorldAxis" in physical,
    "Authoring hinges never power the housing":
        "constraint.ActuatorType=Enum.ActuatorType.None" in mechanics
        and "hinge.ActuatorType=Enum.ActuatorType.None" in mechanics
        and "Enum.ActuatorType.Motor" not in mechanics,
    "Bearings reject shaft welded to housing": "shaftGroup==housingGroup" in bearings,
    "Fast gear stages have separate output ceiling": "local MAX_OUTPUT_SPEED=240" in transmission,
    "Gear ratios are still tooth-count based": "ratio=-left.Teeth/right.Teeth" in transmission,
    "Output drive torque follows ratio and load": "local outputTorque=drive.Weight/ratio" in transmission,
    "One-click connected assembly detection": "function Service:DetectConnected" in assembly,
    "Assembly detection traverses physical gear meshes": "GearMath.AutoMeshable" in assembly,
    "Assembly click sends detection request": 'action="DetectConnectedAssembly"' in assembly_tool,
}
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
if not all(checks.values()):
    raise SystemExit("Active motor runtime source regression detected")
print("Source routing checks passed; test live motor physics in Studio.")
