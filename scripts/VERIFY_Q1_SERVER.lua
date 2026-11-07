--!strict
-- Run in Studio SERVER command bar.
local RunService=game:GetService("RunService")
assert(RunService:IsServer(),"Run on server")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local FORGE=require(ReplicatedStorage:WaitForChild("FORGE"))
assert(FORGE.Version=="4.4.1")
local report=FORGE.GetBootReport()
assert(report,"FORGE server boot report unavailable")
assert(game:GetService("ReplicatedStorage"):FindFirstChild("__FORGE_NETWORK"),
 "FORGE secure transport is not mounted")
print("OPENWORKS Q1 SERVER PASS: FORGE "..FORGE.Version.." and secure networking")
