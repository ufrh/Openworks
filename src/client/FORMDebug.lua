--!strict
-- Temporary FORM construction harness. Intentionally not a Duotone UI.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Document = require(FORM.Document)
local Preview = require(script.Parent.Preview)
local BlenderCamera = require(script.Parent.BlenderCamera)
local GridOverlay = require(script.Parent.GridOverlay)
local ViewGizmo = require(script.Parent.ViewGizmo)
local TransformGizmo = require(script.Parent.TransformGizmo)

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
		nodeInfo.Text = if node then ("Primitive: " .. node.kind) else "Primitive: none"
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
		-- Fresh geometry begins at the locked workspace origin.
		local component = document:create(kind, Vector3.zero)
		selectComponent(component.id)
		changed(component)
		if cameraController then cameraController:frameSelected() end
	end
	pair("Block", function() create("Block") end, "Cylinder", function() create("Cylinder") end)
	pair("Tube", function() create("Tube") end, "Hole Block", function() create("HoleBlock") end)

	line("3D TRANSFORM HANDLES")
	local transformStatus = line("Mode: MOVE (G)")
	local function setTransformMode(mode: string)
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

	line("PARAMETRIC PRIMITIVE EDITOR")
	line("NUMERIC PRIMITIVE EDITOR // 0.05 / 15deg")
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

	local deleteRow = row(29)
	button(deleteRow, "Delete Component", 0, 1, function()
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

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then return end
		local mouse = UserInputService:GetMouseLocation()
		if viewGizmo:containsPoint(mouse) or transformGizmo:isDragging() or transformGizmo:capturesPoint(mouse) then return end
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
		if typeof(id) == "number" and document.components[id] then
			selectComponent(id)
		end
	end)

	refresh()
	message("Fixed-origin workspace. Direct shapes; CSG only inside special templates.")
end

return Debug
