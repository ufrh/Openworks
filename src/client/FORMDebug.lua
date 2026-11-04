--!strict
-- Temporary FORM construction harness. Intentionally not a Duotone UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Document = require(FORM.Document)
local Compiler = require(FORM.Compiler)
local Quantize = require(FORM.Quantize)
local Preview = require(script.Parent.Preview)
local BlenderCamera = require(script.Parent.BlenderCamera)
local GridOverlay = require(script.Parent.GridOverlay)
local ViewGizmo = require(script.Parent.ViewGizmo)
local TransformGizmo = require(script.Parent.TransformGizmo)
local SketchEditor = require(script.Parent.SketchEditor)
local ToolVisualizer = require(script.Parent.ToolVisualizer)

local Debug = {}

local function make(className: string, properties, parent: Instance)
	local obj = Instance.new(className)
	for key, value in pairs(properties) do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

function Debug.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local document = Document.new()
	local selectedId: number? = nil
	local nodeIndex = 1
	local cameraController: any = nil
	local activeTool: string? = nil
	local sawFirst = nil
	local meshSaw = true
	local historyInfo: any = nil
	local historyRows = {}
	local sketchEditor: any = nil
	local toolVisualizer = ToolVisualizer.new(playerGui)
	local drillThrough = true

	local grid = GridOverlay.new(playerGui)

	local gui = make("ScreenGui", {
		Name = "FORM_DebugUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	local panel = make("Frame", {
		Name = "Controls",
		BackgroundColor3 = Color3.fromRGB(25, 29, 33),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(314, 595),
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, panel)

	local title = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = "FORM // DEBUG 01",
		TextColor3 = Color3.fromRGB(231, 236, 239),
		Font = Enum.Font.Code,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 28),
	}, panel)
	local status = make("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Text = "Local prototype. No server shipping or saving.",
		TextColor3 = Color3.fromRGB(159, 198, 204),
		Font = Enum.Font.Code,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromOffset(12, 544),
		Size = UDim2.new(1, -24, 0, 47),
	}, panel)
	local scroll = make("ScrollingFrame", {
		Name = "Editor",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Position = UDim2.fromOffset(10, 38),
		Size = UDim2.new(1, -20, 0, 505),
	}, panel)
	make("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, scroll)

	local layoutOrder = 0
	local function row(height: number)
		layoutOrder += 1
		return make("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = layoutOrder,
			Size = UDim2.new(1, -8, 0, height),
		}, scroll)
	end
	local function line(text: string, height: number?)
		local container = row(height or 20)
		return make("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			Text = text,
			TextColor3 = Color3.fromRGB(184, 195, 200),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromScale(1, 1),
		}, container)
	end
	local function button(parent: Instance, text: string, x: number, width: number, callback)
		local control = make("TextButton", {
			AutoButtonColor = true,
			BackgroundColor3 = Color3.fromRGB(56, 63, 70),
			BorderSizePixel = 0,
			Font = Enum.Font.Code,
			Text = text,
			TextColor3 = Color3.fromRGB(235, 238, 240),
			TextSize = 13,
			Position = UDim2.new(x, 0, 0, 0),
			Size = UDim2.new(width, -4, 1, 0),
		}, parent)
		make("UICorner", { CornerRadius = UDim.new(0, 3) }, control)
		control.MouseButton1Click:Connect(callback)
		return control
	end
	local function pair(left: string, leftFn, right: string, rightFn)
		local container = row(29)
		button(container, left, 0, 0.5, leftFn)
		button(container, right, 0.5, 0.5, rightFn)
	end
	local function message(value: string)
		status.Text = value
		print("[FORM] " .. value)
	end

	local info = line("Selection: none")
	local nodeInfo = line("Node: none")

	local highlight = make("Highlight", {
		Name = "FORM_Selection",
		FillTransparency = 1,
		OutlineTransparency = 0,
		OutlineColor = Color3.fromRGB(100, 234, 246),
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
	}, workspace)

	local preview
	local transformGizmo: any = nil
	local textFields = {}
	local function selectedComponent()
		return if selectedId then document.components[selectedId] else nil
	end
	local function selectedNode()
		local component = selectedComponent()
		return if component then component.nodes[nodeIndex] else nil
	end
	local function displayNumber(value: number): string
		return string.format("%.2f", value)
	end
	local function refresh()
		local component = selectedComponent()
		local node = selectedNode()
		info.Text = if component then ("Selection: " .. component.name) else "Selection: none"
		nodeInfo.Text = if node then ("Material: " .. node.kind) else "Material: none"
		if historyInfo then
			local active = 0
			if component then
				for _, feature in ipairs(component.operations) do
					if feature.enabled ~= false then active += 1 end
				end
			end
			historyInfo.Text = if component
				then string.format("Fabrication: %d features (%d active)", #component.operations, active)
				else "Fabrication: no material selected"
		end
		for slot, entry in ipairs(historyRows) do
			local operation = if component
				then component.operations[#component.operations - slot + 1] else nil
			entry.container.Visible = operation ~= nil
			if operation then
				local description
				if operation.kind == "SketchExtrude" then
					description = "SKETCH " .. string.upper(operation.mode) .. " (" .. #operation.points .. "p)"
				elseif operation.kind == "Drill" then
					description = string.format("DRILL Ø%.0f%s", operation.diameter * 280,
						if operation.through == false then " BLIND" else "")
				elseif operation.kind == "Inset" then
					description = string.format("INSET %.0fmm", operation.margin * 280)
				elseif operation.kind == "File" then
					description = string.format("FILE %s %.0fmm", operation.edge, operation.width * 280)
				elseif operation.kind == "Groove" then
					description = string.format("GROOVE %.0fmm", operation.kerf * 280)
				else
					description = string.format("KERF %.0fmm", operation.kerf * 280)
				end
				entry.label.Text = string.format("%02d %s", operation.id, description)
				entry.label.TextColor3 = if operation.enabled == false
					then Color3.fromRGB(120, 135, 143)
					else Color3.fromRGB(216, 231, 236)
				entry.toggle.Text = if operation.enabled == false then "OFF" else "ON"
				entry.toggle.BackgroundColor3 = if operation.enabled == false
					then Color3.fromRGB(57, 66, 76)
					else Color3.fromRGB(46, 97, 86)
			end
		end
		for _, binding in ipairs(textFields) do
			local box = binding.box
			local value = nil
			if node then
				local property = if binding.field == "position" then Document.minCorner(node) else node[binding.field]
				if binding.axis ~= " " then
					value = property[binding.axis]
				end
			end
			if not box:IsFocused() then
				box.Text = if value ~= nil then displayNumber(value) else "-"
			end
		end
		local model = if component then preview:getModel(component.id) else nil
		highlight.Adornee = model
		highlight.Enabled = model ~= nil
		if transformGizmo then
			if component and node then
				transformGizmo:show(component, nodeIndex)
			else
				transformGizmo:hide()
			end
		end
	end

	preview = Preview.new(message, function(id)
		if id == selectedId then refresh() end
	end)

	local function selectComponent(id: number?)
		selectedId = id
		local component = selectedComponent()
		nodeIndex = if component then #component.nodes else 1
		refresh()
	end

	local function changed(component)
		preview:render(component)
		refresh()
	end

	transformGizmo = TransformGizmo.new(playerGui, document, function(phase: string, component, index: number, dirty: boolean?)
		if phase == "begin" then
			preview:beginLive(component, index)
		elseif phase == "update" then
			-- Update the existing solid immediately; no duplicate ghost.
			preview:updateLive(component, index)
			refresh()
		elseif phase == "finish" then
			if dirty then
				preview:finishLive(component)
			else
				preview:cancelLive(component.id)
			end
			refresh()
		end
	end)

	line("CREATE COMPONENT")
	local function create(kind: string)
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		-- Fresh geometry begins at the locked workspace origin.
		local component = document:create(kind, Vector3.zero)
		selectComponent(component.id)
		changed(component)
		if cameraController then cameraController:frameSelected() end
	end
	pair("Block", function() create("Block") end, "Cylinder", function() create("Cylinder") end)
	line("Material corner starts on grid lines.", 22)
	line("FABRICATION TOOLS // TOP FACE")
	local toolStatus = line("Tool: none")
	historyInfo = line("Fabrication: 0 cuts")
	local function setTool(kind: string?)
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		activeTool = kind
		sawFirst = nil
		toolVisualizer:hide()
		if kind then
			transformGizmo:setHidden(true)
			toolStatus.Text = "Tool: " .. string.upper(kind)
			local guidance = {
				Drill = "Drill: hover for depth preview; wheel adjusts diameter; click to bore",
				Inset = "Inset: hover top face and click to make a rectangular pocket",
				File = "File: hover near a top stock edge and click to chamfer it",
				Groove = "Groove: click start then end to cut a channel",
				Kerf = "Kerf: click start then end for a through slot",
			}
			message(guidance[kind] or "Choose a fabrication operation")
		else
			transformGizmo:setMode("Move")
			toolStatus.Text = "Tool: none"
			message("Fabrication tool cleared")
		end
	end
	pair("Drill", function() setTool("Drill") end, "Saw (Profile)", function()
		local component = selectedComponent()
		if not component then message("Select a workpiece before using Saw") return end
		if not sketchEditor then message("Sketch workspace unavailable") return end
		activeTool, sawFirst = nil, nil
		toolVisualizer:hide()
		toolStatus.Text = "Tool: SAW"
		sketchEditor:start(component, "Saw")
		transformGizmo:setHidden(true)
	end)
	pair("Inset / Pocket", function() setTool("Inset") end,
		"File Edge", function() setTool("File") end)
	pair("Groove", function() setTool("Groove") end,
		"Straight Kerf", function() setTool("Kerf") end)
	pair("Sketch / Extrude", function()
		local component = selectedComponent()
		if not component then message("Create or select a workpiece first") return end
		if not sketchEditor then message("Sketch workspace is not initialized") return end
		activeTool = nil
		sawFirst = nil
		toolVisualizer:hide()
		transformGizmo:setHidden(true)
		toolStatus.Text = "Tool: SKETCH"
		sketchEditor:start(component)
		transformGizmo:setHidden(true)
	end, "New Body Sketch", function()
		if not sketchEditor then message("Sketch workspace is not initialized") return end
		activeTool = nil
		sawFirst = nil
		toolVisualizer:hide()
		transformGizmo:setHidden(true)
		toolStatus.Text = "Tool: NEW BODY"
		sketchEditor:start(nil)
		transformGizmo:setHidden(true)
	end)
	pair("Exit Tool", function() setTool(nil) end, "Undo Last Cut", function()
		local component = selectedComponent()
		if not component then message("Select a material first") return end
		sawFirst = nil
		local ok, reason = document:undoOperation(component)
		if ok then changed(component) message("Last fabrication cut removed")
		else message(reason) end
	end)
	local function toolNumberRow(caption: string, initial: string)
		local container = row(30)
		make("TextLabel", {
			BackgroundTransparency = 1, Font = Enum.Font.Code,
			Text = caption, TextSize = 12, TextColor3 = Color3.fromRGB(184, 195, 200),
			TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.65, 0, 1, 0),
		}, container)
		local input = make("TextBox", {
			BackgroundColor3 = Color3.fromRGB(45, 51, 56),
			BorderSizePixel = 0, ClearTextOnFocus = false,
			Font = Enum.Font.Code, TextSize = 13, Text = initial,
			TextColor3 = Color3.fromRGB(235, 238, 240),
			Position = UDim2.new(0.65, 0, 0, 1), Size = UDim2.new(0.35, -4, 1, -2),
		}, container)
		make("UICorner", { CornerRadius = UDim.new(0, 3) }, input)
		return input
	end
	line("DRILL  /  PRECISION CONTROLS")
	local diameterInput = toolNumberRow("Diameter (mm)  [wheel]", "56")
	local drillDepthInput = toolNumberRow("Blind depth (mm)", "28")
	local throughRow = row(29)
	local throughButton: TextButton? = nil
	throughButton = button(throughRow, "Drill: THROUGH (click to toggle)", 0, 1, function()
		drillThrough = not drillThrough
		if throughButton then
			throughButton.Text = if drillThrough then "Drill: THROUGH (click to toggle)"
				else "Drill: BLIND (click to toggle)"
		end
	end)
	line("Wheel: diameter ±2mm   Shift+Wheel: ±10mm", 20)
	line("POCKET  /  GROOVE  /  EDGE")
	local insetMarginInput = toolNumberRow("Inset border (mm)", "28")
	local insetDepthInput = toolNumberRow("Inset depth (mm)", "28")
	local grooveWidthInput = toolNumberRow("Groove width (mm)", "28")
	local grooveDepthInput = toolNumberRow("Groove depth (mm)", "28")
	local fileWidthInput = toolNumberRow("File chamfer (mm)", "14")
	local kerfInput = toolNumberRow("Through kerf (mm)", "14")
	local meshRow = row(29)
	local meshButton: any
	meshButton = button(meshRow, "EditableMesh kerf: ON (native fallback)", 0, 1, function()
		meshSaw = not meshSaw
		meshButton.Text = "EditableMesh kerf: " .. (if meshSaw then "ON" else "OFF")
	end)
	line("Groove/Kerf: click start, then end on top face.", 24)

	line("3D TRANSFORM HANDLES")
	local transformStatus = line("Mode: MOVE (G)")
	local function setTransformMode(mode: string)
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		toolVisualizer:hide()
		activeTool = nil
		sawFirst = nil
		toolStatus.Text = "Tool: none"
		transformGizmo:setMode(mode)
		transformStatus.Text = "Mode: " .. string.upper(mode)
	end
	pair("Move [G]", function() setTransformMode("Move") end,
		"Scale [S]", function() setTransformMode("Scale") end)
	pair("Rotate [R]", function() setTransformMode("Rotate") end,
		"Hide Handles", function()
			transformGizmo:setHidden(true)
			transformStatus.Text = "Mode: HIDDEN (G/S/R)"
		end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if sketchEditor and sketchEditor.active then return end
		if processed or UserInputService:GetFocusedTextBox() then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == Enum.KeyCode.G then
			setTransformMode("Move")
		elseif input.KeyCode == Enum.KeyCode.S then
			setTransformMode("Scale")
		elseif input.KeyCode == Enum.KeyCode.R then
			setTransformMode("Rotate")
		end
	end)

	line("MATERIAL ENVELOPE EDITOR")
	line("Boundary snap 0.05 / rotation 15°")
	local function editRow(label: string, field: string, axes)
		local container = row(32)
		make("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Code,
			Text = label,
			TextColor3 = Color3.fromRGB(184, 195, 200),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0, 45, 1, 0),
		}, container)
		for index, axis in ipairs(axes) do
			local slot = make("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 45 + (index - 1) * 80, 0, 0),
				Size = UDim2.fromOffset(77, 32),
			}, container)
			make("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.Code,
				Text = axis or " ",
				TextColor3 = Color3.fromRGB(137, 149, 158),
				TextSize = 12,
				Size = UDim2.fromOffset(15, 32),
			}, slot)
			local box = make("TextBox", {
				BackgroundColor3 = Color3.fromRGB(45, 51, 56),
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				Font = Enum.Font.Code,
				Text = "-",
				TextColor3 = Color3.fromRGB(235, 238, 240),
				TextSize = 13,
				Position = UDim2.fromOffset(17, 2),
				Size = UDim2.fromOffset(59, 27),
			}, slot)
			make("UICorner", { CornerRadius = UDim.new(0, 3) }, box)
			table.insert(textFields, { box = box, field = field, axis = axis })
			box.FocusLost:Connect(function()
				local component = selectedComponent()
				if not component then refresh() return end
				local value = tonumber(box.Text)
				local axisArgument = if axis == " " then nil else axis
				local ok, reason = document:editNode(component, nodeIndex, field, axisArgument, value :: any)
				if not ok then message(reason) else changed(component) end
				refresh()
			end)
		end
	end
	editRow("MIN", "position", { "X", "Y", "Z" })
	editRow("SIZE", "size", { "X", "Y", "Z" })
	editRow("ROT", "rotation", { "X", "Y", "Z" })

	line("FEATURE HISTORY  /  LAST 6")
	for slot = 1, 6 do
		local entry = row(27)
		local label = make("TextLabel", {
			BackgroundTransparency = 1, Text = "",
			Font = Enum.Font.Code, TextSize = 11,
			TextColor3 = Color3.fromRGB(215, 228, 234),
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.64, 0, 1, 0),
		}, entry)
		local toggle = button(entry, "ON", 0.65, 0.18, function()
			local component = selectedComponent()
			local operation = component and component.operations[#component.operations - slot + 1]
			if not operation then return end
			local ok, reason = document:setOperationEnabled(component, operation.id, operation.enabled == false)
			if ok then changed(component) else message(reason) end
		end)
		button(entry, "X", 0.84, 0.16, function()
			local component = selectedComponent()
			local operation = component and component.operations[#component.operations - slot + 1]
			if not operation then return end
			local ok, reason = document:removeOperation(component, operation.id)
			if ok then changed(component) else message(reason) end
		end)
		table.insert(historyRows, { container = entry, label = label, toggle = toggle })
		entry.Visible = false
	end

	local deleteRow = row(29)
	button(deleteRow, "Delete Component", 0, 1, function()
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		local component = selectedComponent()
		if not component then message("No selection") return end
		preview:remove(component.id)
		document:removeComponent(component.id)
		selectComponent(document.order[#document.order])
		message("Component removed")
	end)


	-- Read the actual compiled solid when available; fall back to editable node dimensions.
	local function selectionBounds()
		local component = selectedComponent()
		if not component then return nil, nil end
		local model = preview:getModel(component.id)
		if model then return model:GetBoundingBox() end
		local node = component.nodes[1]
		return CFrame.new(node.position), node.size
	end

	local function sceneBounds()
		local minimum: Vector3? = nil
		local maximum: Vector3? = nil
		for _, id in ipairs(document.order) do
			local component = document.components[id]
			local model = preview:getModel(id)
			local frame: CFrame
			local size: Vector3
			if model then
				frame, size = model:GetBoundingBox()
			else
				local node = component.nodes[1]
				frame = CFrame.new(node.position)
				size = node.size
			end
			local half = size / 2
			for _, x in ipairs({ -1, 1 }) do
				for _, y in ipairs({ -1, 1 }) do
					for _, z in ipairs({ -1, 1 }) do
						local corner = frame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						if minimum then
							minimum = Vector3.new(math.min(minimum.X, corner.X), math.min(minimum.Y, corner.Y), math.min(minimum.Z, corner.Z))
							maximum = Vector3.new(math.max(maximum.X, corner.X), math.max(maximum.Y, corner.Y), math.max(maximum.Z, corner.Z))
						else
							minimum = corner
							maximum = corner
						end
					end
				end
			end
		end
		if not minimum or not maximum then return nil, nil end
		return CFrame.new((minimum + maximum) / 2), maximum - minimum
	end


	cameraController = BlenderCamera.new(selectionBounds, sceneBounds)
	pair("Zoom Selected (F)", function()
		if not cameraController:frameSelected() then message("Select a component first") end
	end, "Zoom All (Home)", function()
		if not cameraController:frameAll() then message("No components to frame") end
	end)
	line("RMB / MMB drag: orbit origin", 24)
	line("Ctrl+MMB / wheel: hybrid zoom", 24)
	line("Numpad 1/3/7 views | 5 ortho", 24)
	line("F / Home: zoom only (fixed origin)", 24)
	line("Drag view gizmo; drag zoom control", 24)

	local viewGizmo = ViewGizmo.new(gui, cameraController)
	cameraController:setOnFrame(function(cameraFrame, label)
		viewGizmo:update(cameraFrame, label)
	end)
	sketchEditor = SketchEditor.new(playerGui, cameraController,
		function(component, data)
			if component then
				local ok, reason = document:addOperation(component, "SketchExtrude", data)
				if ok then changed(component) end
				return ok, reason
			end
			-- Standalone sketch: construct a snapped bounding workpiece, then
			-- intersect it with the sketched through-extrusion. The retained
			-- result is a normal CSG solid, not a persistent EditableMesh.
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			for _, p in ipairs(data.points) do
				minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
				minZ, maxZ = math.min(minZ, p.Y), math.max(maxZ, p.Y)
			end
			local width, length = maxX - minX, maxZ - minZ
			if width < Quantize.MinSize or length < Quantize.MinSize then
				return false, "New body sketch is smaller than the minimum workpiece"
			end
			-- Give the temporary intersection block a little lateral overlap.
			-- Coplanar sketch/bounds walls can create unreliable CSG seams;
			-- this extra stock gets discarded by IntersectAsync, leaving the
			-- authored sketch dimensions completely unchanged.
			local margin = Quantize.Grid * 2
			local body = document:create("Block", Vector3.new(minX - margin, 0, minZ - margin))
			for _, axisInfo in ipairs({
				{ "X", width + 2 * margin },
				{ "Y", data.depth },
				{ "Z", length + 2 * margin },
			}) do
				local ok, reason = document:editNode(body, 1, "size", axisInfo[1], axisInfo[2])
				if not ok then
					document:removeComponent(body.id)
					return false, reason
				end
			end
			local middleX = (minX + maxX) * 0.5
			local middleZ = (minZ + maxZ) * 0.5
			local localPoints = {}
			for _, p in ipairs(data.points) do
				table.insert(localPoints, Vector2.new(p.X - middleX, p.Y - middleZ))
			end
			local ok, reason = document:addOperation(body, "SketchExtrude", {
				points = localPoints, mode = "Intersect",
				depth = data.depth, through = true,
			})
			if not ok then
				document:removeComponent(body.id)
				return false, reason
			end
			selectComponent(body.id)
			changed(body)
			return true, nil
		end,
		message,
		function()
			transformGizmo:setMode("Move")
			toolStatus.Text = "Tool: none"
			transformStatus.Text = "Mode: MOVE (G)"
		end
	)


	-- The mouse wheel is handed to an active precision drill, otherwise it
	-- retains the BlenderCamera dolly/FOV zoom behavior.
	cameraController:setWheelHandler(function(steps: number): boolean
		if activeTool ~= "Drill" or UserInputService:GetFocusedTextBox() then return false end
		local current = tonumber(diameterInput.Text) or 56
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local increment = if shift then 10 else 2
		local node = selectedNode()
		local cap = if node then math.max(5, math.min(node.size.X, node.size.Z) * 280) else 2000
		local nextMM = math.clamp(math.round(current + steps * increment), 5, cap)
		diameterInput.Text = string.format("%.0f", nextMM)
		return true
	end)

	local function millimeters(box: TextBox, label: string): (number?, string?)
		local mm = tonumber(box.Text)
		if not mm or not Quantize.isFinite(mm) or mm < 5 or mm > 35840 then
			return nil, label .. " must be between 5 mm and 35840 mm"
		end
		return mm / 280, nil
	end

	local function nearestTopEdge(node, localPoint: Vector3): (string?, number)
		if node.kind ~= "Block" then return nil, math.huge end
		local hx, hz = node.size.X / 2, node.size.Z / 2
		local edge, distance = nil, math.huge
		for _, option in ipairs({
			{ "X+", math.abs(localPoint.X - hx) },
			{ "X-", math.abs(localPoint.X + hx) },
			{ "Z+", math.abs(localPoint.Z - hz) },
			{ "Z-", math.abs(localPoint.Z + hz) },
		}) do
			if option[2] < distance then edge, distance = option[1], option[2] end
		end
		return if distance <= math.min(0.18, math.min(node.size.X, node.size.Z) * 0.40)
			then edge else nil, distance
	end

	-- Only ever raycast the actual manufactured geometry. Tool indicators
	-- are CanQuery=false so the ghost itself cannot steal the mouse.
	local function fabricationHit()
		if not activeTool or (sketchEditor and sketchEditor.active) then return nil end
		if UserInputService:GetFocusedTextBox() or cameraController.dragging then return nil end
		local mouse = UserInputService:GetMouseLocation()
		if mouse.X < 345 and mouse.Y < 615 then return nil end
		local camera = workspace.CurrentCamera
		if not camera then return nil end
		if mouse.X > camera.ViewportSize.X - 340 and mouse.Y > 225 and mouse.Y < 610 then return nil end
		if viewGizmo:containsPoint(mouse) or transformGizmo:capturesPoint(mouse) then return nil end
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { preview.root }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		if not hit then return nil end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local id = if model then model:GetAttribute("FORMComponentId") else nil
		local component = if typeof(id) == "number" then document.components[id] else nil
		if not component then return nil end
		local node = component.nodes[1]
		local pose = Compiler.pose(node)
		local normal = pose:VectorToObjectSpace(hit.Normal)
		if normal.Y < 0.72 then return nil end
		local localPoint = pose:PointToObjectSpace(hit.Position)
		local x = Quantize.snap(localPoint.X, Quantize.Grid)
		local z = Quantize.snap(localPoint.Z, Quantize.Grid)
		return { component = component, id = id, node = node, pose = pose,
			point = localPoint, x = x, z = z }
	end

	RunService.RenderStepped:Connect(function()
		local target = fabricationHit()
		if not target then toolVisualizer:hide() return end
		local node, pose = target.node, target.pose
		if activeTool == "Drill" then
			local diameter = millimeters(diameterInput, "Diameter")
			local depth = millimeters(drillDepthInput, "Drill depth")
			if not diameter or not depth then toolVisualizer:hide() return end
			toolVisualizer:drill(pose, node, target.x, target.z,
				diameter, depth, drillThrough)
		elseif activeTool == "Inset" then
			local margin = millimeters(insetMarginInput, "Inset border")
			local depth = millimeters(insetDepthInput, "Inset depth")
			if not margin or not depth or node.kind ~= "Block"
				or margin * 2 >= math.min(node.size.X, node.size.Z) then
				toolVisualizer:hide() return
			end
			toolVisualizer:inset(pose, node, margin, depth)
		elseif activeTool == "File" then
			local width = millimeters(fileWidthInput, "File width")
			local edge = nearestTopEdge(node, target.point)
			if not edge or not width then toolVisualizer:hide() return end
			toolVisualizer:file(pose, node, edge, width)
		elseif activeTool == "Groove" or activeTool == "Kerf" then
			if sawFirst and sawFirst.id == target.id then
				local box = if activeTool == "Groove" then grooveWidthInput else kerfInput
				local width = millimeters(box, "Cut width")
				local depth = if activeTool == "Groove"
					then millimeters(grooveDepthInput, "Groove depth") else node.size.Y
				if width and depth then
					toolVisualizer:groove(pose, node,
						Vector2.new(sawFirst.x, sawFirst.z), Vector2.new(target.x, target.z),
						width, depth)
				else
					toolVisualizer:hide()
				end
			else
				toolVisualizer:hide()
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if sketchEditor and sketchEditor.active then return end
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then return end
		local target = fabricationHit()
		if not target then
			-- Selection still works when the editor is not using a fabrication tool.
			if activeTool then return end
			local mouse = UserInputService:GetMouseLocation()
			if viewGizmo:containsPoint(mouse) or transformGizmo:capturesPoint(mouse) then return end
			local camera = workspace.CurrentCamera
			if not camera then return end
			local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { preview.root }
			local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
			if not hit then return end
			local model = hit.Instance:FindFirstAncestorOfClass("Model")
			local id = if model then model:GetAttribute("FORMComponentId") else nil
			if typeof(id) == "number" and document.components[id] then selectComponent(id) end
			return
		end
		if target.id ~= selectedId then selectComponent(target.id) sawFirst = nil end
		if not activeTool then return end
		local component, node = target.component, target.node
		local x, z = target.x, target.z
		local kind = activeTool
		local data = nil
		if kind == "Drill" then
			local diameter, errorA = millimeters(diameterInput, "Diameter")
			local depth, errorB = millimeters(drillDepthInput, "Drill depth")
			if not diameter or not depth then message(errorA or errorB) return end
			data = { x = x, z = z, diameter = diameter,
				depth = depth, through = drillThrough }
		elseif kind == "Inset" then
			local margin, errorA = millimeters(insetMarginInput, "Inset border")
			local depth, errorB = millimeters(insetDepthInput, "Inset depth")
			if not margin or not depth then message(errorA or errorB) return end
			data = { margin = margin, depth = depth }
		elseif kind == "File" then
			local width, reason = millimeters(fileWidthInput, "File width")
			if not width then message(reason) return end
			local edge = nearestTopEdge(node, target.point)
			if not edge then message("Move closer to an upper stock perimeter edge") return end
			data = { edge = edge, width = width }
		elseif kind == "Groove" or kind == "Kerf" then
			if not sawFirst then
				sawFirst = { id = target.id, x = x, z = z }
				message("Start placed; click the same workpiece for the end of the cut")
				return
			end
			if sawFirst.id ~= target.id then
				sawFirst = nil
				message("Cut path must stay on the same workpiece")
				return
			end
			local widthBox = if kind == "Groove" then grooveWidthInput else kerfInput
			local width, errorA = millimeters(widthBox, "Cut width")
			local depth, errorB = node.size.Y, nil
			if kind == "Groove" then
				depth, errorB = millimeters(grooveDepthInput, "Groove depth")
			end
			if not width or not depth then message(errorA or errorB) return end
			data = {
				x1 = sawFirst.x, z1 = sawFirst.z, x2 = x, z2 = z,
				kerf = width, depth = depth, through = kind == "Kerf",
				useMesh = meshSaw and kind == "Kerf",
			}
			kind = if kind == "Kerf" then "Saw" else "Groove"
		else
			return
		end
		local ok, reason = document:addOperation(component, kind, data)
		if not ok then message(reason or "Unable to apply fabrication") return end
		if kind == "Saw" or kind == "Groove" then sawFirst = nil end
		changed(component)
		message(kind .. " operation recorded; compiling CSG")
	end)

	refresh()
	message("Surface sketches now support polygon extrusion (Add / Remove / Intersect).")
end

return Debug
