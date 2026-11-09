--!strict
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Openworks")
local Fabricator = require(Shared.FORM.Fabricator)
local Compiler = require(Shared.FORM.Compiler)
local Document = require(Shared.FORM.Document)
local Interference = require(Shared.Assembly.Interference)
local Resolver = require(Shared.Assembly.MechanicalResolver)
local Constraints = require(Shared.Assembly.ConstraintCompiler)
local BenchDrive = require(Shared.Assembly.BenchDrive)
local Session = {}
function Session.compile(document: any, poses: any, cache: any?): (any?, string?)
	local parts = {}
	local function cleanup()
		for _, part in pairs(parts) do
			part:Destroy()
		end
	end
	for _, id in ipairs(document.order) do
		local component = Document.snapshot(document.components[id])
		local stored = cache and cache[id]
		local ok, part = pcall(function()
			if stored and stored.revision == component.revision then
				return stored.part:Clone()
			end
			if Fabricator.requiresCompile(component) then
				return Fabricator.compile(component)
			end
			return Compiler.nativePart(component.nodes[1])
		end)
		if not ok or not part then
			cleanup()
			return nil, "Manufacturing failed for component " .. id
		end
		if not poses[tostring(id)] then
			part:Destroy()
			cleanup()
			return nil, "Missing component pose"
		end
		parts[id] = part
		if cache and (not stored or stored.revision ~= component.revision) then
			if stored then
				stored.part:Destroy()
			end
			cache[id] = { revision = component.revision, part = part:Clone() }
		end
		local source = part.CFrame
		part:SetAttribute("OWSourceLocalFrame", source)
		part:SetAttribute("OWComponentId", id)
		part.Name = component.name
		part.CFrame = poses[tostring(id)] * source
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = true
	end
	return parts, nil
end
function Session.validate(parts: any, changedId: number?): (boolean, string?, any?)
	local ids = {}
	for id in pairs(parts) do
		table.insert(ids, id)
	end
	table.sort(ids)
	local floor = Instance.new("Part")
	floor.Size = Vector3.new(1000, 0.1, 1000)
	floor.CFrame = CFrame.new(120, 199.92, 0)
	floor.Anchored = true
	for _, id in ipairs(ids) do
		if changedId and changedId ~= id then
			continue
		end
		local clear, reason = Interference.pair(parts[id], floor)
		if not clear then
			floor:Destroy()
			return false, id .. " / stage: " .. tostring(reason), { id }
		end
	end
	floor:Destroy()
	for i = 1, #ids do
		for j = i + 1, #ids do
			if changedId and ids[i] ~= changedId and ids[j] ~= changedId then
				continue
			end
			local ok, reason = Interference.pair(parts[ids[i]], parts[ids[j]])
			if not ok then
				return false,
					ids[i] .. " / " .. ids[j] .. ": " .. tostring(reason),
					{ ids[i], ids[j] }
			end
		end
	end
	return true, nil, nil
end
function Session.destroy(session: any)
	if not session then
		return
	end
	if
		session.player
		and session.player.Parent
		and session.focus
		and session.player.ReplicationFocus == session.focus
	then
		session.player.ReplicationFocus = session.previousFocus
	end
	if session.root then
		session.root:Destroy()
	elseif session.parts then
		for _, p in pairs(session.parts) do
			p:Destroy()
		end
	end
end
function Session.start(
	player: Player,
	document: any,
	layout: any,
	parts: any,
	slot: number
): (any?, string?)
	local shift = Vector3.new(slot * 1200, 0, 0)
	local poses = {}
	for key, pose in pairs(layout.poses) do
		poses[key] = pose + shift
	end
	local session = {
		player = player,
		previousFocus = player.ReplicationFocus,
		parts = parts,
		relations = {},
		source = document.components,
		grounded = table.clone(layout.grounded),
		paused = false,
		released = 0,
		drives = {},
		center = Vector3.new(120, 200, 0) + shift,
	}
	local root = Instance.new("Folder")
	root.Name = "OPENWORKS_Simulation_" .. player.UserId
	session.root = root
	for _, part in pairs(parts) do
		part.CFrame += shift
		part.Parent = root
	end
	local success, problem = xpcall(function()
		local floor = Instance.new("Part")
		floor.Name = "SimulationFloor"
		floor.Size = Vector3.new(1000, 0.1, 1000)
		floor.Position = Vector3.new(120, 199.92, 0) + shift
		floor.Anchored = true
		floor.CanCollide = true
		floor.CanQuery = false
		floor.Color = Color3.fromRGB(51, 88, 130)
		floor.Material = Enum.Material.SmoothPlastic
		floor.Parent = root
		for index, record in ipairs(layout.supports) do
			local relation, reason =
				Resolver.resolve(record, document.components, poses, layout.grounded)
			if not relation then
				error(reason)
			end
			local objects, problem = Constraints.compileResolved(relation, parts, root)
			if not objects then
				error(problem)
			end
			table.insert(session.relations, {
				index = index,
				record = record,
				objects = objects,
				relation = relation,
				localAxis = parts[relation.bodyId].CFrame:VectorToObjectSpace(relation.direction),
			})
		end
		for id, part in pairs(parts) do
			local component = document.components[id]
			if component.nodes[1].kind == "Cylinder" then
				local marker = Instance.new("SurfaceGui")
				marker.Name = "OW_RotationWitness"
				marker.Face = Enum.NormalId.Right
				marker.CanvasSize = Vector2.new(100, 100)
				marker.LightInfluence = 0
				marker.Parent = part
				local bar = Instance.new("Frame")
				bar.Position = UDim2.fromScale(0.5, 0.47)
				bar.Size = UDim2.fromScale(0.43, 0.06)
				bar.BorderSizePixel = 0
				bar.BackgroundColor3 = Color3.fromRGB(255, 90, 60)
				bar.Parent = marker
			end
		end
		root.Parent = workspace
		session.focus = parts[document.order[1]]
		player.ReplicationFocus = session.focus
		for id, part in pairs(parts) do
			part.Anchored = layout.grounded[tostring(id)] == true
			if not part.Anchored then
				part:SetNetworkOwner(nil)
			end
		end
	end, debug.traceback)
	if not success then
		Session.destroy(session)
		return nil, tostring(problem)
	end
	session.acceptedRelations = table.clone(session.relations)
	session.initial = {}
	for id, part in pairs(parts) do
		session.initial[id] = part.CFrame
	end
	return session, nil
end
function Session.update(session: any, dt: number?)
	session.auditClock = (session.auditClock or 0) + (dt or 0.05)
	if session.auditClock < 0.05 then
		return
	end
	session.auditClock = 0
	if session.paused then
		return
	end
	local poses = {}
	for id, part in pairs(session.parts) do
		poses[tostring(id)] = part.CFrame * part:GetAttribute("OWSourceLocalFrame"):Inverse()
	end
	for i = #session.relations, 1, -1 do
		local item = session.relations[i]
		-- Mechanisms with manufactured retention do not automatically
		-- disengage from sub-millimeter solver corrections. They remain
		-- connected unless the user removes the retained relationship.
		-- Unretained shaft/guide supports still release on disengagement.
		if item.relation.model == "RetainedPivotV1"
			or item.relation.model == "DualPinRigidV1"
			or item.relation.model == "RetainedBoreV1"
			or item.relation.model == "LimitedGuideV1" then
			continue
		end
		if not Resolver.resolve(item.record, session.source, poses, session.grounded) then
			Constraints.destroy(item.objects)
			session.drives[item.index] = nil
			session.released += 1
			table.remove(session.relations, i)
		end
	end
end
function Session.pause(session: any, paused: boolean)
	if session.paused == paused then
		return
	end
	if paused then
		session.velocities = {}
		for id, part in pairs(session.parts) do
			session.velocities[id] = { part.AssemblyLinearVelocity, part.AssemblyAngularVelocity }
			part.Anchored = true
		end
	else
		for id, part in pairs(session.parts) do
			part.Anchored = session.grounded[tostring(id)] == true
			if not part.Anchored then
				part:SetNetworkOwner(nil)
				local velocity = session.velocities[id]
				part.AssemblyLinearVelocity = velocity[1]
				part.AssemblyAngularVelocity = velocity[2]
			end
		end
	end
	session.paused = paused
end

function Session.reset(session: any): (boolean, string?)
	local wasPaused = session.paused
	Session.pause(session, true)
	for _, item in ipairs(session.relations) do
		Constraints.destroy(item.objects)
	end
	session.relations = {}
	for id, part in pairs(session.parts) do
		part.CFrame = session.initial[id]
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
		session.velocities[id] = { Vector3.zero, Vector3.zero }
	end
	for _, item in ipairs(session.acceptedRelations) do
		local objects, problem =
			Constraints.compileResolved(item.relation, session.parts, session.root)
		if not objects then
			return false, problem
		end
		table.insert(session.relations, {
			index = item.index,
			record = item.record,
			relation = item.relation,
			objects = objects,
			localAxis = item.localAxis,
		})
	end
	session.released = 0
	for index, drive in pairs(session.drives or {}) do
		Session.drive(session, index, drive.speed, drive.effort, drive.mode, drive.target)
	end
	if not wasPaused then
		Session.pause(session, false)
	end
	return true, nil
end
-- The simulation drive is external equipment, never persisted to FORM.
function Session.drive(session: any, index: number, speed: number, effort: number,
	mode: string?, target: number?): (boolean, string?)
	local jointItem = nil
	for _, item in ipairs(session.relations) do
		if item.index == index then
			jointItem = item
			break
		end
	end
	if not jointItem then
		return false, "Joint is no longer active; reset the simulation"
	end
	local valid, reason = BenchDrive.validate(jointItem.relation, speed, effort, mode, target)
	if not valid then
		return false, reason
	end
	BenchDrive.apply(jointItem.objects, jointItem.relation, speed, effort, mode, target)
	if effort == 0 or (mode ~= "Servo" and speed == 0) then
		session.drives[index] = nil
	else
		session.drives[index] = { speed = speed, effort = effort, mode = mode or "Motor", target = target }
	end
	return true, nil
end

return Session
