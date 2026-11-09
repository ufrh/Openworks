--!strict
-- OPENWORKS phase 01: native first-person tools and camera controls.
-- The launcher reads this marker to report the local client build.
local BUILD = "2026.11.09.PHASE01.NATIVE-TOOLS"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FORGE = require(ReplicatedStorage:WaitForChild("FORGE"))
local Construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local PrimitiveRegistry = require(Construction:WaitForChild("PrimitiveRegistry"))

local controllers = script:WaitForChild("Controllers")
local CameraController = require(controllers:WaitForChild("CameraController"))
local ToolController = require(controllers:WaitForChild("ToolController"))

FORGE.Start({ Roots = {} })

local camera = CameraController.new()
camera:Start()

local tools = ToolController.new()
tools:Start()

local entries = PrimitiveRegistry.List()
if not PrimitiveRegistry.IsAvailable() then
    warn("[OPENWORKS] Primitive library not found in ReplicatedStorage; run the Studio generator and save the place.")
else
    print(string.format("[OPENWORKS] Registered %d Studio primitive templates", #entries))
end

print(string.format("[OPENWORKS] %s | FORGE %s | Phase 01 client ready", BUILD, tostring(FORGE.Version)))
