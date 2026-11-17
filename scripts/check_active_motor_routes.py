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

checks = {
    "ConstructionService boots Unified": 'require(script.Parent:WaitForChild("UnifiedSimulationService"))' in construction,
    "Unified dispatches Physical/Rack": "return if rack then self.Rack else self.Physical" in router,
    "Physical shaft-only actuator": 'drive.Name="PoweredMotor_ShaftOnlyDrive"' in physical,
    "Physical bearing is passive": "constraint.ActuatorType=Enum.ActuatorType.None" in physical,
    "Physical motor transmits to mounted gears": "session.Gears:SetDrive(motor.ShaftId,motor.NativeSpeed" in physical,
    "Physical always anchors stator": "for key in pairs(motorStators)" in physical,
    "Physical frees motor rotor group": 'session.GroundKeys["p:"..tostring(id)]=nil' in physical,
    "Physical servo/hold/toggle": all(x in physical for x in (
        'motor.DriveType=="Servo"', 'motor.InputMode=="Toggle"',
        "motor.Constraint.CurrentAngle")),
    "Rack motors register before kinematic skip": 'makeMotor(edge,nil,p1,runtime,true)' in rack,
    "Rack motors use actual kinematic solver": "if motorDrive then motorDrive.Speed" in rack
        and "session.Gears:Step(dt," in rack,
    "Rack always anchors stator": "for key in pairs(motorStators)" in rack,
    "Rack servo/hold/toggle": all(x in rack for x in (
        'motor.DriveType=="Servo"', 'motor.InputMode=="Toggle"',
        "motor.ShaftId")),
    "Gear transmission accepts shaft commands": "function Transmission:SetDrive(id,speed,budget,worldAxis)" in transmission,
    "Kinematic solver accepts servo goals": "function Kinematics:Step(dt,drivenId,shaftAxis,inputSpeed,servoGoal)" in kinematics,
    "Runtime path is visible in Studio Output": "[OPENWORKS][SIM ROUTER]" in router,
}
for label, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {label}")
if not all(checks.values()):
    raise SystemExit("Active motor runtime source regression detected")
print("Source routing checks passed; test live motor physics in Studio.")
