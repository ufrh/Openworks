--!strict
-- Interactive 3D orientation widget, rendered in a ViewportFrame.
-- Click an axis for cardinal views; drag the ViewportFrame to orbit the scene.
local UserInputService = game:GetService("UserInputService")

local ViewGizmo = {}
ViewGizmo.__index = ViewGizmo

local COLORS = {
	X = Color3.fromRGB(223, 91, 92),
	Y = Color3.fromRGB(102, 201, 120),
	Z = Color3.fromRGB(96, 149, 241),
}
local AXES = {
	{ label = "X", direction = Vector3.xAxis, view = "Right", color = COLORS.X },
	{ label = "-X", direction = -Vector3.xAxis, view = "Left", color = COLORS.X:Lerp(Color3.new(0, 0, 0), 0.38) },
	{ label = "Y", direction = Vector3.yAxis, view = "Top", color = COLORS.Y },
	{ label = "-Y", direction = -Vector3.yAxis, view = "Bottom", color = COLORS.Y:Lerp(Color3.new(0, 0, 0), 0.38) },
	{ label = "Z", direction = Vector3.zAxis, view = "Front", color = COLORS.Z },
	{ label = "-Z", direction = -Vector3.zAxis, view = "Back", color = COLORS.Z:Lerp(Color3.new(0, 0, 0), 0.38) },
}

local function new(class: string, properties, parent: Instance)
	local object = Instance.new(class)
	for k, v in pairs(properties) do (object :: any)[k] = v end
	object.Parent = parent
	return object
end

local function rod(model: Instance, direction: Vector3, color: Color3)
	local size: Vector3
	if math.abs(direction.X) > 0 then
		size = Vector3.new(0.67, 0.05, 0.05)
	elseif math.abs(direction.Y) > 0 then
		size = Vector3.new(0.05, 0.67, 0.05)
	else
		size = Vector3.new(0.05, 0.05, 0.67)
	end
	new("Part", {
		Name = "AxisRod", Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
		Material = Enum.Material.SmoothPlastic, Color = color,
		Size = size, CFrame = CFrame.new(direction * 0.35),
	}, model)
end

function ViewGizmo.new(gui: ScreenGui, controller)
	local panel = new("Frame", {
		Name = "ViewNavigator",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(144, 206),
		BackgroundColor3 = Color3.fromRGB(28, 33, 38),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 7) }, panel)
	local heading = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Code, Text = "USER PERSP",
		TextColor3 = Color3.fromRGB(226, 237, 240),
		TextSize = 12, Size = UDim2.new(1, 0, 0, 21),
		ZIndex = 5,
	}, panel)

	local viewport = new("ViewportFrame", {
		Name = "DragToOrbit",
		Position = UDim2.fromOffset(9, 22),
		Size = UDim2.fromOffset(126, 126),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		Ambient = Color3.fromRGB(210, 215, 220),
		LightColor = Color3.fromRGB(245, 245, 245),
		LightDirection = Vector3.new(-1, -1, -1),
		ZIndex = 5,
	}, panel)
	local world = new("WorldModel", { Name = "OrientationAxes" }, viewport)
	local scene = new("Model", { Name = "Gizmo" }, world)
	new("Part", {
		Name = "Origin", Shape = Enum.PartType.Ball, Anchored = true,
		CanCollide = false, CanQuery = false,
		Material = Enum.Material.SmoothPlastic, Color = Color3.fromRGB(160, 171, 179),
		Size = Vector3.new(0.12, 0.12, 0.12), CFrame = CFrame.new(),
	}, scene)
	for _, axis in ipairs(AXES) do
		rod(scene, axis.direction, axis.color)
		new("Part", {
			Name = "Axis_" .. axis.label,
			Shape = Enum.PartType.Ball, Anchored = true,
			CanCollide = false, CanTouch = false, CanQuery = false,
			Material = Enum.Material.SmoothPlastic,
			Color = axis.color,
			Size = Vector3.new(0.23, 0.23, 0.23),
			CFrame = CFrame.new(axis.direction * 0.75),
		}, scene)
	end
	local camera = new("Camera", {
		Name = "GizmoCamera",
		FieldOfView = 33,
		CFrame = CFrame.lookAt(Vector3.new(3, 3, 3), Vector3.zero),
	}, viewport)
	viewport.CurrentCamera = camera

	local projection = new("TextButton", {
		Name = "ProjectionToggle",
		BackgroundColor3 = Color3.fromRGB(56, 63, 70),
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		Text = "ORTHO / PERSP [5]", TextSize = 11,
		TextColor3 = Color3.fromRGB(236, 239, 241),
		Position = UDim2.fromOffset(8, 149),
		Size = UDim2.fromOffset(128, 21), ZIndex = 6,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, projection)
	projection.Activated:Connect(function() controller:toggleProjection() end)
	local panButton = new("TextButton", {
		Name = "DragPan",
		BackgroundColor3 = Color3.fromRGB(66, 75, 83),
		BorderSizePixel = 0, Font = Enum.Font.Code,
		Text = "HAND  ·  DRAG TO PAN", TextSize = 11,
		TextColor3 = Color3.fromRGB(236, 239, 241),
		Position = UDim2.fromOffset(8, 176),
		Size = UDim2.fromOffset(128, 23),
		Active = true, ZIndex = 6,
	}, panel)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, panButton)

	-- Labels are 2D overlays, aligned to the 3D ball endpoints at each camera update.
	-- They are not active buttons, so drag input still belongs to the ViewportFrame.
	local labels = {}
	for _, axis in ipairs(AXES) do
		local label = new("TextLabel", {
			Name = "Label_" .. axis.view,
			BackgroundColor3 = axis.color,
			BackgroundTransparency = 0.12, BorderSizePixel = 0,
			Font = Enum.Font.Code, Text = axis.label,
			TextColor3 = Color3.new(1, 1, 1), TextSize = 10,
			Size = UDim2.fromOffset(22, 22),
			Active = false, ZIndex = 7,
		}, panel)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, label)
		table.insert(labels, { axis = axis, label = label, location = Vector2.zero })
	end

	local self = setmetatable({
		panel = panel,
		viewport = viewport,
		camera = camera,
		heading = heading,
		labels = labels,
		controller = controller,
		dragging = false,
		panning = false,
		start = Vector2.zero,
		previous = Vector2.zero,
		didDrag = false,
		connections = {},
	}, ViewGizmo)

	local function connect(signal, callback)
		table.insert(self.connections, signal:Connect(callback))
	end
	connect(viewport.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		self.start = position
		self.previous = position
		self.dragging = true
		self.didDrag = false
	end)

	connect(panButton.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		self.panning = true
		self.dragging = false
		self.previous = Vector2.new(input.Position.X, input.Position.Y)
	end)
	connect(UserInputService.InputChanged, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
		if not self.dragging and not self.panning then return end
		local nextPosition = Vector2.new(input.Position.X, input.Position.Y)
		local delta = nextPosition - self.previous
		self.previous = nextPosition
		if self.panning then
			controller:panPixels(delta.X, delta.Y)
			return
		end
		if (nextPosition - self.start).Magnitude > 3 then self.didDrag = true end
		if self.didDrag then controller:orbitDelta(delta) end
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if self.panning then
			self.panning = false
			return
		end
		if not self.dragging then return end
		self.dragging = false
		if self.didDrag then return end
		local pos = self.start - viewport.AbsolutePosition
		local best, bestDistance = nil, 15
		for _, item in ipairs(self.labels) do
			local distance = (pos - item.location).Magnitude
			if distance < bestDistance then
				best, bestDistance = item.axis.view, distance
			end
		end
		if best then controller:setView(best) end
	end)
	connect(UserInputService.WindowFocusReleased, function()
		self.dragging = false
		self.panning = false
	end)
	return self
end

function ViewGizmo:containsPoint(point: Vector2): boolean
	local origin = self.panel.AbsolutePosition
	local size = self.panel.AbsoluteSize
	return point.X >= origin.X and point.X <= origin.X + size.X
		and point.Y >= origin.Y and point.Y <= origin.Y + size.Y
end

function ViewGizmo:update(sceneFrame: CFrame, viewName: string)
	if self.heading.Text ~= viewName then self.heading.Text = viewName end
	-- The gizmo uses its own ViewportFrame, so scene parts never enter its WorldModel.
	self.camera.CFrame = CFrame.lookAt(-sceneFrame.LookVector * 4, Vector3.zero, sceneFrame.UpVector)
	local center = Vector2.new(self.viewport.AbsoluteSize.X / 2, self.viewport.AbsoluteSize.Y / 2)
	local projectionScale = 44
	for _, item in ipairs(self.labels) do
		local axis = item.axis
		local x = axis.direction:Dot(sceneFrame.RightVector)
		local y = axis.direction:Dot(sceneFrame.UpVector)
		local inFront = axis.direction:Dot(sceneFrame.LookVector) < 0
		local location = center + Vector2.new(x * projectionScale, -y * projectionScale)
		item.location = location
		local diameter = if inFront then 23 else 18
		local label = item.label
		label.Position = UDim2.fromOffset(9 + location.X - diameter / 2, 22 + location.Y - diameter / 2)
		label.Size = UDim2.fromOffset(diameter, diameter)
		label.BackgroundTransparency = if inFront then 0.07 else 0.5
		label.TextTransparency = if inFront then 0 else 0.35
		label.ZIndex = if inFront then 9 else 7
	end
end

function ViewGizmo:destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.panel:Destroy()
end

return ViewGizmo
