--!strict
-- Manufacture from a block, cylinder, or authored sketch. The construction
-- workspace is an editor boundary, not the shape the player must start with.
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FORM = ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM")
local Quantize = require(FORM.Quantize)

local ComponentPlacement = {}
ComponentPlacement.__index = ComponentPlacement

local MM = 280
local WORKSPACE_HEIGHT_MM = 1000
local KINDS = { "Block", "Cylinder", "Sketch" }
local PRESETS = {
	Block = {
		{ label = "Small block", dimensions = "140, 56, 140" },
		{ label = "Medium block", dimensions = "280, 84, 280" },
		{ label = "Long bar", dimensions = "560, 56, 140" },
		{ label = "Flat plate", dimensions = "280, 28, 280" },
	},
	Cylinder = {
		{ label = "Small shaft", dimensions = "14, 140" },
		{ label = "Standard shaft", dimensions = "28, 140" },
		{ label = "Large shaft", dimensions = "56, 280" },
		{ label = "Heavy shaft", dimensions = "84, 560" },
	},
	Sketch = {
		{ label = "Small grid", dimensions = "140, 140" },
		{ label = "Medium grid", dimensions = "280, 280" },
		{ label = "Large grid", dimensions = "560, 560" },
		{ label = "Wide grid", dimensions = "560, 280" },
	},
}
ComponentPlacement.WORKSPACE_HEIGHT_MM = WORKSPACE_HEIGHT_MM

local function make(kind: string, properties: any, parent: Instance): any
	local object = Instance.new(kind)
	for key, value in pairs(properties) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function label(parent: Instance, value: string, y: number, height: number): TextLabel
	return make("TextLabel", {
		BackgroundTransparency = 1,
		Text = value,
		TextWrapped = true,
		TextColor3 = Color3.fromRGB(226, 238, 242),
		TextSize = 13,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, y),
		Size = UDim2.new(1, -32, 0, height),
	}, parent)
end

local function button(parent: Instance, value: string, position: UDim2, size: UDim2): TextButton
	local control = make("TextButton", {
		BackgroundColor3 = Color3.fromRGB(52, 65, 72),
		BorderSizePixel = 0,
		Text = value,
		Font = Enum.Font.Code,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		Position = position,
		Size = size,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, control)
	return control
end

local function parseDimensions(raw: string, count: number): { number }?
	local values = {}
	for term in string.gmatch(raw, "[^,%s]+") do
		local number = tonumber(term)
		if not number or not Quantize.isFinite(number) or number < 14
			or number > Quantize.MaxSize * MM then
			return nil
		end
		table.insert(values, number)
	end
	return if #values == count then values else nil
end

function ComponentPlacement.new(
	playerGui: PlayerGui,
	grid: any,
	onPlace: any,
	onStatus: any,
	onCancel: any
)
	local ui = make("ScreenGui", {
		Name = "FORM_CreateComponent",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 50,
	}, playerGui)
	local launch = button(
		ui, "+ Create Component",
		UDim2.fromOffset(20, 20), UDim2.fromOffset(190, 42)
	)
	local form = make("Frame", {
		Name = "ComponentSpecification",
		Visible = false,
		BackgroundColor3 = Color3.fromRGB(24, 30, 35),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(346, 432),
	}, ui)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, form)
	label(form, "NEW COMPONENT", 12, 24)
	label(form, "Name", 48, 20)
	local nameBox = make("TextBox", {
		Name = "ComponentName",
		Text = "",
		PlaceholderText = "Component name",
		ClearTextOnFocus = false,
		BackgroundColor3 = Color3.fromRGB(45, 54, 61),
		BorderSizePixel = 0,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.Code,
		TextSize = 13,
		Position = UDim2.fromOffset(16, 70),
		Size = UDim2.new(1, -32, 0, 29),
	}, form)
	make("UICorner", { CornerRadius = UDim.new(0, 4) }, nameBox)

	local modeIndex = 1
	local selectedPreset = 1
	local kindButton = button(
		form, "Starting geometry: Block",
		UDim2.fromOffset(16, 105), UDim2.fromOffset(314, 29)
	)
	local presetTitle = label(form, "STOCK PRESETS", 137, 19)
	local presetButtons = {}
	for index = 1, 4 do
		presetButtons[index] = button(
			form, "",
			UDim2.fromOffset(16, 160 + (index - 1) * 35),
			UDim2.fromOffset(314, 31)
		)
	end
	local dimensionsLabel = label(form, "X, Y, Z (mm)", 299, 20)
	local dimensions = make("TextBox", {
		Name = "Dimensions",
		Text = "140, 56, 140",
		ClearTextOnFocus = false,
		BackgroundColor3 = Color3.fromRGB(45, 54, 61),
		BorderSizePixel = 0,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.Code,
		TextSize = 13,
		Position = UDim2.fromOffset(16, 323),
		Size = UDim2.fromOffset(314, 29),
	}, form)
	make("UICorner", { CornerRadius = UDim.new(0, 4) }, dimensions)
	local feedback = label(form, "Choose stock dimensions or draw a sketch.", 356, 27)
	feedback.TextSize = 11
	local cancel = button(
		form, "Cancel",
		UDim2.fromOffset(16, 391), UDim2.fromOffset(150, 32)
	)
	local nextStep = button(
		form, "Place Block",
		UDim2.fromOffset(172, 391), UDim2.fromOffset(158, 32)
	)
	local hint = label(ui, "Left click to place · Esc to cancel", 0, 30)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -48)
	hint.Size = UDim2.fromOffset(500, 30)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Visible = false

	local self = setmetatable({
		ui = ui,
		launch = launch,
		form = form,
		hint = hint,
		grid = grid,
		placing = false,
		showLaunch = true,
		size = Vector3.new(1, WORKSPACE_HEIGHT_MM / MM, 1),
		name = "",
		kind = "Block",
		shaftDiameter = 0,
		shaftLength = 0,
		blockSize = Vector3.zero,
		lastPosition = nil,
		onPlace = onPlace,
		onStatus = onStatus,
		onCancel = onCancel,
	}, ComponentPlacement)

	local function updateForm()
		local kind = KINDS[modeIndex]
		kindButton.Text = "Starting geometry: " .. kind
		presetTitle.Text = if kind == "Sketch" then "CONSTRUCTION GRID"
			else "STOCK PRESETS"
		dimensionsLabel.Text = if kind == "Block" then "Width X, Height Y, Depth Z (mm)"
			elseif kind == "Cylinder" then "Diameter, Length (mm)"
			else "Grid width X, depth Z (mm)"
		dimensions.Text = PRESETS[kind][selectedPreset].dimensions
		for index, control in ipairs(presetButtons) do
			control.Text = PRESETS[kind][index].label
			control.BackgroundColor3 = if index == selectedPreset then
				Color3.fromRGB(34, 112, 137) else Color3.fromRGB(52, 65, 72)
		end
		nextStep.Text = "Place " .. (if kind == "Sketch" then "Sketch Grid" else kind)
	end
	kindButton.Activated:Connect(function()
		modeIndex = modeIndex % #KINDS + 1
		selectedPreset = 1
		updateForm()
	end)
	for index, control in ipairs(presetButtons) do
		control.Activated:Connect(function()
			selectedPreset = index
			updateForm()
		end)
	end
	updateForm()

	local function groundPoint(): Vector3?
		local camera = workspace.CurrentCamera
		if not camera then return nil end
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local exclude = {}
		local character = Players.LocalPlayer.Character
		if character then table.insert(exclude, character) end
		for _, name in ipairs({ "FORM_LocalPreview", "FORM_TransformGrips" }) do
			local root = workspace:FindFirstChild(name)
			if root then table.insert(exclude, root) end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclude
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		local point: Vector3?
		if hit and hit.Normal.Y > 0.65 then
			point = hit.Position
		else
			if math.abs(ray.Direction.Y) < 1e-6 then return nil end
			local t = -ray.Origin.Y / ray.Direction.Y
			if t < 0 then return nil end
			point = ray.Origin + ray.Direction * t
		end
		return Vector3.new(
			Quantize.snap(point.X - self.size.X * 0.5, Quantize.Grid),
			Quantize.snap(point.Y, Quantize.Grid),
			Quantize.snap(point.Z - self.size.Z * 0.5, Quantize.Grid)
		)
	end
	local function close(keepGrid: boolean)
		self.placing = false
		self.lastPosition = nil
		form.Visible = false
		hint.Visible = false
		launch.Visible = self.showLaunch
		if not keepGrid then grid:clear() end
	end
	function self:close()
		close(false)
		if onCancel then onCancel() end
	end
	function self:open()
		close(false)
		form.Visible = true
		launch.Visible = false
		feedback.Text = "Choose stock dimensions or draw a sketch."
	end
	function self:setLaunchVisible(value: boolean)
		self.showLaunch = value
		if not self.placing and not form.Visible then
			launch.Visible = value
		end
	end
	launch.Activated:Connect(function()
		self:open()
	end)
	cancel.Activated:Connect(function()
		self:close()
	end)
	nextStep.Activated:Connect(function()
		local kind = KINDS[modeIndex]
		local values = parseDimensions(dimensions.Text, if kind == "Block" then 3 else 2)
		if not values then
			feedback.Text = "Dimensions must be finite values from 14 to 35,840 mm."
			return
		end
		if not nameBox.Text:match("%S") then
			feedback.Text = "Enter a component name."
			return
		end
		local x, z, block, diameter, length
		if kind == "Block" then
			block = Vector3.new(values[1], values[2], values[3]) / MM
			x = math.max(280, values[1] + 56)
			z = math.max(280, values[3] + 56)
		elseif kind == "Cylinder" then
			diameter = values[1] / MM
			length = values[2] / MM
			x = math.max(280, values[1] * 2)
			z = math.max(280, values[1] * 2)
		else
			x, z = values[1], values[2]
		end
		local size = Quantize.vector(
			Vector3.new(x, WORKSPACE_HEIGHT_MM, z) / MM,
			Quantize.Size
		)
		if math.min(size.X, size.Y, size.Z) < Quantize.MinSize
			or math.max(size.X, size.Y, size.Z) > Quantize.MaxSize then
			feedback.Text = "Construction bounds exceed the supported workspace."
			return
		end
		self.kind = kind
		self.size = size
		self.blockSize = block or Vector3.zero
		self.shaftDiameter = diameter or 0
		self.shaftLength = length or 0
		self.name = string.sub(nameBox.Text, 1, 64)
		self.placing = true
		self.lastPosition = nil
		form.Visible = false
		launch.Visible = false
		hint.Text = "Place " .. kind .. " · Left click to confirm · Esc to cancel"
		hint.Visible = true
		grid:setVisible(false)
		onStatus("Position the " .. kind:lower() .. " workspace on the ground.")
	end)
	RunService:BindToRenderStep(
		"FORM_PlaceSketchGrid",
		Enum.RenderPriority.Camera.Value + 3,
		function()
			if not self.placing then return end
			local position = groundPoint()
			if not position then
				self.lastPosition = nil
				grid:setVisible(false)
				return
			end
			if position ~= self.lastPosition then
				grid:update(position, self.size)
				self.lastPosition = position
			end
			grid:setVisible(true)
		end
	)
	self.inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if not self.placing then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			self:close()
			return
		end
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local position = groundPoint()
		if not position then return end
		grid:update(position, self.size)
		grid:setVisible(true)
		close(true)
		onPlace(
			self.name, self.size, position, self.kind,
			self.shaftDiameter, self.shaftLength, self.blockSize
		)
	end)
	return self
end

function ComponentPlacement:destroy()
	self.placing = false
	RunService:UnbindFromRenderStep("FORM_PlaceSketchGrid")
	if self.inputConnection then
		self.inputConnection:Disconnect()
		self.inputConnection = nil
	end
	self.ui:Destroy()
end

return ComponentPlacement
