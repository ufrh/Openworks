--!strict
local Players, RS = game:GetService("Players"), game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Openworks"):WaitForChild("Assembly")
local References = require(Shared.GeometryReferences)
local Alignment = require(Shared.Alignment)
local FitInspection = require(Shared.FitInspection)
local Catalog = require(Shared.RelationshipCatalog)
local Resolver = require(Shared.MechanicalResolver)
local SupportGeometry = require(Shared.SupportGeometry)
local Layout = require(Shared.AssemblyLayout)
local Panel = require(script.Parent.Parent.Parent.Experience.UI.WorkbenchPanel)
local Manipulator = require(script.Parent.PrecisionManipulator)
local BearingInstaller = require(script.Parent.BearingInstaller)
local PivotInstaller = require(script.Parent.PivotInstaller)
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
	local panel = Panel.new("Assembly", { "Parts", "Move", "Install", "Align", "Mechanics" })
	panel.tabs.Parts.Text = "Parts"
	panel.tabs.Align.Text = "Align"
	panel.tabs.Mechanics.Text = "Joints"
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
		partButtons = {},
		selectionIntent = nil,
		modelIndex = 1,
		travelAxis = "Y",
		history = {},
		redo = {},
		connections = {},
	}, Controller)
	local parts, move, install, align, mechanics =
		panel.pages.Parts, panel.pages.Move, panel.pages.Install,
		panel.pages.Align, panel.pages.Mechanics
	self.installMode = "Bearing"
	Panel.button(install, "Bearing · bore → shaft", function()
		self:setInstallMode("Bearing")
	end)
	Panel.button(install, "Pin pivot · two bores → hardware", function()
		self:setInstallMode("Pivot")
	end)
	self.bearingPanel = Panel.list(install)
	self.pivotPanel = Panel.list(install)
	self.installer = BearingInstaller.new(self, self.bearingPanel)
	self.pivotInstaller = PivotInstaller.new(self, self.pivotPanel)
	self.pivotPanel.Visible = false
	Panel.label(
		parts,
		"Create or machine material, position components, then install mechanical connections from their manufactured geometry.",
		48
	)
	Panel.button(parts, "+ New manufactured component", function()
		if self.pending or self.manipulator.gizmo:isDragging() then return end
		if self.onCreateComponent then self.onCreateComponent() end
	end)
	Panel.button(parts, "Edit selected component", function()
		if self.pending or self.manipulator.gizmo:isDragging() then return end
		if not self.selectedId then return self:_report("Select a component to edit") end
		if self.onEditComponent then self.onEditComponent(self.selectedId) end
	end)
	Panel.button(parts, "Install shaft in housing", function()
		self:setInstallMode("Bearing")
		self.panel:show("Install")
		self.selectionIntent = "installBore"
		self:_report("Select the housing with the bore you want to use")
	end)
	Panel.button(parts, "Install pin pivot", function()
		self:setInstallMode("Pivot")
		self.selectionIntent = "pivotBody"
		self:_report("Select the first drilled link")
	end)
	Panel.button(parts, "▶ Simulate", function()
		if not self.pending and self.onSimulate then
			self.onSimulate()
		end
	end)
	Panel.label(parts, "COMPONENTS  ·  [Fixed] indicates grounded", 30)
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
	local precision = Panel.list(move)
	precision.Visible = false
	local precisionToggle
	precisionToggle = Panel.button(move, "Precision fields", function()
		precision.Visible = not precision.Visible
		precisionToggle.Text = if precision.Visible
			then "Hide precision fields"
			else "Precision fields"
	end)
	self.orientation = Panel.button(precision, "Axes: Local", function()
		if self.pending or self.manipulator.gizmo:isDragging() then
			return
		end
		self.manipulator.options.world = not self.manipulator.options.world
		self.orientation.Text = "Axes: "
			.. (if self.manipulator.options.world then "World" else "Local")
		self.manipulator.gizmo:refresh()
	end)
	self.snap = Panel.input(precision, "Snap: millimeters, degrees", "1, 5")
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
	self.position = Panel.input(precision, "Position X, Y, Z (mm from stage center)", "0, 0, 0")
	self.rotation = Panel.input(precision, "Rotation X, Y, Z (degrees)", "0, 0, 0")
	Panel.button(precision, "Apply position + rotation", function()
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
		"Select the moving component and target reference. Mates position geometry; they do not create joints.",
		52
	)
	Panel.button(align, "Use selected component as A", function()
		if self.selectedId then
			self:setReference("a")
			self:_report("Reference A assigned")
		else
			self.selectionIntent = "a"
			self:_report("Select component A in the viewport or Components")
		end
	end)
	Panel.button(align, "Pick target component (B)", function()
		self.selectionIntent = "b"
		self:_report("Select component B in the viewport or Components")
	end)
	self.choices = Panel.label(align, "Moving part: — / Target: —", 52)
	Panel.label(align, "GEOMETRIC REFERENCES")
	self.refsRoot = Panel.list(align)
	self.offset = Panel.input(align, "Face spacing / offset (mm)", "0")
	Panel.button(align, "Measure selected references", function()
		self:measureFit()
	end)
	for _, item in ipairs({
		{ "Concentric", "Concentric axes" },
		{ "Coincident", "Coincident faces" },
		{ "Parallel", "Parallel" },
		{ "Distance", "Face offset" },
	}) do
		Panel.button(align, item[2], function()
			self:align(item[1])
		end)
	end
	Panel.button(align, "Clear chosen parts", function()
		self.a, self.b, self.selectionIntent = nil, nil, nil
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
	Panel.button(mechanics, "Use selected component as A", function()
		if self.selectedId then
			self:setReference("a")
			self:_report("Joint member A assigned")
		else
			self.selectionIntent = "a"
			self:_report("Select member A and its bore")
		end
	end)
	Panel.button(mechanics, "Pick joint member (B)", function()
		self.selectionIntent = "b"
		self:_report("Select member B and its bore")
	end)
	self.modelButton = Panel.label(mechanics, "", 32)
	for index, spec in ipairs(Catalog) do
		Panel.button(mechanics, spec.name, function()
			self.modelIndex = index
			self.fixtures = {}
			self.selectionIntent = nil
			self:mechanicsText()
		end)
	end
	self.modelHelp = Panel.label(mechanics, "", 84)
	self.travelAxisButton = Panel.button(mechanics, "Guide travel axis: Y", function()
		self.travelAxis = if self.travelAxis == "Y" then "X"
			elseif self.travelAxis == "X" then "Z" else "Y"
		self.travelAxisButton.Text = "Guide travel axis: " .. self.travelAxis
	end)
	Panel.button(mechanics, "Identify positioned pivot hardware", function()
		self:detectPivotHardware()
	end)
	Panel.button(mechanics, "Pick hardware / fixture", function()
		if Catalog[self.modelIndex].fixtures == 0 then
			return self:_report("This joint uses only its source components")
		end
		self.selectionIntent = "fixture"
		self:_report("Select hardware in order: " .. self:fixtureDescription())
	end)
	Panel.button(mechanics, "Clear hardware selection", function()
		self.fixtures = {}
		self.selectionIntent = nil
		self:mechanicsText()
	end)
	self.fixturesRoot = Panel.list(mechanics)
	Panel.label(mechanics, "BORE REFERENCES", 26)
	self.jointReferencesRoot = Panel.list(mechanics)
	Panel.button(mechanics, "Register joint", function()
		self:registerSupport()
	end)
	Panel.button(mechanics, "Measure joint references", function()
		self:measureFit()
	end)
	Panel.button(mechanics, "Check assembly", function()
		self:validate()
	end)
	Panel.button(mechanics, "▶ Simulate", function()
		if self.onSimulate then
			self.onSimulate()
		end
	end)
	Panel.label(mechanics, "MECHANICAL CONNECTIONS", 26)
	self.relationshipDetail = Panel.label(mechanics, "Select a relationship to inspect", 56)
	self.relationshipsRoot = Panel.list(mechanics)
	Panel.button(mechanics, "Remove selected relationship", function()
		local index = self.jointIndex
		if not index or not self.layout or not self.layout.supports[index] then
			return self:_report("Select the mechanical relationship to remove")
		end
		self.jointIndex = nil
		self:mutate("RemoveSupport", index, self.layout.revision)
	end)
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
				self.selectionIntent = nil
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

function Controller:setInstallMode(mode: string)
	if mode ~= "Bearing" and mode ~= "Pivot" then return end
	self.installer:restore()
	self.pivotInstaller:restore()
	self.installMode = mode
	self.selectionIntent = nil
	self.bearingPanel.Visible = mode == "Bearing"
	self.pivotPanel.Visible = mode == "Pivot"
	self.panel:show("Install")
	self.manipulator.gizmo:setHidden(false)
end

function Controller:name(id: number?): string
	local c = id and self.bridge.getAssemblyState().document.components[id]
	return if c then c.name .. " #" .. id else "—"
end

function Controller:choiceText()
	self.choices.Text = "A  " .. self:name(self.a and self.a.id)
		.. (if self.a then " · " .. self.a.ref else "")
		.. "\nB  " .. self:name(self.b and self.b.id)
		.. (if self.b then " · " .. self.b.ref else "")
	self.mechanicalChoices.Text = "Member A  " .. self:name(self.a and self.a.id)
		.. (if self.a then " · " .. self.a.ref else "")
		.. "\nMember B  " .. self:name(self.b and self.b.id)
		.. (if self.b then " · " .. self.b.ref else "")
end

function Controller:fixtureDescription(): string
	local model = Catalog[self.modelIndex].model
	if model == "DualPinRigidV1" then
		return "pin A → caps A1/A2 → pin B → caps B1/B2"
	elseif model == "RetainedPivotV1" then
		return "pin → lower retainer → upper retainer"
	elseif model == "RetainedBoreV1" then
		return "first end stop → second end stop"
	elseif model == "LinearGuideV1" then
		return "four surrounding rails"
	elseif model == "LimitedGuideV1" then
		return "four rails → two travel stops"
	end
	return "no separate fixtures"
end

function Controller:addFixture(id: number)
	local spec = Catalog[self.modelIndex]
	if spec.fixtures == 0 then
		self.selectionIntent = nil
		return self:_report("This relationship does not require hardware")
	end
	if (self.a and id == self.a.id) or (self.b and id == self.b.id) then
		return self:_report("Joint members cannot also be their own fixtures")
	end
	if table.find(self.fixtures, id) then
		return self:_report("That component is already selected as hardware")
	end
	if #self.fixtures >= spec.fixtures then
		self.selectionIntent = nil
		return self:_report("Hardware selection is complete")
	end
	table.insert(self.fixtures, id)
	self:mechanicsText()
	if #self.fixtures == spec.fixtures then
		self.selectionIntent = nil
		self:_report("Hardware selected. Register Joint validates the complete physical fit.")
	else
		self:_report(string.format("%d/%d hardware parts. Select the next: %s",
			#self.fixtures, spec.fixtures, self:fixtureDescription()))
	end
end

function Controller:mechanicsText()
	local item = Catalog[self.modelIndex]
	self.modelButton.Text = "Joint model: " .. item.name
	self.modelHelp.Text = item.motion .. "\n" .. item.help
	self.travelAxisButton.Visible = item.model == "LinearGuideV1" or item.model == "LimitedGuideV1"
	Panel.clear(self.fixturesRoot)
	for i, id in ipairs(self.fixtures) do
		Panel.button(self.fixturesRoot, i .. ". " .. self:name(id) .. " ×", function()
			table.remove(self.fixtures, i)
			self:mechanicsText()
		end)
	end
	Panel.label(
		self.fixturesRoot,
		string.format("%d / %d fixtures · %s", #self.fixtures, item.fixtures,
			self:fixtureDescription())
	)
end

function Controller:refreshLists()
	local state = self.bridge.getAssemblyState()
	Panel.clear(self.partsRoot)
	table.clear(self.partButtons)
	for _, id in ipairs(state.document.order) do
		local label = self:name(id)
		if self.layout.grounded[tostring(id)] then
			label ..= " [Fixed]"
		end
		local item = Panel.button(self.partsRoot, label, function()
			self:select(id)
		end)
		self.partButtons[id] = item
		item.BackgroundColor3 = if id == self.selectedId
			then Color3.fromRGB(27, 119, 135)
			else Color3.fromRGB(43, 65, 79)
	end
	Panel.clear(self.relationshipsRoot)
	if self.jointIndex and not self.layout.supports[self.jointIndex] then
		self.jointIndex = nil
	end
	for i, record in ipairs(self.layout.supports) do
		local specName = record.model
		for _, spec in ipairs(Catalog) do
			if spec.model == record.model then
				specName = spec.name
				break
			end
		end
		local item = Panel.button(
			self.relationshipsRoot,
			string.format("#%d  %s  ·  %s", i, specName,
				self:name(record.movingId or record.shaftId)),
			function()
				self.jointIndex = i
				self:refreshLists()
				self:_report("Relationship selected. Inspect its members or remove explicitly.")
			end
		)
		item.BackgroundColor3 = if self.jointIndex == i
			then Color3.fromRGB(27, 119, 135)
			else Color3.fromRGB(43, 65, 79)
	end
	local selected = self.jointIndex and self.layout.supports[self.jointIndex]
	if selected then
		self.relationshipDetail.Text =
			string.format("#%d  %s\nA: %s   B: %s",
				self.jointIndex, selected.model,
				self:name(selected.movingId or selected.shaftId),
				self:name(selected.bodyId))
	else
		self.relationshipDetail.Text =
			if #self.layout.supports == 0 then "No registered relationships"
			else "Select a relationship to inspect"
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
	if id ~= self.selectedId and not self.selectionIntent then
		self.refIndex = 1
	end
	self.selectedId = id
	local intent = self.selectionIntent
	if intent == "a" or intent == "b" then
		local refs = References.list(state.document.components[id])
		local preferred = 1
		for index, ref in ipairs(refs) do
			if ref.feature or ref.id == "shaft" then
				preferred = index
				break
			end
		end
		self.refIndex = preferred
	end
	for componentId, button in pairs(self.partButtons) do
		button.BackgroundColor3 = if componentId == id
			then Color3.fromRGB(27, 119, 135)
			else Color3.fromRGB(43, 65, 79)
	end
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
	if intent == "a" or intent == "b" then
		self:setReference(intent)
		self.selectionIntent = nil
		self:choiceText()
		self:_report("Member " .. string.upper(intent)
			.. " selected. Choose the drilled reference if needed.")
	elseif intent == "fixture" then
		self:addFixture(id)
	elseif intent == "installBore" or intent == "installShaft" then
		self.installer:select(id, intent)
	elseif type(intent) == "string" and string.sub(intent, 1, 5) == "pivot" then
		self.pivotInstaller:select(id, intent)
	end
end
function Controller:cycleReference(delta: number?)
	local state = self.bridge.getAssemblyState()
	local component = self.selectedId and state.document.components[self.selectedId]
	local refs = component and References.list(component) or {}
	Panel.clear(self.refsRoot)
	Panel.clear(self.jointReferencesRoot)
	if #refs == 0 then
		Panel.label(self.refsRoot, "No source references")
		Panel.label(self.jointReferencesRoot, "Select a manufactured part")
		return
	end
	self.refIndex = (self.refIndex - 1 + (delta or 1)) % #refs + 1
	for index, ref in ipairs(refs) do
		local caption = if ref.id == "shaft"
			then "Shaft centerline"
			elseif ref.feature then "Hole Ø" .. string.format("%.1f mm", ref.diameter * 280)
			else "Face " .. ref.id
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
		if ref.feature or ref.id == "shaft" then
			Panel.button(self.jointReferencesRoot, caption .. "  →  A", function()
				self.refIndex = index
				self:setReference("a")
				self:cycleReference(0)
				self:choiceText()
			end)
			Panel.button(self.jointReferencesRoot, caption .. "  →  B", function()
				self.refIndex = index
				self:setReference("b")
				self:cycleReference(0)
				self:choiceText()
			end)
		end
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
		self:_report("Placement accepted.")
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
function Controller:measureFit()
	if not self.a or not self.b or not self.layout then
		return self:_report("Select reference A and reference B to measure their fit")
	end
	local state = self.bridge.getAssemblyState()
	local componentA = state.document.components[self.a.id]
	local componentB = state.document.components[self.b.id]
	local poseA = self.layout.poses[tostring(self.a.id)]
	local poseB = self.layout.poses[tostring(self.b.id)]
	if not componentA or not componentB or not poseA or not poseB then
		return self:_report("Referenced geometry or positioning is no longer available")
	end
	local refA = References.get(componentA, self.a.ref)
	local refB = References.get(componentB, self.b.ref)
	if not refA or not refB then
		return self:_report("Choose valid manufactured datum references")
	end
	local measure, reason = FitInspection.measure(
		References.world(refA, poseA), References.world(refB, poseB)
	)
	self:_report(if measure then FitInspection.describe(measure) else tostring(reason))
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
		elseif method == "RegisterRelationship" then
			-- The installed pin and its retainers now belong to this joint.
			-- Clear the fixture picker for the next independent connection.
			self.fixtures = {}
			self.selectionIntent = nil
			self:mechanicsText()
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
-- Detect geometry the player has already manufactured and positioned.
-- This is a lookup, not a snap, a generated fastener, or an installed joint.
function Controller:detectPivotHardware(): boolean
	if not self.layout or not self.a or not self.b
		or self.a.id == self.b.id then
		self:_report("Select the two drilled link references first")
		return false
	end
	local state = self.bridge.getAssemblyState()
	local components = state.document.components
	local poses = self.layout.poses
	local candidates = {}
	for pinId, component in pairs(components) do
		if pinId == self.a.id or pinId == self.b.id
			or component.nodes[1].kind ~= "Cylinder"
			or not poses[tostring(pinId)] then
			continue
		end
		local hasCut = false
		for _, operation in ipairs(component.operations or {}) do
			if operation.enabled ~= false then hasCut = true break end
		end
		if hasCut then continue end
		local pose = poses[tostring(pinId)]
		local half = component.nodes[1].size.Y * 0.5
		local ends = {}
		for capId, cap in pairs(components) do
			if capId == pinId or capId == self.a.id or capId == self.b.id then continue end
			local capSize = SupportGeometry.box(cap)
			local capPose = poses[tostring(capId)]
			if not capSize or not capPose then continue end
			local difference = capPose.Position - pose.Position
			local axial = difference:Dot(pose.YVector)
			local radial = (difference - pose.YVector * axial).Magnitude
			if radial > 3 / 280 or
				math.abs(math.abs(axial) - (half + capSize.Y * 0.5)) > 3 / 280 then
				continue
			end
			ends[if axial > 0 then 1 else -1] = capId
		end
		if ends[-1] and ends[1] then
			local record = {
				model = "RetainedPivotV1",
				bodyId = self.b.id,
				movingId = self.a.id,
				featureId = self.b.ref,
				movingFeatureId = self.a.ref,
				pinId = pinId,
				stopIds = {ends[-1], ends[1]},
			}
			local relation = Resolver.resolve(record, components, poses, self.layout.grounded)
			if relation then
				table.insert(candidates, {pinId, ends[-1], ends[1]})
			end
		end
	end
	if #candidates ~= 1 then
		self:_report(if #candidates == 0 then
			"No valid positioned pin and end-cap pair found" else
			"Multiple pin assemblies match; select the intended hardware manually")
		return false
	end
	self.fixtures = candidates[1]
	for index, spec in ipairs(Catalog) do
		if spec.model == "RetainedPivotV1" then
			self.modelIndex = index
			break
		end
	end
	self:mechanicsText()
	self:_report("Located manufactured pin and both retainers. Register the pivot to connect.")
	return true
end

function Controller:registerSupport()
	if not self.a then
		return self:_report("Select the moving part, then click This is the part that moves")
	end
	local spec = Catalog[self.modelIndex]
	if spec.model == "RetainedPivotV1" and #self.fixtures == 0 then
		self:detectPivotHardware()
	end
	if #self.fixtures ~= spec.fixtures then
		return self:_report("This relationship requires " .. spec.fixtures .. " fixture components")
	end
	if spec.model == "RetainedPivotV1" or spec.model == "DualPinRigidV1" then
		if not self.b or self.a.id == self.b.id then
			return self:_report("Choose two different drilled link members (A and B)")
		end
	end
	self:mutate(
		"RegisterRelationship",
		spec.model,
		self.a.id,
		if self.b then self.b.id else 0,
		if self.b then self.b.ref else "",
		self.fixtures,
		self.layout.revision,
		if spec.model == "RetainedPivotV1" or spec.model == "DualPinRigidV1"
			then self.a.ref else nil,
		if spec.model == "LinearGuideV1" or spec.model == "LimitedGuideV1"
			then self.travelAxis else nil
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
	self.selectionIntent = nil
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
		-- Picking the rim of a manufactured bore selects its source axis.
		-- No mesh triangle IDs or hidden collision hit-boxes are involved.
		local nearestIndex, nearestDistance = nil, math.huge
		for index, ref in ipairs(refs) do
			if ref.feature then
				local worldRef = References.world(ref, pose)
				local distance = (hit.Position - worldRef.point).Magnitude
				if distance < math.max(0.11, ref.diameter * 0.9)
					and distance < nearestDistance then
					nearestIndex, nearestDistance = index, distance
				end
			end
		end
		if nearestIndex then
			if self.panel.current == "Install" then
				if self.installMode == "Bearing"
					and self.installer.housingId == id then
					self.installer:chooseBore(refs[nearestIndex].id)
				elseif self.installMode == "Pivot" then
					if self.pivotInstaller.bodyId == id then
						self.pivotInstaller:chooseBore("pivotBody", refs[nearestIndex].id)
				elseif self.pivotInstaller.movingId == id then
						self.pivotInstaller:chooseBore("pivotMover", refs[nearestIndex].id)
					end
				end
			end
			self.refIndex = nearestIndex
			if self.a and self.a.id == id then self.a.ref = refs[nearestIndex].id end
			if self.b and self.b.id == id then self.b.ref = refs[nearestIndex].id end
			self:cycleReference(0)
			self:choiceText()
			return
		end
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
		"CAD assembly ready. Select geometry, position components, and register manufactured joints."
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
	self.installer:restore()
	self.pivotInstaller:restore()
	self.selectionIntent = nil
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
