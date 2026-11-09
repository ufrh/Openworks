--!strict
-- OPENWORKS reset baseline. Game-specific systems intentionally not installed.
local BUILD = "2026.11.08.FRESH.START"
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FORGE = require(ReplicatedStorage:WaitForChild("FORGE"))
FORGE.Start({ Roots = {} })
print(string.format("[OPENWORKS] %s | FORGE %s | Client baseline ready", BUILD, tostring(FORGE.Version)))
