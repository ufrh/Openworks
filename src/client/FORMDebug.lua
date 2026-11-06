--!strict
-- Temporary FORM construction harness. Intentionally not a Duotone UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Document = require(FORM.Document)
local Compiler = require(FORM.Compiler)
local Fabricator = require(FORM.Fabricator)
local GeometryCutter = require(FORM.GeometryCutter)
local Quantize = require(FORM.Quantize)
local Preview = require(script.Parent.Preview)
local BlenderCamera = require(script.Parent.BlenderCamera)
local GridOverlay = require(script.Parent.GridOverlay)
local ViewGizmo = require(script.Parent.ViewGizmo)
local TransformGizmo = require(script.Parent.TransformGizmo)
local SketchEditor = require(script.Parent.SketchEditor)
local ToolVisualizer = require(script.Parent.ToolVisualizer)
local SurfacePicker = require(script.Parent.SurfacePicker)
local FaceTools = require(FORM.FaceTools)

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
	local historyInfo: any = nil
	local historyRows = {}
	local sketchEditor: any = nil
	local toolVisualizer = ToolVisualizer.new(playerGui)
	local surfacePicker: any = nil
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

	-- Explicit adornment border instead of an outline-only Highlight.
	-- SelectionBox outlines the selected solid's bounding volume;
	-- it does not attempt CSG mesh readback for an exact contour.
	local selectionBorder = make("SelectionBox", {
		Name = "FORM_SelectionBorder",
		Color3 = Color3.fromRGB(100, 234, 246),
		LineThickness = 0.018,
		SurfaceTransparency = 1,
		Transparency = 0.08,
		Visible = false,
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
				elseif operation.kind == "Drill" or operation.kind == "DrillFace" then
					description = string.format("DRILL Ø%.0f%s", operation.diameter * 280,
						if operation.through == false then " BLIND" else "")
				elseif operation.kind == "Inset" then
					description = string.format("INSET %.0fmm", operation.margin * 280)
				elseif operation.kind == "File" then
					description = string.format("FILE %s %.0fmm", operation.edge, operation.width * 280)
				elseif operation.kind == "FileMesh" then
					description = string.format("%s %.0fmm · %d seg",
						if operation.interior then "FILE INNER (PAUSED)" else "FILE EDGE",
						operation.width*280,operation.segments or 1)
				elseif operation.kind == "InsetFace" then
					description = string.format("INSET FACE %.0fmm",operation.margin*280)
				elseif operation.kind == "Groove" then
					description = string.format("GROOVE %.0fmm", operation.kerf * 280)
				elseif operation.kind == "GrooveFace" then
					description = string.format("%s %.0fmm",
						if operation.through then "KERF" else "GROOVE",operation.width*280)
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
		selectionBorder.Adornee = if model then model:FindFirstChildWhichIsA("BasePart") else nil
		selectionBorder.Visible = selectionBorder.Adornee ~= nil
		if transformGizmo then
			if component and node then
				transformGizmo:show(component, nodeIndex)
			else
				transformGizmo:hide()
			end
		end
	end

	surfacePicker = SurfacePicker.new(message)
	preview = Preview.new(message, function(id,model)
		surfacePicker:request(id,model,document.components[id])
		if id == selectedId then refresh() end
	end)

	local function selectComponent(id: number?)
		if id~=selectedId then toolVisualizer:stopAnimation() end
		selectedId = id
		local component = selectedComponent()
		nodeIndex = if component then #component.nodes else 1
		refresh()
	end

	local function changed(component)
		toolVisualizer:stopAnimation()
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
	line("FABRICATION TOOLS // MANUFACTURED SURFACES")
	local toolStatus = line("Tool: none")
	historyInfo = line("Fabrication: 0 cuts")
	local function setTool(kind: string?)
		toolVisualizer:stopAnimation()
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		activeTool = kind
		toolVisualizer:hide()
		if kind then
			transformGizmo:setHidden(true)
			toolStatus.Text = "Tool: " .. string.upper(kind)
			local guidance = {
				Drill = "Drill: hover a face, wheel to change diameter, click to bore",
				Inset = "Inset: hover a planar manufactured face; wheel sets border width; click",
				File = "File: width via wheel, 1 flat segment or 2-12 rounded segments",
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
		activeTool = nil
		toolVisualizer:hide()
		toolStatus.Text = "Tool: SAW"
		sketchEditor:start(component, "Saw")
		transformGizmo:setHidden(true)
	end)
	pair("Inset / Pocket", function() setTool("Inset") end,
		"File Edge", function() setTool("File") end)
	pair("Sketch / Extrude", function()
		local component = selectedComponent()
		if not component then message("Create or select a workpiece first") return end
		if not sketchEditor then message("Sketch workspace is not initialized") return end
		activeTool = nil
		toolVisualizer:hide()
		transformGizmo:setHidden(true)
		toolStatus.Text = "Tool: SKETCH"
		sketchEditor:start(component)
		transformGizmo:setHidden(true)
	end, "New Body Sketch", function()
		if not sketchEditor then message("Sketch workspace is not initialized") return end
		activeTool = nil
		toolVisualizer:hide()
		transformGizmo:setHidden(true)
		toolStatus.Text = "Tool: NEW BODY"
		sketchEditor:start(nil)
		transformGizmo:setHidden(true)
	end)
	pair("Exit Tool", function() setTool(nil) end, "Undo Last Cut", function()
		local component = selectedComponent()
		if not component then message("Select a material first") return end
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
	line("Wheel: Drill 2 | File 1 | Inset 2 mm", 20)
	line("Shift+Wheel: coarse · Alt+Wheel: File segments", 20)
	line("POCKET  /  FILE EDGE")
	local insetMarginInput = toolNumberRow("Inset border (mm)  [wheel]", "28")
	local insetDepthInput = toolNumberRow("Inset depth (mm)", "28")
	local fileWidthInput = toolNumberRow("File chamfer (mm)  [wheel]", "14")
	local fileSegmentsInput = toolNumberRow("File segments (1–12)", "1")

	line("File: 1 flat / 2–12 rounded; inside File paused.", 24)

	line("3D TRANSFORM HANDLES")
	local transformStatus = line("Mode: MOVE (G)")
	local function setTransformMode(mode: string)
		if sketchEditor and sketchEditor.active then sketchEditor:stop() end
		toolVisualizer:hide()
		activeTool = nil
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
		if toolVisualizer:isAnimating() then return end
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
		surfacePicker:remove(component.id)
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
				if ok then
					changed(component)
					toolVisualizer:animateSketch(Compiler.pose(component.nodes[1]),
						component.nodes[1],data)
				end
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
			toolVisualizer:animateSketch(Compiler.pose(body.nodes[1]),body.nodes[1],
				{points=localPoints,mode="Intersect",depth=data.depth})
			return true, nil
		end,
		message,
		function()
			transformGizmo:setMode("Move")
			toolStatus.Text = "Tool: none"
			transformStatus.Text = "Mode: MOVE (G)"
		end
	)


	-- Active fabrication tools use the scroll wheel for the dimension under
	-- the cursor, not camera zoom. The input field stays authoritative, so
	-- typed values and wheel edits share the exact same CSG history path.
	-- Ctrl+MMB remains available for camera zoom while using a tool.
	local dimensionTools={
		Drill={ box=diameterInput, step=2, coarse=10, default=56 },
		File={ box=fileWidthInput, step=1, coarse=5, default=14, minimum=6 },
		Inset={ box=insetMarginInput, step=2, coarse=10, default=28 },
	}
	cameraController:setWheelHandler(function(steps:number):boolean
		local entry=dimensionTools[activeTool]
		if not entry or UserInputService:GetFocusedTextBox() then return false end
		-- ALT + wheel changes geometric rounding segmentation. Plain
		-- wheel still changes File width, matching the Drill workflow.
		if activeTool=="File" and (
			UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)) then
			local current=tonumber(fileSegmentsInput.Text) or 1
			local count=math.clamp(math.floor(current+steps+0.5),1,12)
			fileSegmentsInput.Text=tostring(count)
			toolStatus.Text=string.format("FILE: %d %s",count,
				if count==1 then "flat segment" else "rounded segments")
			return true
		end
		local shift=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local increment=if shift then entry.coarse else entry.step
		local current=tonumber(entry.box.Text)
		if not current or current~=current then current=entry.default end
		local node=selectedNode()
		-- Bounds only protect the numeric UI from absurd dimensions.
		-- The actual face/edge geometry validator applies stricter limits
		-- before committing File or Inset.
		local limit=35840
		if node then
			local major=math.max(node.size.X,node.size.Y,node.size.Z)*280
			if activeTool=="Drill" then
				limit=math.max(5,math.min(major*2,35840))
			elseif activeTool=="File" then
				limit=math.max(5,math.min(major*0.5,35840))
			else
				limit=math.max(5,math.min(major*0.45,35840))
			end
		end
		local nextMM=math.clamp(math.round(current+steps*increment),entry.minimum or 5,limit)
		entry.box.Text=string.format("%.0f",nextMM)
		toolStatus.Text=string.format("Tool: %s · %d mm",
			string.upper(activeTool),nextMM)
		return true
	end)

	local function millimeters(box: TextBox, label: string): (number?, string?)
		local mm = tonumber(box.Text)
		if not mm or not Quantize.isFinite(mm) or mm < 5 or mm > 35840 then
			return nil, label .. " must be between 5 mm and 35840 mm"
		end
		return mm / 280, nil
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
		-- The rendered CSG may still be the previous revision while
		-- asynchronous remanufacturing is in progress. Never pick stale
		-- topology or commit a feature against a replaced mesh.
		local state = preview.states[id]
		if activeTool and (not state or state.key~=Fabricator.geometryKey(component)) then
			return nil
		end
		local pose = Compiler.pose(node)
		local normal = pose:VectorToObjectSpace(hit.Normal)
		
		local localPoint = pose:PointToObjectSpace(hit.Position)
		local x = Quantize.snap(localPoint.X, Quantize.Grid)
		local z = Quantize.snap(localPoint.Z, Quantize.Grid)
		return { component = component, id = id, node = node, pose = pose,
			point = localPoint, x = x, z = z, hit = hit }
	end

	-- Edge tools use screen-space segments, not a face raycast. This lets
	-- the player select an entire vertical/re-entrant edge even if the mouse
	-- is over empty background or its neighboring top face.
	local function fileEdgeTarget()
		if activeTool~="File" or (sketchEditor and sketchEditor.active)
			or UserInputService:GetFocusedTextBox() or cameraController.dragging then
			return nil
		end
		local camera=workspace.CurrentCamera
		if not camera then return nil end
		local mouse=UserInputService:GetMouseLocation()
		if mouse.X<345 and mouse.Y<615 then return nil end
		if mouse.X>camera.ViewportSize.X-340 and mouse.Y>225 and mouse.Y<610 then
			return nil
		end
		if viewGizmo:containsPoint(mouse) or transformGizmo:capturesPoint(mouse) then
			return nil
		end
		local best,bestDistance=nil,math.huge
		for id,component in pairs(document.components) do
			local state=preview.states[id]
			if not state or state.key~=Fabricator.geometryKey(component) then continue end
			local topology=surfacePicker:get(id,preview:getModel(id),component)
			if not topology then continue end
			local edge,distance=topology.closestEdge(topology,camera,mouse,18)
			if edge and distance and distance<bestDistance then
				bestDistance=distance
				best={id=id,component=component,node=component.nodes[1],
					pose=Compiler.pose(component.nodes[1]),topology=topology,edge=edge}
			end
		end
		return best
	end

	-- Derive a single validated filing operation from a current, visible
	-- manufactured edge. Hover and click use identical face normals and
	-- inside/outer classification, so a preview cannot promise another cut.
	local function fileSegments():number?
		local n=tonumber(fileSegmentsInput.Text)
		if not n or n~=math.floor(n) or n<1 or n>12 then
			return nil
		end
		return n
	end

	local function bevelData(topology,edge,pose:CFrame,width:number,segments:number)
		if not edge or #edge.faces~=2 or edge.curved then
			return nil,"Select a straight manufactured edge between two faces"
		end
		local f1,f2=topology.faces[edge.faces[1]],topology.faces[edge.faces[2]]
		if not f1 or not f2 or f1.curved or f2.curved then
			return nil,"Filing curved faces is not yet supported"
		end
		local partFrame=topology.part.CFrame
		local a=pose:PointToObjectSpace(partFrame:PointToWorldSpace(edge.a))
		local b=pose:PointToObjectSpace(partFrame:PointToWorldSpace(edge.b))
		local n1=pose:VectorToObjectSpace(partFrame:VectorToWorldSpace(f1.normal))
		local n2=pose:VectorToObjectSpace(partFrame:VectorToWorldSpace(f2.normal))
		local interior=edge.interior==true
			or ((string.find(f1.tag or "","_floor")~=nil)
				and (string.find(f2.tag or "","_wall")~=nil))
			or ((string.find(f2.tag or "","_floor")~=nil)
				and (string.find(f1.tag or "","_wall")~=nil))
		if interior then return nil,"Interior edge filing is paused" end
		local ok,why=GeometryCutter.validateFile(a,b,n1,n2,width,false,segments)
		if not ok then return nil,why end
		-- A bevel cannot be wider than either of its adjacent physical
		-- faces. Especially important for shallow recesses: cutting right
		-- through the opposite wall creates the huge triangular shards
		-- that CSG produces with overlarge, overlapping cutters.
		local dot=f1.normal:Dot(f2.normal)
		local sign=if interior then -1 else 1
		local mid=(edge.a+edge.b)/2
		for _,side in ipairs({
			{face=f1,dir=(f1.normal*dot-f2.normal).Unit*sign},
			{face=f2,dir=(f2.normal*dot-f1.normal).Unit*sign},
		}) do
			if side.face.polygon then
				local available=0
				for _,vertex in ipairs(side.face.polygon) do
					available=math.max(available,(vertex-mid):Dot(side.dir))
				end
				if available+0.002<width then
					return nil,"Chamfer width exceeds the neighboring face"
				end
			end
		end
		return {a=a,b=b,normalA=n1,normalB=n2,
			width=width,interior=interior,segments=segments,
			taperA=false,taperB=false},nil
	end

	RunService.RenderStepped:Connect(function(dt)
		if toolVisualizer:update(dt) then return end
		if activeTool=="File" then
			local selection=fileEdgeTarget()
			local width=millimeters(fileWidthInput,"File width")
			if not selection or not width then toolVisualizer:hide() return end
			local segments=fileSegments()
			if not segments then toolVisualizer:hide() return end
			local plan=bevelData(selection.topology,selection.edge,selection.pose,width,segments)
			if not plan then toolVisualizer:hide() return end
			local edge=selection.edge
			toolVisualizer:meshEdge(selection.topology.part,edge,width,plan.interior,
				selection.topology.faces[edge.faces[1]].normal,
				selection.topology.faces[edge.faces[2]].normal,
				nil,nil,segments)
			return
		end
		local target = fabricationHit()
		if not target then toolVisualizer:hide() return end
		local node, pose = target.node, target.pose
		if activeTool == "Drill" then
			local diameter = millimeters(diameterInput, "Diameter")
			local depth = millimeters(drillDepthInput, "Drill depth")
			if not diameter or not depth then toolVisualizer:hide() return end
			local topology=surfacePicker:get(target.id,preview:getModel(target.id),target.component)
			if not topology or topology.part~=target.hit.Instance then
				toolVisualizer:hide() return
			end
			local face=topology.faceAt(topology,target.hit.Position,target.hit.Normal)
			if not face then toolVisualizer:hide() return end
			local origin=pose:PointToObjectSpace(target.hit.Position)
			local worldNormal=topology.part.CFrame:VectorToWorldSpace(face.normal)
			toolVisualizer:drillFace(pose,origin,
				pose:VectorToObjectSpace(worldNormal),diameter,depth,drillThrough,node.size.Magnitude,node.size)
		elseif activeTool == "Inset" then
			local margin = millimeters(insetMarginInput, "Inset border")
			local depth = millimeters(insetDepthInput, "Inset depth")
			if not margin or not depth then toolVisualizer:hide() return end
			local topology = surfacePicker:get(target.id,preview:getModel(target.id),target.component)
			if not topology or topology.part ~= target.hit.Instance then
				toolVisualizer:hide() return
			end
			local face = topology.faceAt(topology,target.hit.Position,target.hit.Normal)
			if not face then
				toolVisualizer:hide() return
			end
			local inset = FaceTools.inset(face,margin)
			if not inset then toolVisualizer:hide() return end
			toolVisualizer:meshFace(topology.part,inset,margin,depth)

		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if sketchEditor and sketchEditor.active then return end
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then return end
		if activeTool=="File" then
			local selection=fileEdgeTarget()
			if not selection then
				message("Hover a visible full-length edge to file")
				return
			end
			local width,why=millimeters(fileWidthInput,"File width")
			if not width then message(why) return end
			local segments=fileSegments()
			if not segments then message("File segments must be a whole number from 1 to 12") return end
			local data,reason=bevelData(selection.topology,selection.edge,selection.pose,width,segments)
			if not data then message(reason or "Unable to file selected edge") return end
			if selection.id~=selectedId then selectComponent(selection.id) end
			local ok,err=document:addOperation(selection.component,"FileMesh",data)
			if not ok then message(err or "Unable to file edge") return end
			changed(selection.component)
			toolVisualizer:animateFile(selection.pose,data)
			message("Filing edge · compiling CSG")
			return
		end
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
		if target.id ~= selectedId then selectComponent(target.id) end
		if not activeTool then return end
		local component, node = target.component, target.node
		-- Click handlers share the same local manufacturing frame as hover.
		-- 'pose' was scoped only inside RenderStepped, causing the nil
		-- PointToObjectSpace crash on every face-based operation.
		local pose = target.pose
		local x, z = target.x, target.z
		local kind = activeTool
		local data = nil
		if kind == "Drill" then
			local diameter,errorA=millimeters(diameterInput,"Diameter")
			local depth,errorB=millimeters(drillDepthInput,"Drill depth")
			if not diameter or not depth then message(errorA or errorB) return end
			local topology,why=surfacePicker:get(target.id,preview:getModel(target.id),target.component)
			if not topology then message(why or "Surface indexing in progress") return end
			if topology.part~=target.hit.Instance then message("Surface selection changed") return end
			local face=topology.faceAt(topology,target.hit.Position,target.hit.Normal)
			if not face then message("Select a visible manufactured face") return end
			local worldNormal=topology.part.CFrame:VectorToWorldSpace(face.normal)
			data={origin=pose:PointToObjectSpace(target.hit.Position),
				normal=pose:VectorToObjectSpace(worldNormal),
				diameter=diameter,depth=depth,through=drillThrough}
			kind="DrillFace"
		elseif kind == "Inset" then
			local margin,errorA=millimeters(insetMarginInput,"Inset border")
			local depth,errorB=millimeters(insetDepthInput,"Inset depth")
			if not margin or not depth then message(errorA or errorB) return end
			local topology,why=surfacePicker:get(target.id,preview:getModel(target.id),target.component)
			if not topology then message(why or "Compiling face topology") return end
			if topology.part~=target.hit.Instance then message("Face selection is out of date") return end
			local face=topology.faceAt(topology,target.hit.Position,target.hit.Normal)
			if not face then message("No planar manufactured face under pointer") return end
			local points,reason=FaceTools.inset(face,margin)
			if not points then message(reason or "Face cannot be inset") return end
			local localPoints={}
			for _,point in ipairs(points) do
				local world=topology.part.CFrame:PointToWorldSpace(point)
				table.insert(localPoints,pose:PointToObjectSpace(world))
			end
			local worldNormal=topology.part.CFrame:VectorToWorldSpace(face.normal)
			kind="InsetFace"
			data={points=localPoints,normal=pose:VectorToObjectSpace(worldNormal),
				margin=margin,depth=depth}

		else
			return
		end
		local ok, reason = document:addOperation(component, kind, data)
		if not ok then message(reason or "Unable to apply fabrication") return end
		changed(component)
		if kind=="DrillFace" then
			toolVisualizer:animateDrill(pose,data.origin,data.normal,
				data.diameter,data.depth,data.through,node.size)
		elseif kind=="InsetFace" then
			toolVisualizer:animateInset(pose,data.points,data.normal,data.depth)
		end
		message(kind .. " operation recorded; compiling CSG")
	end)

	refresh()
	message("Precision fabrication ready: Sketch, Saw, Drill, Inset, File.")
end

return Debug
