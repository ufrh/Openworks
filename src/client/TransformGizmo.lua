--!strict
-- Small, camera-adaptive part grips with one Highlight per interactive axis handle.
-- Three positive-axis move arrows, six face scale spheres, three rotation knobs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize = require(FORM.Quantize)

local TransformGizmo = {}
TransformGizmo.__index = TransformGizmo

local AXES = {
	{ normal = Vector3.xAxis, name = "X+", axis = "X", color = Color3.fromRGB(224, 88, 91) },
	{ normal = -Vector3.xAxis, name = "X-", axis = "X", color = Color3.fromRGB(224, 88, 91) },
	{ normal = Vector3.yAxis, name = "Y+", axis = "Y", color = Color3.fromRGB(99, 205, 122) },
	{ normal = -Vector3.yAxis, name = "Y-", axis = "Y", color = Color3.fromRGB(99, 205, 122) },
	{ normal = Vector3.zAxis, name = "Z+", axis = "Z", color = Color3.fromRGB(94, 155, 235) },
	{ normal = -Vector3.zAxis, name = "Z-", axis = "Z", color = Color3.fromRGB(94, 155, 235) },
}
local MOVE_AXES = { AXES[1], AXES[3], AXES[5] }
local MM_PER_STUD = 280 -- Roblox standard physical scale, 0.28 m per stud.
local ROTATIONS = {
	{ normal = Vector3.xAxis, radial = Vector3.yAxis, axis = "X", color = Color3.fromRGB(224, 88, 91) },
	{ normal = Vector3.yAxis, radial = Vector3.zAxis, axis = "Y", color = Color3.fromRGB(99, 205, 122) },
	{ normal = Vector3.zAxis, radial = Vector3.xAxis, axis = "Z", color = Color3.fromRGB(94, 155, 235) },
}

local function frame(node)
	return CFrame.new(node.position) * CFrame.fromOrientation(
		math.rad(node.rotation.X), math.rad(node.rotation.Y), math.rad(node.rotation.Z))
end

local function getAxis(v: Vector3, axis: string): number
	if axis == "X" then return v.X elseif axis == "Y" then return v.Y end
	return v.Z
end

local function putAxis(v: Vector3, axis: string, n: number): Vector3
	if axis == "X" then return Vector3.new(n, v.Y, v.Z) end
	if axis == "Y" then return Vector3.new(v.X, n, v.Z) end
	return Vector3.new(v.X, v.Y, n)
end

local function rayFor(point: Vector2): (Vector3?, Vector3?)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	return ray.Origin, ray.Direction.Unit
end

-- Closest parameter along world axis to a viewport ray. Use camera-facing
-- projection as a fallback when the camera looks almost parallel to the axis.
local function axisParameter(point: Vector2, pivot: Vector3, axis: Vector3): number?
	local origin, direction = rayFor(point)
	if not origin or not direction then return nil end
	local b = axis:Dot(direction)
	local denominator = 1 - b * b
	if denominator > 0.0005 then
		local delta = origin - pivot
		return (delta:Dot(axis) - b * delta:Dot(direction)) / denominator
	end
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local right = camera.CFrame.RightVector
	local up = camera.CFrame.UpVector
	local screenAxis = Vector2.new(axis:Dot(right), -axis:Dot(up))
	if screenAxis.Magnitude < 0.05 then return nil end
	local pivot2d, visible = camera:WorldToViewportPoint(pivot)
	if not visible then return nil end
	local next2d, _ = camera:WorldToViewportPoint(pivot + axis)
	local pixels = Vector2.new(next2d.X - pivot2d.X, next2d.Y - pivot2d.Y)
	if pixels.Magnitude < 0.001 then return nil end
	return (point - Vector2.new(pivot2d.X, pivot2d.Y)):Dot(pixels) / pixels:Dot(pixels)
end

local function planeRadial(point: Vector2, center: Vector3, normal: Vector3): Vector3?
	local origin, direction = rayFor(point)
	if not origin or not direction then return nil end
	local denom = normal:Dot(direction)
	if math.abs(denom) < 0.015 then return nil end
	local distance = normal:Dot(center - origin) / denom
	if distance < 0 then return nil end
	local radial = origin + direction * distance - center
	if radial.Magnitude < 0.001 then return nil end
	return radial.Unit
end

local function visualScale(position: Vector3): number
	local camera = workspace.CurrentCamera
	if not camera then return 0.12 end
	local viewport = camera.ViewportSize
	local distance = (camera.CFrame.Position - position).Magnitude
	-- Approx. 8 screen pixels per grip, independent of the object dimensions.
	local worldPerPixel = 2 * distance * math.tan(math.rad(camera.FieldOfView) / 2) / math.max(viewport.Y, 1)
	return math.clamp(worldPerPixel * 8, 0.025, 0.34)
end

-- Cone tip is a user-supplied MeshPart named "Cone" directly inside ReplicatedStorage.
local coneTemplate = ReplicatedStorage:WaitForChild("Cone")
assert(coneTemplate:IsA("MeshPart"), "ReplicatedStorage.Cone must be a MeshPart")

local function makePart(parent: Instance, name: string, color: Color3, shape: Enum.PartType): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Parent = parent
	return part
end

local function newArrow(folder: Folder, name: string, color: Color3)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = folder

	local stem = makePart(model, "Stem", color, Enum.PartType.Cylinder)
	local tip = coneTemplate:Clone()
	tip.Name = "Tip"
	tip.Anchored = true
	tip.CanCollide = false
	tip.CanTouch = false
	tip.CanQuery = true
	tip.CastShadow = false
	tip.Material = Enum.Material.SmoothPlastic
	tip.Color = color
	tip.TextureID = ""
	tip.Parent = model

	local highlight = Instance.new("Highlight")
	highlight.Name = "AxisHighlight"
	highlight.Adornee = model
	highlight.FillColor = color
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model

	return { model = model, part = tip, stem = stem, tip = tip,
		highlight = highlight }
end

local function newSphere(folder: Folder, name: string, color: Color3)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = folder
	local part = makePart(model, "Sphere", color, Enum.PartType.Ball)
	local highlight = Instance.new("Highlight")
	highlight.Name = "AxisHighlight"
	highlight.Adornee = model
	highlight.FillColor = color
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model
	return { model = model, part = part, highlight = highlight }
end

local function newRotationGrip(folder: Folder, name: string, color: Color3)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = folder
	local part = makePart(model, "Knob", color, Enum.PartType.Ball)
	local highlight = Instance.new("Highlight")
	highlight.Name = "AxisHighlight"
	highlight.Adornee = model
	highlight.FillColor = color
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model
	return { model = model, part = part, highlight = highlight }
end

local function placeArrow(grip, face: Vector3, direction: Vector3, unit: number)
	-- The arrow's length scales with camera distance; diameter remains delicate.
	local shaftLength = unit * 3.0
	local shaftDiameter = unit * 0.12
	local tipLength = unit * 0.95
	local tipDiameter = unit * 0.62
	local begin = face + direction * (unit * 2.0)
	local stemCenter = begin + direction * (shaftLength / 2)
	local tipCenter = begin + direction * (shaftLength + tipLength / 2)
	-- Native cylinder runs on local X.
	grip.stem.Size = Vector3.new(shaftLength, shaftDiameter, shaftDiameter)
	grip.stem.CFrame = CFrame.lookAt(stemCenter, stemCenter + direction)
		* CFrame.Angles(0, math.pi / 2, 0)
	-- ReplicatedStorage.Cone is modeled pointing along local +Y.
	grip.tip.Size = Vector3.new(tipDiameter, tipLength, tipDiameter)
	grip.tip.CFrame = CFrame.lookAt(tipCenter, tipCenter + direction)
		* CFrame.Angles(-math.pi / 2, 0, 0)
end

local function newMeasurement(playerGui: PlayerGui)
	local gui = Instance.new("BillboardGui")
	gui.Name = "FORM_TransformMeasurement"
	gui.Size = UDim2.fromOffset(126, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0.18, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.Parent = playerGui
	local label = Instance.new("TextLabel")
	label.Name = "Distance"
	label.BackgroundColor3 = Color3.fromRGB(20, 25, 29)
	label.BackgroundTransparency = 0.12
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 15
	label.TextColor3 = Color3.fromRGB(242, 245, 247)
	label.Text = ""
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = label
	return gui, label
end

function TransformGizmo.new(playerGui: PlayerGui, document, onChange)
	local folder = Instance.new("Folder")
	folder.Name = "FORM_TransformGrips"
	folder.Parent = workspace
	local measurement, measurementText = newMeasurement(playerGui)
	local self = setmetatable({
		document = document, onChange = onChange, folder = folder,
		grips = {}, lookup = {}, connections = {},
		mode = "Move", hidden = false, component = nil, index = nil,
		dragStart = nil, dragChanged = false, hovered = nil, visualFrame = nil, visualSize = nil,
		measurement = measurement, measurementText = measurementText,
	}, TransformGizmo)

	for _, spec in ipairs(MOVE_AXES) do
		local arrow = newArrow(folder, "Move_" .. spec.axis, spec.color)
		local grip = {
			model = arrow.model, part = arrow.part, stem = arrow.stem, tip = arrow.tip,
			highlight = arrow.highlight, baseColor = spec.color, hoverAlpha = 0,
			normal = spec.normal, axis = spec.axis, mode = "Move",
		}
		table.insert(self.grips, grip)
		self.lookup[grip.stem] = grip
		self.lookup[grip.tip] = grip
	end
	for _, spec in ipairs(AXES) do
		local sphere = newSphere(folder, "Scale_" .. spec.name, spec.color)
		local grip = {
			model = sphere.model, part = sphere.part,
			highlight = sphere.highlight, baseColor = spec.color, hoverAlpha = 0,
			normal = spec.normal, axis = spec.axis, mode = "Scale",
		}
		table.insert(self.grips, grip)
		self.lookup[grip.part] = grip
	end
	for _, spec in ipairs(ROTATIONS) do
		local control = newRotationGrip(folder, "Rotate_" .. spec.axis, spec.color)
		local grip = {
			model = control.model, part = control.part,
			highlight = control.highlight, baseColor = spec.color, hoverAlpha = 0, normal = spec.normal,
			radial = spec.radial, axis = spec.axis, mode = "Rotate",
		}
		table.insert(self.grips, grip)
		self.lookup[grip.part] = grip
	end

	local function connect(signal, fn)
		table.insert(self.connections, signal:Connect(fn))
	end

	local function pick(point: Vector2)
		local camera = workspace.CurrentCamera
		if not camera then return nil end
		local ray = camera:ViewportPointToRay(point.X, point.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { folder }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 2048, params)
		return if hit then self.lookup[hit.Instance] else nil
	end

	local function begin(grip, point: Vector2)
		if self.hidden or not self.component or not self.index then return end
		local node = self.component.nodes[self.index]
		if not node then return end
		local cf = frame(node)
		local direction = cf:VectorToWorldSpace(grip.normal)
		local pivot = node.position
		local radial = if grip.mode == "Rotate"
			then cf:VectorToWorldSpace(grip.radial) else nil
		self.dragStart = {
			component = self.component, index = self.index,
			position = node.position, size = node.size, rotation = node.rotation,
			grip = grip, direction = direction, pivot = pivot,
			initialParameter = if grip.mode == "Face" then axisParameter(point, pivot, direction) else nil,
			initialRadial = if radial then (planeRadial(point, pivot, direction) or radial) else nil,
		}
		self.dragChanged = false
		self.hovered = grip
		self.measurement.Adornee = grip.part
		self.measurement.Enabled = true
		self.measurementText.Text = if grip.mode == "Rotate" then "0°" else "0 mm"
		self.onChange("begin", self.component, self.index)
	end

	local function drag(point: Vector2)
		local start = self.dragStart
		if not start then return end
		local position, size, rotation = nil, nil, nil
		if start.grip.mode ~= "Rotate" then
			local parameter = axisParameter(point, start.pivot, start.direction)
			if not parameter or not start.initialParameter then return end
			local distance = Quantize.snap(parameter - start.initialParameter, Quantize.Grid)
			if self.mode == "Move" then
				position = start.position + start.direction * distance
			elseif self.mode == "Scale" then
				local old = getAxis(start.size, start.grip.axis)
				local new = math.clamp(Quantize.snap(old + distance, Quantize.Grid),
					Quantize.MinSize, Quantize.MaxSize)
				size = putAxis(start.size, start.grip.axis, new)
				position = start.position + start.direction * ((new - old) / 2)
			end
		else
			local current = planeRadial(point, start.pivot, start.direction)
			if not current or not start.initialRadial then return end
			local initial = start.initialRadial
			local radians = math.atan2(start.direction:Dot(initial:Cross(current)), initial:Dot(current))
			rotation = putAxis(start.rotation, start.grip.axis,
				getAxis(start.rotation, start.grip.axis) + math.deg(radians))
		end
		local ok = document:applyTransform(start.component, start.index, position, size, rotation, self.mode == "Scale")
		if ok then
			local node = start.component.nodes[start.index]
			if node.position ~= start.position or node.size ~= start.size or node.rotation ~= start.rotation then
				self.dragChanged = true
			end
			local delta
			if self.mode == "Move" then
				delta = (node.position - start.position):Dot(start.direction)
			elseif self.mode == "Scale" then
				delta = getAxis(node.size, start.grip.axis) - getAxis(start.size, start.grip.axis)
			else
				delta = getAxis(node.rotation, start.grip.axis) - getAxis(start.rotation, start.grip.axis)
				if delta > 180 then delta -= 360 elseif delta < -180 then delta += 360 end
			end
			self.measurementText.Text = if self.mode == "Rotate"
				then string.format("%+.0f°", delta)
				else string.format("%+.1f mm", delta * MM_PER_STUD)
			self:refresh()
			self.onChange("update", start.component, start.index)
		end
	end

	local function finish()
		local start = self.dragStart
		if not start then return end
		self.dragStart = nil
		self.measurement.Enabled = false
		self.measurement.Adornee = nil
		local changed = self.dragChanged
		self.dragChanged = false
		self.onChange("finish", start.component, start.index, changed)
		self:refresh()
	end

	connect(UserInputService.InputBegan, function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or self.dragStart then return end
		local point = UserInputService:GetMouseLocation()
		local grip = pick(point)
		if grip and grip.mode == self.mode then
			begin(grip, point)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if self.dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
			drag(UserInputService:GetMouseLocation())
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then finish() end
	end)
	connect(RunService.RenderStepped, function(dt)
		-- Hover is resolved individually; a captured handle remains emphasized.
		if self.hidden or not self.component then
			self.hovered = nil
		elseif self.dragStart then
			self.hovered = self.dragStart.grip
		else
			self.hovered = pick(UserInputService:GetMouseLocation())
		end
		self:refresh(dt)
	end)
	self._pick = pick
	return self
end

function TransformGizmo:isDragging(): boolean
	return self.dragStart ~= nil
end

function TransformGizmo:capturesPoint(point: Vector2): boolean
	if self.dragStart then return true end
	if self.hidden or not self.component then return false end
	return self._pick(point) ~= nil
end

function TransformGizmo:setMode(mode: string)
	if mode ~= "Move" and mode ~= "Scale" and mode ~= "Rotate" or self.dragStart then return end
	self.mode, self.hidden = mode, false
	self:refresh()
end

function TransformGizmo:setHidden(hidden: boolean)
	if self.dragStart then return end
	self.hidden = hidden
	self:refresh()
end

function TransformGizmo:show(component, index: number)
	if self.component ~= component or self.index ~= index then
		self.visualFrame, self.visualSize = nil, nil
	end
	self.component, self.index = component, index
	self:refresh()
end

function TransformGizmo:hide()
	if self.dragStart then return end
	self.component, self.index = nil, nil
	self.visualFrame, self.visualSize, self.hovered = nil, nil, nil
	self:refresh()
end

function TransformGizmo:refresh(dt: number?)
	local node = if self.component and self.index
		then self.component.nodes[self.index] else nil
	local targetFrame = if node then frame(node) else nil
	local cf = targetFrame
	local size = if node then node.size else nil
	if node and targetFrame then
		-- Exponential smoothing is frame-rate independent. Source node stays snapped.
		local alpha = if dt then 1 - math.exp(-26 * dt) else (if self.visualFrame then 0 else 1)
		self.visualFrame = if self.visualFrame then self.visualFrame:Lerp(targetFrame, alpha) else targetFrame
		self.visualSize = if self.visualSize then self.visualSize:Lerp(node.size, alpha) else node.size
		cf = self.visualFrame
		size = self.visualSize
	else
		self.visualFrame, self.visualSize = nil, nil
	end
	for _, grip in ipairs(self.grips) do
		local hoverTarget = if grip == self.hovered then 1 else 0
		local hoverBlend = if dt then 1 - math.exp(-18 * dt) else 1
		grip.hoverAlpha += (hoverTarget - grip.hoverAlpha) * hoverBlend
		grip.highlight.FillColor = grip.baseColor:Lerp(Color3.new(1, 1, 1), grip.hoverAlpha * 0.38)
		local visible = node ~= nil and not self.hidden and grip.mode == self.mode
		grip.highlight.Enabled = visible
		for _, part in ipairs(if grip.mode == "Move"
			then { grip.stem, grip.tip } else { grip.part }) do
			part.Transparency = if visible then 0 else 1
			part.CanQuery = visible
		end
		if visible and node then
			local unit = visualScale(cf.Position)
			if grip.mode == "Move" then
				local direction = cf:VectorToWorldSpace(grip.normal)
				local face = cf:PointToWorldSpace(
					grip.normal * (getAxis(size, grip.axis) / 2))
				placeArrow(grip, face, direction, unit)
			elseif grip.mode == "Scale" then
				grip.part.Position = cf:PointToWorldSpace(
					grip.normal * (getAxis(size, grip.axis) / 2 + unit * 0.75))
				grip.part.Size = Vector3.one * unit * (1.35 + 0.18 * grip.hoverAlpha)
			else
				grip.part.Position = cf:PointToWorldSpace(grip.radial * (unit * 6))
				grip.part.Size = Vector3.one * unit * (1 + 0.14 * grip.hoverAlpha)
			end
		end
	end
end

function TransformGizmo:destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.folder:Destroy()
	self.measurement:Destroy()
end

return TransformGizmo
