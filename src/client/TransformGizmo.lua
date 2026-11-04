--!strict
-- Previous stock Roblox handles restored by request.
-- Six face-resize grips anchor the opposite face as dimensions change.
-- Source primitives are modified in real time; no ghost or gratuitous CSG.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize = require(FORM.Quantize)

local TransformGizmo = {}
TransformGizmo.__index = TransformGizmo

local function nodeCFrame(node): CFrame
	return CFrame.new(node.position)
		* CFrame.fromOrientation(
			math.rad(node.rotation.X),
			math.rad(node.rotation.Y),
			math.rad(node.rotation.Z)
		)
end

local function field(vector: Vector3, axis: string): number
	if axis == "X" then return vector.X end
	if axis == "Y" then return vector.Y end
	return vector.Z
end

local function withAxis(vector: Vector3, axis: string, value: number): Vector3
	if axis == "X" then return Vector3.new(value, vector.Y, vector.Z) end
	if axis == "Y" then return Vector3.new(vector.X, value, vector.Z) end
	return Vector3.new(vector.X, vector.Y, value)
end

local function axisOf(normal: Vector3): string
	if math.abs(normal.X) > 0 then return "X" end
	if math.abs(normal.Y) > 0 then return "Y" end
	return "Z"
end

function TransformGizmo.new(playerGui: PlayerGui, document, onChange)
	local proxy = Instance.new("Part")
	proxy.Name = "FORM_TransformProxy"
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanTouch = false
	proxy.CanQuery = false
	proxy.CastShadow = false
	proxy.Transparency = 1
	proxy.Material = Enum.Material.Neon
	proxy.Color = Color3.fromRGB(109, 214, 226)
	proxy.Size = Vector3.one * 0.2
	proxy.Parent = workspace

	local move = Instance.new("Handles")
	move.Name = "FORM_MoveHandles"
	move.Style = Enum.HandlesStyle.Movement
	move.Color3 = Color3.fromRGB(94, 215, 231)
	move.Adornee = proxy
	move.Visible = false
	move.Faces = Faces.new(
		Enum.NormalId.Top, Enum.NormalId.Bottom,
		Enum.NormalId.Left, Enum.NormalId.Right,
		Enum.NormalId.Front, Enum.NormalId.Back
	)
	move.Parent = playerGui

	local resize = Instance.new("Handles")
	resize.Name = "FORM_ScaleHandles"
	resize.Style = Enum.HandlesStyle.Resize
	resize.Color3 = Color3.fromRGB(247, 196, 109)
	resize.Adornee = proxy
	resize.Visible = false
	resize.Faces = Faces.new(
		Enum.NormalId.Top, Enum.NormalId.Bottom,
		Enum.NormalId.Left, Enum.NormalId.Right,
		Enum.NormalId.Front, Enum.NormalId.Back
	)
	resize.Parent = playerGui

	local rotate = Instance.new("ArcHandles")
	rotate.Name = "FORM_RotateHandles"
	rotate.Color3 = Color3.fromRGB(203, 159, 244)
	rotate.Adornee = proxy
	rotate.Visible = false
	rotate.Parent = playerGui

	local self = setmetatable({
		document = document,
		onChange = onChange,
		proxy = proxy,
		move = move,
		resize = resize,
		rotate = rotate,
		mode = "Move",
		hidden = false,
		component = nil,
		index = nil,
		dragStart = nil,
		dragChanged = false,
		connections = {},
	}, TransformGizmo)

	local function connect(signal, callback)
		table.insert(self.connections, signal:Connect(callback))
	end

	local function beginDrag()
		if not self.component or not self.index then return end
		local node = self.component.nodes[self.index]
		if not node then return end
		self.dragStart = {
			component = self.component,
			index = self.index,
			position = node.position,
			size = node.size,
			rotation = node.rotation,
		}
		self.dragChanged = false
		proxy.Transparency = 1
		self.onChange("begin", self.dragStart.component, self.dragStart.index)
	end

	local function endDrag()
		if not self.dragStart then return end
		local start = self.dragStart
		local changed = self.dragChanged
		self.dragStart = nil
		self.dragChanged = false
		proxy.Transparency = 1
		self.onChange("finish", start.component, start.index, changed)
	end

	local function apply(position: Vector3?, size: Vector3?, rotation: Vector3?)
		local origin = self.dragStart
		if not origin then return end
		local ok, reason = document:applyTransform(origin.component, origin.index, position, size, rotation, self.mode == "Scale")
		if ok then
			local node = origin.component.nodes[origin.index]
			if node.position ~= origin.position or node.size ~= origin.size or node.rotation ~= origin.rotation then
				self.dragChanged = true
			end
			self:show(origin.component, origin.index)
			self.onChange("update", origin.component, origin.index)
		end
	end

	for _, handles in ipairs({ move, resize }) do
		connect(handles.MouseButton1Down, function(_face)
			if self.mode == (if handles == move then "Move" else "Scale") then beginDrag() end
		end)
		connect(handles.MouseDrag, function(face: Enum.NormalId, distance: number)
			local start = self.dragStart
			if not start then return end
			if self.mode ~= (if handles == move then "Move" else "Scale") then return end
			local normal = Vector3.FromNormalId(face)
			local rotation = CFrame.fromOrientation(
				math.rad(start.rotation.X),
				math.rad(start.rotation.Y),
				math.rad(start.rotation.Z)
			)
			local worldDirection = rotation:VectorToWorldSpace(normal)
			if handles == move then
				apply(start.position + worldDirection * distance, nil, nil)
			else
				local axis = axisOf(normal)
				local oldDimension = field(start.size, axis)
				local newDimension = math.clamp(
					Quantize.snap(oldDimension + distance, Quantize.Grid),
					Quantize.MinSize,
					Quantize.MaxSize
				)
				local actualChange = newDimension - oldDimension
				local newSize = withAxis(start.size, axis, newDimension)
				-- Face-local sizing: moving a + or - face shifts the center by
				-- half the dimension change, leaving the opposite face anchored.
				local newPosition = start.position + worldDirection * (actualChange / 2)
				apply(newPosition, newSize, nil)
			end
		end)
		connect(handles.MouseButton1Up, function(_face)
			endDrag()
		end)
	end

	connect(rotate.MouseButton1Down, function(_axis)
		if self.mode == "Rotate" then beginDrag() end
	end)
	connect(rotate.MouseDrag, function(axis: Enum.Axis, relativeAngle: number, _deltaRadius: number)
		local start = self.dragStart
		if not start or self.mode ~= "Rotate" then return end
		local axisName = axis.Name
		if axisName ~= "X" and axisName ~= "Y" and axisName ~= "Z" then return end
		local nextRotation = withAxis(start.rotation, axisName,
			field(start.rotation, axisName) + math.deg(relativeAngle))
		apply(nil, nil, nextRotation)
	end)
	connect(rotate.MouseButton1Up, function(_axis)
		endDrag()
	end)

	return self
end

function TransformGizmo:isDragging(): boolean
	return self.dragStart ~= nil
end

function TransformGizmo:capturesPoint(_point: Vector2): boolean
	return self.dragStart ~= nil
end

function TransformGizmo:setMode(mode: string)
	if mode ~= "Move" and mode ~= "Scale" and mode ~= "Rotate" then return end
	if self.dragStart then return end
	self.mode = mode
	self.hidden = false
	self:refresh()
end

function TransformGizmo:setHidden(hidden: boolean)
	if self.dragStart then return end
	self.hidden = hidden
	self:refresh()
end

function TransformGizmo:show(component, index: number)
	self.component = component
	self.index = index
	self:refresh()
end

function TransformGizmo:hide()
	if self.dragStart then return end
	self.component = nil
	self.index = nil
	self:refresh()
end

function TransformGizmo:refresh()
	local node = if self.component and self.index
		then self.component.nodes[self.index]
		else nil
	local visible = node ~= nil
	self.move.Visible = visible and not self.hidden and self.mode == "Move"
	self.resize.Visible = visible and not self.hidden and self.mode == "Scale"
	self.rotate.Visible = visible and not self.hidden and self.mode == "Rotate"
	if not node then return end

	self.proxy.CFrame = nodeCFrame(node)
	self.proxy.Size = Vector3.new(
		math.max(node.size.X, Quantize.MinSize),
		math.max(node.size.Y, Quantize.MinSize),
		math.max(node.size.Z, Quantize.MinSize)
	)
end

function TransformGizmo:destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.move:Destroy()
	self.resize:Destroy()
	self.rotate:Destroy()
	self.proxy:Destroy()
end

return TransformGizmo
