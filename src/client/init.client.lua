--!strict
-- OPENWORKS client bootstrap: native tools, Forge, editor and simulation controllers.
-- The launcher reads this marker to report the local client build.
local BUILD = "2026.11.12.UI-V2-PHASE5-ASSEMBLY-SIM"

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FORGE = require(ReplicatedStorage:WaitForChild("FORGE"))
local Construction = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("Construction")
local PrimitiveRegistry = require(Construction:WaitForChild("PrimitiveRegistry"))

local controllers = script:WaitForChild("Controllers")
local CameraController = require(controllers:WaitForChild("CameraController"))
local ToolController = require(controllers:WaitForChild("ToolController"))
local ConstructionController = require(controllers:WaitForChild("ConstructionController"))
local AssemblyController = require(controllers:WaitForChild("AssemblyController"))
local AssemblyToolController=require(controllers:WaitForChild("AssemblyToolController"))
local UnifiedExplorer = require(controllers:WaitForChild("UnifiedExplorer"))
local WorldVisuals = require(controllers:WaitForChild("WorldVisuals"))
local VisualFeedback = require(controllers:WaitForChild("VisualFeedback"))
local PlotSaveController = require(controllers:WaitForChild("PlotSaveController"))

FORGE.Start({ Roots = {} })

local camera = CameraController.new()
camera:Start()

local tools = ToolController.new()
tools:Start()

local feedback = VisualFeedback.new()
feedback:Start()

local constructionController = ConstructionController.new(tools)
local assemblyController = AssemblyController.new(tools)
local assemblyToolController=AssemblyToolController.new(tools)
constructionController.Feedback=feedback
assemblyController.Feedback=feedback
assemblyToolController.Feedback=feedback
-- Edit authors geometry/joints, Assembly names and chooses member sets,
-- and Simulate exclusively runs registered assemblies.
constructionController.Assembly = assemblyController
assemblyController.Construction = constructionController

-- A subtool hotkey must not steal a key already being used by a live
-- shaft-fit/precision interaction or an active modal.
tools:SetShortcutGuard(function(primary,current,_next,key)
    if constructionController.PendingMateChoice
        or constructionController.LockedAlignment
        or (constructionController.Numeric and constructionController.Numeric.Active)
        or (constructionController.Layered and constructionController.Layered.Alignment) then
        return false
    end
    if primary=="Mechanics" and current=="Connect"
        and key==Enum.KeyCode.E and assemblyController.ManualActive
        and (assemblyController.Stage=="Preview" or assemblyController.Stage=="Fit") then
        return false -- E is live shaft roll during fitting.
    end
    if assemblyToolController.Stage=="Naming" then return false end
    return true
end)

constructionController:Start()
assemblyController:Start()
assemblyToolController:Start()

local unifiedExplorer=UnifiedExplorer.new(tools,
    constructionController,assemblyController,assemblyToolController,feedback)
constructionController.UnifiedExplorer=unifiedExplorer
assemblyController.UnifiedExplorer=unifiedExplorer
assemblyToolController.UnifiedExplorer=unifiedExplorer
unifiedExplorer:Start()
-- Domain controllers started before the shared panel so they retain their
-- existing networking/camera initialization. Refresh once now that the dock
-- owns status/Properties; no legacy instruction HUD should linger on join.
constructionController:RefreshHUD()
assemblyController:RefreshHUD()
assemblyToolController:Refresh()
unifiedExplorer:OnConstructionSelection()

local worldVisuals = WorldVisuals.new(feedback)
worldVisuals:Start()

local plotSave = PlotSaveController.new()
plotSave:Start()

local entries = PrimitiveRegistry.List()
if not PrimitiveRegistry.IsAvailable() then
    warn("[OPENWORKS] Primitive library not found in ReplicatedStorage; run the Studio generator and save the place.")
else
    print(string.format("[OPENWORKS] Registered %d Studio primitive templates", #entries))
end

print(string.format("[OPENWORKS] %s | FORGE %s | UI v2 phase 5 / unified assembly and simulation workspace", BUILD, tostring(FORGE.Version)))
