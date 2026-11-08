--!strict
-- OPENWORKS runtime build stamp. This is deliberately created BEFORE
-- requiring FORM or the gizmo. If any module fails during startup, Studio
-- still shows which entry script it actually executed.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BUILD = "2026.11.08.CAD-ASSEMBLY.1"
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local oldBadge = playerGui:FindFirstChild("OPENWORKS_BuildStamp")
if oldBadge then oldBadge:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "OPENWORKS_BuildStamp"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui:SetAttribute("Build", BUILD)
gui:SetAttribute("Source", "src/client/init.client.lua")
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Badge"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -16, 1, -16)
panel.Size = UDim2.fromOffset(330, 65)
panel.BorderSizePixel = 0
panel.BackgroundColor3 = Color3.fromRGB(22, 29, 33)
panel.BackgroundTransparency = 0.08
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 7)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Color = Color3.fromRGB(81, 113, 120)
stroke.Thickness = 1
stroke.Transparency = 0.35
stroke.Parent = panel

local function textLine(name: string, y: number, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(11, y)
	label.Size = UDim2.new(1, -22, 0, 18)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.TextColor3 = color
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = panel
	return label
end

local heading = textLine("Product", 5, 12, Color3.fromRGB(237, 245, 246))
heading.Text = if RunService:IsStudio() then "OPENWORKS  /  STUDIO DEV" else "OPENWORKS  /  DEV"
local revision = textLine("Revision", 24, 11, Color3.fromRGB(149, 209, 211))
revision.Text = "BUILD " .. BUILD .. "  |  GIZMO LOADING"
local status = textLine("Startup", 43, 10, Color3.fromRGB(197, 199, 203))
status.Text = "STARTING CLIENT..."

local function displayStatus(state: string, description: string, problem: boolean)
	status.Text = state .. "  /  " .. description
	status.TextColor3 = if problem then Color3.fromRGB(255, 149, 142)
		else Color3.fromRGB(139, 216, 169)
	gui:SetAttribute("State", state)
end

print("[OPENWORKS] CLIENT BUILD " .. BUILD .. " loaded from StarterPlayerScripts.Openworks")

-- Check the actual loaded gizmo ModuleScript, not a claim about the
-- GitHub branch. This exposes Rojo sync and require-cache mismatches.
local gizmoModule = script:FindFirstChild("Tools") and script.Tools:FindFirstChild("Transform") and script.Tools.Transform:FindFirstChild("TransformGizmo")
if gizmoModule and gizmoModule:IsA("ModuleScript") then
	local ok, loaded = pcall(require, gizmoModule)
	if ok and typeof(loaded) == "table" then
		local gizmoRevision = tostring(loaded.Revision or "UNSTAMPED")
		revision.Text = "BUILD " .. BUILD .. "  |  " .. gizmoRevision
		gui:SetAttribute("GizmoRevision", gizmoRevision)
		print("[OPENWORKS] TRANSFORM " .. gizmoRevision)
	else
		revision.Text = "BUILD " .. BUILD .. "  |  GIZMO LOAD ERROR"
		gui:SetAttribute("GizmoRevision", "ERROR")
		warn("[OPENWORKS] Gizmo module failed: " .. tostring(loaded))
	end
else
	revision.Text = "BUILD " .. BUILD .. "  |  GIZMO NOT SYNCED"
	gui:SetAttribute("GizmoRevision", "MISSING")
	warn("[OPENWORKS] TransformGizmo ModuleScript was not found at startup")
end

-- FORGE is the application runtime. Controllers are discovered through its
-- actual Loader/Registry/DependencyGraph/Lifecycle, not manual require().
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local forgeModule=ReplicatedStorage:WaitForChild("FORGE",15)
if not forgeModule then
	displayStatus("BOOT ERROR","FORGE not synced to ReplicatedStorage",true)
	return
end
local loaded,FORGE=pcall(require,forgeModule)
if not loaded then
	displayStatus("BOOT ERROR","FORGE require failed",true)
	warn("[OPENWORKS] FORGE require failed: "..tostring(FORGE))
	return
end
local controllerRoot=script:WaitForChild("Controllers",10)
if not controllerRoot then
	displayStatus("BOOT ERROR","OpenWorks FORGE Controllers missing",true)
	return
end
local started,errorMessage=pcall(function()
	FORGE.Start({Roots={controllerRoot}})
end)
if not started then
	displayStatus("BOOT ERROR","FORGE.Start failed",true)
	warn("[OPENWORKS] FORGE startup failed: "..tostring(errorMessage))
	return
end
local runtime=FORGE:GetController("OpenWorksRuntime")
if not runtime or runtime._Failed then
	displayStatus("BOOT ERROR","OpenWorksRuntime controller failed",true)
	warn("[OPENWORKS] FORGE controller not initialized; inspect FORGE boot report")
	return
end
gui:SetAttribute("FORGEVersion",tostring(FORGE.Version))
displayStatus("READY","FORGE "..tostring(FORGE.Version).." / Free · Edit · Assembly",false)
print("[OPENWORKS] BUILD "..BUILD.." / FORGE "..tostring(FORGE.Version).." READY")

