--!strict
-- Editable CSG previews with live source feedback and throttled async recompiles.
-- Source nodes remain authoritative; stale compilation results are discarded.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Openworks = ReplicatedStorage:WaitForChild("Openworks")
local FORM = Openworks:WaitForChild("FORM")
local Compiler = require(FORM.Compiler)
local Document = require(FORM.Document)

local Preview = {}
Preview.__index = Preview

local function sourcePose(node): CFrame
	local r = node.rotation
	return CFrame.new(node.position) * CFrame.fromOrientation(
		math.rad(r.X), math.rad(r.Y), math.rad(r.Z)
	)
end

function Preview.new(onStatus, onRendered)
	local root = Instance.new("Folder")
	root.Name = "FORM_LocalPreview"
	root.Parent = workspace
	return setmetatable({
		root = root,
		models = {},
		jobs = {},
		live = {},
		onStatus = onStatus,
		onRendered = onRendered,
	}, Preview)
end

function Preview:getModel(id: number): Model?
	return self.models[id]
end

function Preview:remove(id: number)
	local job = self.jobs[id]
	if job then
		job.cancelled = true
		job.pending = nil
		self.jobs[id] = nil
	end
	local live = self.live[id]
	if live then
		live.ghost:Destroy()
		self.live[id] = nil
	end
	local model = self.models[id]
	if model then model:Destroy() end
	self.models[id] = nil
end

function Preview:render(component)
	local id = component.id
	local job = self.jobs[id]
	if not job then
		job = { pending = nil, running = false, cancelled = false }
		self.jobs[id] = job
	end
	job.pending = Document.snapshot(component)
	if job.running then return end

	job.running = true
	task.spawn(function()
		while job.pending and not job.cancelled do
			local snapshot = job.pending
			job.pending = nil
			local live = self.live[id]
			if not live then self.onStatus("Compiling " .. snapshot.name .. "...") end
			local ok, compiled = pcall(Compiler.compile, snapshot)
			if job.cancelled or job.pending then
				if ok then compiled:Destroy() end
			elseif not ok then
				self.onStatus("CSG failed: " .. tostring(compiled))
				if live and not live.active then
					live.ghost:Destroy()
					self.live[id] = nil
				end
			else
				local model = Instance.new("Model")
				model.Name = snapshot.name
				model:SetAttribute("FORMComponentId", id)
				compiled.Parent = model
				model.Parent = self.root
				local previous = self.models[id]
				self.models[id] = model
				if previous then previous:Destroy() end
				live = self.live[id]
				if not live then
					self.onStatus(snapshot.name .. " compiled (rev " .. snapshot.revision .. ")")
				elseif not live.active and live.finalRevision == snapshot.revision then
					live.ghost:Destroy()
					self.live[id] = nil
					self.onStatus(snapshot.name .. " compiled (rev " .. snapshot.revision .. ")")
				end
				self.onRendered(id, model)
			end
		end
		job.running = false
	end)
end

function Preview:beginLive(component, index: number)
	local existing = self.live[component.id]
	if existing then existing.ghost:Destroy() end
	local ghost = Instance.new("Part")
	ghost.Name = "FORM_LiveSource_" .. component.id
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanTouch = false
	ghost.CanQuery = false
	ghost.CastShadow = false
	ghost.Material = Enum.Material.Neon
	ghost.Transparency = 0.65
	ghost.Parent = self.root
	self.live[component.id] = {
		ghost = ghost, active = true, scheduled = false,
		component = component, index = index, finalRevision = nil,
	}
	self:updateLive(component, index)
end

function Preview:updateLive(component, index: number)
	local live = self.live[component.id]
	if not live or not live.active then return end
	local node = component.nodes[index]
	if not node then return end
	live.index = index
	local ghost = live.ghost
	if node.kind == "Cylinder" or node.kind == "Tube" then
		ghost.Shape = Enum.PartType.Cylinder
		ghost.Size = Vector3.new(node.size.Y, node.size.X, node.size.X)
		ghost.CFrame = sourcePose(node) * CFrame.Angles(0, 0, math.pi / 2)
	else
		ghost.Shape = Enum.PartType.Block
		ghost.Size = node.size
		ghost.CFrame = sourcePose(node)
	end
	ghost.Color = if node.operation == "Subtract" then Color3.fromRGB(252, 111, 101)
		else Color3.fromRGB(92, 227, 212)
	-- Coalesce many pointer events. CSG operations may yield for several frames.
	-- The worker only keeps the most recent snapshot and never blocks dragging.
	if live.scheduled then return end
	live.scheduled = true
	task.delay(0.11, function()
		if self.live[component.id] ~= live then return end
		live.scheduled = false
		if live.active then self:render(component) end
	end)
end

function Preview:cancelLive(id: number)
	local live = self.live[id]
	if not live then return end
	live.ghost:Destroy()
	self.live[id] = nil
end

function Preview:finishLive(component)
	local live = self.live[component.id]
	if not live then
		self:render(component)
		return
	end
	live.active = false
	live.finalRevision = component.revision
	self:render(component)
end

return Preview
