--!strict
-- One visible primitive per component. Native solids update immediately;
-- material-cut histories compile asynchronously when geometry changes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Compiler = require(ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM").Compiler)
local Fabricator = require(ReplicatedStorage:WaitForChild("Openworks"):WaitForChild("FORM").Fabricator)
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
	part.Reflectance = 0
	part.Transparency = 0
	if part:IsA("PartOperation") then
		part.UsePartColor = true
	elseif part:IsA("MeshPart") then
		-- Mesh CSG results preserve source face colors; they are kept white by
		-- Compiler/Extrusion so this displayed tint is uniform.
		part.TextureID = ""
	end
end

function Preview.new(onStatus, onRendered)
	local root = Instance.new("Folder")
	root.Name = "FORM_LocalPreview"
	root.Parent = workspace
	local self = setmetatable({
		root = root,
		models = {},
		states = {},
		jobs = {},
		dragging = {},
		onStatus = onStatus,
		onRendered = onRendered,
	}, Preview)
	-- Only the rendering interpolates. Parametric source remains precisely snapped.
	self.renderConnection = RunService.RenderStepped:Connect(function(dt)
		local alpha = 1 - math.exp(-26 * dt)
		for _, state in pairs(self.states) do
			if state.smoothing and state.part and state.part.Parent then
				state.part.CFrame = state.part.CFrame:Lerp(state.targetFrame, alpha)
				state.part.Size = state.part.Size:Lerp(state.targetSize, alpha)
				if not state.dragging and
					(state.part.Position - state.targetFrame.Position).Magnitude < 0.0005 and
					(state.part.Size - state.targetSize).Magnitude < 0.0005 then
					state.part.CFrame = state.targetFrame
					state.part.Size = state.targetSize
					state.smoothing = false
				end
			end
		end
	end)
	return self
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
	local targetFrame = Compiler.pose(component.nodes[1]) * localFrame
	local targetSize = part.Size
	if previous and previous.smoothing and previous.part and not madeWithCSG then
		-- Native shapes can interpolate their dimensions. Resizing a CSG
		-- MeshPart distorts its generated mesh and creates broken-looking faces.
		part.CFrame = previous.part.CFrame
		part.Size = previous.part.Size
	else
		part.CFrame = targetFrame
	end
	if previous and previous.part then previous.part:Destroy() end
	part.Parent = model
	self.states[id] = {
		part = part,
		localFrame = localFrame,
		key = key,
		kind = component.nodes[1].kind,
		boolean = madeWithCSG,
		targetFrame = targetFrame, targetSize = targetSize,
		smoothing = not madeWithCSG and previous ~= nil and previous.smoothing or false,
		dragging = self.dragging[id] == true,
	}
	self.onRendered(id, model)
end

function Preview:updateGeometry(component)
	local node = component.nodes[1]
	local key = Fabricator.geometryKey(component)
	local requiresCut = Fabricator.requiresCompile(component)
	local state = self.states[component.id]

	-- Uncut workpieces remain native Parts, avoiding gratuitous CSG calls.
	if not requiresCut then
		local part: BasePart
		if state and state.part:IsA("Part") and not state.boolean
			and state.kind == node.kind then
			part = state.part
			state.targetSize = Compiler.partSize(node)
			state.targetFrame = Compiler.pose(node) * state.localFrame
			if not state.smoothing then
				part.Size = state.targetSize
				part.CFrame = state.targetFrame
			end
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

	-- Keep the last valid manufactured mesh intact until the replacement is
	-- compiled. Stretching it to the new block envelope turns its openings,
	-- surface normals and colors into visually corrupted geometry.
	state.targetFrame = Compiler.pose(node) * state.localFrame
	if state.boolean then
		state.targetSize = state.part.Size
	else
		state.targetSize = Compiler.partSize(node)
	end
	if not state.smoothing then
		state.part.CFrame = state.targetFrame
		state.part.Size = state.targetSize
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
			local expectedKey = Fabricator.geometryKey(snapshot)
			if not Fabricator.requiresCompile(snapshot) then continue end
			self.onStatus("Manufacturing " .. snapshot.name .. "...")
			local ok, output, summary = pcall(Fabricator.compile, snapshot)
			if not ok then
				self.onStatus("Fabrication CSG failed: " .. tostring(output))
				continue
			end

			if job.cancelled or job.pending
				or self.dragging[id]
				or not Fabricator.requiresCompile(component)
				or expectedKey ~= Fabricator.geometryKey(component) then
				output:Destroy()
				if not job.cancelled and not self.dragging[id]
					and Fabricator.requiresCompile(component) and not job.pending then
					job.pending = Document.snapshot(component)
				end
			else
				self:replace(component, output, expectedKey, true)
				self.onStatus(snapshot.name .. " ready: " .. summary)
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
	local state = self.states[component.id]
	if state then state.smoothing, state.dragging = true, true end
	-- No ghost meshes and no background Boolean builds during dragging.
	self:updateGeometry(component)
end

function Preview:updateLive(component, _index: number)
	self:updateGeometry(component)
end

function Preview:finishLive(component)
	self.dragging[component.id] = nil
	local state = self.states[component.id]
	if state then state.dragging = false end
	self:render(component)
end

function Preview:cancelLive(id: number)
	self.dragging[id] = nil
	local state = self.states[id]
	if state then state.dragging = false end
end

return Preview
