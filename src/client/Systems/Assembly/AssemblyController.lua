--!strict
local Players, RS = game:GetService('Players'), game:GetService('ReplicatedStorage')
local Shared = RS:WaitForChild('Openworks'):WaitForChild('Assembly')
local References = require(Shared.GeometryReferences)
local Alignment = require(Shared.Alignment)
local Manipulator = require(script.Parent.PrecisionManipulator)
local Controller = {}
Controller.__index = Controller
local function solid(state:any, id:number):BasePart?
	local entry = state.projection.cache[id]
	local p = entry and entry.model:FindFirstChild('Solid', true)
	return if p and p:IsA('BasePart') then p else nil
end
local function source(part:BasePart):CFrame
	return part:GetAttribute('OWSourceLocalFrame') or CFrame.identity
end
local function row(parent:Instance, text:string, action:any?):any
	local item = Instance.new(if action then 'TextButton' else 'TextLabel')
	item.Size = UDim2.new(1, -12, 0, 32)
	item.BackgroundColor3 = Color3.fromRGB(39, 63, 74)
	item.BorderSizePixel = 0
	item.Text = text
	item.TextColor3 = Color3.fromRGB(225, 240, 245)
	item.TextSize = 12
	item.Font = Enum.Font.Gotham
	item.TextWrapped = true
	item.Parent = parent
	if action then item.Activated:Connect(action) else item.BackgroundTransparency = 1 end
	return item
end
local function input(parent:Instance, text:string):TextBox
	local field = Instance.new('TextBox')
	field.Size = UDim2.new(1, -12, 0, 30)
	field.Text = text
	field.ClearTextOnFocus = false
	field.BackgroundColor3 = Color3.fromRGB(30, 46, 58)
	field.TextColor3 = Color3.new(1, 1, 1)
	field.TextSize = 12
	field.Font = Enum.Font.Code
	field.Parent = parent
	return field
end
local function numbers(text:string, count:number):{number}?
	local out = {}
	for word in string.gmatch(text, '[^,%s]+') do
		local n = tonumber(word)
		if not n or n ~= n or math.abs(n)>10000 then
			return nil
		end
		table.insert(out, n)
	end
	return if #out == count then out else nil
end
function Controller.new(bridge:any, remote:any, documents:any, _world:any)
	local gui = Instance.new('ScreenGui')
	gui.Name = 'OPENWORKS_AssemblyControls'
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 82
	gui.Parent = Players.LocalPlayer:WaitForChild('PlayerGui')
	local panel = Instance.new('ScrollingFrame')
	panel.Size = UDim2.new(0, 315, 1, -90)
	panel.Position = UDim2.new(1, -329, 0, 70)
	panel.BackgroundColor3 = Color3.fromRGB(22, 35, 44)
	panel.BorderSizePixel = 0
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.CanvasSize = UDim2.new()
	panel.ScrollBarThickness = 4
	panel.Parent = gui
	local list = Instance.new('UIListLayout')
	list.Padding = UDim.new(0, 5)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	local self = setmetatable({bridge = bridge, remote = remote, documents = documents, gui = gui,
			manipulator = Manipulator.new(), active = false, pending = false, selectedId = nil,
			refIndex = 1, a = nil, b = nil, layout = nil, highlights = {}}, Controller)
	row(panel, 'ASSEMBLY / CAD')
	self.status = row(panel, 'Select a component, then move or rotate.')
	self.status.Size = UDim2.new(1, -12, 0, 60)
	row(panel, 'Move', function() self.manipulator:setMode('Move') end)
	row(panel, 'Rotate', function() self.manipulator:setMode('Rotate') end)
	self.orientation = row(panel, 'Orientation: Local', function()
			if self.pending or self.manipulator.gizmo:isDragging() then
				return
			end
			local options = self.manipulator.options
			options.world = not options.world
			self.orientation.Text = 'Orientation: ' .. (if options.world then 'World' else 'Local')
			self.manipulator.gizmo:refresh()
		end)
	row(panel, 'Snap: translation in mm, rotation in degrees')
	self.snap = input(panel, '1, 5')
	self.snap.FocusLost:Connect(function()
			local n = numbers(self.snap.Text, 2)
			if not n or n[1] <= 0 or n[1]>280 or n[2] <= 0 or n[2]>180 then
				self:_report('Snap requires 0–280 mm and 0–180°, both greater than zero') return
			end
			self.manipulator.options.translationStep = n[1]/280
			self.manipulator.options.rotationStep = n[2]
		end)
	row(panel, 'Source origin: world X, Y, Z (studs)')
	self.position = input(panel, '0, 0, 0')
	row(panel, 'Source rotation: X, Y, Z (degrees)')
	self.rotation = input(panel, '0, 0, 0')
	row(panel, 'Apply numerical pose', function()
			local p, r = numbers(self.position.Text, 3), numbers(self.rotation.Text, 3)
			if not p or not r then
				self:_report('Enter three finite numbers in each field') return
			end
			self:place(CFrame.new(table.unpack(p))*CFrame.fromOrientation(math.rad(r[1]), math.rad(r[2]), math.rad(r[3])))
		end)
	self.reference = row(panel, 'Reference: select a component', function() self:cycleReference() end)
	row(panel, 'Set moving reference A', function() self:setReference('a') end)
	row(panel, 'Set fixed reference B', function() self:setReference('b') end)
	self.choices = row(panel, 'A: — / B: —')
	row(panel, 'Plane offset (mm)')
	self.offset = input(panel, '0')
	for _, kind in ipairs({'Concentric', 'Coincident', 'Parallel', 'Distance'}) do
		row(panel, kind, function() self:align(kind) end)
	end
	row(panel, 'Register shaft / bore support', function() self:registerSupport() end)
	row(panel, 'Remove last support', function()
			if not self.layout or #self.layout.supports == 0 then
				return
			end
			self:mutate('RemoveSupport', #self.layout.supports, self.layout.revision)
		end)
	row(panel, 'Toggle selected ground fixture', function()
			if not self.selectedId or not self.layout then
				return
			end
			self:mutate('SetGrounded', self.selectedId, self.layout.revision, not self.layout.grounded[tostring(self.selectedId)])
		end)
	row(panel, 'Save workshop', function()
			if self.pending then
				self:_report('Wait for placement validation') return
			end
			local ok, accepted, why = pcall(function() return self.documents:SaveNow(true) end)
			self:_report(if ok and accepted then 'Workshop saved' else tostring(if ok then why else accepted))
		end)
	row(panel, 'Ground fixture = external stationary support. Bore support permits rotation AND sliding. Stops require manufactured geometry.').Size = UDim2.new(1, -12, 0, 80)
	self.manipulator.onCommit = function(frame)
		local state = self.bridge.getAssemblyState()
		local part = self.selectedId and solid(state, self.selectedId)
		if part then
			self:place(frame*source(part):Inverse())
		end
	end
	return self
end
function Controller:_report(text:string)
	self.status.Text = text end
function Controller:reload()
	local ok, accepted, state = pcall(function() return self.remote:GetLayout() end)
	if not ok or not accepted then error(tostring(if ok then state else accepted)) end
	self.layout = state
	local stage = self.bridge.getAssemblyState()
	stage.projection.assemblyPoses = state.poses
	for id in pairs(stage.document.components) do
		local p = solid(stage, id)
		if p and state.poses[tostring(id)] then
			p.CFrame = state.poses[tostring(id)]*source(p) end
	end
	if self.selectedId then
		self:select(self.selectedId)
	end
end
function Controller:clearHighlights()
	for _, h in ipairs(self.highlights) do
		h:Destroy()
	end
	table.clear(self.highlights)
end
function Controller:highlight(id:number, color:Color3)
	local part = solid(self.bridge.getAssemblyState(), id)
	if not part then
		return
	end
	local h = Instance.new('Highlight')
	h.Adornee = part
	h.FillColor = color
	h.FillTransparency = .7
	h.OutlineColor = color
	h.Parent = part
	table.insert(self.highlights, h)
end
function Controller:select(id:number)
	if self.pending or not self.active then
		return
	end
	local state = self.bridge.getAssemblyState()
	local part = solid(state, id)
	if not part then
		return
	end
	if id ~= self.selectedId then
		self.refIndex = 1 end
	self.selectedId = id self.manipulator:select(part)
	self:clearHighlights() self:highlight(id, Color3.fromRGB(90, 220, 240))
	local pose = self.layout and self.layout.poses[tostring(id)] or part.CFrame*source(part):Inverse()
	local p = pose.Position local x, y, z = pose:ToOrientation()
	self.position.Text = string.format('%.6f, %.6f, %.6f', p.X, p.Y, p.Z)
	self.rotation.Text = string.format('%.6f, %.6f, %.6f', math.deg(x), math.deg(y), math.deg(z))
	self:cycleReference(0)
end
function Controller:cycleReference(delta:number?)
	local state = self.bridge.getAssemblyState()
	local component = self.selectedId and state.document.components[self.selectedId]
	local refs = component and References.list(component) or {}
	if #refs == 0 then
		self.reference.Text = 'No source references' return end
	self.refIndex = (self.refIndex-1+(delta or 1))%#refs+1
	self.reference.Text = 'Reference: ' .. refs[self.refIndex].id .. ' (click to cycle)'
end
function Controller:setReference(slot:string)
	local state = self.bridge.getAssemblyState()
	local component = self.selectedId and state.document.components[self.selectedId]
	local refs = component and References.list(component) or {}
	local ref = refs[self.refIndex]
	if not ref then
		return
	end
	self[slot] = {id = self.selectedId, ref = ref.id}
	self.choices.Text = 'A: ' .. (if self.a then self.a.id .. ' / ' .. self.a.ref else '—') ..
	'\nB: ' .. (if self.b then self.b.id .. ' / ' .. self.b.ref else '—')
end
function Controller:place(pose:CFrame)
	if not self.active or self.pending or not self.selectedId then
		return
	end
	local state = self.bridge.getAssemblyState()
	local id = self.selectedId
	local component = state.document.components[id]
	local part = solid(state, id)
	if not part or not component then
		return
	end
	self.pending = true
	state.projection.placementPending = true
	self.manipulator.gizmo:setHidden(true)
	part.CFrame = pose*source(part)
	self:_report('Checking manufactured solid clearance…')
	local ok, accepted, result, conflicts = pcall(function()
			return self.remote:SetPose(id, component.revision, self.layout.revision, pose)
		end)
	self.pending = false
	state.projection.placementPending = false
	if ok and accepted then
		self.layout.poses[tostring(id)] = pose
		self.layout.revision = result
		self:_report('Placement accepted. No joint created.')
	else
		part.CFrame = self.layout.poses[tostring(id)]*source(part)
		self:_report('Rejected: ' .. tostring(if ok then result else accepted))
	end
	self:select(id) self.manipulator.gizmo:setHidden(false)
	if ok and not accepted and type(conflicts) == 'table' then
		self:clearHighlights()
		for _, conflict in ipairs(conflicts) do
			self:highlight(conflict, Color3.fromRGB(255, 75, 75))
		end
	end
end
function Controller:align(kind:string)
	if self.pending or not self.a or not self.b or self.a.id == self.b.id then
		self:_report('Set A and B on different components') return
	end
	local state = self.bridge.getAssemblyState()
	local ca, cb = state.document.components[self.a.id], state.document.components[self.b.id]
	if not ca or not cb then
		return
	end
	local a, b = References.get(ca, self.a.ref), References.get(cb, self.b.ref)
	if not a or not b then
		self:_report('A source reference no longer exists') return
	end
	local offset = numbers(self.offset.Text, 1)
	if not offset then
		self:_report('Enter a finite offset in mm') return
	end
	local pa, pb = self.layout.poses[tostring(ca.id)], self.layout.poses[tostring(cb.id)]
	local pose, reason = Alignment.solve(kind, pa, References.world(a, pa), References.world(b, pb), offset[1]/280)
	if not pose then
		self:_report(tostring(reason)) return
	end
	self:select(ca.id) self:place(pose)
end
function Controller:mutate(method:string, ...:any)
	if self.pending or not self.active then
		return
	end
	self.pending = true
	self.manipulator.gizmo:setHidden(true)
	local args = table.pack(...)
	local ok, accepted, why = pcall(function() return self.remote[method](self.remote, table.unpack(args, 1, args.n)) end)
	self.pending = false
	if ok and accepted then self:reload() self:_report('Assembly updated')
	else self:_report(tostring(if ok then why else accepted)) end
	self.manipulator.gizmo:setHidden(false)
end
function Controller:registerSupport()
	if not self.a or not self.b then
		self:_report('Choose shaft and bore references A / B') return
	end
	local shaft = if self.a.ref == 'shaft' then self.a elseif self.b.ref == 'shaft' then self.b else nil
	if not shaft then
		self:_report('One reference must be an uncut shaft axis') return
	end
	local bore = if shaft == self.a then self.b else self.a
	self:mutate('RegisterSupport', bore.id, bore.ref, shaft.id, self.layout.revision)
end
function Controller:Enter()
	self.active = true
	self.gui.Enabled = true
	self.bridge.enterAssembly()
	self:reload()
	local state = self.bridge.getAssemblyState()
	state.projection.gizmoPicker = function(point) return self.pending or self.manipulator:capturesPoint(point) end
	state.projection.facePicker = function(id, hit)
		local component = state.document.components[id]
		local pose = self.layout.poses[tostring(id)]
		if not component or not pose then
			return
		end
		local refs = References.list(component)
		for index, ref in ipairs(refs) do
			local world = References.world(ref, pose)
			if world.kind == 'Plane' and world.direction:Dot(hit.Normal)>.999
				and math.abs((hit.Position-world.point):Dot(world.direction))<.01 then
				self.refIndex = index self:cycleReference(0) break
			end
		end
	end
	self.manipulator.onActiveChanged = function(active)
		state.projection.precisionManipulating = active end
	self:_report('Stationary assembly. Pick source references A / B for explicit alignment.' ..
		(if #self.layout.quarantined>0 then ' Legacy joints quarantined: ' .. #self.layout.quarantined else ''))
end
function Controller:Exit()
	if self.pending then
		error('Wait for assembly validation to finish')
	end
	self.manipulator.gizmo.finish()
	if self.pending then
		error('Wait for placement validation')
	end
	self.active = false
	self.gui.Enabled = false
	self.manipulator:select(nil) self:clearHighlights()
	local projection = self.bridge.getAssemblyState().projection
	projection.gizmoPicker = nil
	projection.facePicker = nil
	projection.precisionManipulating = false
	self.manipulator.onActiveChanged = nil
	self.bridge.leaveAssembly()
end
function Controller:Update(_dt:number)
	if not self.active or self.pending or self.manipulator.gizmo:isDragging() then
		return
	end
	self.bridge.getAssemblyState().projection:flush()
	if self.selectedId then
		local part = solid(self.bridge.getAssemblyState(), self.selectedId)
		if part ~= self.manipulator.part then
			self:select(self.selectedId)
		end
	end
end
function Controller:Destroy()
	self.active = false
	self.manipulator.onCommit = nil
	self.manipulator:Destroy() self:clearHighlights() self.gui:Destroy()
end
return Controller
