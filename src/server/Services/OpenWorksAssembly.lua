--!strict
local RS, Players, RunService = game:GetService('ReplicatedStorage'), game:GetService('Players'), game:GetService('RunService')
local FORGE = require(RS:WaitForChild('FORGE'))
local Shared = RS:WaitForChild('Openworks'):WaitForChild('Assembly')
local Layout = require(Shared.AssemblyLayout)
local Resolver = require(Shared.MechanicalResolver)
local Session = require(script.Parent.Parent.Simulation.AssemblySession)
local Service = FORGE.Service('OpenWorksAssembly')
local function document(player:Player):any
	local docs = FORGE:GetService('OpenWorksDocuments')
	return docs and docs.documents[player]
end
local function changed(player:Player)
	local docs = FORGE:GetService('OpenWorksDocuments')
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
	for _, name in ipairs({'GetLayout', 'SetPose', 'SetGrounded', 'RegisterSupport', 'RemoveSupport',
			'StartSimulation', 'StopSimulation', 'ListJoints', 'Install', 'Remove', 'SetActuator'}) do self:Expose(name) end
	self:Track(RunService.Heartbeat:Connect(function()
				for _, session in pairs(self.sessions) do
					Session.update(session)
				end
			end))
	self:Track(Players.PlayerRemoving:Connect(function(player)
				self:StopSimulation(player)
				task.delay(3, function()
						self.layouts[player] = nil
						self.graphs[player] = nil
						self.busy[player] = nil
					end)
			end))
end
function Service:IsBusy(player:Player):boolean
	return self.busy[player] == true or self.sessions[player] ~= nil
end
function Service:_layout(player:Player):any
	local state = self.layouts[player]
	if not state then
		state = {version = 2, revision = 0, poses = {}, grounded = {}, supports = {}, quarantined = {}}
		self.layouts[player] = state
	end
	local doc = document(player)
	if doc then
		for index, id in ipairs(doc.order) do
			local key = tostring(id)
			if not state.poses[key] then
				state.poses[key] = Layout.initial(index, doc.components[id]) end
		end
	end
	return state
end
function Service:GetLayout(player:Player)
	if not document(player) then
		return false, 'Manufacturing document is not loaded'
	end
	return true, self:_layout(player)
end
function Service:SetPose(player:Player, id:any, componentRevision:any, layoutRevision:any, pose:any)
	if self:IsBusy(player) then
		return false, 'Assembly is validating or simulating'
	end
	local doc = document(player)
	local component = doc and doc.components[id]
	if not component or component.revision ~= componentRevision then
		return false, 'Stale component revision'
	end
	local state = self:_layout(player)
	if layoutRevision ~= state.revision then
		return false, 'Stale assembly revision; reload layout'
	end
	if not Layout.validFrame(pose) then
		return false, 'Invalid or out-of-workspace pose'
	end
	self.busy[player] = true
	local proposed = table.clone(state.poses)
	proposed[tostring(id)] = pose
	local parts = nil
	local success, accepted, reason, conflicts = xpcall(function()
			local problem
			parts, problem = Session.compile(doc, proposed)
			if not parts then
				return false, problem
			end
			local clear, why, pair = Session.validate(parts, id)
			if not clear then
				return false, why, pair
			end
			if not player.Parent then
				return false, 'Player left'
			end
			state.poses = proposed
			state.revision += 1
			changed(player)
			return true, state.revision
		end, debug.traceback)
	if parts then
		Session.destroy({parts = parts})
	end
	self.busy[player] = nil
	if not success then
		warn(accepted) return false, 'Placement validation failed'
	end
	return accepted, reason, conflicts
end
function Service:SetGrounded(player:Player, id:any, revision:any, enabled:any)
	if self:IsBusy(player) then
		return false, 'Stop simulation or wait for validation'
	end
	local doc = document(player)
	local state = self:_layout(player)
	if not doc or not doc.components[id] or revision ~= state.revision or typeof(enabled) ~= 'boolean' then
		return false, 'Invalid grounding request or stale layout'
	end
	state.grounded[tostring(id)] = if enabled then true else nil
	state.revision += 1 changed(player)
	return true, state.revision
end
function Service:RegisterSupport(player:Player, bodyId:any, featureId:any, shaftId:any, revision:any)
	if self:IsBusy(player) then
		return false, 'Stop simulation or wait for validation'
	end
	local doc = document(player)
	local state = self:_layout(player)
	if not doc or revision ~= state.revision or type(featureId) ~= 'string' or #featureId>96 then
		return false, 'Invalid support request or stale layout'
	end
	if #state.supports >= 96 then
		return false, 'Support limit reached'
	end
	local record = {model = 'BoreSupportV1', bodyId = bodyId, featureId = featureId, shaftId = shaftId}
	local resolved, reason = Resolver.resolve(record, doc.components, state.poses)
	if not resolved then
		return false, reason
	end
	for _, prior in ipairs(state.supports) do
		if prior.shaftId == shaftId then
			return false, 'One support per shaft in this model; avoids redundant solver constraints'
		end
	end
	table.insert(state.supports, record)
	state.revision += 1 changed(player)
	return true, state.revision
end
function Service:RemoveSupport(player:Player, index:any, revision:any)
	if self:IsBusy(player) then
		return false, 'Stop simulation or wait for validation'
	end
	local state = self:_layout(player)
	if revision ~= state.revision or type(index) ~= 'number' or index%1 ~= 0 or not state.supports[index] then
		return false, 'Support not found or stale layout'
	end
	table.remove(state.supports, index)
	state.revision += 1 changed(player)
	return true, state.revision
end
function Service:StartSimulation(player:Player, revision:any)
	if self:IsBusy(player) then
		return false, 'Assembly is busy'
	end
	local doc = document(player)
	local state = self:_layout(player)
	if not doc or #doc.order == 0 or revision ~= state.revision then
		return false, 'Empty or stale assembly'
	end
	self.busy[player] = true
	local parts = nil
	local success, accepted, reason = xpcall(function()
			local problem
			parts, problem = Session.compile(doc, state.poses)
			if not parts then
				return false, problem
			end
			local clear, why = Session.validate(parts)
			if not clear then
				return false, why
			end
			if not player.Parent then
				return false, 'Player left'
			end
			local slot = 1
			while self.slots[slot] do
				slot += 1 end
			local session, issue = Session.start(player, doc, state, parts, slot)
			if session then
				self.slots[slot] = player
				session.slot = slot end
			parts = nil
			if not session then
				return false, issue
			end
			self.sessions[player] = session
			return true, session.center
		end, debug.traceback)
	if parts then
		Session.destroy({parts = parts})
	end
	self.busy[player] = nil
	if not success then
		warn(accepted) return false, 'Simulation setup failed'
	end
	return accepted, reason
end
function Service:StopSimulation(player:Player)
	if self.busy[player] then
		return false, 'Validation in progress'
	end
	local session = self.sessions[player]
	if session then
		self.slots[session.slot] = nil end
	Session.destroy(session)
	self.sessions[player] = nil
	return true, nil
end
function Service:Snapshot(player:Player):any return self:_layout(player) end
function Service:Restore(player:Player, joints:any, saved:any)
	self.graphs[player] = nil
	local state = {version = 2, revision = 0, poses = {}, grounded = {}, supports = {}, quarantined = {}}
	self.layouts[player] = state
	if type(joints) == 'table' then
		state.quarantined = joints end
	if type(saved) == 'table' and saved.version == 2 then
		state.quarantined = if type(saved.quarantined) == 'table' then saved.quarantined else state.quarantined
		local doc = document(player)
		for key, pose in pairs(saved.poses or {}) do
			if type(key) == 'string' and doc and doc.components[tonumber(key)] and Layout.validFrame(pose) then
				state.poses[key] = pose
				if saved.grounded and saved.grounded[key] == true then
					state.grounded[key] = true end
			end
		end
		for _, record in ipairs(saved.supports or {}) do
			if #state.supports >= 96 then
				break
			end
			if doc and Resolver.resolve(record, doc.components, state.poses) then table.insert(state.supports, record)
			else
				table.insert(state.quarantined, record)
			end
		end
	end
end
function Service:RemoveComponent(player:Player, id:number)
	local state = self:_layout(player)
	state.poses[tostring(id)] = nil
	state.grounded[tostring(id)] = nil
	for i = #state.supports, 1, -1 do
		local r = state.supports[i]
		if r.bodyId == id or r.shaftId == id then
			table.remove(state.supports, i)
		end
	end
	state.revision += 1
end
function Service:ListJoints(_player:Player) return true, {} end
function Service:Install(_player:Player, ...:any) return false, 'Legacy fastening retired; alignment does not install hardware' end
function Service:Remove(_player:Player, ...:any) return false, 'Use RemoveSupport for validated supports' end
function Service:SetActuator(_player:Player, ...:any)
	return false, 'No manufactured actuator model is available; passive supports cannot generate torque'
end
function Service:Stop()
	for _, session in pairs(self.sessions) do
		Session.destroy(session)
	end
	self.sessions = {}
	self.layouts = {}
end
return Service
