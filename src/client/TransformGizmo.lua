--!strict
-- FORM custom transform widget: screen-space projected onto actual 3D axes.
-- No stock Roblox Handles/ArcHandles and no non-editable compiled geometry edits.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Quantize = require(ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM").Quantize)

local TransformGizmo = {}
TransformGizmo.__index = TransformGizmo

local AXES = {
	{ name = "X", vector = Vector3.xAxis, color = Color3.fromRGB(230, 98, 103) },
	{ name = "Y", vector = Vector3.yAxis, color = Color3.fromRGB(108, 205, 139) },
	{ name = "Z", vector = Vector3.zAxis, color = Color3.fromRGB(101, 157, 245) },
}

local function create(class: string, props, parent: Instance)
	local item = Instance.new(class)
	for key, value in pairs(props) do
		(item :: any)[key] = value
	end
	item.Parent = parent
	return item
end

local function coordinate(v: Vector3, axis: string): number
	if axis == "X" then return v.X end
	if axis == "Y" then return v.Y end
	return v.Z
end

local function replaceAxis(v: Vector3, axis: string, value: number): Vector3
	if axis == "X" then return Vector3.new(value, v.Y, v.Z) end
	if axis == "Y" then return Vector3.new(v.X, value, v.Z) end
	return Vector3.new(v.X, v.Y, value)
end

local function rotationOf(node): CFrame
	return CFrame.fromOrientation(
		math.rad(node.rotation.X),
		math.rad(node.rotation.Y),
		math.rad(node.rotation.Z)
	)
end

local function drawSegment(line: Frame, start: Vector2, finish: Vector2, thickness: number)
	local direction = finish - start
	local length = direction.Magnitude
	if length < 0.01 then
		line.Visible = false
		return
	end
	line.Visible = true
	local midpoint = (start + finish) / 2
	line.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
	line.Size = UDim2.fromOffset(length, thickness)
	line.Rotation = math.deg(math.atan2(direction.Y, direction.X))
end

local function getScreen(camera: Camera, point: Vector3): (Vector2, boolean)
	local projected = camera:WorldToViewportPoint(point)
	return Vector2.new(projected.X, projected.Y), projected.Z > 0
end

function TransformGizmo.new(playerGui: PlayerGui, document, onChange)
	local gui = create("ScreenGui", {
		Name = "FORM_CustomTransformGizmo",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
	}, playerGui)

	local center = create("Frame", {
		Name = "OriginDot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(212, 220, 227),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(7, 7),
		ZIndex = 30,
		Visible = false,
	}, gui)
	create("UICorner", { CornerRadius = UDim.new(1, 0) }, center)

	local axisElements = {}
	for _, axis in ipairs(AXES) do
		local line = create("Frame", {
			Name = axis.name .. "AxisLine",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = axis.color,
			BorderSizePixel = 0,
			ZIndex = 28, Visible = false,
		}, gui)
		local knob = create("TextButton", {
			Name = axis.name .. "TransformHandle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = axis.color,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Text = axis.name,
			TextColor3 = Color3.fromRGB(15, 21, 29),
			TextSize = 10,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(18, 18),
			ZIndex = 31, Visible = false,
		}, gui)
		create("UICorner", { CornerRadius = UDim.new(0, 5) }, knob)
		create("UIStroke", {
			Color = Color3.fromRGB(18, 27, 32),
			Thickness = 1,
			Transparency = 0.18,
		}, knob)

		local ring = {}
		for i = 1, 24 do
			ring[i] = create("Frame", {
				Name = axis.name .. "RotateArc" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = axis.color,
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				ZIndex = 27, Visible = false,
			}, gui)
		end
		axisElements[axis.name] = { axis = axis, line = line, knob = knob, ring = ring }
	end

	local self = setmetatable({
		document = document,
		onChange = onChange,
		gui = gui,
		center = center,
		axes = axisElements,
		component = nil,
		index = nil,
		mode = "Move",
		hidden = false,
		drag = nil,
		connections = {},
		camera = nil,
	}, TransformGizmo)

	local function connect(signal, fn)
		table.insert(self.connections, signal:Connect(fn))
	end

	for _, axis in ipairs(AXES) do
		local knob = axisElements[axis.name].knob
		connect(knob.InputBegan, function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			self:beginDrag(axis.name, Vector2.new(input.Position.X, input.Position.Y))
		end)
	end

	connect(UserInputService.InputChanged, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement or not self.drag then return end
		self:moveDrag(Vector2.new(input.Position.X, input.Position.Y))
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and self.drag then
			self:finishDrag()
		end
	end)
	connect(UserInputService.WindowFocusReleased, function()
		if self.drag then self:finishDrag() end
	end)

	RunService:BindToRenderStep("FORM_CustomTransformRender", Enum.RenderPriority.Camera.Value + 12, function()
		self:update()
	end)

	return self
end

function TransformGizmo:beginDrag(axisName: string, pointer: Vector2)
	if self.drag or self.hidden or not self.component or not self.index then return end
	local node = self.component.nodes[self.index]
	local camera = workspace.CurrentCamera
	if not node or not camera then return end

	local basis = rotationOf(node)
	local direction = basis:VectorToWorldSpace(
		if axisName == "X" then Vector3.xAxis
		elseif axisName == "Y" then Vector3.yAxis else Vector3.zAxis
	)
	local p, front = getScreen(camera, node.position)
	local step = math.clamp((camera.CFrame.Position - node.position).Magnitude * 0.12, 0.01, 0.25)
	local q = getScreen(camera, node.position + direction * step)
	if not front then return end
	local projected = (q - p) / step
	if self.mode ~= "Rotate" and projected.Magnitude < 1 then return end

	self.drag = {
		component = self.component,
		index = self.index,
		axisName = axisName,
		startPointer = pointer,
		lastPointerAngle = math.atan2(pointer.Y - p.Y, pointer.X - p.X),
		accumulatedAngle = 0,
		screenCenter = p,
		screenDirection = if projected.Magnitude >= 1 then projected.Unit else Vector2.xAxis,
		pixelsPerStud = math.max(2, projected.Magnitude),
		worldDirection = direction,
		position = node.position,
		size = node.size,
		rotation = node.rotation,
		dirty = false,
	}
	self.onChange("begin", self.component, self.index)
end

function TransformGizmo:moveDrag(pointer: Vector2)
	local d = self.drag
	if not d then return end
	local position, size, rotation
	if self.mode == "Rotate" then
		local angle = math.atan2(pointer.Y - d.screenCenter.Y, pointer.X - d.screenCenter.X)
		local delta = math.atan2(math.sin(angle - d.lastPointerAngle), math.cos(angle - d.lastPointerAngle))
		d.lastPointerAngle = angle
		d.accumulatedAngle += delta
		local degrees = math.deg(d.accumulatedAngle)
		rotation = replaceAxis(d.rotation, d.axisName, coordinate(d.rotation, d.axisName) + degrees)
	else
		local mouseDelta = pointer - d.startPointer
		local projectedPixels = mouseDelta:Dot(d.screenDirection)
		local distance = Quantize.snap(projectedPixels / d.pixelsPerStud, Quantize.Grid)
		if self.mode == "Move" then
			position = d.position + d.worldDirection * distance
		elseif self.mode == "Scale" then
			local original = coordinate(d.size, d.axisName)
			local desired = math.clamp(original + distance, Quantize.MinSize, Quantize.MaxSize)
			size = replaceAxis(d.size, d.axisName, desired)
			-- Face-anchor scaling for blocks. Radial cylinder resizing stays centered.
			if d.component.nodes[d.index].kind ~= "Cylinder"
				and d.component.nodes[d.index].kind ~= "Tube" then
				position = d.position + d.worldDirection * ((desired - original) / 2)
			end
		end
	end
	local ok = self.document:applyTransform(d.component, d.index, position, size, rotation)
	if not ok then return end
	local node = d.component.nodes[d.index]
	d.dirty = d.dirty or node.position ~= d.position or node.size ~= d.size or node.rotation ~= d.rotation
	self.onChange("update", d.component, d.index)
end

function TransformGizmo:finishDrag()
	local d = self.drag
	if not d then return end
	self.drag = nil
	self.onChange("finish", d.component, d.index, d.dirty)
end

function TransformGizmo:isDragging(): boolean
	return self.drag ~= nil
end

function TransformGizmo:capturesPoint(point: Vector2): boolean
	if self.hidden or not self.component then return false end
	for _, entry in pairs(self.axes) do
		if entry.knob.Visible then
			local p = entry.knob.AbsolutePosition
			local size = entry.knob.AbsoluteSize
			if point.X >= p.X - 5 and point.Y >= p.Y - 5
				and point.X <= p.X + size.X + 5 and point.Y <= p.Y + size.Y + 5 then
				return true
			end
		end
	end
	return false
end

function TransformGizmo:setMode(mode: string)
	if self.drag then return end
	if mode ~= "Move" and mode ~= "Scale" and mode ~= "Rotate" then return end
	self.mode = mode
	self.hidden = false
end

function TransformGizmo:setHidden(value: boolean)
	if self.drag then return end
	self.hidden = value
end

function TransformGizmo:show(component, index: number)
	self.component, self.index = component, index
end

function TransformGizmo:hide()
	if self.drag then return end
	self.component, self.index = nil, nil
end

function TransformGizmo:update()
	local node = if self.component and self.index
		then self.component.nodes[self.index] else nil
	local camera = workspace.CurrentCamera
	local usable = node ~= nil and camera ~= nil and not self.hidden
	if not usable then
		self.center.Visible = false
		for _, entry in pairs(self.axes) do
			entry.line.Visible = false
			entry.knob.Visible = false
			for _, segment in ipairs(entry.ring) do segment.Visible = false end
		end
		return
	end

	local position = node.position
	local p, visible = getScreen(camera, position)
	if not visible then
		self.center.Visible = false
		for _, entry in pairs(self.axes) do
			entry.line.Visible = false
			entry.knob.Visible = false
			for _, segment in ipairs(entry.ring) do segment.Visible = false end
		end
		return
	end
	self.center.Visible = true
	self.center.Position = UDim2.fromOffset(p.X, p.Y)
	local basis = rotationOf(node)
	local px1 = getScreen(camera, position + camera.CFrame.RightVector)
	local pxPerStud = math.max(1, (px1 - p).Magnitude)
	-- Scale with camera magnification and projected part size, but clamp to a
	-- compact screen footprint; tiny 0.05-stud parts still have usable grips.
	local apparentSize = math.max(node.size.X, node.size.Y, node.size.Z) * pxPerStud
	local length = math.clamp(19 + apparentSize * 0.4, 29, 88)
	local ringWorldRadius = length / pxPerStud

	for _, axis in ipairs(AXES) do
		local entry = self.axes[axis.name]
		local dir = basis:VectorToWorldSpace(axis.vector)
		if self.mode == "Rotate" then
			entry.line.Visible = false
			local u = basis:VectorToWorldSpace(
				if axis.name == "X" then Vector3.yAxis else Vector3.xAxis
			)
			local v = dir:Cross(u)
			local projected = {}
			for i = 0, 24 do
				local a = i / 24 * math.pi * 2
				local coord = position + (u * math.cos(a) + v * math.sin(a)) * ringWorldRadius
				projected[i + 1] = getScreen(camera, coord)
			end
			for i = 1, 24 do
				drawSegment(entry.ring[i], projected[i], projected[i + 1], 1.8)
			end
			local markerPoint = projected[4 + (if axis.name == "X" then 0 elseif axis.name == "Y" then 7 else 14)]
			entry.knob.Position = UDim2.fromOffset(markerPoint.X, markerPoint.Y)
			entry.knob.Visible = true
		else
			for _, segment in ipairs(entry.ring) do segment.Visible = false end
			local step = math.clamp((camera.CFrame.Position - position).Magnitude * 0.12, 0.01, 0.25)
			local endProjection = getScreen(camera, position + dir * step)
			local radial = endProjection - p
			if radial.Magnitude < 1.25 then
				entry.line.Visible = false
				entry.knob.Visible = false
			else
				local endPoint = p + radial.Unit * length
				drawSegment(entry.line, p, endPoint, 2)
				entry.knob.Position = UDim2.fromOffset(endPoint.X, endPoint.Y)
				entry.knob.Visible = true
			end
		end
		local label = entry.knob
		label.Size = if self.mode == "Scale" then UDim2.fromOffset(17, 17)
			elseif self.mode == "Rotate" then UDim2.fromOffset(16, 16)
			else UDim2.fromOffset(18, 18)
		label.Text = if self.mode == "Rotate" then axis.name else axis.name
	end
end

function TransformGizmo:destroy()
	if self.drag then self:finishDrag() end
	RunService:UnbindFromRenderStep("FORM_CustomTransformRender")
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.gui:Destroy()
end

return TransformGizmo
