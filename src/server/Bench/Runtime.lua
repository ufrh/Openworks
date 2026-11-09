--!strict
-- Drives all five scales concurrently, gathers per-joint telemetry, and exports CSV.
-- This is a BENCHMARK, not an authoritative pass/fail certification.
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Config = require(script.Parent.Config)
local Geometry = require(script.Parent.Geometry)
local Singles = require(script.Parent.Mechanisms)
local Coupled = require(script.Parent.Coupled)

local Runtime = {}
Runtime.__index = Runtime

local function csvCell(value)
	local s = tostring(value == nil and "" or value)
	return '"' .. s:gsub('"', '""') .. '"'
end

local function n(value)
	return string.format("%.6f", value or 0)
end

local function titleFor(index)
	local t = Config.Tests[index]
	return if t then t[1] .. " " .. t[2] else "Unknown"
end

function Runtime.new(remote)
	local old = Workspace:FindFirstChild("OPENWORKS_PhysicsBenchmark")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "OPENWORKS_PhysicsBenchmark"
	root.Parent = Workspace
	local self = setmetatable({
		remote = remote,
		root = root,
		index = 1,
		running = false,
		stopRequested = false,
		rigs = {},
		rows = {},
		errors = {},
	}, Runtime)
	self:mount(1)
	return self
end

function Runtime:send(kind, payload)
	self.remote:FireAllClients(kind, payload)
end

function Runtime:status(message)
	print("[OW PHYSICS BENCH] " .. message)
	self:send("status", {
		text = message,
		index = self.index,
		test = titleFor(self.index),
		running = self.running,
		totalRows = #self.rows,
		stepping = Workspace.PhysicsSteppingMethod.Name,
	})
end

function Runtime:mount(index)
	if self.running then
		return
	end
	self.index = math.clamp(index, 1, #Config.Tests)
	self.root:ClearAllChildren()
	self.rigs = {}
	self.errors = {}
	for i, candidate in ipairs(Config.Scales) do
		local s = candidate / Config.ReferenceScale
		local origin = Vector3.new((i - 3) * 38, 0, 0)
		local model = Instance.new("Model")
		model.Name = string.format("%02d_%g_stud", self.index, candidate)
		model.Parent = self.root
		local stage = Instance.new("Part")
		stage.Name = "Non-colliding display platform"
		stage.Anchored, stage.CanCollide, stage.CanTouch = true, false, false
		stage.Size = Vector3.new(31, 0.2, 29)
		stage.Position = origin + Vector3.new(0, -1.3, 0)
		stage.Material = Enum.Material.SmoothPlastic
		stage.Color = Color3.fromRGB(35, 47, 62)
		stage.Parent = model
		local tag = Instance.new("BillboardGui")
		tag.Name = "ScaleLabel"
		tag.Size = UDim2.fromOffset(220, 42)
		tag.StudsOffset = Vector3.new(0, 2, 0)
		tag.AlwaysOnTop = true
		tag.Parent = stage
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(24, 34, 45)
		label.BackgroundTransparency = 0.1
		label.TextColor3 = Color3.fromRGB(235, 245, 252)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Text = string.format("%g stud reference", candidate)
		label.Parent = tag

		local geom = Geometry.new(model, origin, s)
		local ok, result = pcall(function()
			return if self.index <= 12 then Singles.build(self.index, geom)
				else Coupled.build(self.index, geom)
		end)
		if ok then
			self.rigs[i] = { geometry = result, scale = candidate }
		else
			self.errors[i] = tostring(result)
			warn(string.format("[OW PHYSICS BENCH] %s at %g: %s",
				titleFor(self.index), candidate, tostring(result)))
		end
	end
	self:status("Ready | " .. titleFor(self.index) .. " | five scale candidates")
end

function Runtime:drive(phase, reversed)
	for _, rig in pairs(self.rigs) do
		local g = rig.geometry
		local active = phase ~= "idle"
		g:setLoad(phase == "heavy" or phase == "extreme")
		for _, entry in ipairs(g.motors) do
			local c = entry.instance
			if entry.kind == "angular" or entry.kind == "cylAngular" then
				local rpm = if phase == "extreme" then 600 else 180
				local angular = if active then rpm * math.pi / 30 else 0
				if reversed then angular = -angular end
				c.AngularVelocity = angular
			elseif entry.kind == "linear" then
				local speed = if phase == "extreme" then 9 else 3.5
				c.Velocity = if active then (if reversed then -1 else 1) * speed * g.factor else 0
			end
		end
		for _, c in ipairs(g.joints) do
			if c:IsA("RopeConstraint") then
				c.WinchEnabled = active
				c.WinchTarget = (if reversed then 5 else 2.5) * g.factor
			end
		end
	end
end

local function deviation(c)
	local a, b = c.Attachment0, c.Attachment1
	if not a or not b or not a.Parent or not b.Parent then
		return math.huge, math.huge
	end
	local delta = b.WorldPosition - a.WorldPosition
	local class = c.ClassName
	local err
	if class == "PrismaticConstraint" or class == "CylindricalConstraint" then
		local axis = a.WorldAxis
		err = (delta - axis * delta:Dot(axis)).Magnitude
	elseif class == "RodConstraint" then
		err = math.abs(delta.Magnitude - c.Length)
	elseif class == "RopeConstraint" then
		err = math.max(0, delta.Magnitude - c.Length)
	elseif class == "PlaneConstraint" then
		err = math.abs(delta:Dot(a.WorldAxis))
	elseif class == "SpringConstraint" then
		return 0, 0 -- A spring has no required position while moving.
	else
		err = delta.Magnitude
	end
	local angle = 0
	if class == "HingeConstraint" or class == "PrismaticConstraint" then
		local dot = math.clamp(math.abs(a.WorldAxis:Dot(b.WorldAxis)), 0, 1)
		angle = math.deg(math.acos(dot))
	end
	return err, angle
end

local function freshStats()
	return {
		samples = 0, sumJoint = 0, maxJoint = 0,
		sumAngle = 0, maxAngle = 0, sumMotor = 0,
		motorSamples = 0, sumFrame = 0, maxFrame = 0,
		throttleSum = 0, invalid = 0,
	}
end

local function record(g, data, candidate, dt, includeMotors)
	local maxErr, maxAngle = 0, 0
	for _, c in ipairs(g.joints) do
		local err, angle = deviation(c)
		if err ~= err or err == math.huge or angle ~= angle then
			data.invalid += 1
		else
			maxErr = math.max(maxErr, err / candidate)
			maxAngle = math.max(maxAngle, angle)
		end
	end
	data.samples += 1
	data.sumJoint += maxErr
	data.maxJoint = math.max(data.maxJoint, maxErr)
	data.sumAngle += maxAngle
	data.maxAngle = math.max(data.maxAngle, maxAngle)
	data.sumFrame += dt
	data.maxFrame = math.max(data.maxFrame, dt)
	data.throttleSum += Workspace:GetPhysicsThrottling()
	if includeMotors then
		for _, motor in ipairs(g.motors) do
			local c = motor.instance
			local a, b = c.Attachment0, c.Attachment1
			if a and b and a.Parent and b.Parent then
				local measured, target
				if motor.kind == "linear" then
					measured = (b.Parent.AssemblyLinearVelocity - a.Parent.AssemblyLinearVelocity):Dot(a.WorldAxis)
					target = c.Velocity
				else
					measured = (b.Parent.AssemblyAngularVelocity - a.Parent.AssemblyAngularVelocity):Dot(a.WorldAxis)
					target = c.AngularVelocity
				end
				if target ~= 0 then
					local errorRatio = math.abs(math.abs(measured) - math.abs(target)) / math.max(1, math.abs(target))
					if errorRatio == errorRatio then
						data.sumMotor += errorRatio
						data.motorSamples += 1
					else
						data.invalid += 1
					end
				end
			end
		end
	end
end

function Runtime:runPhase(phase, trial)
	local metrics = {}
	for i = 1, #Config.Scales do
		metrics[i] = freshStats()
	end
	local total, sinceSample, reversed, pulseOne, pulseTwo = 0, 0, false, false, false
	self:drive(phase, false)
	while total < Config.SecondsPerPhase and not self.stopRequested do
		local dt = RunService.Heartbeat:Wait()
		total += dt
		sinceSample += dt
		if not reversed and total > Config.SecondsPerPhase / 2 then
			reversed = true
			if phase == "extreme" then self:drive(phase, true) end
		end
		if (phase == "heavy" or phase == "extreme") and
			((not pulseOne and total > Config.SecondsPerPhase * 0.3) or
				(not pulseTwo and total > Config.SecondsPerPhase * 0.65)) then
			if total < Config.SecondsPerPhase * 0.5 then pulseOne = true else pulseTwo = true end
			for _, rig in pairs(self.rigs) do
				local g = rig.geometry
				local body = g.movers[1]
				if body then
					local change = Vector3.new(2, -4, 1) * g.factor
					body:ApplyImpulse(change * body.AssemblyMass * (if phase == "extreme" then 3 else 1))
				end
			end
		end
		if sinceSample >= Config.SampleInterval then
			for i, rig in pairs(self.rigs) do
				record(rig.geometry, metrics[i], rig.scale, dt, phase ~= "idle")
			end
			sinceSample = 0
		end
	end
	for i, candidate in ipairs(Config.Scales) do
		local m = metrics[i]
		local count = math.max(1, m.samples)
		local row = {
			titleFor(self.index), candidate, Workspace.PhysicsSteppingMethod.Name,
			Workspace.Gravity, phase, trial,
			m.samples, m.sumJoint / count, m.maxJoint,
			m.sumAngle / count, m.maxAngle,
			if m.motorSamples > 0 then m.sumMotor / m.motorSamples else 0,
			m.sumFrame / count, m.maxFrame, m.throttleSum / count,
			m.invalid, if self.errors[i] then "BUILD_ERROR" else if self.stopRequested then "INTERRUPTED" else "RECORDED",
			self.errors[i] or "",
		}
		table.insert(self.rows, row)
	end
end

function Runtime:run(all)
	if self.running then return end
	self.running = true
	self.stopRequested = false
	local first, last = self.index, if all then #Config.Tests else self.index
	self:status(if all then "Running all 17 mechanisms" else "Running " .. titleFor(first))
	task.spawn(function()
		for testIndex = first, last do
			if self.stopRequested then break end
			self.index = testIndex
			for trial = 1, Config.Trials do
				if self.stopRequested then break end
				for _, phase in ipairs(Config.Phases) do
					if self.stopRequested then break end
					self.running = false -- allow controlled reconstruction; no external commands during task.
					self:mount(testIndex)
					self.running = true
					self:status(string.format("%s | trial %d/%d | %s",
						titleFor(testIndex), trial, Config.Trials, phase))
					self:runPhase(phase, trial)
				end
			end
		end
		local wasStopped = self.stopRequested
		self.running = false
		self.stopRequested = false
		self:mount(self.index)
		self:status((if wasStopped then "Stopped" else "Finished") ..
			" | " .. tostring(#self.rows) .. " results | use Export CSV")
	end)
end

function Runtime:export()
	local header = {
		"test", "reference_studs", "physics_stepping", "gravity",
		"phase", "trial", "samples", "mean_rel_joint_error", "peak_rel_joint_error",
		"mean_axis_error_deg", "peak_axis_error_deg", "mean_motor_speed_error",
		"mean_heartbeat_dt_s", "peak_heartbeat_dt_s", "mean_physics_throttle_pct",
		"invalid_samples", "status", "detail",
	}
	local lines = { table.concat(header, ",") }
	for _, row in ipairs(self.rows) do
		local cells = {}
		for _, value in ipairs(row) do
			table.insert(cells, csvCell(value))
		end
		table.insert(lines, table.concat(cells, ","))
	end
	local csv = table.concat(lines, "\n")
	-- GUI textbox is easiest to copy; Output fallback is split to avoid truncating one line.
	self:send("csv", csv)
	print("[OW PHYSICS BENCH] CSV export: " .. #self.rows .. " rows. Copy from the benchmark GUI.")
	for startIndex = 1, #lines, 35 do
		local segment = {}
		for i = startIndex, math.min(#lines, startIndex + 34) do
			table.insert(segment, lines[i])
		end
		print("[OW PHYSICS CSV]\n" .. table.concat(segment, "\n"))
	end
	return csv
end

function Runtime:handle(player, action, value)
	if not RunService:IsStudio() or typeof(action) ~= "string" then return end
	if action == "prev" and not self.running then
		self:mount(if self.index == 1 then #Config.Tests else self.index - 1)
	elseif action == "next" and not self.running then
		self:mount(if self.index == #Config.Tests then 1 else self.index + 1)
	elseif action == "run" then
		self:run(false)
	elseif action == "all" then
		if not self.running then
			self.index = 1
			self:run(true)
		end
	elseif action == "stop" then
		self.stopRequested = true
	elseif action == "export" then
		self:export()
	elseif action == "status" then
		self:status("Ready | " .. titleFor(self.index))
	end
end

return Runtime
