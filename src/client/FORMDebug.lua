--!strict
-- Temporary FORM construction harness. Intentionally not a Duotone UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Document = require(FORM.Document)
local Preview = require(script.Parent.Preview)

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

local function startCamera(getSelectionPosition)
	local target = Vector3.new(0, 2, 0)
	local yaw = math.rad(40)
	local pitch = math.rad(30)
	local distance = 26
	local orbiting = false
	local panning = false

	local function activeCamera(): Camera
		local camera = workspace.CurrentCamera
		while not camera do
			workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
			camera = workspace.CurrentCamera
		end
		return camera
	end

	local function updateCamera()
		local camera = activeCamera()
		camera.CameraType = Enum.CameraType.Scriptable
		local offset = Vector3.new(
			math.cos(pitch) * math.sin(yaw),
			math.sin(pitch),
			math.cos(pitch) * math.cos(yaw)
		) * distance
		camera.CFrame = CFrame.lookAt(target + offset, target)
		camera.Focus = CFrame.new(target)
	end

	RunService:BindToRenderStep("FORM_DebugCamera", Enum.RenderPriority.Camera.Value + 1, updateCamera)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
			panning = true
		elseif input.KeyCode == Enum.KeyCode.F then
			local point = getSelectionPosition()
			if point then
				target = point
				distance = math.clamp(distance, 10, 45)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbiting = false
		elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
			panning = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if orbiting then
				yaw -= input.Delta.X * 0.007
				pitch = math.clamp(pitch + input.Delta.Y * 0.006, math.rad(6), math.rad(85))
			elseif panning then
				local camera = activeCamera()
				local speed = distance / 600
				target += (-camera.CFrame.RightVector * input.Delta.X + camera.CFrame.UpVector * input.Delta.Y) * speed
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			distance = math.clamp(distance * (if input.Position.Z > 0 then 0.85 else 1.15), 4, 130)
		end
	end)

	return function(point: Vector3?)
		if point then
			target = point
			distance = 18
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

	local focusCamera = startCamera(function()
		local node = selectedNode()
		return if node then node.position else nil
	end)
	pair("Focus (F)", function()
		local node = selectedNode()
		if node then focusCamera(node.position) end
	end, "Deselect", function() selectComponent(nil) end)
	line("Right drag: orbit  |  Middle drag: pan", 24)
	line("Wheel: zoom  |  Left click: select", 24)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
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
