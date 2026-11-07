--!strict
-- Blender-style viewport navigation for FORM's temporary 3D editor.
-- Coordinate convention: Roblox Y-up; Front = +Z, Right = +X, Top = +Y.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BlenderCamera = {}
BlenderCamera.__index = BlenderCamera

local RENDER_NAME = "FORM_BlenderViewportCamera"
local INITIAL_FOV = 60
local MIN_FOV = 22
local MAX_FOV = 75
local MIN_DISTANCE = 0.75
local MAX_DISTANCE = 2000
local MIN_ORTHO_HEIGHT = 0.06
local MAX_ORTHO_HEIGHT = 2000
local ORBIT_SENSITIVITY = 0.007
local SNAP_ANGLE = math.rad(15)
local POLE_LIMIT = math.rad(89.9)
local function halfTan(fov: number): number
	return math.tan(math.rad(fov) / 2)
end
local PERSPECTIVE_TAN = halfTan(INITIAL_FOV)

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

local function mouseDragMode(_button: Enum.UserInputType?): string
	-- The workspace pivot is locked. MMB/RMB orbit; Ctrl+MMB zooms.
	if isCtrlDown() then return "Zoom" end
	return "Orbit"
end

local function boundsRadius(size: Vector3): number
	return math.max(0.042, size.Magnitude / 2)
end

function BlenderCamera.new(getSelectedBounds, getSceneBounds)
	local self = setmetatable({
		target = Vector3.zero,
		active=false,
		displayedTarget = Vector3.zero,
		displayedYaw = math.rad(40),
		displayedPitch = math.rad(30),
		displayedRoll = 0,
		displayedDistance = 8,
		displayedOrthoHeight = 2 * 8 * PERSPECTIVE_TAN,
		yaw = math.rad(40),
		pitch = math.rad(30),
		roll = 0,
		distance = 8,
		fov = INITIAL_FOV,
		displayedFov = INITIAL_FOV,
		orthographicHeight = 2 * 8 * PERSPECTIVE_TAN,
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
		onWheel = nil,
		connections = {},
	}, BlenderCamera)

	local function connect(signal, callback)
		table.insert(self.connections, signal:Connect(callback))
	end

	connect(UserInputService.InputBegan, function(input, processed)
		if not self.active then return end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton3
			or kind == Enum.UserInputType.MouseButton2
			or (kind == Enum.UserInputType.MouseButton1 and isAltDown()) then
			-- Roblox's default camera can mark RMB/MMB processed; navigation still owns them.
			if UserInputService:GetFocusedTextBox() then return end
			if processed and kind == Enum.UserInputType.MouseButton1 then return end
			if self.dragging then return end
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
				self:zoom(math.pow(0.92, dy + dx))
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
		if not self.active then return end
		if input.UserInputType ~= Enum.UserInputType.MouseWheel or processed then return end
		local steps = input.Position.Z
		if steps == 0 then return end
		-- Precision fabrication tools get the wheel before the camera;
		-- this is a direct callback, no double-zoom or delayed event race.
		if self.onWheel and self.onWheel(steps) then return end
		-- Wheel zoom must not alter the orbit pivot, view orientation or grid origin.
		self:zoom(math.pow(0.86, steps))
	end)

	connect(UserInputService.WindowFocusReleased, function()
		self:releaseMouse()
	end)

	-- Reacquire CurrentCamera after character resets / Studio camera replacement.
	connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
		self.camera = nil
		self.projectionDirty = true
	end)

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 2, function(dt)
		if not self.active then return end
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
				local mode = mouseDragMode(self.dragButton)
				if mode == "Orbit" then
					self:orbitDelta(delta)
				else
					self:zoom(math.exp(delta.Y * 0.012))
				end
			end
		end

		camera.CameraType = Enum.CameraType.Scriptable

		if self.projectionDirty then
			self.projectionDirty = false
			-- Real orthographic is a Studio Beta; do not teleport thousands of
			-- studs backward to fake it on clients where it is not supported.
			self.nativeOrtho = pcall(function()
				camera.OrthographicMode = Enum.OrthographicMode.Vertical
				camera.ProjectionType = if self.orthographic
					then Enum.ProjectionType.Orthographic
					else Enum.ProjectionType.Perspective
			end)
		end
		if not self.nativeOrtho and self.orthographic then
			self.orthographic = false
			self.autoOrthographic = false
		end

		local alpha = 1 - math.exp(-math.max(0, dt) * 16)
		self.displayedFov += (self.fov - self.displayedFov) * alpha
		camera.FieldOfView = self.displayedFov
		self.displayedTarget = self.target
		self.displayedOrthoHeight += (self.orthographicHeight - self.displayedOrthoHeight) * alpha
		if self.nativeOrtho and self.orthographic then
			camera.OrthographicSize = self.displayedOrthoHeight
		end


		-- Orbit around the active component workspace origin, which moves
		-- to the clicked placement point when a component is created.
		local yawDelta = (self.yaw - self.displayedYaw + math.pi) % (2 * math.pi) - math.pi
		local rollDelta = (self.roll - self.displayedRoll + math.pi) % (2 * math.pi) - math.pi
		self.displayedYaw += yawDelta * alpha
		self.displayedPitch += (self.pitch - self.displayedPitch) * alpha
		self.displayedRoll += rollDelta * alpha
		self.displayedDistance += (self.distance - self.displayedDistance) * alpha
		local direction = Vector3.new(
			math.cos(self.displayedPitch) * math.sin(self.displayedYaw),
			math.sin(self.displayedPitch),
			math.cos(self.displayedPitch) * math.cos(self.displayedYaw)
		)
		local upVector = Vector3.yAxis
		if self.axisView == "Top" and math.abs(self.displayedPitch - math.pi / 2) < 0.05 then
			upVector = -Vector3.zAxis
		elseif self.axisView == "Bottom" and math.abs(self.displayedPitch + math.pi / 2) < 0.05 then
			upVector = Vector3.zAxis
		end
		local frame = CFrame.lookAt(
			self.target+direction * self.displayedDistance,
			self.target,
			upVector
		) * CFrame.Angles(0, 0, self.displayedRoll)
		camera.CFrame = frame
		camera.Focus = CFrame.new(self.target)
		if self.onFrame then self.onFrame(frame, self:viewLabel()) end
	end)

	return self
end

-- Exposed for the draggable ViewportFrame orientation gizmo.
function BlenderCamera:orbitDelta(delta: Vector2)
	self.yaw -= delta.X * ORBIT_SENSITIVITY
	self.pitch = math.clamp(self.pitch + delta.Y * ORBIT_SENSITIVITY, -POLE_LIMIT, POLE_LIMIT)
	self.roll = 0
	if self.autoOrthographic then self:setProjection(false) end
	self.axisView = nil
end

function BlenderCamera:getFocusTarget(): Vector3
	return self.target
end

-- Entering workspace is a mode switch, not an animated camera flight.
-- Snap both internal interpolants AND the actual CurrentCamera now.
function BlenderCamera:snapNow()
	self.displayedYaw=self.yaw
	self.displayedPitch=self.pitch
	self.displayedRoll=self.roll
	self.displayedDistance=self.distance
	self.displayedFov=self.fov
	self.displayedOrthoHeight=self.orthographicHeight
	self.displayedTarget=self.target
	local camera=workspace.CurrentCamera
	if not camera or not self.active then return end
	self.camera=camera
	camera.CameraType=Enum.CameraType.Scriptable
	camera.FieldOfView=self.fov
	local ok=pcall(function()
		camera.OrthographicMode=Enum.OrthographicMode.Vertical
		camera.ProjectionType=if self.orthographic
			then Enum.ProjectionType.Orthographic
			else Enum.ProjectionType.Perspective
	end)
	self.nativeOrtho=ok
	self.projectionDirty=false
	if ok and self.orthographic then
		camera.OrthographicSize=self.orthographicHeight
	end
	if not ok and self.orthographic then
		self.orthographic=false
		self.autoOrthographic=false
	end
	local direction=Vector3.new(
		math.cos(self.pitch)*math.sin(self.yaw),
		math.sin(self.pitch),
		math.cos(self.pitch)*math.cos(self.yaw))
	local up=Vector3.yAxis
	if self.axisView=="Top" then up=-Vector3.zAxis
	elseif self.axisView=="Bottom" then up=Vector3.zAxis end
	local frame=CFrame.lookAt(self.target+direction*self.distance,
		self.target,up)*CFrame.Angles(0,0,self.roll)
	camera.CFrame=frame
	camera.Focus=CFrame.new(self.target)
	if self.onFrame then self.onFrame(frame,self:viewLabel()) end
end

function BlenderCamera:setActive(active:boolean)
	if self.active==active then return end
	self.active=active
	if active then
		self.projectionDirty=true
		self:snapNow()
	else
		self:releaseMouse()
		local camera=workspace.CurrentCamera
		if camera then
			camera.CameraType=Enum.CameraType.Custom
			pcall(function()camera.ProjectionType=Enum.ProjectionType.Perspective end)
		end
	end
end

function BlenderCamera:setFocusTarget(point:Vector3)
	-- Component workspace enters at the exact ground placement point.
	self.target=point
	self.displayedTarget=point
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

function BlenderCamera:setWheelHandler(callback)
	self.onWheel = callback
end

function BlenderCamera:setProjection(enabled: boolean)
	if self.orthographic == enabled then return end
	if enabled then
		self.orthographicHeight = math.clamp(2 * self.distance * halfTan(self.fov), MIN_ORTHO_HEIGHT, MAX_ORTHO_HEIGHT)
	else
		self.distance = math.clamp(self.orthographicHeight / (2 * halfTan(self.fov)), MIN_DISTANCE, MAX_DISTANCE)
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
	-- Hybrid dolly/lens zoom, about 60% physical travel and 40% FoV change.
	-- Zoom does not change target, yaw, pitch, roll, or construction objects.
	factor = math.clamp(factor, 0.05, 20)
	if self.orthographic and self.nativeOrtho then
		self.orthographicHeight = math.clamp(self.orthographicHeight * factor, MIN_ORTHO_HEIGHT, MAX_ORTHO_HEIGHT)
		return
	end
	local desiredScale = self.distance * halfTan(self.fov) * factor
	local dollyDistance = math.clamp(self.distance * math.pow(factor, 0.6), MIN_DISTANCE, MAX_DISTANCE)
	local desiredFov = math.deg(2 * math.atan(desiredScale / dollyDistance))
	local fov = math.clamp(desiredFov, MIN_FOV, MAX_FOV)
	local distance = math.clamp(desiredScale / halfTan(fov), MIN_DISTANCE, MAX_DISTANCE)
	self.fov = fov
	self.distance = distance
end

function BlenderCamera:frameBounds(frame: CFrame?, size: Vector3?)
	if not frame or not size then return false end
	-- Frame adjusts zoom relative to the current component workspace pivot.
	local radius = (frame.Position-self.target).Magnitude + boundsRadius(size)
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	local aspect = viewport.X / math.max(1, viewport.Y)
	local effectiveHalfFov = math.atan(halfTan(self.fov) * math.min(1, aspect))
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
