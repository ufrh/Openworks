--!strict
-- Interactive top-face sketch workspace. 2D polygon data is authoritative;
-- all drawing widgets are lightweight reusable Parts, never EditableMeshes.
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize = require(FORM.Quantize)
local Compiler = require(FORM.Compiler)
local SketchProfile = require(FORM.SketchProfile)

local SketchEditor = {}
SketchEditor.__index = SketchEditor

local COLORS = {
	Add = Color3.fromRGB(94, 211, 157),
	Remove = Color3.fromRGB(245, 172, 108),
	Intersect = Color3.fromRGB(180, 158, 252),
}
local ACCENT = Color3.fromRGB(99, 223, 220)
local MM_PER_STUD = 280

local function make(class: string, properties, parent: Instance)
	local result = Instance.new(class)
	for key, value in pairs(properties) do (result :: any)[key] = value end
	result.Parent = parent
	return result
end

local function text(parent: Instance, value: string, top: number, size: number, color: Color3?)
	return make("TextLabel", {
		BackgroundTransparency = 1,
		Text = value, Font = Enum.Font.Code, TextSize = size,
		TextColor3 = color or Color3.fromRGB(219, 230, 236),
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(14, top),
		Size = UDim2.new(1, -28, 0, 23),
	}, parent)
end

local function button(parent: Instance, title: string, rect: UDim2, pos: UDim2, callback)
	local b = make("TextButton", {
		BackgroundColor3 = Color3.fromRGB(57, 66, 76),
		BorderSizePixel = 0, Text = title,
		TextColor3 = Color3.fromRGB(236, 245, 248),
		TextSize = 12, Font = Enum.Font.Code,
		Position = pos, Size = rect, AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
	b.Activated:Connect(callback)
	return b
end

local function newVisual(folder: Folder, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = Vector3.one * 0.05
	part.Transparency = 1
	part.Parent = folder
	return part
end

function SketchEditor.new(playerGui: PlayerGui, cameraController, onCommit, onStatus, onExit)
	local visuals = Instance.new("Folder")
	visuals.Name = "FORM_SketchVisualization"
	visuals.Parent = workspace
	local gui = make("ScreenGui", {
		Name = "FORM_SketchWorkspace", ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
	}, playerGui)
	local panel = make("Frame", {
		Name = "SketchDock", AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 236),
		Size = UDim2.fromOffset(328, 365),
		BackgroundColor3 = Color3.fromRGB(25, 31, 37),
		BorderSizePixel = 0,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
	make("UIStroke", {
		Color = Color3.fromRGB(75, 95, 107),
		Thickness = 1,
		Transparency = 0.25,
	}, panel)
	local stripe = make("Frame", {
		BorderSizePixel = 0, BackgroundColor3 = ACCENT,
		Size = UDim2.new(1, 0, 0, 3),
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 2) }, stripe)
	text(panel, "FORM  /  PROFILE SKETCH", 13, 15, ACCENT)
	local subtitle = text(panel, "Click the material's top construction plane", 36, 11)
	subtitle.TextColor3 = Color3.fromRGB(159, 180, 190)
	local count = text(panel, "0 vertices  ·  OPEN PROFILE", 63, 12)
	local modeTitle = text(panel, "BOOLEAN OPERATION", 92, 11)
	modeTitle.TextColor3 = Color3.fromRGB(167, 184, 191)
	local self = setmetatable({
		camera = cameraController, onCommit = onCommit, onStatus = onStatus,
		onExit = onExit, gui = gui, panel = panel, visuals = visuals,
		lines = {}, dots = {}, gridParts = {}, connections = {},
		active = false, component = nil, standalone = false, points = {}, closed = false,
		mode = "Remove", through = true, depthMM = 56,
		cursor = nil, count = count, subtitle = subtitle,
	}, SketchEditor)

	local modeButtons = {}
	for i, mode in ipairs({ "Add", "Remove", "Intersect" }) do
		local b = button(panel, mode, UDim2.fromOffset(96, 29),
			UDim2.fromOffset(14 + (i - 1) * 105, 117), function()
				self.mode = mode
				self:updateControls()
			end)
		modeButtons[mode] = b
	end
	self.modeButtons = modeButtons
	self.modeTitle = modeTitle

	local depthTitle = text(panel, "EXTRUSION DEPTH   (mm)", 157, 11)
	self.depthTitle = depthTitle
	depthTitle.TextColor3 = Color3.fromRGB(167, 184, 191)
	local depthBox = make("TextBox", {
		Position = UDim2.fromOffset(14, 180),
		Size = UDim2.fromOffset(136, 30),
		BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(47, 56, 65),
		Font = Enum.Font.Code, TextSize = 14, Text = "56",
		ClearTextOnFocus = false, TextColor3 = Color3.fromRGB(241, 246, 249),
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, depthBox)
	self.depthBox = depthBox
	depthBox.FocusLost:Connect(function()
		local mm = tonumber(depthBox.Text)
		if mm and mm == mm and mm > 0 and mm <= 128 * MM_PER_STUD then
			self.depthMM = mm
		else
			self.onStatus("Enter a positive extrusion depth in mm")
		end
		self:updateControls()
	end)
	self.throughButton = button(panel, "THROUGH: ON", UDim2.fromOffset(156, 30),
		UDim2.fromOffset(157, 180), function()
			self.through = not self.through
			self:updateControls()
		end)

	button(panel, "Undo Vertex", UDim2.fromOffset(144, 29),
		UDim2.fromOffset(14, 225), function() self:undoPoint() end)
	button(panel, "Close Profile", UDim2.fromOffset(145, 29),
		UDim2.fromOffset(169, 225), function() self:closeProfile() end)
	local info = text(panel, "LMB: point   •   Enter: close   •   Backspace: undo", 264, 10)
	info.TextColor3 = Color3.fromRGB(157, 173, 183)
	local helper = text(panel, "Use Escape to exit sketch mode.", 283, 10)
	helper.TextColor3 = Color3.fromRGB(157, 173, 183)
	self.commitButton = button(panel, "EXTRUDE / COMMIT", UDim2.fromOffset(189, 38),
		UDim2.fromOffset(14, 313), function() self:commit() end)
	self.cancelButton = button(panel, "Cancel", UDim2.fromOffset(112, 38),
		UDim2.fromOffset(202, 313), function() self:stop() end)

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not self.active or processed or UserInputService:GetFocusedTextBox() then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mouse = UserInputService:GetMouseLocation()
			if self:isOverUI(mouse) then return end
			self:addPointUnderCursor()
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			self:closeProfile()
		elseif input.KeyCode == Enum.KeyCode.Backspace then
			self:undoPoint()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			self:stop()
		end
	end))
	table.insert(self.connections, RunService.RenderStepped:Connect(function()
		self:render()
	end))
	self:updateControls()
	return self
end

function SketchEditor:isOverUI(point: Vector2): boolean
	local pos, size = self.panel.AbsolutePosition, self.panel.AbsoluteSize
	if point.X >= pos.X and point.X <= pos.X + size.X
		and point.Y >= pos.Y and point.Y <= pos.Y + size.Y then
		return true
	end
	-- Existing FORM debug controls and view orientation navigator.
	if point.X < 345 and point.Y < 615 then return true end
	local cam = workspace.CurrentCamera
	if cam and point.X > cam.ViewportSize.X - 170 and point.Y < 225 then return true end
	return false
end

function SketchEditor:projectMouse(point: Vector2): Vector2?
	if not self.component then return nil end
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local node = self.component.nodes[1]
	local frame = Compiler.pose(node)
	local planeCenter = frame:PointToWorldSpace(Vector3.new(0, node.size.Y / 2, 0))
	local planeNormal = frame.UpVector
	local denominator = ray.Direction:Dot(planeNormal)
	if math.abs(denominator) < 0.001 then return nil end
	local distance = (planeCenter - ray.Origin):Dot(planeNormal) / denominator
	if distance <= 0 then return nil end
	local location = ray.Origin + ray.Direction * distance
	local localPoint = frame:PointToObjectSpace(location)
	return Vector2.new(
		Quantize.snap(localPoint.X, Quantize.Grid),
		Quantize.snap(localPoint.Z, Quantize.Grid)
	)
end

function SketchEditor:start(component)
	if self.active then self:stop() end
	self.standalone = component == nil
	if self.standalone then
		-- Local sketch coordinates coincide with world X/Z. Its top face is
		-- precisely Y = 0, so it projects onto the permanent construction grid.
		self.component = {
			nodes = {{
				position = Vector3.new(0, -0.025, 0),
				size = Vector3.new(6, 0.05, 6),
				rotation = Vector3.zero,
			}},
		}
		self.mode, self.through = "Add", false
	else
		self.component = component
	end
	self.active = true
	self.closed = false
	self.points = {}
	self.cursor = nil
	self.gui.Enabled = true
	self.camera:setView("Top")
	if not self.standalone then self.camera:frameSelected() end
	self:updateControls()
	self.onStatus(if self.standalone
		then "New body sketch: draw a closed outline directly on the world grid"
		else "Sketch active: click vertices on the selected workpiece's top face")
end

function SketchEditor:stop()
	if not self.active then return end
	self.active = false
	self.component = nil
	self.standalone = false
	self.points = {}
	self.cursor = nil
	self.closed = false
	self.gui.Enabled = false
	for _, part in ipairs(self.lines) do part.Transparency = 1 end
	for _, part in ipairs(self.dots) do part.Transparency = 1 end
	for _, part in ipairs(self.gridParts) do part.Transparency = 1 end
	self.onExit()
end

function SketchEditor:addPointUnderCursor()
	if not self.active or self.closed then return end
	local point = self:projectMouse(UserInputService:GetMouseLocation())
	if not point then
		self.onStatus("Sketch plane is outside the camera view")
		return
	end
	if #self.points >= 3 and (self.points[1] - point).Magnitude <= Quantize.Grid * 1.5 then
		self:closeProfile()
		return
	end
	if #self.points >= 64 then
		self.onStatus("A sketch supports at most 64 vertices")
		return
	end
	if #self.points > 0 and (self.points[#self.points] - point).Magnitude < Quantize.Grid * 0.5 then
		self.onStatus("Move to another grid point before placing the next vertex")
		return
	end
	table.insert(self.points, point)
	self:updateControls()
end

function SketchEditor:undoPoint()
	if not self.active then return end
	if self.closed then
		self.closed = false
	else
		table.remove(self.points)
	end
	self:updateControls()
end

function SketchEditor:closeProfile()
	if not self.active then return end
	local points, _, reason = SketchProfile.prepare(self.points)
	if not points then
		self.onStatus(reason or "Invalid sketch profile")
		return
	end
	self.points = points
	self.closed = true
	self:updateControls()
	self.onStatus("Profile closed. Choose the operation, then EXTRUDE / COMMIT.")
end

function SketchEditor:updateControls()
	self.count.Text = string.format("%d vertices  ·  %s", #self.points,
		if self.closed then "CLOSED PROFILE" else "OPEN PROFILE")
	self.count.TextColor3 = if self.closed then COLORS[self.mode] else Color3.fromRGB(215, 228, 234)
	self.modeTitle.Text = if self.standalone then "NEW BODY  /  CONSTRUCTION PROFILE" else "BOOLEAN OPERATION"
	self.depthTitle.Text = if self.standalone then "BODY HEIGHT   (mm)" else "EXTRUSION DEPTH   (mm)"
	for mode, b in pairs(self.modeButtons) do
		b.Visible = not self.standalone
		b.BackgroundColor3 = if self.mode == mode then COLORS[mode]
			else Color3.fromRGB(57, 66, 76)
		b.TextColor3 = if self.mode == mode then Color3.fromRGB(20, 28, 33)
			else Color3.fromRGB(236, 245, 248)
	end
	self.throughButton.Text = "THROUGH: " .. (if self.through then "ON" else "OFF")
	self.throughButton.Visible = not self.standalone and self.mode == "Remove"
	self.depthBox.Text = string.format("%.1f", self.depthMM)
	self.depthBox.TextEditable = self.standalone
		or not (self.mode == "Intersect" or (self.mode == "Remove" and self.through))
	self.commitButton.Text = if self.standalone then "CREATE NEW BODY" else "EXTRUDE / COMMIT"
	self.commitButton.BackgroundColor3 = if self.closed then COLORS[self.mode]
		else Color3.fromRGB(68, 78, 86)
	self.commitButton.TextColor3 = if self.closed then Color3.fromRGB(19, 27, 31)
		else Color3.fromRGB(171, 183, 190)
end

function SketchEditor:commit()
	if not self.active or not self.component then return end
	if not self.closed then
		self.onStatus("Close a valid profile before extruding")
		return
	end
	local depth = Quantize.snap(self.depthMM / MM_PER_STUD, Quantize.Grid)
	if depth < Quantize.MinSize then
		self.onStatus("Extrusion depth must be at least 14 mm (0.05 studs)")
		return
	end
	local points = table.clone(self.points)
	local component = if self.standalone then nil else self.component
	local success, reason = self.onCommit(component, {
		points = points, mode = self.mode, depth = depth, through = self.through,
	})
	if not success then
		self.onStatus(reason or "Unable to commit sketch")
		return
	end
	local newBody = self.standalone
	local mode = self.mode
	self:stop()
	self.onStatus(if newBody
		then string.format("New body sketched (%d vertices, %.1f mm high)", #points, depth * MM_PER_STUD)
		else string.format("Sketch %s committed (%d vertices, %.1f mm)", mode, #points, depth * MM_PER_STUD))
end

local function extrusionRange(node, mode: string, depth: number, through: boolean): (number, number)
	local half = node.size.Y / 2
	if mode == "Add" then return half - 0.04, half + depth end
	if mode == "Intersect" or through then return -half - 0.04, half + 0.04 end
	return half - depth, half + 0.04
end

local function placeSegment(part: Part, a: Vector3, b: Vector3, width: number, color: Color3)
	local length = (b - a).Magnitude
	if length < 0.0001 then
		part.Transparency = 1
		return
	end
	part.Color = color
	part.Transparency = 0.03
	part.Size = Vector3.new(width, width, length)
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
end

function SketchEditor:render()
	if not self.active or not self.component then return end
	local node = self.component.nodes[1]
	local cf = Compiler.pose(node)
	local camera = workspace.CurrentCamera
	local distance = if camera then (camera.CFrame.Position - node.position).Magnitude else 5
	local thickness = math.clamp(distance * 0.003, 0.009, 0.045)
	local function worldAt(p: Vector2, height: number)
		return cf:PointToWorldSpace(Vector3.new(p.X, height, p.Y))
	end
	local mouse = UserInputService:GetMouseLocation()
	self.cursor = if self.closed or self:isOverUI(mouse) then nil else self:projectMouse(mouse)
	if self.cursor then
		self.subtitle.Text = string.format("Grid 0.10  |  Snap 0.05  |  X %.2f  Z %.2f",
			self.cursor.X + (if self.standalone then 0 else node.size.X / 2),
			self.cursor.Y + (if self.standalone then 0 else node.size.Z / 2))
	else
		self.subtitle.Text = "Click the top construction plane  ·  Snap 0.05"
	end
	-- Overlay a local workpiece grid slightly above the face, even though
	-- the global floor grid may be hidden beneath solid stock.
	local gridSegments = {}
	local xHalf, zHalf = node.size.X / 2, node.size.Z / 2
	local step = math.max(0.1, Quantize.snap(math.max(node.size.X, node.size.Z) / 40, 0.1))
	local nx, nz = math.floor(node.size.X / step), math.floor(node.size.Z / step)
	for i = 0, nx do
		local x = -xHalf + i * step
		table.insert(gridSegments, {
			cf:PointToWorldSpace(Vector3.new(x, node.size.Y / 2 + 0.018, -zHalf)),
			cf:PointToWorldSpace(Vector3.new(x, node.size.Y / 2 + 0.018, zHalf)),
			i % 5 == 0,
		})
	end
	for i = 0, nz do
		local z = -zHalf + i * step
		table.insert(gridSegments, {
			cf:PointToWorldSpace(Vector3.new(-xHalf, node.size.Y / 2 + 0.018, z)),
			cf:PointToWorldSpace(Vector3.new(xHalf, node.size.Y / 2 + 0.018, z)),
			i % 5 == 0,
		})
	end
	if self.standalone then table.clear(gridSegments) end
	for i, entry in ipairs(gridSegments) do
		if not self.gridParts[i] then
			self.gridParts[i] = newVisual(self.visuals, "SketchGrid_" .. i)
		end
		placeSegment(self.gridParts[i], entry[1], entry[2], thickness * 0.45,
			Color3.fromRGB(117, 155, 169))
		self.gridParts[i].Transparency = if entry[3] then 0.48 else 0.76
	end
	for i = #gridSegments + 1, #self.gridParts do
		self.gridParts[i].Transparency = 1
	end
	local segments = {}
	local surfaceY = node.size.Y / 2 + 0.035
	local color = if self.closed then COLORS[self.mode] else ACCENT
	local function segment(a: Vector3, b: Vector3, tint: Color3?)
		table.insert(segments, { a, b, tint or color })
	end
	if self.closed then
		local bottom, top = extrusionRange(node, self.mode,
			Quantize.snap(self.depthMM / MM_PER_STUD, Quantize.Grid), self.through)
		for i, p in ipairs(self.points) do
			local q = self.points[i % #self.points + 1]
			segment(worldAt(p, top), worldAt(q, top))
			segment(worldAt(p, bottom), worldAt(q, bottom), color:Lerp(Color3.new(0, 0, 0), 0.30))
			segment(worldAt(p, bottom), worldAt(p, top), color:Lerp(Color3.new(1, 1, 1), 0.2))
		end
	else
		for i = 1, #self.points - 1 do
			segment(worldAt(self.points[i], surfaceY), worldAt(self.points[i + 1], surfaceY))
		end
		if self.cursor and #self.points > 0 then
			segment(worldAt(self.points[#self.points], surfaceY),
				worldAt(self.cursor, surfaceY), Color3.fromRGB(246, 198, 125))
		end
	end
	for i, detail in ipairs(segments) do
		if not self.lines[i] then
			self.lines[i] = newVisual(self.visuals, "SketchEdge" .. i)
		end
		placeSegment(self.lines[i], detail[1], detail[2], thickness, detail[3])
	end
	for i = #segments + 1, #self.lines do self.lines[i].Transparency = 1 end
	local points = table.clone(self.points)
	if self.cursor then table.insert(points, self.cursor) end
	for i, p in ipairs(points) do
		if not self.dots[i] then
			self.dots[i] = newVisual(self.visuals, "Vertex" .. i)
			self.dots[i].Shape = Enum.PartType.Ball
		end
		local part = self.dots[i]
		part.Color = if self.cursor and i == #points then Color3.fromRGB(255, 201, 113) else color
		part.Size = Vector3.one * thickness * 3.2
		part.Position = worldAt(p, if self.closed then node.size.Y / 2 + 0.04 else surfaceY)
		part.Transparency = 0
	end
	for i = #points + 1, #self.dots do self.dots[i].Transparency = 1 end
end

function SketchEditor:destroy()
	self:stop()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.visuals:Destroy()
	self.gui:Destroy()
end

return SketchEditor
