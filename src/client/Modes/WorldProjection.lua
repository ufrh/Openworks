--!strict
-- Client-local physical bodies in Free Mode. FORM's authoritative CAD mesh
-- stays in Edit coordinates; this layer owns separate world/assembly copies.
-- Q2/Q4 will replace this local representation with server-owned bodies.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local WorldProjection = {}
WorldProjection.__index = WorldProjection

local function setBodyMode(entry:any, simulated:boolean)
	for _, part in ipairs(entry.model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = not simulated
			part.CanCollide = simulated
			part.CanTouch = simulated
			part.CanQuery = true
			if simulated then
				if entry.dragMode == "Assembly" then
					-- Workshop metal: high static friction, almost no bounce.
					part.CustomPhysicalProperties = PhysicalProperties.new(2.5, .8, .02, 100, 100)
				end
				if part:IsA("MeshPart") or part:IsA("PartOperation") then
					-- Hull would fill openings. Roblox collision is still approximate.
					pcall(function()
							part.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
						end)
				end
			else
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	-- Assembly has its own viewport picker. Native detectors
	-- remain exclusive to Free Mode to prevent competing input controllers.
	if entry.detector then
		entry.detector.Enabled = simulated and entry.dragMode ~= "Assembly" end
end

function WorldProjection.new(onSelect:((number)->())?)
	local root = Instance.new("Folder")
	root.Name = "OPENWORKS_LocalWorldComponents"
	return setmetatable({
			root = root, cache = {}, published = {}, mode = nil, onSelect = onSelect,
			dragConnections = {},
			precisionManipulating = false,
		}, WorldProjection)
end

function WorldProjection:_savePositions()
	if self.root.Parent == nil then
		return
	end
	for _, entry in pairs(self.cache) do
		if entry.model.Parent == self.root then
			-- Store displacement/rotation relative to the component's *unmoved*
			-- world pose, so a recompilation can replace the solid in place.
			if self.mode == "Free" and entry.basePivot then
				entry.freeDelta = entry.model:GetPivot()*entry.basePivot:Inverse()
			elseif self.mode == "Assembly" and entry.stageBasePivot then
				entry.stageDelta = entry.model:GetPivot()*entry.stageBasePivot:Inverse()
			end
		end
	end
end

function WorldProjection:show(preview:any, document:any, workspaceData:any,
		targetCorner:Vector3?, simulateAssembly:boolean?)
	if self.simulating then
		return
	end
	if self.precisionManipulating or self.placementPending then
		self.deferredShow = {preview, document, workspaceData, targetCorner, simulateAssembly}
		return
	end
	if not workspaceData then
		self:clear() return
	end
	self:_savePositions()
	local free = targetCorner == nil

	local simulated = free
	local live = {}
	self.root.Parent = workspace
	local serverRoot = workspace:FindFirstChild("OPENWORKS_Published")
	local serverBucket = serverRoot and
	serverRoot:FindFirstChild(tostring(Players.LocalPlayer.UserId))
	for _, component in pairs(document.components) do
		-- Prefer replicated server-owned physics to local cloned Free bodies.
		local replicated = if free and serverBucket then
		serverBucket:FindFirstChild("Component_" .. component.id) else nil
		if replicated and replicated:IsA("BasePart") then
			local prior = self.cache[component.id]
			if prior then prior.model:Destroy()
				self.cache[component.id] = nil end
			local tracked = self.published[component.id]
			if not tracked or tracked.part ~= replicated or not tracked.connection then
				if tracked and tracked.connection then
					tracked.connection:Disconnect()
				end
				local detector = replicated:FindFirstChildOfClass("DragDetector")
				local connection = if detector then detector.DragStart:Connect(function()
						if self.mode == "Free" and self.onSelect then
							self.onSelect(component.id, "Free")
						end
					end) else nil
				self.published[component.id] = {part = replicated, connection = connection}
			end
			live[component.id] = true
			continue
		end
		local state = preview.states[component.id]
		local source = state and state.part
		local sourceModel = preview:getModel(component.id)
		-- Never expose a primitive/placeholder while the initial sketch compiles.
		if not sourceModel or not source or not source.Parent then
			continue
		end

		local entry = self.cache[component.id]
		local delta = entry and (if free then entry.freeDelta else entry.stageDelta)
		or CFrame.identity
		if entry and entry.source ~= source then
			entry.model:Destroy()
			self.cache[component.id] = nil
			entry = nil
		end
		if not entry then
			local model = sourceModel:Clone()
			if not model then
				continue
			end
			model.Name = component.name
			model.Parent = self.root
			local solid = model:FindFirstChild("Solid", true)
			if not solid or not solid:IsA("BasePart") then
				model:Destroy()
				continue
			end
			local detector = Instance.new("DragDetector")
			detector.Name = "OpenWorks_PhysicalDrag"
			detector.DragStyle = Enum.DragDetectorDragStyle.TranslatePlaneOrLine
			detector.ResponseStyle = Enum.DragDetectorResponseStyle.Physical
			detector.RunLocally = true
			detector.ApplyAtCenterOfMass = false
			detector.Responsiveness = 12
			detector.MaxForce = math.clamp(solid:GetMass()*1200, 500, 100000)
			detector.MaxTorque = math.clamp(solid:GetMass()*900, 250, 60000)
			detector.Enabled = false
			detector.Parent = solid
			local componentId = component.id
			detector.DragStart:Connect(function()
					if (self.mode == "Free" or self.mode == "Assembly") and self.onSelect then
						self.onSelect(componentId, self.mode)
					end
				end)
			entry = {
				model = model, detector = detector, source = source,
				basePivot = model:GetPivot(), freeDelta = if free then delta else CFrame.identity,
				stageBasePivot = model:GetPivot(), stageDelta = if not free then delta else CFrame.identity,
			}
			self.cache[component.id] = entry
		end

		-- All translation from editing into the world uses the original component
		-- workspace origin; player-physics displacement is independent of geometry.
		local origin = component.worldOrigin or workspaceData.worldCorner
		local editOrigin = component.workspaceOrigin or workspaceData.editCorner
		local sourcePivot = sourceModel:GetPivot()
		local desiredBase:CFrame
		if free then
			desiredBase = CFrame.new(origin-editOrigin)*sourcePivot
		else
			-- Each workpiece starts in its own slot above the stage. Reusing
			-- Free-mode origins made separately created solids spawn intersecting.
			local index = 1
			for i, componentId in ipairs(document.order) do
				if componentId == component.id then
					index = i break end
			end
			-- Compute vertical height from the actual rotated collision bounds.
			-- Native cylinders have their long dimension in Part.Size.X.
			local basis = sourcePivot.Rotation
			local height = .5*(math.abs(basis.XVector.Y)*source.Size.X+
				math.abs(basis.YVector.Y)*source.Size.Y+
				math.abs(basis.ZVector.Y)*source.Size.Z)
			local slot = Vector3.new(
				((index-1)%3-1)*7,
				math.max(.3, height+.15),
				math.floor((index-1)/3)*7)
			desiredBase = CFrame.new(targetCorner+Vector3.new(workspaceData.size.X*.5, 0,
					workspaceData.size.Z*.5)+slot)*sourcePivot.Rotation
		end
		-- On an unchanged Free body, leave physics completely untouched. Other
		-- CSG jobs finishing must not interrupt an active physical drag.
		local matchingMode = self.mode == (if free then "Free" else "Assembly")
		local sameBase = if free then entry.basePivot == desiredBase
	else entry.stageBasePivot == desiredBase
		entry.dragMode = if free then "Free" else "Assembly"
		if not (matchingMode and simulated and sameBase) then
			-- Freeze before moving; otherwise teleporting an unanchored body
			-- between the world and Assembly would inject unwanted impulses.
			setBodyMode(entry, false)
			entry.model:PivotTo(delta*desiredBase)
			if free then
				entry.basePivot = desiredBase
			else
				entry.stageBasePivot = desiredBase
			end
			setBodyMode(entry, simulated)
		end
		if entry.detector then
			entry.detector.Enabled = free end
		if not free and self.assemblyPoses and self.assemblyPoses[tostring(component.id)] then
			local solid = entry.model:FindFirstChild("Solid", true)
			if solid and solid:IsA("BasePart") then
				local sourceFrame = solid:GetAttribute("OWSourceLocalFrame") or CFrame.identity
				solid.CFrame = self.assemblyPoses[tostring(component.id)]*sourceFrame
			end
		end
		live[component.id] = true
	end
	for id, entry in pairs(self.cache) do
		if not live[id] then
			entry.model:Destroy()
			self.cache[id] = nil
		end
	end
	self.mode = if free then "Free" else "Assembly"
	if not free then
		self:_ensureAssemblyInput()
	end
end

function WorldProjection:flush()
	local pending = self.deferredShow
	if not pending then
		return
	end
	self.deferredShow = nil
	self:show(table.unpack(pending, 1, 5))
end

function WorldProjection:_beginAssemblyDrag()
	if self.mode ~= "Assembly" or self.precisionManipulating then
		return
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) then return end
	local mouse = UserInputService:GetMouseLocation()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if self.gizmoPicker and self.gizmoPicker(mouse) then
		return
	end
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {self.root}
	local result = workspace:Raycast(ray.Origin, ray.Direction*5000, params)
	if not result then
		return
	end
	local selectedId = nil
	local selectedPart = nil
	for id, entry in pairs(self.cache) do
		if entry.model:IsAncestorOf(result.Instance) then
			selectedId = id
			selectedPart = entry.model:FindFirstChild("Solid", true)
			break
		end
	end
	if not selectedId or not selectedPart or not selectedPart:IsA("BasePart") then
		return
	end
	if self.onSelect then
		self.onSelect(selectedId, "Assembly")
	end
	if self.facePicker then
		self.facePicker(selectedId, result)
	end

end

function WorldProjection:_ensureAssemblyInput()
	if #self.dragConnections>0 then
		return
	end
	table.insert(self.dragConnections, UserInputService.InputBegan:Connect(function(input, processed)
				if processed or UserInputService:GetFocusedTextBox() then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					self:_beginAssemblyDrag()
				end
			end))

end

function WorldProjection:clear()
	self.deferredShow = nil
	self:_savePositions()
	self.mode = nil
	-- Suspend physics while in Edit, preserving its last world-space pose.
	for _, entry in pairs(self.cache) do
		setBodyMode(entry, false)
	end
	self.root.Parent = nil
end

function WorldProjection:Destroy()
	self:clear()
	for _, connection in ipairs(self.dragConnections) do
		connection:Disconnect()
	end
	table.clear(self.dragConnections)
	for _, item in pairs(self.published) do
		if item.connection then
			item.connection:Disconnect()
		end
	end
	table.clear(self.published)
	for id, entry in pairs(self.cache) do
		entry.model:Destroy()
		self.cache[id] = nil
	end
	self.root:Destroy()
end
return WorldProjection

