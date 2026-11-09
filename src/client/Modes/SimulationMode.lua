--!strict
local Input = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Panel = require(script.Parent.Parent.Experience.UI.WorkbenchPanel)
local Simulation = {}
Simulation.__index = Simulation

function Simulation.new(bridge: any, remote: any, onStop: () -> ())
	local panel = Panel.new("Simulation", { "Run", "Drive", "Test", "Parts" })
	local self = setmetatable({
		bridge = bridge,
		remote = remote,
		panel = panel,
		active = false,
		pending = false,
		paused = false,
		selectedId = nil,
		axisIndex = 1,
		driveTargets = {},
		driveIndex = nil,
		driveKind = nil,
		elapsed = 0,
		generation = 0,
	}, Simulation)
	local run, drive, test, parts = panel.pages.Run, panel.pages.Drive, panel.pages.Test, panel.pages.Parts
	Panel.label(
		run,
		"Physics runs on a separate copy. Stopping restores the saved CAD layout.",
		48
	)
	self.pauseButton = Panel.button(run, "Pause", function()
		self:control(if self.paused then "Resume" else "Pause")
	end)
	Panel.button(run, "Reset simulation", function()
		self:control("Reset")
	end)
	Panel.button(run, "Return to assembly", function()
		if not self.pending then
			onStop()
		end
	end)
	Panel.button(run, "Frame mechanism (Home)", function()
		bridge.frameAssembly(nil)
	end)
	Panel.button(run, "Reset view", function()
		bridge.resetAssemblyCamera()
	end)
	Panel.label(drive, "EXTERNAL TEST-BENCH ACTUATORS", 26)
	Panel.label(
		drive,
		"Drive an installed revolute, cylindrical, or prismatic joint. This is external test equipment, not a manufactured motor.",
		58
	)
	self.driveRoot = Panel.list(drive)
	self.driveSelection = Panel.label(drive, "Select a joint", 40)
	self.driveSpeed = Panel.input(drive, "Speed (RPM for pivots / mm/s for slides)", "15")
	self.driveEffort = Panel.input(drive, "Torque (N·stud) / linear force", "220")
	Panel.button(drive, "Run drive", function()
		self:drive(true)
	end)
	Panel.button(drive, "Reverse direction", function()
		local speed = tonumber(self.driveSpeed.Text)
		if speed and speed ~= 0 then
			self.driveSpeed.Text = tostring(-speed)
			self:drive(true)
		end
	end)
	Panel.button(drive, "Stop drive", function()
		self:drive(false)
	end)
	Panel.button(drive, "Refresh joint list", function()
		self:refreshDriveTargets()
	end)

	Panel.label(
		test,
		"Apply transient forces to a selected body. Use Drive for continuous controlled motion.",
		64
	)
	self.selection = Panel.label(test, "Select a body in Components", 40)
	self.axis = Panel.button(test, "Axis: Motion / local Y", function()
		self.axisIndex = self.axisIndex % 4 + 1
		self.axis.Text = "Axis: "
			.. ({ "Motion / local Y", "World X", "World Y", "World Z" })[self.axisIndex]
	end)
	self.spin = Panel.input(test, "Spin strength (1–360)", "90")
	Panel.button(test, "Spin +", function()
		self:impulse("Spin", 1)
	end)
	Panel.button(test, "Spin −", function()
		self:impulse("Spin", -1)
	end)
	self.push = Panel.input(test, "Push strength (1–360)", "100")
	Panel.button(test, "Push +", function()
		self:impulse("Push", 1)
	end)
	Panel.button(test, "Push −", function()
		self:impulse("Push", -1)
	end)
	Panel.label(
		test,
		"Rotation markers display angular motion. Response depends on inertia, constraints, and contact.",
		52
	)
	self.partsRoot = Panel.list(parts)
	Panel.button(parts, "Frame selected (F)", function()
		bridge.frameAssembly(self.selectedId)
	end)
	self.input = Input.InputBegan:Connect(function(input, processed)
		if
			not self.active
			or self.pending
			or processed
			or Input:GetFocusedTextBox()
			or input.UserInputType ~= Enum.UserInputType.MouseButton1
			or Input:IsKeyDown(Enum.KeyCode.LeftAlt)
			or Input:IsKeyDown(Enum.KeyCode.RightAlt)
			or Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
			or Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
		then
			return
		end
		local root = workspace:FindFirstChild("OPENWORKS_Simulation_" .. Players.LocalPlayer.UserId)
		local camera = workspace.CurrentCamera
		if not root or not camera then
			return
		end
		local mouse = Input:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { root }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
		local id = hit and hit.Instance:GetAttribute("OWComponentId")
		if id then
			self:select(id)
		end
	end)
	return self
end

function Simulation:select(id: number)
	local component = self.bridge.getAssemblyState().document.components[id]
	if not component then
		return
	end
	self.selectedId = id
	self.selection.Text = component.name .. " #" .. id
	self.bridge.setAssemblySelection(id)
	self.panel:show("Test")
end

function Simulation:report(message: string)
	self.panel.status.Text = message
end

function Simulation:status(state: any)
	self.paused = state.paused
	self.pauseButton.Text = if self.paused then "Resume" else "Pause"
	self:report(
		(if self.paused then "Paused" else "Running")
			.. " · "
			.. state.supports
			.. " active relationships"
			.. (
				if state.released > 0
					then "\n" .. state.released .. " released after losing engagement. Reset to restore."
					else ""
			)
	)
end

function Simulation:control(action: string)
	if not self.active or self.pending then
		return
	end
	self.pending = true
	local ok, accepted, result = pcall(function()
		return self.remote:SimulationControl(action)
	end)
	self.pending = false
	if ok and accepted then
		self:status(result)
	else
		self:report(tostring(if ok then result else accepted))
	end
end

function Simulation:refreshDriveTargets()
	if not self.active then
		return
	end
	local success, accepted, targets = pcall(function()
		return self.remote:ListDriveTargets()
	end)
	if not success or not accepted then
		return self:report(tostring(if success then targets else accepted))
	end
	self.driveTargets = targets
	Panel.clear(self.driveRoot)
	local components = self.bridge.getAssemblyState().document.components
	for _, target in ipairs(targets) do
		local mover = components[target.movingId]
		local name = if mover then mover.name else "Component " .. tostring(target.movingId)
		Panel.button(self.driveRoot,
			string.format("#%d  %s  ·  %s", target.index, name, target.kind),
			function()
				self.driveIndex = target.index
				self.driveKind = target.kind
				self.driveSelection.Text = string.format("Joint #%d · %s · %s",
					target.index, name, target.kind)
				self.driveSpeed.Text = if target.kind == "Prismatic" then "80" else "15"
			end
		)
	end
	if #targets == 0 then
		Panel.label(self.driveRoot, "No active mechanical joints")
	end
	if not self.driveIndex or not table.find(
		(function()
			local ids = {}
			for _, target in ipairs(targets) do table.insert(ids, target.index) end
			return ids
		end)(), self.driveIndex) then
		self.driveIndex = nil
		self.driveKind = nil
		self.driveSelection.Text = "Select a joint"
	end
end

function Simulation:drive(enabled: boolean)
	if not self.active or self.pending then
		return
	end
	if not self.driveIndex then
		return self:report("Select the joint to drive")
	end
	local speed, effort = tonumber(self.driveSpeed.Text), tonumber(self.driveEffort.Text)
	if enabled and (not speed or not effort or speed ~= speed or effort ~= effort) then
		return self:report("Enter finite speed and effort values")
	end
	local value = if not enabled then 0 elseif self.driveKind == "Prismatic"
		then speed / 280 else speed * (2 * math.pi / 60)
	local force = if enabled then effort else 0
	self.pending = true
	local ok, accepted, message = pcall(function()
		return self.remote:SetBenchDrive(self.driveIndex, value, force)
	end)
	self.pending = false
	self:report(if ok and accepted then message else tostring(if ok then message else accepted))
end

function Simulation:impulse(kind: string, sign: number)
	if not self.active or self.pending then
		return
	end
	local value = tonumber((if kind == "Spin" then self.spin else self.push).Text)
	if not value or value ~= value or value < 1 or value > 360 then
		return self:report("Enter a strength from 1 to 360")
	end
	if not self.selectedId then
		return self:report("Select a body in Components first")
	end
	self.pending = true
	local ok, accepted, message = pcall(function()
		return self.remote:TestImpulse(
			self.selectedId,
			kind,
			({ "Motion", "X", "Y", "Z" })[self.axisIndex],
			value * sign
		)
	end)
	self.pending = false
	self:report(if ok and accepted then message else tostring(if ok then message else accepted))
	self.elapsed = -2
end

function Simulation:Enter()
	self.bridge.enterAssembly()
	local ok, layout = self.remote:GetLayout()
	if not ok then
		error(tostring(layout))
	end
	local accepted, center = self.remote:StartSimulation(layout.revision)
	if not accepted then
		error(tostring(center))
	end
	self.active = true
	self.generation += 1
	self.elapsed, self.paused, self.pending = 0, false, false
	local projection = self.bridge.getAssemblyState().projection
	projection.simulating = true
	projection:clear()
	self.bridge.setSimulationFocus(center)
	self.panel.gui.Enabled = true
	self.pauseButton.Text = "Pause"
	self:report("Simulation running. Use Drive for motors or Loads for impulses.")
	self:refreshDriveTargets()
	Panel.clear(self.partsRoot)
	local doc = self.bridge.getAssemblyState().document
	self.selectedId = self.bridge.getAssemblySelection() or self.selectedId
	for _, id in ipairs(doc.order) do
		local component = doc.components[id]
		Panel.button(
			self.partsRoot,
			component.name .. (if layout.grounded[tostring(id)] then " [Fixed]" else ""),
			function()
				self.selectedId = id
				self.selection.Text = component.name .. " #" .. id
				self.bridge.setAssemblySelection(id)
				self.panel:show("Test")
			end
		)
	end
	if not self.selectedId or not doc.components[self.selectedId] then
		self.selectedId = doc.order[1]
	end
	if self.selectedId then
		self.selection.Text = doc.components[self.selectedId].name .. " #" .. self.selectedId
		self.bridge.setAssemblySelection(self.selectedId)
	end
	local generation = self.generation
	task.spawn(function()
		local root =
			workspace:WaitForChild("OPENWORKS_Simulation_" .. Players.LocalPlayer.UserId, 10)
		if not root then
			return
		end
		local deadline = os.clock() + 5
		repeat
			if not self.active or self.generation ~= generation then
				return
			end
			local count = 0
			for _, part in ipairs(root:GetChildren()) do
				if part:IsA("BasePart") and part:GetAttribute("OWComponentId") then
					count += 1
				end
			end
			if count >= #doc.order then
				break
			end
			task.wait(0.1)
		until os.clock() >= deadline
		if self.active and self.generation == generation then
			self.bridge.frameAssembly(nil)
		end
	end)
end

function Simulation:Update(dt: number)
	if not self.active or self.pending then
		return
	end
	self.elapsed += dt
	if self.elapsed < 1 then
		return
	end
	self.elapsed = 0
	self.pending = true
	local generation = self.generation
	task.spawn(function()
		local ok, accepted, state = pcall(function()
			return self.remote:SimulationStatus()
		end)
		if self.active and self.generation == generation then
			self.pending = false
			if ok and accepted then
				self:status(state)
			elseif ok then
				self:report("Simulation stopped. Return to Assembly.")
			end
		end
	end)
end

function Simulation:Exit()
	local ok, reason = self.remote:StopSimulation()
	if not ok then
		error(tostring(reason))
	end
	self.active, self.pending = false, false
	self.generation += 1
	self.panel.gui.Enabled = false
	self.bridge.getAssemblyState().projection.simulating = false
	self.bridge.leaveAssembly()
end

function Simulation:CleanupFailedEnter()
	pcall(function()
		self.remote:StopSimulation()
	end)
	self.active, self.pending = false, false
	self.panel.gui.Enabled = false
	self.generation += 1
	self.bridge.getAssemblyState().projection.simulating = false
	self.bridge.leaveAssembly()
end

function Simulation:Destroy()
	self.input:Disconnect()
	self.panel.gui:Destroy()
end
return Simulation
