--!strict
-- OPENWORKS runtime build stamp. This is deliberately created BEFORE
-- requiring FORM or the gizmo. If any module fails during startup, Studio
-- still shows which entry script it actually executed.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BUILD = "2026.11.06.02"
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
local gizmoModule = script:FindFirstChild("TransformGizmo")
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

local debugModule = script:WaitForChild("FORMDebug")
local loaded, Debug = pcall(require, debugModule)
if not loaded then
	displayStatus("BOOT ERROR", "FORMDebug require failed", true)
	warn("[OPENWORKS] FORMDebug require failed: " .. tostring(Debug))
	return
end
local started, errorMessage = pcall(Debug.start)
if not started then
	displayStatus("BOOT ERROR", "FORMDebug.start failed", true)
	warn("[OPENWORKS] FORMDebug startup failed: " .. tostring(errorMessage))
	return
end

displayStatus("READY", "FORM viewport active", false)
print("[OPENWORKS] BUILD " .. BUILD .. " / FORM READY")
