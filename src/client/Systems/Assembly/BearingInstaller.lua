--!strict
-- Bore-first mechanical installation UI. Users select actual geometry,
-- adjust one physically meaningful offset, then commit the validated fit.
-- No mate IDs, manual constraint modes, or generated fastening hardware.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Openworks"):WaitForChild("Assembly")
local References = require(Shared.GeometryReferences)
local Panel = require(script.Parent.Parent.Parent.Experience.UI.WorkbenchPanel)

local Installer = {}
Installer.__index = Installer

local function solid(parent: any, id: number): BasePart?
	local cache = parent.bridge.getAssemblyState().projection.cache[id]
	local p = cache and cache.model:FindFirstChild("Solid", true)
	return if p and p:IsA("BasePart") then p else nil
end

local function source(part: BasePart): CFrame
	return part:GetAttribute("OWSourceLocalFrame") or CFrame.identity
end

function Installer.new(parent: any, page: Frame)
	local self = setmetatable({
		parent = parent,
		housingId = nil,
		boreId = nil,
		shaftId = nil,
		offsetMM = 0,
		previewPose = nil,
		previewValid = false,
		previewing = false,
	}, Installer)
	Panel.label(page, "SHAFT → BORE INSTALLATION", 28)
	Panel.label(page,
		"Choose a manufactured housing hole, then a shaft. Adjust the insertion position; the finished solids determine whether they fit.",
		64)
	Panel.button(page, "1 · Select housing / bore", function()
		self:restore()
		parent.selectionIntent = "installBore"
		parent:_report("Select the housing in the viewport or Components")
	end)
	self.housingLabel = Panel.label(page, "Housing: —", 36)
	self.bores = Panel.list(page)
	Panel.button(page, "2 · Select shaft", function()
		if not self.boreId then
			return parent:_report("Select a manufactured bore first")
		end
		self:restore()
		parent.selectionIntent = "installShaft"
		parent:_report("Select the manufactured shaft in the viewport or Components")
	end)
	self.shaftLabel = Panel.label(page, "Shaft: —", 36)
	Panel.label(page, "AXIAL INSERTION", 25)
	self.positionField = Panel.input(page, "Shaft axis center relative to bore center (mm)", "0")
	self.positionField.FocusLost:Connect(function()
		local value = tonumber(self.positionField.Text)
		if not value or value ~= value or math.abs(value) > 35840 then
			self.positionField.Text = tostring(self.offsetMM)
			return parent:_report("Enter a finite axial offset within ±35,840 mm")
		end
		self.offsetMM = value
		self:preview()
	end)
	for _, step in ipairs({-10, -1, 1, 10}) do
		Panel.button(page, (if step > 0 then "+" else "") .. step .. " mm", function()
			self.offsetMM = math.clamp(self.offsetMM + step, -35840, 35840)
			self.positionField.Text = tostring(self.offsetMM)
			self:preview()
		end)
	end
	Panel.button(page, "Preview fit", function()
		self:preview()
	end)
	self.fitLabel = Panel.label(page, "Select a bore and shaft to inspect their fit.", 72)
	Panel.button(page, "Finalize bearing installation", function()
		self:finalize()
	end)
	Panel.button(page, "Cancel placement / restore CAD pose", function()
		self:clear()
	end)
	return self
end

function Installer:refresh()
	local parent = self.parent
	self.housingLabel.Text = "Housing: " .. parent:name(self.housingId)
	self.shaftLabel.Text = "Shaft: " .. parent:name(self.shaftId)
	Panel.clear(self.bores)
	local document = parent.bridge.getAssemblyState().document
	local component = self.housingId and document.components[self.housingId]
	if not component then
		Panel.label(self.bores, "No housing selected", 28)
		return
	end
	local found = 0
	for _, reference in ipairs(References.list(component)) do
		if not reference.feature then continue end
		found += 1
		local id = reference.id
		local caption = string.format(
			"%s  Bore Ø%.1f mm%s",
			if id == self.boreId then "●" else "○",
			reference.diameter * 280,
			if reference.feature.through then "" else " · blind"
		)
		Panel.button(self.bores, caption, function()
			self:chooseBore(id)
		end)
	end
	if found == 0 then
		Panel.label(self.bores, "No drilled openings found. Machine a hole in Edit.", 48)
	end
end

function Installer:restore()
	if not self.shaftId then return end
	local parent = self.parent
	local part = solid(parent, self.shaftId)
	local pose = parent.layout and parent.layout.poses[tostring(self.shaftId)]
	if part and pose then
		part.CFrame = pose * source(part)
	end
	self.previewPose = nil
	self.previewValid = false
end

function Installer:clear()
	self:restore()
	self.housingId = nil
	self.boreId = nil
	self.shaftId = nil
	self.offsetMM = 0
	self.positionField.Text = "0"
	self.fitLabel.Text = "Select a bore and shaft to inspect their fit."
	self.parent.selectionIntent = nil
	self.parent.manipulator.gizmo:setHidden(false)
	self:refresh()
end

function Installer:chooseBore(referenceId: string)
	self:restore()
	local document = self.parent.bridge.getAssemblyState().document
	local component = self.housingId and document.components[self.housingId]
	local bore = component and References.get(component, referenceId)
	if not bore or not bore.feature or not bore.feature.through then
		return self.parent:_report("Choose a manufactured through-bore")
	end
	self.boreId = referenceId
	self.parent.selectionIntent = if self.shaftId then nil else "installShaft"
	self:refresh()
	self.parent:_report(if self.shaftId then "Bore selected; preview the insertion depth"
		else "Bore selected. Now select the shaft.")
	if self.shaftId then self:preview() end
end

function Installer:select(id: number, intent: string)
	local document = self.parent.bridge.getAssemblyState().document
	local component = document.components[id]
	if not component then return end
	if intent == "installBore" then
		if id == self.shaftId then
			return self.parent:_report("The housing must be different from the shaft")
		end
		self:restore()
		self.housingId = id
		self.boreId = nil
		local holes = {}
		for _, reference in ipairs(References.list(component)) do
			if reference.feature and reference.feature.through then
				table.insert(holes, reference)
			end
		end
		if #holes == 1 then
			self:chooseBore(holes[1].id)
		else
			self.parent.selectionIntent = nil
			self.parent:_report(if #holes == 0 then
				"Housing has no manufactured through-bore. Drill one in Edit." else
				"Choose the intended bore in the Install page.")
		end
	elseif intent == "installShaft" then
		if id == self.housingId then
			return self.parent:_report("Select a separate manufactured shaft")
		end
		if not References.get(component, "shaft") then
			return self.parent:_report(
				"Selected component has no cylindrical shaft. Start with Cylinder stock."
			)
		end
		self:restore()
		self.shaftId = id
		self.parent.selectionIntent = nil
		self.parent:_report("Shaft selected. Adjust axial insertion and finalize the fit.")
		self:preview()
	end
	self:refresh()
	self.parent.panel:show("Install")
end

function Installer:preview()
	if self.previewing or self.parent.pending then return end
	local parent = self.parent
	if not parent.active or not parent.layout or not self.boreId or not self.shaftId then
		return parent:_report("Choose a housing bore and a shaft first")
	end
	self.previewing = true
	parent.pending = true
	parent.manipulator.gizmo:setHidden(true)
	local worked, accepted, report, invalidPose = pcall(function()
		return parent.remote:PreviewBearingPlacement(
			self.housingId, self.boreId, self.shaftId,
			self.offsetMM, parent.layout.revision
		)
	end)
	parent.pending = false
	self.previewing = false
	local valid = worked and accepted == true and type(report) == "table"
	local pose = if valid then report.pose else invalidPose
	if typeof(pose) == "CFrame" then
		local part = solid(parent, self.shaftId)
		if part then part.CFrame = pose * source(part) end
	end
	self.previewPose = if valid then pose else nil
	self.previewValid = valid
	local message = if valid then
		string.format("Fit accepted · nominal stem clearance %.2f mm. Final solid checked at %.1f mm offset.",
			report.clearanceMM, self.offsetMM)
		else "Fit rejected · " .. tostring(if worked then report else accepted)
	self.fitLabel.Text = message
	parent:_report(message)
	parent:clearHighlights()
	if self.shaftId then
		parent:highlight(self.shaftId, if valid then
			Color3.fromRGB(55, 215, 145) else Color3.fromRGB(245, 85, 85))
	end
end

function Installer:finalize()
	local parent = self.parent
	if not self.previewValid or not parent.layout or self.previewing or parent.pending then
		return parent:_report("Preview and resolve any fit errors before finalizing")
	end
	parent.pending = true
	local worked, accepted, report = pcall(function()
		return parent.remote:FinalizeBearingPlacement(
			self.housingId, self.boreId, self.shaftId,
			self.offsetMM, parent.layout.revision
		)
	end)
	parent.pending = false
	if not worked or not accepted then
		self.previewValid = false
		self.fitLabel.Text = "Finalize rejected · " .. tostring(if worked then report else accepted)
		return parent:_report(self.fitLabel.Text)
	end
	-- Clear ghost state before refreshing the server-authored pose and joint.
	self.previewPose = nil
	self.previewValid = false
	local ok, why = pcall(function() parent:reload() end)
	if not ok then
		return parent:_report("Installation committed; layout refresh failed: " .. tostring(why))
	end
	self:clear()
	parent:_report("Bearing installed. Its motion is determined by manufactured geometry.")
end

return Installer
