--!strict
local Input = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Panel = require(script.Parent.Parent.Experience.UI.WorkbenchPanel)
local Simulation = {}
Simulation.__index = Simulation

function Simulation.new(bridge: any, remote: any, onStop: () -> ())
	local panel = Panel.new("Simulation", { "Run", "Test", "Parts" })
	local self = setmetatable({
		bridge = bridge,
		remote = remote,
		panel = panel,
		active = false,
		pending = false,
		paused = false,
		selectedId = nil,
		axisIndex = 1,
		elapsed = 0,
		generation = 0,
	}, Simulation)
	local run, test, parts = panel.pages.Run, panel.pages.Test, panel.pages.Parts
	Panel.label(
		run,
		"Simulation uses a separate copy. Stop returns to your saved assembly layout.",
		48
	)
	self.pauseButton = Panel.button(run, "Pause", function()
		self:control(if self.paused then "Resume" else "Pause")
	end)
	Panel.button(run, "Start over", function()
		self:control("Reset")
	end)
	Panel.button(run, "Back to building", function()
		if not self.pending then
			onStop()
		end
	end)
	Panel.button(run, "Frame all (Home)", function()
		bridge.frameAssembly(nil)
	end)
	Panel.button(run, "Reset view", function()
		bridge.resetAssemblyCamera()
	end)
	Panel.label(
		test,
		"External bench tests: apply a one-shot impulse to the selected body. These controls do not install a motor.",
		64
	)
	self.selection = Panel.label(test, "Choose a body in Parts", 40)
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
		"The shaft end marker makes axial rotation visible. Spin response depends on inertia and collisions.",
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

function Simulation:impulse(kind: string, sign: number)
	if not self.active or self.pending then
		return
	end
	local value = tonumber((if kind == "Spin" then self.spin else self.push).Text)
	if not value or value ~= value or value < 1 or value > 360 then
		return self:report("Enter a strength from 1 to 360")
	end
	if not self.selectedId then
		return self:report("Select a body in Parts first")
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
	self:report("Running · select a body in Parts, then use Test to spin or push it.")
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
