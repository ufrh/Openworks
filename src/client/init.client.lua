--!strict
-- OPENWORKS phase 01: native first-person tools and camera controls.
-- The launcher reads this marker to report the local client build.
local BUILD = "2026.11.09.PHASE05.PHYSICAL-CONTEXT"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FORGE = require(ReplicatedStorage:WaitForChild("FORGE"))
local Construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local PrimitiveRegistry = require(Construction:WaitForChild("PrimitiveRegistry"))

local controllers = script:WaitForChild("Controllers")
local CameraController = require(controllers:WaitForChild("CameraController"))
local ToolController = require(controllers:WaitForChild("ToolController"))
local ConstructionController = require(controllers:WaitForChild("ConstructionController"))
local AssemblyController = require(controllers:WaitForChild("AssemblyController"))
local ContextKeybinds = require(controllers:WaitForChild("ContextKeybinds"))

FORGE.Start({ Roots = {} })

local camera = CameraController.new()
camera:Start()

local tools = ToolController.new()
tools:Start()

local constructionController = ConstructionController.new(tools)
constructionController:Start()

local assemblyController = AssemblyController.new(tools)
assemblyController:Start()

local contextKeybinds = ContextKeybinds.new(
    tools, constructionController, assemblyController
)
contextKeybinds:Start()

local entries = PrimitiveRegistry.List()
if not PrimitiveRegistry.IsAvailable() then
    warn("[OPENWORKS] Primitive library not found in ReplicatedStorage; run the Studio generator and save the place.")
else
    print(string.format("[OPENWORKS] Registered %d Studio primitive templates", #entries))
end

print(string.format("[OPENWORKS] %s | FORGE %s | Phase 05 client ready", BUILD, tostring(FORGE.Version)))
