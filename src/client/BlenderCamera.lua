--!strict
-- Blender-style viewport navigation for FORM's temporary 3D editor.
-- Coordinate convention: Roblox Y-up; Front = +Z, Right = +X, Top = +Y.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BlenderCamera = {}
BlenderCamera.__index = BlenderCamera

local RENDER_NAME = "FORM_BlenderViewportCamera"
local FOV = 60
local MIN_DISTANCE = 0.25
local MAX_DISTANCE = 2000
local MIN_ORTHO_HEIGHT = 0.1
local MAX_ORTHO_HEIGHT = 2000
local ORBIT_SENSITIVITY = 0.007
local SNAP_ANGLE = math.rad(15)
local POLE_LIMIT = math.rad(89.9)
local PERSPECTIVE_TAN = math.tan(math.rad(FOV) / 2)
local FALLBACK_TAN = math.tan(math.rad(1) / 2)

local function isShiftDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function isCtrlDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

local function isAltDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
end

local function mouseDragMode(): string
	if isCtrlDown() then return "Dolly" end
	if isShiftDown() then return "Pan" end
	return "Orbit"
end

local function boundsRadius(size: Vector3): number
	return math.max(0.5, size.Magnitude / 2)
end

function BlenderCamera.new(getSelectedBounds, getSceneBounds)
	local self = setmetatable({
		target = Vector3.new(0, 2, 0),
		yaw = math.rad(40),
		pitch = math.rad(30),
		roll = 0,
		distance = 26,
		orthographicHeight = 2 * 26 * PERSPECTIVE_TAN,
		orthographic = false,
		axisView = nil,
		autoOrthographic = false,
		dragging = false,
		dragButton = nil,
		savedMouseBehavior = Enum.MouseBehavior.Default,
		camera = nil,
		projectionDirty = true,
		nativeOrtho = false,
		getSelectedBounds = getSelectedBounds,
		getSceneBounds = getSceneBounds,
		onFrame = nil,
		connections = {},
	}, BlenderCamera)

	local function connect(signal, callback)
		table.insert(self.connections, signal:Connect(callback))
	end

	connect(UserInputService.InputBegan, function(input, processed)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton3
			or (kind == Enum.UserInputType.MouseButton1 and isAltDown()) then
			if processed or UserInputService:GetFocusedTextBox() then return end
			self.dragging = true
			self.dragButton = kind
			self.savedMouseBehavior = UserInputService.MouseBehavior
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			return
		end

		if processed or UserInputService:GetFocusedTextBox() then return end
		if kind ~= Enum.UserInputType.Keyboard then return end
		local key = input.KeyCode
		local shift = isShiftDown()
		local ctrl = isCtrlDown()

		if key == Enum.KeyCode.KeypadOne then
			self:setView(if ctrl then "Back" else "Front")
		elseif key == Enum.KeyCode.KeypadThree then
			self:setView(if ctrl then "Left" else "Right")
		elseif key == Enum.KeyCode.KeypadSeven then
			self:setView(if ctrl then "Bottom" else "Top")
		elseif key == Enum.KeyCode.KeypadFive then
			self:toggleProjection()
		elseif key == Enum.KeyCode.KeypadPeriod or key == Enum.KeyCode.F then
			self:frameSelected()
		elseif key == Enum.KeyCode.Home then
			self:frameAll()
		elseif key == Enum.KeyCode.KeypadNine then
			self.yaw += math.pi
			self.pitch = math.clamp(-self.pitch, -POLE_LIMIT, POLE_LIMIT)
			self.roll = 0
			self.axisView = nil
		elseif key == Enum.KeyCode.KeypadFour or key == Enum.KeyCode.KeypadSix
			or key == Enum.KeyCode.KeypadTwo or key == Enum.KeyCode.KeypadEight then
			local dx = (if key == Enum.KeyCode.KeypadFour then -1 elseif key == Enum.KeyCode.KeypadSix then 1 else 0)
			local dy = (if key == Enum.KeyCode.KeypadEight then 1 elseif key == Enum.KeyCode.KeypadTwo then -1 else 0)
			if shift and not ctrl and dx ~= 0 then
				self.roll += dx * SNAP_ANGLE
			elseif ctrl or shift then
				self:panPixels(-dx * 65, dy * 65)
			else
				self.yaw += dx * SNAP_ANGLE
				self.pitch = math.clamp(self.pitch + dy * SNAP_ANGLE, -POLE_LIMIT, POLE_LIMIT)
				self.axisView = nil
				-- Blender auto-perspective after orbiting away from a cardinal view.
				if self.autoOrthographic then
					self:setProjection(false)
				end
			end
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if self.dragging and input.UserInputType == self.dragButton then
			self:releaseMouse()
		end
	end)

	connect(UserInputService.InputChanged, function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.MouseWheel or processed then return end
		local steps = input.Position.Z
		if steps == 0 then return end
		if isShiftDown() then
			self:panPixels(0, -steps * 40)
		elseif isCtrlDown() then
			self:panPixels(steps * 40, 0)
		else
			self:zoom(math.pow(0.85, steps))
		end
	end)

	connect(UserInputService.WindowFocusReleased, function()
		self:releaseMouse()
	end)

	-- Reacquire CurrentCamera after character resets / Studio camera replacement.
	connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
		self.camera = nil
		self.projectionDirty = true
	end)

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 2, function()
		local camera = workspace.CurrentCamera
		if not camera then return end
		if camera ~= self.camera then
			self.camera = camera
			self.projectionDirty = true
		end

		if self.dragging then
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCurrentPosition then
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			end
			local delta = UserInputService:GetMouseDelta()
			if delta.Magnitude > 0 then
				local mode = mouseDragMode()
				if mode == "Orbit" then
					self.yaw -= delta.X * ORBIT_SENSITIVITY
					self.pitch = math.clamp(self.pitch + delta.Y * ORBIT_SENSITIVITY, -POLE_LIMIT, POLE_LIMIT)
					self.roll = 0
					if self.autoOrthographic then self:setProjection(false) end
					self.axisView = nil
				elseif mode == "Pan" then
					self:panPixels(delta.X, delta.Y)
				else
					self:zoom(math.exp(delta.Y * 0.012))
				end
			end
		end

		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = FOV

		if self.projectionDirty then
			self.projectionDirty = false
			self.nativeOrtho = pcall(function()
				camera.OrthographicMode = Enum.OrthographicMode.Vertical
				camera.ProjectionType = if self.orthographic
					then Enum.ProjectionType.Orthographic
					else Enum.ProjectionType.Perspective
			end)
		end

		local renderDistance = self.distance
		if self.orthographic then
			if self.nativeOrtho then
				camera.OrthographicSize = self.orthographicHeight
			else
				-- Fallback for clients without native orthographic support.
				-- 1-degree FOV + an increased distance preserves apparent scale.
				camera.FieldOfView = 1
				renderDistance = math.min(MAX_DISTANCE * 20, self.orthographicHeight / (2 * FALLBACK_TAN))
			end
		end

		local direction = Vector3.new(
			math.cos(self.pitch) * math.sin(self.yaw),
			math.sin(self.pitch),
			math.cos(self.pitch) * math.cos(self.yaw)
		)
		local upVector = Vector3.yAxis
		if self.axisView == "Top" then
			direction = Vector3.yAxis
			upVector = -Vector3.zAxis
		elseif self.axisView == "Bottom" then
			direction = -Vector3.yAxis
			upVector = Vector3.zAxis
		end
		local orientation = CFrame.lookAt(self.target + direction * renderDistance, self.target, upVector)
		camera.CFrame = orientation * CFrame.Angles(0, 0, self.roll)
		camera.Focus = CFrame.new(self.target)
		if self.onFrame then self.onFrame(camera.CFrame, self:viewLabel()) end
	end)

	return self
end

function BlenderCamera:viewLabel(): string
	local suffix = if self.orthographic then "ORTHO" else "PERSP"
	return (self.axisView or "USER"):upper() .. " " .. suffix
end

function BlenderCamera:releaseMouse()
	if not self.dragging then return end
	self.dragging = false
	self.dragButton = nil
	UserInputService.MouseBehavior = self.savedMouseBehavior
end

function BlenderCamera:setOnFrame(callback)
	self.onFrame = callback
end

function BlenderCamera:setProjection(enabled: boolean)
	if self.orthographic == enabled then return end
	if enabled then
		self.orthographicHeight = math.clamp(2 * self.distance * PERSPECTIVE_TAN, MIN_ORTHO_HEIGHT, MAX_ORTHO_HEIGHT)
	else
		self.distance = math.clamp(self.orthographicHeight / (2 * PERSPECTIVE_TAN), MIN_DISTANCE, MAX_DISTANCE)
	end
	self.orthographic = enabled
	self.projectionDirty = true
end

function BlenderCamera:toggleProjection()
	self:setProjection(not self.orthographic)
	self.autoOrthographic = false
end

function BlenderCamera:setView(view: string)
	local cardinal = {
		Front = { 0, 0 },
		Back = { math.pi, 0 },
		Right = { math.pi / 2, 0 },
		Left = { -math.pi / 2, 0 },
		Top = { 0, math.pi / 2 },
		Bottom = { 0, -math.pi / 2 },
	}
	local angles = cardinal[view]
	if not angles then return end
	self.yaw = angles[1]
	self.pitch = angles[2]
	self.roll = 0
	self.axisView = view
	self.autoOrthographic = true
	self:setProjection(true)
end

function BlenderCamera:zoom(factor: number)
	if self.orthographic then
		self.orthographicHeight = math.clamp(self.orthographicHeight * factor, MIN_ORTHO_HEIGHT, MAX_ORTHO_HEIGHT)
	else
		self.distance = math.clamp(self.distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	end
end

function BlenderCamera:panPixels(dx: number, dy: number)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local height = math.max(1, camera.ViewportSize.Y)
	local visibleHeight = if self.orthographic then self.orthographicHeight
		else 2 * self.distance * PERSPECTIVE_TAN
	local perPixel = visibleHeight / height
	self.target += (-camera.CFrame.RightVector * dx + camera.CFrame.UpVector * dy) * perPixel
end

function BlenderCamera:frameBounds(frame: CFrame?, size: Vector3?)
	if not frame or not size then return false end
	self.target = frame.Position
	local radius = boundsRadius(size)
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	local aspect = viewport.X / math.max(1, viewport.Y)
	local effectiveHalfFov = math.atan(PERSPECTIVE_TAN * math.min(1, aspect))
	local desiredDistance = math.clamp(radius / math.sin(effectiveHalfFov) * 1.25, MIN_DISTANCE, MAX_DISTANCE)
	self.distance = desiredDistance
	self.orthographicHeight = math.clamp(radius * 2.8, MIN_ORTHO_HEIGHT, MAX_ORTHO_HEIGHT)
	return true
end

function BlenderCamera:frameSelected(): boolean
	local frame, size = self.getSelectedBounds()
	return self:frameBounds(frame, size)
end

function BlenderCamera:frameAll(): boolean
	local frame, size = self.getSceneBounds()
	return self:frameBounds(frame, size)
end

function BlenderCamera:destroy()
	self:releaseMouse()
	RunService:UnbindFromRenderStep(RENDER_NAME)
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then
		pcall(function() camera.ProjectionType = Enum.ProjectionType.Perspective end)
		camera.CameraType = Enum.CameraType.Custom
	end
end

return BlenderCamera
