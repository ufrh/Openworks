--!strict
-- One visible primitive per component. Native shapes update immediately;
-- special parametric cutters compile ONLY when shape dimensions change.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Compiler = require(ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM").Compiler)
local Document = require(ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM").Document)

local Preview = {}
Preview.__index = Preview

local function configure(part: BasePart)
	part.Name = "Solid"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(170, 190, 196)
	if part:IsA("PartOperation") then part.UsePartColor = true end
end

function Preview.new(onStatus, onRendered)
	local root = Instance.new("Folder")
	root.Name = "FORM_LocalPreview"
	root.Parent = workspace
	return setmetatable({
		root = root,
		models = {},
		states = {},
		jobs = {},
		dragging = {},
		onStatus = onStatus,
		onRendered = onRendered,
	}, Preview)
end

function Preview:getModel(id: number): Model?
	return self.models[id]
end

function Preview:remove(id: number)
	self.dragging[id] = nil
	local job = self.jobs[id]
	if job then
		job.cancelled = true
		job.pending = nil
		self.jobs[id] = nil
	end
	local model = self.models[id]
	if model then model:Destroy() end
	self.models[id] = nil
	self.states[id] = nil
end

function Preview:ensure(component)
	local model = self.models[component.id]
	if model then return model end
	model = Instance.new("Model")
	model.Name = component.name
	model:SetAttribute("FORMComponentId", component.id)
	model.Parent = self.root
	self.models[component.id] = model
	return model
end

function Preview:replace(component, part: BasePart, key: string, madeWithCSG: boolean)
	local id = component.id
	local model = self:ensure(component)
	local previous = self.states[id]
	local localFrame = part.CFrame -- template-space frame, before world transform
	configure(part)
	part.CFrame = Compiler.pose(component.nodes[1]) * localFrame
	if previous and previous.part then previous.part:Destroy() end
	part.Parent = model
	self.states[id] = {
		part = part,
		localFrame = localFrame,
		key = key,
		kind = component.nodes[1].kind,
		boolean = madeWithCSG,
	}
	self.onRendered(id, model)
end

function Preview:updateGeometry(component)
	local node = component.nodes[1]
	local key = Compiler.geometryKey(node)
	local requiresCut = Compiler.requiresBoolean(node)
	local state = self.states[component.id]

	-- Native blocks/cylinders and special templates before a valid hole
	-- exists are regular Parts. Never compile or reconstruct them on edits.
	if not requiresCut then
		local part: BasePart
		if state and state.part:IsA("Part") and not state.boolean
			and state.kind == node.kind then
			part = state.part
			part.Size = Compiler.partSize(node)
			part.CFrame = Compiler.pose(node) * state.localFrame
			state.key = key
		else
			part = Compiler.nativePart(node)
			self:replace(component, part, key, false)
		end
		return false
	end

	if not state then
		-- A single visible, directly transformable placeholder until the
		-- parametric primitive has been manufactured once.
		self:replace(component, Compiler.nativePart(node), "", false)
		state = self.states[component.id]
	end

	-- Moving/rotating already-manufactured CSG solids changes only CFrame.
	-- Resizing temporarily stretches the current solid until re-manufacture.
	state.part.CFrame = Compiler.pose(node) * state.localFrame
	if state.key ~= key then
		state.part.Size = Compiler.partSize(node)
	end
	return state.key ~= key or not state.boolean
end

function Preview:queueManufacture(component)
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
			local source = snapshot.nodes[1]
			local expectedKey = Compiler.geometryKey(source)
			if not Compiler.requiresBoolean(source) then continue end
			self.onStatus("Manufacturing " .. snapshot.name .. "...")
			local ok, output = pcall(Compiler.compileTemplate, source)
			if not ok then
				self.onStatus("Primitive CSG failed: " .. tostring(output))
				continue
			end

			local current = component.nodes[1]
			if job.cancelled or job.pending
				or self.dragging[id]
				or not Compiler.requiresBoolean(current)
				or expectedKey ~= Compiler.geometryKey(current) then
				output:Destroy()
				if not job.cancelled and not self.dragging[id]
					and Compiler.requiresBoolean(current) and not job.pending then
					job.pending = Document.snapshot(component)
				end
			else
				self:replace(component, output, expectedKey, true)
				self.onStatus(snapshot.name .. " ready")
			end
		end
		job.running = false
	end)
end

function Preview:render(component)
	local requiresManufacture = self:updateGeometry(component)
	if requiresManufacture and not self.dragging[component.id] then
		self:queueManufacture(component)
	end
end

function Preview:beginLive(component, _index: number)
	self.dragging[component.id] = true
	-- No ghost meshes and no background Boolean builds during dragging.
	self:updateGeometry(component)
end

function Preview:updateLive(component, _index: number)
	self:updateGeometry(component)
end

function Preview:finishLive(component)
	self.dragging[component.id] = nil
	self:render(component)
end

function Preview:cancelLive(id: number)
	self.dragging[id] = nil
end

return Preview
