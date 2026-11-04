--!strict
-- Temporary FORM construction harness. Intentionally not a Duotone UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Document = require(FORM.Document)
local Preview = require(script.Parent.Preview)
local BlenderCamera = require(script.Parent.BlenderCamera)

local Debug = {}

local function make(className: string, properties, parent: Instance)
	local obj = Instance.new(className)
	for key, value in pairs(properties) do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function drawGrid()
	local folder = make("Folder", { Name = "FORM_DebugGrid" }, workspace)
	for i = -20, 20, 2 do
		for axis = 1, 2 do
			local line = make("Part", {
				Name = "Grid",
				Anchored = true,
				CanCollide = false,
				CanTouch = false,
				CanQuery = false,
				Material = Enum.Material.SmoothPlastic,
				Color = Color3.fromRGB(85, 95, 100),
				Transparency = if i == 0 then 0.35 else 0.72,
				Size = if axis == 1 then Vector3.new(0.025, 0.025, 40) else Vector3.new(40, 0.025, 0.025),
				Position = if axis == 1 then Vector3.new(i, -0.15, 0) else Vector3.new(0, -0.15, i),
			}, folder)
			line.CastShadow = false
		end
	end
end

function Debug.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local document = Document.new()
	local selectedId: number? = nil
	local nodeIndex = 1
	local spawnCount = 0

	drawGrid()

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
		nodeInfo.Text = if node then (string.format("Node %d/%d: %s [%s]", nodeIndex, #component.nodes, node.kind, node.operation)) else "Node: none"
		for _, binding in ipairs(textFields) do
			local box = binding.box
			local value = nil
			if node then
				local property = node[binding.field]
				if binding.axis ~= " " then
					value = property[binding.axis]
				elseif (binding.field == "bore" and node.kind == "HoleBlock") or (binding.field == "wall" and node.kind == "Tube") then
					value = property
				end
			end
			if not box:IsFocused() then
				box.Text = if value ~= nil then displayNumber(value) else "-"
			end
		end
		local model = if component then preview:getModel(component.id) else nil
		highlight.Adornee = model
		highlight.Enabled = model ~= nil
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

	line("CREATE COMPONENT")
	local function create(kind: string)
		spawnCount += 1
		local index = spawnCount - 1
		local position = Vector3.new((index % 4) * 5, 3, math.floor(index / 4) * 5)
		local component = document:create(kind, position)
		selectComponent(component.id)
		changed(component)
	end
	pair("Block", function() create("Block") end, "Cylinder", function() create("Cylinder") end)
	pair("Tube", function() create("Tube") end, "Hole Block", function() create("HoleBlock") end)

	line("EDIT SELECTED COMPONENT")
	local function add(kind: string, operation: string)
		local component = selectedComponent()
		if not component then message("Select a component first") return end
		local base = component.nodes[1].position
		local offset = if operation == "Subtract" then Vector3.zero else Vector3.new(1.5, 0, 0)
		local node = document:addNode(component, operation, kind, base + offset)
		if operation == "Subtract" then
			node.size = if kind == "Cylinder" then Vector3.new(1.5, 4, 1.5) else Vector3.new(1.5, 3, 1.5)
		end
		nodeIndex = #component.nodes
		changed(component)
	end
	pair("+ Block", function() add("Block", "Add") end, "+ Cylinder", function() add("Cylinder", "Add") end)
	pair("- Block", function() add("Block", "Subtract") end, "- Cylinder", function() add("Cylinder", "Subtract") end)
	pair("< Prev Node", function()
		local component = selectedComponent()
		if component then nodeIndex = math.max(1, nodeIndex - 1) refresh() end
	end, "Next Node >", function()
		local component = selectedComponent()
		if component then nodeIndex = math.min(#component.nodes, nodeIndex + 1) refresh() end
	end)

	line("NUMERIC NODE EDITOR // SNAP 0.05 / 15deg")
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
	editRow("POS", "position", { "X", "Y", "Z" })
	editRow("SIZE", "size", { "X", "Y", "Z" })
	editRow("ROT", "rotation", { "X", "Y", "Z" })
	editRow("HOLE", "bore", { " " })
	editRow("WALL", "wall", { " " })

	pair("Delete Node", function()
		local component = selectedComponent()
		if not component then message("No selection") return end
		local ok, reason = document:deleteNode(component, nodeIndex)
		if not ok then message(reason) return end
		nodeIndex = math.min(nodeIndex, #component.nodes)
		changed(component)
	end, "Delete Component", function()
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

	local cameraController = BlenderCamera.new(selectionBounds, sceneBounds)
	pair("Frame Selected (F)", function()
		if not cameraController:frameSelected() then message("Select a component first") end
	end, "Frame All (Home)", function()
		if not cameraController:frameAll() then message("No components to frame") end
	end)
	line("MMB orbit | Shift+MMB pan", 24)
	line("Ctrl+MMB dolly | Wheel zoom", 24)
	line("Numpad 1/3/7 views | 5 ortho", 24)
	line("F selected | Home all | Alt+LMB orbit", 24)

	-- Minimal view-axis navigator; like Blender's gizmo, aligned to world axes.
	local nav = make("Frame", {
		Name = "ViewNavigator",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(140, 149),
		BackgroundColor3 = Color3.fromRGB(28, 33, 38),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 7) }, nav)
	local viewText = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		Text = "USER PERSP",
		TextColor3 = Color3.fromRGB(226, 237, 240),
		TextSize = 13,
		Size = UDim2.new(1, 0, 0, 24),
	}, nav)
	local projectionButton = make("TextButton", {
		Name = "ProjectionToggle",
		BackgroundColor3 = Color3.fromRGB(56, 63, 70),
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		Text = "ORTHO / PERSP [5]",
		TextSize = 11,
		TextColor3 = Color3.fromRGB(238, 240, 241),
		Position = UDim2.fromOffset(6, 122),
		Size = UDim2.fromOffset(128, 22),
	}, nav)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, projectionButton)
	projectionButton.Activated:Connect(function()
		cameraController:toggleProjection()
	end)

	local axes = {
		{ label = "X", vector = Vector3.xAxis, view = "Right", color = Color3.fromRGB(221, 91, 91) },
		{ label = "-X", vector = -Vector3.xAxis, view = "Left", color = Color3.fromRGB(143, 63, 63) },
		{ label = "Y", vector = Vector3.yAxis, view = "Top", color = Color3.fromRGB(111, 195, 114) },
		{ label = "-Y", vector = -Vector3.yAxis, view = "Bottom", color = Color3.fromRGB(64, 116, 68) },
		{ label = "Z", vector = Vector3.zAxis, view = "Front", color = Color3.fromRGB(94, 141, 232) },
		{ label = "-Z", vector = -Vector3.zAxis, view = "Back", color = Color3.fromRGB(62, 88, 143) },
	}
	for _, axis in ipairs(axes) do
		local control = make("TextButton", {
			Name = axis.view,
			AutoButtonColor = true,
			BackgroundColor3 = axis.color,
			BorderSizePixel = 0,
			Font = Enum.Font.Code,
			Text = axis.label,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 11,
			Size = UDim2.fromOffset(24, 24),
		}, nav)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, control)
		axis.control = control
		control.Activated:Connect(function()
			cameraController:setView(axis.view)
		end)
	end
	cameraController:setOnFrame(function(cameraFrame, label)
		if viewText.Text ~= label then viewText.Text = label end
		for _, axis in ipairs(axes) do
			local x = axis.vector:Dot(cameraFrame.RightVector)
			local y = axis.vector:Dot(cameraFrame.UpVector)
			local near = axis.vector:Dot(cameraFrame.LookVector) < 0
			local diameter = if near then 24 else 18
			local control = axis.control
			control.Size = UDim2.fromOffset(diameter, diameter)
			control.Position = UDim2.fromOffset(70 + x * 34 - diameter / 2, 72 - y * 34 - diameter / 2)
			control.BackgroundTransparency = if near then 0 else 0.3
			control.ZIndex = if near then 5 else 3
			control.Text = if near then axis.label else ""
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then return end
		local mouse = UserInputService:GetMouseLocation()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { preview.root }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		if not hit then selectComponent(nil) return end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local id = if model then model:GetAttribute("FORMComponentId") else nil
		if typeof(id) == "number" and document.components[id] then
			selectComponent(id)
		end
	end)

	refresh()
	message("Ready: add a Block, then use - Cylinder to cut a hole")
end

return Debug
