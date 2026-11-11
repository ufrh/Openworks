--!strict
-- OPENWORKS phase 01: native first-person tools and camera controls.
-- The launcher reads this marker to report the local client build.
local BUILD = "2026.11.10.STUDIO-UI-VISUAL-REFINEMENT"

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
local WorldVisuals = require(controllers:WaitForChild("WorldVisuals"))
local PlotSaveController = require(controllers:WaitForChild("PlotSaveController"))

FORGE.Start({ Roots = {} })

local camera = CameraController.new()
camera:Start()

local tools = ToolController.new()
tools:Start()

local constructionController = ConstructionController.new(tools)
local assemblyController = AssemblyController.new(tools)
-- A single Edit tool owns both primitive operations and joint authoring;
-- the companion controller exclusively owns Simulate actions on tool 3.
constructionController.Assembly = assemblyController
assemblyController.Construction = constructionController
constructionController:Start()
assemblyController:Start()

local contextKeybinds = ContextKeybinds.new(
    tools, constructionController, assemblyController
)
contextKeybinds:Start()

local worldVisuals = WorldVisuals.new()
worldVisuals:Start()

local plotSave = PlotSaveController.new()
plotSave:Start()

local entries = PrimitiveRegistry.List()
if not PrimitiveRegistry.IsAvailable() then
    warn("[OPENWORKS] Primitive library not found in ReplicatedStorage; run the Studio generator and save the place.")
else
    print(string.format("[OPENWORKS] Registered %d Studio primitive templates", #entries))
end

print(string.format("[OPENWORKS] %s | FORGE %s | Studio-style UI / adornment joints / locked-mouse crank ready", BUILD, tostring(FORGE.Version)))
