--!strict
local RS, Players, RunService =
	game:GetService("ReplicatedStorage"), game:GetService("Players"), game:GetService("RunService")
local FORGE = require(RS:WaitForChild("FORGE"))
local Shared = RS:WaitForChild("Openworks"):WaitForChild("Assembly")
local Layout = require(Shared.AssemblyLayout)
local Resolver = require(Shared.MechanicalResolver)
local Catalog = require(Shared.RelationshipCatalog)
local Session = require(script.Parent.Parent.Simulation.AssemblySession)
local Service = FORGE.Service("OpenWorksAssembly")
local function document(player: Player): any
	local docs = FORGE:GetService("OpenWorksDocuments")
	return docs and docs.documents[player]
end
local function changed(player: Player)
	local docs = FORGE:GetService("OpenWorksDocuments")
	if docs then
		docs:Changed(player, nil, false)
	end
end
function Service:Init()
	self.layouts = {}
	self.sessions = {}
	self.busy = {}
	self.graphs = {}
	self.slots = {}
	self.cache = {}
	self.lastImpulse = {}
	self.epochs = {}
	self.characterConnections = {}
	for _, name in ipairs({
		"GetLayout",
		"SetPose",
		"SetGrounded",
		"RegisterSupport",
		"RemoveSupport",
		"RegisterRelationship",
		"ValidateAssembly",
		"SimulationControl",
		"TestImpulse",
		"SimulationStatus",
		"SetBenchDrive",
		"ListDriveTargets",
		"StartSimulation",
		"StopSimulation",
		"ListJoints",
		"Install",
		"Remove",
		"SetActuator",
	}) do
		self:Expose(name)
	end
	local function watch(player)
		self.characterConnections[player] = player.CharacterRemoving:Connect(function()
			self.epochs[player] = (self.epochs[player] or 0) + 1
			if not self.busy[player] then
				self:StopSimulation(player)
			end
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	self:Track(Players.PlayerAdded:Connect(watch))
	self:Track(RunService.Heartbeat:Connect(function(dt)
		for _, session in pairs(self.sessions) do
			Session.update(session, dt)
		end
	end))
	self:Track(Players.PlayerRemoving:Connect(function(player)
		self.epochs[player] = (self.epochs[player] or 0) + 1
		if self.characterConnections[player] then
			self.characterConnections[player]:Disconnect()
		end
		self.characterConnections[player] = nil
		self:StopSimulation(player)
		task.spawn(function()
			while self.busy[player] do
				task.wait(0.1)
			end
			self:StopSimulation(player)
			self.layouts[player] = nil
			self.graphs[player] = nil
			self.busy[player] = nil
			for _, item in pairs(self.cache[player] or {}) do
				item.part:Destroy()
			end
			self.cache[player] = nil
			self.lastImpulse[player] = nil
			self.epochs[player] = nil
		end)
	end))
end
function Service:IsBusy(player: Player): boolean
	return self.busy[player] == true or self.sessions[player] ~= nil
end
function Service:_layout(player: Player): any
	local state = self.layouts[player]
	if not state then
		state = {
			version = 2,
			revision = 0,
			poses = {},
			grounded = {},
			supports = {},
			quarantined = {},
		}
		self.layouts[player] = state
	end
	local doc = document(player)
	if doc then
		for index, id in ipairs(doc.order) do
			local key = tostring(id)
			if not state.poses[key] then
				state.poses[key] = Layout.initial(index, doc.components[id])
			end
		end
	end
	return state
end
function Service:GetLayout(player: Player)
	if not document(player) then
		return false, "Manufacturing document is not loaded"
	end
	return true, self:_layout(player)
end
function Service:SetPose(
	player: Player,
	id: any,
	componentRevision: any,
	layoutRevision: any,
	pose: any
)
	if self:IsBusy(player) then
		return false, "Assembly is validating or simulating"
	end
	local doc = document(player)
	local component = doc and doc.components[id]
	if not component or component.revision ~= componentRevision then
		return false, "Stale component revision"
	end
	local state = self:_layout(player)
	if layoutRevision ~= state.revision then
		return false, "Stale assembly revision; reload layout"
	end
	if not Layout.validFrame(pose) then
		return false, "Invalid or out-of-workspace pose"
	end
	self.busy[player] = true
	local epoch = self.epochs[player] or 0
	local proposed = table.clone(state.poses)
	proposed[tostring(id)] = pose
	local parts = nil
	local success, accepted, reason, conflicts = xpcall(function()
		local problem
		parts, problem = Session.compile(doc, proposed, self:_cache(player))
		if not parts then
			return false, problem
		end
		local clear, why, pair = Session.validate(parts, id)
		if not clear then
			return false, why, pair
		end
		if not player.Parent or epoch ~= (self.epochs[player] or 0) then
			return false, "Session changed; retry after respawning"
		end
		state.poses = proposed
		state.revision += 1
		changed(player)
		return true, state.revision
	end, debug.traceback)
	if parts then
		Session.destroy({ parts = parts })
	end
	self.busy[player] = nil
	if not success then
		warn(accepted)
		return false, "Placement validation failed"
	end
	return accepted, reason, conflicts
end
function Service:SetGrounded(player: Player, id: any, revision: any, enabled: any)
	if self:IsBusy(player) then
		return false, "Stop simulation or wait for validation"
	end
	local doc = document(player)
	local state = self:_layout(player)
	if
		not doc
		or not doc.components[id]
		or revision ~= state.revision
		or typeof(enabled) ~= "boolean"
	then
		return false, "Invalid grounding request or stale layout"
	end
	state.grounded[tostring(id)] = if enabled then true else nil
	state.revision += 1
	changed(player)
	return true, state.revision
end
function Service:RegisterSupport(
	player: Player,
	bodyId: any,
	featureId: any,
	shaftId: any,
	revision: any
)
	return self:RegisterRelationship(
		player,
		"BoreSupportV1",
		shaftId,
		bodyId,
		featureId,
		{},
		revision
	)
end

function Service:RegisterRelationship(
	player: Player,
	model: any,
	movingId: any,
	bodyId: any,
	featureId: any,
	fixtures: any,
	revision: any,
	movingFeatureId: any?
)
	if self:IsBusy(player) then
		return false, "Stop simulation or wait for validation"
	end
	local state, doc = self:_layout(player), document(player)
	if not doc or revision ~= state.revision then
		return false, "Assembly changed; refresh before adding a relationship"
	end
	local spec = nil
	for _, item in ipairs(Catalog) do
		if item.model == model then
			spec = item
			break
		end
	end
	if
		not spec
		or type(fixtures) ~= "table"
		or #fixtures ~= spec.fixtures
		or type(movingId) ~= "number"
		or not doc.components[movingId]
	then
		return false, "Choose the moving part and the required number of fixtures"
	end
	local seen = { [movingId] = true }
	for _, id in ipairs(fixtures) do
		if type(id) ~= "number" or not doc.components[id] or seen[id] then
			return false, "Fixtures must be separate owned components"
		end
		seen[id] = true
	end
	local record = { model = model, movingId = movingId }
	if model == "RetainedPivotV1" then
		if type(bodyId) ~= "number" or bodyId == movingId or type(featureId) ~= "string"
			or type(movingFeatureId) ~= "string" or #featureId > 96 or #movingFeatureId > 96 then
			return false, "Choose a drilled hole on each of the two links"
		end
		record.bodyId = bodyId
		record.featureId = featureId
		record.movingFeatureId = movingFeatureId
		record.pinId = fixtures[1]
		record.stopIds = {fixtures[2], fixtures[3]}
	elseif model == "BoreSupportV1" or model == "RetainedBoreV1" then
		if type(bodyId) ~= "number" or type(featureId) ~= "string" or #featureId > 96 then
			return false, "Choose a target bore"
		end
		record.bodyId, record.shaftId, record.featureId = bodyId, movingId, featureId
	else
		record.guideIds = { fixtures[1], fixtures[2], fixtures[3], fixtures[4] }
	end
	if model == "RetainedBoreV1" then
		record.stopIds = { fixtures[1], fixtures[2] }
	end
	if model == "LimitedGuideV1" then
		record.stopIds = { fixtures[5], fixtures[6] }
	end
	local resolved, problem = Resolver.resolve(record, doc.components, state.poses, state.grounded)
	if not resolved then
		return false, problem
	end
	for _, prior in ipairs(state.supports) do
		if model == "RetainedPivotV1" then
			if prior.pinId == record.pinId then
				return false, "This pin is already assigned to another pivot"
			end
			if prior.model == "RetainedPivotV1"
				and prior.movingId == movingId and prior.bodyId == bodyId
				and prior.featureId == featureId and prior.movingFeatureId == movingFeatureId then
				return false, "This pivot connection already exists"
			end
		elseif prior.model ~= "RetainedPivotV1"
			and (prior.movingId or prior.shaftId) == movingId then
			return false, "Remove the existing guide/bearing before replacing it"
		end
	end
	if #state.supports >= 96 then
		return false, "Relationship limit reached"
	end
	table.insert(state.supports, record)
	state.revision += 1
	changed(player)
	return true, state.revision
end

function Service:_cache(player: Player)
	self.cache[player] = self.cache[player] or {}
	return self.cache[player]
end

function Service:ValidateAssembly(player: Player, revision: any)
	if self:IsBusy(player) then
		return false, "Assembly is busy"
	end
	local doc, state = document(player), self:_layout(player)
	if not doc or revision ~= state.revision then
		return false, "Refresh the assembly first"
	end
	self.busy[player] = true
	local parts = nil
	local ok, report = xpcall(function()
		local problem
		parts, problem = Session.compile(doc, state.poses, self:_cache(player))
		if not parts then
			return { valid = false, message = problem, relationships = {} }
		end
		local clear, why, conflicts = Session.validate(parts)
		local result = {
			valid = clear,
			message = why or "No solid interference detected",
			conflicts = conflicts,
			relationships = {},
		}
		for index, record in ipairs(state.supports) do
			local relation, reason =
				Resolver.resolve(record, doc.components, state.poses, state.grounded)
			table.insert(
				result.relationships,
				{ index = index, valid = relation ~= nil, message = reason or "Ready" }
			)
			if not relation then
				result.valid = false
			end
		end
		return result
	end, debug.traceback)
	if parts then
		Session.destroy({ parts = parts })
	end
	self.busy[player] = nil
	if not ok then
		warn(report)
		return false, "Validation failed; see server diagnostics"
	end
	return true, report
end

function Service:SimulationControl(player: Player, action: any)
	local session = self.sessions[player]
	if not session or self.busy[player] then
		return false, "No active simulation"
	end
	if action == "Pause" then
		Session.pause(session, true)
	elseif action == "Resume" then
		Session.pause(session, false)
	elseif action == "Reset" then
		local ok, problem = Session.reset(session)
		if not ok then
			self:StopSimulation(player)
			return false, problem
		end
	else
		return false, "Unknown simulation action"
	end
	return self:SimulationStatus(player)
end

function Service:SimulationStatus(player: Player)
	local session = self.sessions[player]
	if not session then
		return false, "Simulation stopped"
	end
	return true,
		{ paused = session.paused, supports = #session.relations,
			released = session.released, drives = table.clone(session.drives) }
end

-- Drives are attached to real accepted constraints in the active test.
-- No fabricated motor is implied, and no drive survives StopSimulation.
function Service:ListDriveTargets(player: Player)
	local session = self.sessions[player]
	if not session then
		return false, "Start the simulation first"
	end
	local list = {}
	for _, item in ipairs(session.relations) do
		table.insert(list, {
			index = item.index,
			kind = item.relation.kind,
			model = item.relation.model,
			movingId = item.relation.movingId,
			bodyId = item.relation.bodyId,
		})
	end
	return true, list
end

function Service:SetBenchDrive(player: Player, index: any, speed: any, effort: any)
	local session = self.sessions[player]
	if not session or self.busy[player] then
		return false, "Start the simulation first"
	end
	if type(index) ~= "number" or index % 1 ~= 0
		or type(speed) ~= "number" or type(effort) ~= "number" then
		return false, "Invalid drive target or parameters"
	end
	local ok, reason = Session.drive(session, index, speed, effort)
	if not ok then
		return false, reason
	end
	return true, if speed == 0 or effort == 0 then "Drive disengaged" else "Bench drive engaged"
end

function Service:TestImpulse(player: Player, id: any, kind: any, axisName: any, amount: any)
	local session = self.sessions[player]
	if not session or session.paused then
		return false, "Run or resume the simulation first"
	end
	if typeof(amount) ~= "number" or amount ~= amount or math.abs(amount) > 360 or amount == 0 then
		return false, "Invalid test impulse"
	end
	if os.clock() - (self.lastImpulse[player] or 0) < 0.15 then
		return false, "Wait briefly between impulses"
	end
	local part = session.parts[id]
	if not part or part.Anchored then
		return false, "Select an ungrounded simulation body"
	end
	local sourcePose = part.CFrame * part:GetAttribute("OWSourceLocalFrame"):Inverse()
	local axis = nil
	if axisName == "Motion" then
		for _, item in ipairs(session.relations) do
			if item.relation.movingId == id then
				local body = session.parts[item.relation.bodyId]
				axis = body.CFrame:VectorToWorldSpace(item.localAxis)
				break
			end
		end
		axis = axis or sourcePose.YVector
	elseif axisName == "X" then
		axis = Vector3.xAxis
	elseif axisName == "Y" then
		axis = Vector3.yAxis
	elseif axisName == "Z" then
		axis = Vector3.zAxis
	else
		return false, "Choose Motion, X, Y, or Z"
	end
	if
		part.AssemblyLinearVelocity.Magnitude > 50
		or part.AssemblyAngularVelocity.Magnitude > 50
	then
		return false, "Body is moving too fast; reset before applying another impulse"
	end
	self.lastImpulse[player] = os.clock()
	if kind == "Push" then
		part:ApplyImpulse(axis * part.AssemblyMass * (amount / 280))
	elseif kind == "Spin" then
		local localAxis = part.CFrame:VectorToObjectSpace(axis)
		local size = part.Size
		local inertia = part.AssemblyMass
			/ 12
			* (
				localAxis.X ^ 2 * (size.Y ^ 2 + size.Z ^ 2)
				+ localAxis.Y ^ 2 * (size.X ^ 2 + size.Z ^ 2)
				+ localAxis.Z ^ 2 * (size.X ^ 2 + size.Y ^ 2)
			)
		part:ApplyAngularImpulse(axis * inertia * math.rad(amount))
	else
		return false, "Choose Spin or Push"
	end
	return true, "External bench impulse applied"
end

function Service:RemoveSupport(player: Player, index: any, revision: any)
	if self:IsBusy(player) then
		return false, "Stop simulation or wait for validation"
	end
	local state = self:_layout(player)
	if
		revision ~= state.revision
		or type(index) ~= "number"
		or index % 1 ~= 0
		or not state.supports[index]
	then
		return false, "Support not found or stale layout"
	end
	table.remove(state.supports, index)
	state.revision += 1
	changed(player)
	return true, state.revision
end
function Service:StartSimulation(player: Player, revision: any)
	if self:IsBusy(player) then
		return false, "Assembly is busy"
	end
	local doc = document(player)
	local state = self:_layout(player)
	if not doc or #doc.order == 0 or revision ~= state.revision then
		return false, "Empty or stale assembly"
	end
	self.busy[player] = true
	local epoch = self.epochs[player] or 0
	local parts = nil
	local success, accepted, reason = xpcall(function()
		local problem
		parts, problem = Session.compile(doc, state.poses, self:_cache(player))
		if not parts then
			return false, problem
		end
		local clear, why = Session.validate(parts)
		if not clear then
			return false, why
		end
		if not player.Parent or epoch ~= (self.epochs[player] or 0) then
			return false, "Session changed; retry after respawning"
		end
		local slot = 1
		while self.slots[slot] do
			slot += 1
		end
		local session, issue = Session.start(player, doc, state, parts, slot)
		if session then
			self.slots[slot] = player
			session.slot = slot
		end
		parts = nil
		if not session then
			return false, issue
		end
		self.sessions[player] = session
		return true, session.center
	end, debug.traceback)
	if parts then
		Session.destroy({ parts = parts })
	end
	self.busy[player] = nil
	if not success then
		warn(accepted)
		return false, "Simulation setup failed"
	end
	return accepted, reason
end
function Service:StopSimulation(player: Player)
	if self.busy[player] then
		return false, "Validation in progress"
	end
	local session = self.sessions[player]
	if session then
		self.slots[session.slot] = nil
	end
	Session.destroy(session)
	self.sessions[player] = nil
	return true, nil
end
function Service:Snapshot(player: Player): any
	return self:_layout(player)
end
function Service:Restore(player: Player, joints: any, saved: any)
	self.graphs[player] = nil
	local state =
		{ version = 2, revision = 0, poses = {}, grounded = {}, supports = {}, quarantined = {} }
	self.layouts[player] = state
	if type(joints) == "table" then
		state.quarantined = joints
	end
	if type(saved) == "table" and saved.version == 2 then
		state.quarantined = if type(saved.quarantined) == "table"
			then saved.quarantined
			else state.quarantined
		local doc = document(player)
		for key, pose in pairs(saved.poses or {}) do
			if
				type(key) == "string"
				and doc
				and doc.components[tonumber(key)]
				and Layout.validFrame(pose)
			then
				state.poses[key] = pose
				if saved.grounded and saved.grounded[key] == true then
					state.grounded[key] = true
				end
			end
		end
		local movers = {}
		for _, record in ipairs(saved.supports or {}) do
			if #state.supports >= 96 then
				break
			end
			local mover = if type(record) == "table" then record.movingId or record.shaftId else nil
			if
				doc
				and mover
				and (record.model == "RetainedPivotV1" or not movers[mover])
				and Resolver.resolve(record, doc.components, state.poses, state.grounded)
			then
				if record.model ~= "RetainedPivotV1" then movers[mover] = true end
				table.insert(state.supports, record)
			else
				table.insert(state.quarantined, record)
			end
		end
	end
end
function Service:RemoveComponent(player: Player, id: number)
	local state = self:_layout(player)
	local cached = self.cache[player] and self.cache[player][id]
	if cached then
		cached.part:Destroy()
		self.cache[player][id] = nil
	end
	state.poses[tostring(id)] = nil
	state.grounded[tostring(id)] = nil
	for i = #state.supports, 1, -1 do
		local r = state.supports[i]
		if table.find(Resolver.dependencies(r), id) then
			table.remove(state.supports, i)
		end
	end
	state.revision += 1
end
function Service:ListJoints(_player: Player)
	return true, {}
end
function Service:Install(_player: Player, ...: any)
	return false, "Legacy fastening retired; alignment does not install hardware"
end
function Service:Remove(_player: Player, ...: any)
	return false, "Use RemoveSupport for validated supports"
end
function Service:SetActuator(_player: Player, ...: any)
	return false,
		"No manufactured actuator model is available; passive supports cannot generate torque"
end
function Service:Stop()
	for _, connection in pairs(self.characterConnections) do
		connection:Disconnect()
	end
	self.characterConnections = {}
	for _, session in pairs(self.sessions) do
		Session.destroy(session)
	end
	self.sessions = {}
	self.layouts = {}
	for _, cache in pairs(self.cache) do
		for _, item in pairs(cache) do
			item.part:Destroy()
		end
	end
	self.cache = {}
end
return Service
