--!strict
-- Per-component compilation queue. Stale async results never replace newer edits.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Openworks = ReplicatedStorage:WaitForChild("Openworks")
local FORM = Openworks:WaitForChild("FORM")
local Compiler = require(FORM.Compiler)
local Document = require(FORM.Document)

local Preview = {}
Preview.__index = Preview

function Preview.new(onStatus, onRendered)
	local root = Instance.new("Folder")
	root.Name = "FORM_LocalPreview"
	root.Parent = workspace
	return setmetatable({
		root = root,
		models = {},
		jobs = {},
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
			self.onStatus("Compiling " .. snapshot.name .. "...")
			local ok, compiled = pcall(Compiler.compile, snapshot)

			if job.cancelled or job.pending then
				if ok then compiled:Destroy() end
			elseif not ok then
				self.onStatus("CSG failed: " .. tostring(compiled))
			else
				local model = Instance.new("Model")
				model.Name = snapshot.name
				model:SetAttribute("FORMComponentId", id)
				compiled.Parent = model
				model.Parent = self.root
				local previous = self.models[id]
				self.models[id] = model
				if previous then previous:Destroy() end
				self.onStatus(snapshot.name .. " compiled (rev " .. snapshot.revision .. ")")
				self.onRendered(id, model)
			end
		end
		job.running = false
	end)
end

return Preview
