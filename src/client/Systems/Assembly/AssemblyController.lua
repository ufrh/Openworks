--!strict
local Players, RS = game:GetService("Players"), game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Openworks"):WaitForChild("Assembly")
local References = require(Shared.GeometryReferences)
local Alignment = require(Shared.Alignment)
local Catalog = require(Shared.RelationshipCatalog)
local Layout = require(Shared.AssemblyLayout)
local Panel = require(script.Parent.Parent.Parent.Experience.UI.WorkbenchPanel)
local Manipulator = require(script.Parent.PrecisionManipulator)
local Presets = require(script.Parent.Presets)
local Controller = {}
Controller.__index = Controller
local function solid(state: any, id: number): BasePart?
	local entry = state.projection.cache[id]
	local p = entry and entry.model:FindFirstChild("Solid", true)
	return if p and p:IsA("BasePart") then p else nil
end
local function source(part: BasePart): CFrame
	return part:GetAttribute("OWSourceLocalFrame") or CFrame.identity
end
local function numbers(text: string, count: number): { number }?
	local out = {}
	for word in string.gmatch(text, "[^,%s]+") do
		local n = tonumber(word)
		if not n or n ~= n or math.abs(n) > 1000000 then
			return nil
		end
		table.insert(out, n)
	end
	return if #out == count then out else nil
end
function Controller.new(bridge: any, remote: any, documents: any, _world: any)
	local panel = Panel.new("Assembly", { "Parts", "Move", "Align", "Mechanics" })
	local self = setmetatable({
		bridge = bridge,
		remote = remote,
		documents = documents,
		gui = panel.gui,
		panel = panel,
		status = panel.status,
		manipulator = Manipulator.new(),
		active = false,
		pending = false,
		selectedId = nil,
		refIndex = 1,
		a = nil,
		b = nil,
		layout = nil,
		highlights = {},
		fixtures = {},
		modelIndex = 1,
		history = {},
		redo = {},
		connections = {},
	}, Controller)
	local parts, move, align, mechanics =
		panel.pages.Parts, panel.pages.Move, panel.pages.Align, panel.pages.Mechanics
	Panel.label(
		parts,
		"Select a part here or click its solid. [Fixed] means attached to the external bench.",
		48
	)
	for _, preset in ipairs({ "Bearing", "Linear guide" }) do
		Panel.button(parts, "Create preset: " .. preset, function()
			if self.pending or self.manipulator.gizmo:isDragging() then
				return
			end
			self.pending = true
			self.manipulator.gizmo:setHidden(true)
			self:_report("Building " .. preset .. " preset…")
			local callOk, ok, result = pcall(Presets.build, documents, remote, preset)
			self.pending = false
			local refreshed, issue = pcall(function()
				self:reload()
			end)
			self.manipulator.gizmo:setHidden(false)
			if callOk and ok and refreshed then
				self.selectedId = result
				self:select(result)
				bridge.frameAssembly(result)
				self:_report(
					"Preset assembled. Open Mechanics → Start simulation, then select the mover in Test."
				)
			else
				self:_report(
					tostring(if not callOk then ok elseif not refreshed then issue else result)
				)
			end
		end)
	end
	self.partsRoot = Panel.list(parts)
	Panel.button(parts, "Frame all (Home)", function()
		bridge.frameAssembly(nil)
	end)
	Panel.button(parts, "Reset view", function()
		bridge.resetAssemblyCamera()
	end)
	Panel.button(parts, "Save workshop", function()
		if self.pending then
			return self:_report("Wait for validation to finish")
		end
		local ok, accepted, why = pcall(function()
			return documents:SaveNow(true)
		end)
		self:_report(
			if ok and accepted then "Workshop saved" else tostring(if ok then why else accepted)
		)
	end)
	Panel.label(
		move,
		"W: move • E: rotate • F: frame • Esc: cancel drag\nRMB: orbit • MMB: pan • Wheel: zoom",
		48
	)
	self.selectedLabel = Panel.label(move, "No part selected")
	Panel.button(move, "Move (W)", function()
		self.manipulator:setMode("Move")
	end)
	Panel.button(move, "Rotate (E)", function()
		self.manipulator:setMode("Rotate")
	end)
	self.orientation = Panel.button(move, "Axes: Local", function()
		if self.pending or self.manipulator.gizmo:isDragging() then
			return
		end
		self.manipulator.options.world = not self.manipulator.options.world
		self.orientation.Text = "Axes: "
			.. (if self.manipulator.options.world then "World" else "Local")
		self.manipulator.gizmo:refresh()
	end)
	self.snap = Panel.input(move, "Snap: millimeters, degrees", "1, 5")
	self.snap.FocusLost:Connect(function()
		local n = numbers(self.snap.Text, 2)
		if not n or n[1] <= 0 or n[1] > 280 or n[2] <= 0 or n[2] > 180 then
			self.snap.Text = string.format(
				"%g, %g",
				self.manipulator.options.translationStep * 280,
				self.manipulator.options.rotationStep
			)
			return self:_report(
				"Use a translation snap of 0–280 mm and rotation snap of 0–180°, both above zero"
			)
		end
		self.manipulator.options.translationStep, self.manipulator.options.rotationStep =
			n[1] / 280, n[2]
	end)
	self.position = Panel.input(move, "Position X, Y, Z (mm from stage center)", "0, 0, 0")
	self.rotation = Panel.input(move, "Rotation X, Y, Z (degrees)", "0, 0, 0")
	Panel.button(move, "Apply position + rotation", function()
		local pos, rot = numbers(self.position.Text, 3), numbers(self.rotation.Text, 3)
		if not pos or not rot then
			return self:_report("Enter three numbers in each field")
		end
		self:place(
			CFrame.new(Layout.Center + Vector3.new(table.unpack(pos)) / 280)
				* CFrame.fromOrientation(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		)
	end)
	Panel.button(move, "Undo placement (Ctrl+Z)", function()
		self:undo(false)
	end)
	Panel.button(move, "Redo placement (Ctrl+Y)", function()
		self:undo(true)
	end)
	Panel.button(move, "Frame selected (F)", function()
		bridge.frameAssembly(self.selectedId)
	end)
	Panel.label(
		align,
		"1. Select the moving part and its reference.\n2. Pick the target part. 3. Choose an alignment.",
		52
	)
	Panel.button(align, "Use selection as moving part A", function()
		self:setReference("a")
	end)
	Panel.button(align, "Pick target part B in viewport / Parts", function()
		self.pickTarget = true
		self:_report(
			"Click the target part. Its first bore or source face becomes B; change the reference below if needed."
		)
	end)
	self.choices = Panel.label(align, "A: — / B: —", 52)
	Panel.label(align, "References on selected part")
	self.refsRoot = Panel.list(align)
	self.offset = Panel.input(align, "Face spacing / offset (mm)", "0")
	for _, item in ipairs({
		{ "Concentric", "Align axes (concentric)" },
		{ "Coincident", "Mate faces" },
		{ "Parallel", "Make parallel" },
		{ "Distance", "Set face spacing" },
	}) do
		Panel.button(align, item[2], function()
			self:align(item[1])
		end)
	end
	Panel.button(align, "Clear A / B", function()
		self.a, self.b, self.pickTarget = nil, nil, false
		self:choiceText()
	end)
	Panel.label(align, "Alignment positions geometry. It creates no joint.", 40)
	self.groundButton = Panel.button(mechanics, "Select a part to fix / release", function()
		if not self.selectedId or not self.layout then
			return
		end
		self:mutate(
			"SetGrounded",
			self.selectedId,
			self.layout.revision,
			not self.layout.grounded[tostring(self.selectedId)]
		)
	end)
	self.mechanicalChoices = Panel.label(mechanics, "Moving: — / Housing: —", 52)
	Panel.button(mechanics, "Use selected part as mover", function()
		self:setReference("a")
	end)
	Panel.button(mechanics, "Pick bearing housing / bore", function()
		self.pickTarget = true
		self:_report("Click the housing. Its first bore becomes the bearing reference.")
	end)
	self.modelButton = Panel.label(mechanics, "", 32)
	for index, spec in ipairs(Catalog) do
		Panel.button(mechanics, spec.name, function()
			self.modelIndex = index
			self.fixtures = {}
			self:mechanicsText()
		end)
	end
	self.modelHelp = Panel.label(mechanics, "", 84)
	Panel.button(mechanics, "Add selected part as fixture", function()
		local id = self.selectedId
		if not id then
			return self:_report("Select a fixture first")
		end
		if table.find(self.fixtures, id) then
			return self:_report("Fixture already added")
		end
		if #self.fixtures >= Catalog[self.modelIndex].fixtures then
			return self:_report("Required fixtures already selected")
		end
		table.insert(self.fixtures, id)
		self:mechanicsText()
	end)
	self.fixturesRoot = Panel.list(mechanics)
	Panel.button(mechanics, "Add validated relationship", function()
		self:registerSupport()
	end)
	Panel.button(mechanics, "Check assembly", function()
		self:validate()
	end)
	Panel.button(mechanics, "Start simulation", function()
		if self.onSimulate then
			self.onSimulate()
		end
	end)
	Panel.label(mechanics, "Installed relationships (click to remove)", 40)
	self.relationshipsRoot = Panel.list(mechanics)
	self:mechanicsText()
	self.manipulator.onCommit = function(frame)
		local state = bridge.getAssemblyState()
		local part = self.selectedId and solid(state, self.selectedId)
		if part then
			self:place(frame * source(part):Inverse())
		end
	end
	local input = game:GetService("UserInputService")
	table.insert(
		self.connections,
		input.InputBegan:Connect(function(key, processed)
			if processed or not self.active or input:GetFocusedTextBox() or self.pending then
				return
			end
			local ctrl = input:IsKeyDown(Enum.KeyCode.LeftControl)
				or input:IsKeyDown(Enum.KeyCode.RightControl)
			if key.KeyCode == Enum.KeyCode.Escape then
				self.manipulator:cancel()
				self.pickTarget = false
			elseif ctrl and key.KeyCode == Enum.KeyCode.Z then
				self:undo(false)
			elseif ctrl and key.KeyCode == Enum.KeyCode.Y then
				self:undo(true)
			elseif key.KeyCode == Enum.KeyCode.W then
				self.manipulator:setMode("Move")
			elseif key.KeyCode == Enum.KeyCode.E then
				self.manipulator:setMode("Rotate")
			end
		end)
	)
	return self
end

function Controller:name(id: number?): string
	local c = id and self.bridge.getAssemblyState().document.components[id]
	return if c then c.name .. " #" .. id else "—"
end

function Controller:choiceText()
	self.choices.Text = "A: "
		.. self:name(self.a and self.a.id)
		.. "\nB: "
		.. self:name(self.b and self.b.id)
	self.mechanicalChoices.Text = "Moving: "
		.. self:name(self.a and self.a.id)
		.. "\nHousing: "
		.. self:name(self.b and self.b.id)
end

function Controller:mechanicsText()
	local item = Catalog[self.modelIndex]
	self.modelButton.Text = "Selected: " .. item.name
	self.modelHelp.Text = item.motion .. "\n" .. item.help
	Panel.clear(self.fixturesRoot)
	for i, id in ipairs(self.fixtures) do
		Panel.button(self.fixturesRoot, i .. ". " .. self:name(id) .. " ×", function()
			table.remove(self.fixtures, i)
			self:mechanicsText()
		end)
	end
	Panel.label(
		self.fixturesRoot,
		string.format("%d / %d fixtures selected", #self.fixtures, item.fixtures)
	)
end

function Controller:refreshLists()
	local state = self.bridge.getAssemblyState()
	Panel.clear(self.partsRoot)
	for _, id in ipairs(state.document.order) do
		local label = self:name(id)
		if self.layout.grounded[tostring(id)] then
			label ..= " [Fixed]"
		end
		Panel.button(self.partsRoot, label, function()
			self:select(id)
		end)
	end
	Panel.clear(self.relationshipsRoot)
	for i, record in ipairs(self.layout.supports) do
		local name = record.model
		for _, spec in ipairs(Catalog) do
			if spec.model == name then
				name = spec.name
				break
			end
		end
		Panel.button(
			self.relationshipsRoot,
			name .. ": " .. self:name(record.movingId or record.shaftId) .. " ×",
			function()
				self:mutate("RemoveSupport", i, self.layout.revision)
			end
		)
	end
end

function Controller:validate()
	if self.pending then
		return
	end
	self.pending = true
	self.manipulator.gizmo:setHidden(true)
	self:_report("Checking solids and mechanical relationships…")
	local ok, accepted, report = pcall(function()
		return self.remote:ValidateAssembly(self.layout.revision)
	end)
	self.pending = false
	self.manipulator.gizmo:setHidden(false)
	if not ok or not accepted then
		return self:_report(tostring(if ok then report else accepted))
	end
	local lines = { report.message }
	for _, item in ipairs(report.relationships) do
		if not item.valid then
			table.insert(lines, "#" .. item.index .. ": " .. item.message)
		end
	end
	self:_report(
		(if report.valid then "Ready. " else "Needs attention. ") .. table.concat(lines, "\n")
	)
	self:clearHighlights()
	for _, id in ipairs(report.conflicts or {}) do
		self:highlight(id, Color3.fromRGB(255, 75, 75))
	end
end

function Controller:undo(redo: boolean)
	if self.pending or self.manipulator.gizmo:isDragging() then
		return
	end
	local stack = if redo then self.redo else self.history
	local item = stack[#stack]
	if not item then
		return self:_report(if redo then "Nothing to redo" else "Nothing to undo")
	end
	self:select(item.id)
	if self.selectedId ~= item.id then
		return
	end
	local accepted = self:place(if redo then item.after else item.before, true)
	if accepted then
		table.remove(stack)
		table.insert(if redo then self.history else self.redo, item)
	end
end

function Controller:_report(text: string)
	self.status.Text = text
end
function Controller:reload()
	local ok, accepted, state = pcall(function()
		return self.remote:GetLayout()
	end)
	if not ok or not accepted then
		error(tostring(if ok then state else accepted))
	end
	self.layout = state
	self:refreshLists()
	local stage = self.bridge.getAssemblyState()
	stage.projection.assemblyPoses = state.poses
	for id in pairs(stage.document.components) do
		local p = solid(stage, id)
		if p and state.poses[tostring(id)] then
			p.CFrame = state.poses[tostring(id)] * source(p)
		end
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
function Controller:highlight(id: number, color: Color3)
	local part = solid(self.bridge.getAssemblyState(), id)
	if not part then
		return
	end
	local h = Instance.new("Highlight")
	h.Adornee = part
	h.FillColor = color
	h.FillTransparency = 0.7
	h.OutlineColor = color
	h.Parent = part
	table.insert(self.highlights, h)
end
function Controller:select(id: number)
	if self.pending or not self.active or self.manipulator.gizmo:isDragging() then
		return
	end
	local state = self.bridge.getAssemblyState()
	local part = solid(state, id)
	if not part then
		self.manipulator:select(nil)
		return self:_report("Component geometry is still compiling or no longer exists")
	end
	if id ~= self.selectedId then
		self.refIndex = 1
	end
	self.selectedId = id
	self.manipulator:select(part)
	self:clearHighlights()
	self:highlight(id, Color3.fromRGB(90, 220, 240))
	local pose = self.layout and self.layout.poses[tostring(id)]
		or part.CFrame * source(part):Inverse()
	local p = (pose.Position - Layout.Center) * 280
	local x, y, z = pose:ToOrientation()
	self.position.Text = string.format("%.6f, %.6f, %.6f", p.X, p.Y, p.Z)
	self.rotation.Text = string.format("%.6f, %.6f, %.6f", math.deg(x), math.deg(y), math.deg(z))
	self:cycleReference(0)
	self.selectedLabel.Text = self:name(id)
	self.groundButton.Text = if self.layout.grounded[tostring(id)]
		then "Release " .. self:name(id) .. " from bench"
		else "Fix " .. self:name(id) .. " to bench"
	self.bridge.setAssemblySelection(id)
	if self.pickTarget then
		self.pickTarget = false
		local refs = References.list(state.document.components[id])
		for index, ref in ipairs(refs) do
			if ref.feature then
				self.refIndex = index
				break
			end
		end
		self:setReference("b")
		self.justPickedTarget = id
		self:cycleReference(0)
		self.panel:show("Align")
	end
end
function Controller:cycleReference(delta: number?)
	local state = self.bridge.getAssemblyState()
	local component = self.selectedId and state.document.components[self.selectedId]
	local refs = component and References.list(component) or {}
	Panel.clear(self.refsRoot)
	if #refs == 0 then
		Panel.label(self.refsRoot, "No source references")
		return
	end
	self.refIndex = (self.refIndex - 1 + (delta or 1)) % #refs + 1
	for index, ref in ipairs(refs) do
		local caption = if ref.id == "shaft"
			then "Shaft axis"
			elseif ref.feature then "Bore Ø" .. string.format("%.1f mm", ref.diameter * 280)
			else "Source plane " .. ref.id
		Panel.button(
			self.refsRoot,
			(if index == self.refIndex then "● " else "○ ") .. caption,
			function()
				self.refIndex = index
				if self.a and self.a.id == self.selectedId then
					self.a.ref = ref.id
				end
				if self.b and self.b.id == self.selectedId then
					self.b.ref = ref.id
				end
				self:cycleReference(0)
			end
		)
	end
end
function Controller:setReference(slot: string)
	local state = self.bridge.getAssemblyState()
	local component = self.selectedId and state.document.components[self.selectedId]
	local refs = component and References.list(component) or {}
	local ref = refs[self.refIndex]
	if not ref then
		return
	end
	self[slot] = { id = self.selectedId, ref = ref.id }
	self:choiceText()
end
function Controller:place(pose: CFrame, historyAction: boolean?)
	if not self.active or self.pending or not self.selectedId then
		return
	end
	local state = self.bridge.getAssemblyState()
	local id = self.selectedId
	local priorPose = self.layout.poses[tostring(id)]
	local component = state.document.components[id]
	local part = solid(state, id)
	if not part or not component then
		return
	end
	self.pending = true
	state.projection.placementPending = true
	self.manipulator.gizmo:setHidden(true)
	part.CFrame = pose * source(part)
	self:_report("Checking manufactured solid clearance…")
	local ok, accepted, result, conflicts = pcall(function()
		return self.remote:SetPose(id, component.revision, self.layout.revision, pose)
	end)
	self.pending = false
	state.projection.placementPending = false
	if ok and accepted then
		self.layout.poses[tostring(id)] = pose
		self.layout.revision = result
		if not historyAction then
			table.insert(self.history, { id = id, before = priorPose, after = pose })
			if #self.history > 64 then
				table.remove(self.history, 1)
			end
			table.clear(self.redo)
		end
		self:_report("Placement accepted. No joint created.")
	else
		part.CFrame = self.layout.poses[tostring(id)] * source(part)
		self:_report("Rejected: " .. tostring(if ok then result else accepted))
	end
	self:select(id)
	self.manipulator.gizmo:setHidden(false)
	if ok and not accepted and type(conflicts) == "table" then
		self:clearHighlights()
		for _, conflict in ipairs(conflicts) do
			self:highlight(conflict, Color3.fromRGB(255, 75, 75))
		end
	end
	return ok and accepted
end
function Controller:align(kind: string)
	if self.pending or not self.a or not self.b or self.a.id == self.b.id then
		self:_report("Set A and B on different components")
		return
	end
	local state = self.bridge.getAssemblyState()
	local ca, cb = state.document.components[self.a.id], state.document.components[self.b.id]
	if not ca or not cb then
		return
	end
	local a, b = References.get(ca, self.a.ref), References.get(cb, self.b.ref)
	if not a or not b then
		self:_report("A source reference no longer exists")
		return
	end
	local offset = numbers(self.offset.Text, 1)
	if not offset then
		self:_report("Enter a finite offset in mm")
		return
	end
	local pa, pb = self.layout.poses[tostring(ca.id)], self.layout.poses[tostring(cb.id)]
	local pose, reason =
		Alignment.solve(kind, pa, References.world(a, pa), References.world(b, pb), offset[1] / 280)
	if not pose then
		self:_report(tostring(reason))
		return
	end
	self:select(ca.id)
	self:place(pose)
end
function Controller:mutate(method: string, ...: any)
	if self.pending or not self.active or self.manipulator.gizmo:isDragging() then
		return
	end
	self.pending = true
	self.manipulator.gizmo:setHidden(true)
	local args = table.pack(...)
	local ok, accepted, why = pcall(function()
		return self.remote[method](self.remote, table.unpack(args, 1, args.n))
	end)
	if ok and accepted then
		local refreshed, problem = pcall(function()
			self:reload()
		end)
		if not refreshed then
			accepted, why = false, problem
		end
	end
	self.pending = false
	if self.selectedId then
		self:select(self.selectedId)
	end
	self:_report(
		if ok and accepted then "Assembly updated" else tostring(if ok then why else accepted)
	)
	self.manipulator.gizmo:setHidden(false)
end
function Controller:registerSupport()
	if not self.a then
		return self:_report("Select the moving part, then click Use selected part as mover")
	end
	local spec = Catalog[self.modelIndex]
	if #self.fixtures ~= spec.fixtures then
		return self:_report("This relationship requires " .. spec.fixtures .. " fixture components")
	end
	self:mutate(
		"RegisterRelationship",
		spec.model,
		self.a.id,
		if self.b then self.b.id else 0,
		if self.b then self.b.ref else "",
		self.fixtures,
		self.layout.revision
	)
end
function Controller:Enter()
	self.active = false
	self.pending = true
	self.selectedId = self.bridge.getAssemblySelection() or self.selectedId
	self.gui.Enabled = true
	local ok, reason = pcall(function()
		self.bridge.enterAssembly()
		self:reload()
	end)
	self.pending = false
	if not ok then
		error(reason)
	end
	self.active = true
	self.pickTarget, self.justPickedTarget = false, nil
	local components = self.bridge.getAssemblyState().document.components
	if self.a and not components[self.a.id] then
		self.a = nil
	end
	if self.b and not components[self.b.id] then
		self.b = nil
	end
	for i = #self.fixtures, 1, -1 do
		if not components[self.fixtures[i]] then
			table.remove(self.fixtures, i)
		end
	end
	self:choiceText()
	self:mechanicsText()
	if self.selectedId then
		self:select(self.selectedId)
	end
	self.bridge.setAssemblySelection(self.selectedId)
	local state = self.bridge.getAssemblyState()
	state.projection.gizmoPicker = function(point)
		return self.pending or self.manipulator:capturesPoint(point)
	end
	state.projection.facePicker = function(id, hit)
		if self.justPickedTarget == id then
			self.justPickedTarget = nil
			return
		end
		local component = state.document.components[id]
		local pose = self.layout.poses[tostring(id)]
		if not component or not pose then
			return
		end
		local refs = References.list(component)
		for index, ref in ipairs(refs) do
			local world = References.world(ref, pose)
			if
				world.kind == "Plane"
				and world.direction:Dot(hit.Normal) > 0.999
				and math.abs((hit.Position - world.point):Dot(world.direction)) < 0.01
			then
				self.refIndex = index
				if self.a and self.a.id == id then
					self.a.ref = ref.id
				end
				if self.b and self.b.id == id then
					self.b.ref = ref.id
				end
				self:cycleReference(0)
				break
			end
		end
	end
	self.bridge.setAssemblyInputCaptured(function()
		return self.manipulator.gizmo:isDragging()
	end)
	self.manipulator.onActiveChanged = function(active)
		state.projection.precisionManipulating = active
	end
	self.bridge.frameAssembly(nil)
	self:_report(
		"Select a part. Move it directly, align references, then add a validated relationship."
			.. (
				if #self.layout.quarantined > 0
					then " Legacy joints quarantined: " .. #self.layout.quarantined
					else ""
			)
	)
end
function Controller:Exit()
	if self.pending then
		error("Wait for assembly validation to finish")
	end
	self.manipulator.gizmo.finish()
	if self.pending then
		error("Wait for placement validation")
	end
	self.active = false
	self.gui.Enabled = false
	self.manipulator:select(nil)
	self:clearHighlights()
	local projection = self.bridge.getAssemblyState().projection
	projection.gizmoPicker = nil
	projection.facePicker = nil
	projection.precisionManipulating = false
	self.manipulator.onActiveChanged = nil
	self.bridge.leaveAssembly()
end
function Controller:Update(_dt: number)
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
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.manipulator.onCommit = nil
	self.manipulator:Destroy()
	self:clearHighlights()
	self.gui:Destroy()
end
return Controller
