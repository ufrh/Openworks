--!strict
-- Hole pair → physical pin → two retainers → spacing and phase → finalize.
-- The editor never fabricates any pin or retainer on the player's behalf.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Openworks"):WaitForChild("Assembly")
local References = require(Shared.GeometryReferences)
local Panel = require(script.Parent.Parent.Parent.Experience.UI.WorkbenchPanel)

local Pivot = {}
Pivot.__index = Pivot

local PICKS = {
	pivotBody = "Fixed/first link",
	pivotMover = "Second link",
	pivotPin = "Pivot pin",
	pivotCapA = "Retainer A",
	pivotCapB = "Retainer B",
}

local function solid(parent: any, id: number): BasePart?
	local entry = parent.bridge.getAssemblyState().projection.cache[id]
	local part = entry and entry.model:FindFirstChild("Solid", true)
	return if part and part:IsA("BasePart") then part else nil
end

function Pivot.new(parent: any, page: Frame)
	local self = setmetatable({
		parent = parent,
		bodyId = nil, bodyFeature = nil,
		movingId = nil, movingFeature = nil,
		pinId = nil, capA = nil, capB = nil,
		spacing = 56, phase = 0,
		previewValid = false,
		previewing = false,
	}, Pivot)
	Panel.label(page, "RETAINED PIN PIVOT", 26)
	Panel.label(page,
		"Select two drilled links, a manufactured pin, and two end caps. OpenWorks aligns the geometry and verifies the complete assembly.",
		65)
	self.sections = {}
	for _, item in ipairs({
		{"pivotBody", "1 · Choose first link / bore"},
		{"pivotMover", "2 · Choose second link / bore"},
		{"pivotPin", "3 · Choose manufactured pin"},
		{"pivotCapA", "4 · Choose first retainer"},
		{"pivotCapB", "5 · Choose second retainer"},
	}) do
		local intent, title = item[1], item[2]
		Panel.button(page, title, function()
			self:restore()
			parent.selectionIntent = intent
			parent:_report("Select " .. PICKS[intent] .. " in Components or the viewport")
		end)
		self.sections[intent] = Panel.label(page, "—", 24)
		if intent == "pivotBody" or intent == "pivotMover" then
			self.sections[intent .. "Bores"] = Panel.list(page)
		end
	end
	self.spacingBox = Panel.input(page, "Link bore-center spacing along pin axis (mm)", "56")
	self.phaseBox = Panel.input(page, "Initial relative rotation (degrees)", "0")
	for _, box in ipairs({self.spacingBox, self.phaseBox}) do
		box.FocusLost:Connect(function()
			self:preview()
		end)
	end
	Panel.button(page, "Preview physical fit", function()
		self:preview()
	end)
	self.resultLabel = Panel.label(page, "Select manufactured members and hardware.", 65)
	Panel.button(page, "Finalize pivot", function()
		self:finalize()
	end)
	Panel.button(page, "Cancel and restore CAD positions", function()
		self:clear()
	end)
	self:refresh()
	return self
end

function Pivot:refresh()
	local parent = self.parent
	for _, key in ipairs({"pivotBody", "pivotMover", "pivotPin", "pivotCapA", "pivotCapB"}) do
		local id = if key == "pivotBody" then self.bodyId
			elseif key == "pivotMover" then self.movingId
			elseif key == "pivotPin" then self.pinId
			elseif key == "pivotCapA" then self.capA else self.capB
		local suffix = if key == "pivotBody" then self.bodyFeature
			elseif key == "pivotMover" then self.movingFeature else nil
		self.sections[key].Text = parent:name(id)
			.. (if suffix then "  ·  " .. suffix else "")
	end
	local document = parent.bridge.getAssemblyState().document
	for _, key in ipairs({"pivotBody", "pivotMover"}) do
		local list = self.sections[key .. "Bores"]
		Panel.clear(list)
		local id = if key == "pivotBody" then self.bodyId else self.movingId
		local current = if key == "pivotBody" then self.bodyFeature else self.movingFeature
		local component = id and document.components[id]
		if not component then continue end
		for _, ref in ipairs(References.list(component)) do
			if not ref.feature or not ref.feature.through then continue end
			local feature = ref.id
			Panel.button(list, string.format("%s  Bore Ø%.1f mm",
				if feature == current then "●" else "○",
				ref.diameter * 280), function()
				self:chooseBore(key, feature)
			end)
		end
	end
end

function Pivot:restore()
	local parent = self.parent
	local state = parent.bridge.getAssemblyState()
	for _, id in ipairs({
		self.movingId or 0, self.pinId or 0, self.capA or 0, self.capB or 0
	}) do
		if id == 0 then continue end
		local part = solid(parent, id)
		local pose = parent.layout and parent.layout.poses[tostring(id)]
		if part and pose then
			part.CFrame = pose
				* (part:GetAttribute("OWSourceLocalFrame") or CFrame.identity)
		end
	end
	self.previewValid = false
end

function Pivot:clear()
	self:restore()
	self.bodyId, self.bodyFeature = nil, nil
	self.movingId, self.movingFeature = nil, nil
	self.pinId, self.capA, self.capB = nil, nil, nil
	self.parent.selectionIntent = nil
	self.parent.manipulator.gizmo:setHidden(false)
	self.resultLabel.Text = "Select manufactured members and hardware."
	self:refresh()
end

function Pivot:chooseBore(key: string, feature: string)
	self:restore()
	local parent = self.parent
	local id = if key == "pivotBody" then self.bodyId else self.movingId
	local component = id and parent.bridge.getAssemblyState().document.components[id]
	local ref = component and References.get(component, feature)
	if not ref or not ref.feature or not ref.feature.through then
		return parent:_report("Select a through-bore from the link")
	end
	if key == "pivotBody" then self.bodyFeature = feature
	else self.movingFeature = feature end
	self:refresh()
	parent:_report("Bore selected. Continue with the next manufactured component.")
end

function Pivot:select(id: number, intent: string)
	local parent = self.parent
	local document = parent.bridge.getAssemblyState().document
	local component = document.components[id]
	if not component then return end
	for _, other in ipairs({
		self.bodyId or 0, self.movingId or 0, self.pinId or 0,
		self.capA or 0, self.capB or 0
	}) do
		if other == id then
			return parent:_report("Every link, pin, and retainer must be a distinct component")
		end
	end
	self:restore()
	if intent == "pivotBody" or intent == "pivotMover" then
		local bores = {}
		for _, ref in ipairs(References.list(component)) do
			if ref.feature and ref.feature.through then table.insert(bores, ref) end
		end
		if #bores == 0 then
			return parent:_report("The selected link has no manufactured through-bore")
		end
		if intent == "pivotBody" then
			self.bodyId = id
			self.bodyFeature = if #bores == 1 then bores[1].id else nil
		else
			self.movingId = id
			self.movingFeature = if #bores == 1 then bores[1].id else nil
		end
		if #bores > 1 then
			parent:_report("Choose the intended hole in the Install page")
		end
	elseif intent == "pivotPin" then
		if not References.get(component, "shaft") then
			return parent:_report("The selected pin needs cylindrical shaft geometry")
		end
		self.pinId = id
	elseif intent == "pivotCapA" then
		self.capA = id
	elseif intent == "pivotCapB" then
		self.capB = id
	end
	parent.selectionIntent = nil
	self:refresh()
	parent.panel:show("Install")
	if self.bodyFeature and self.movingFeature
		and self.pinId and self.capA and self.capB then
		self:preview()
	end
end

function Pivot:readParameters(): boolean
	local spacing, phase = tonumber(self.spacingBox.Text), tonumber(self.phaseBox.Text)
	if not spacing or spacing ~= spacing or math.abs(spacing) > 35840
		or not phase or phase ~= phase or math.abs(phase) > 360 then
		self.parent:_report("Enter finite bore spacing (mm) and rotation (±360°)")
		return false
	end
	self.spacing, self.phase = spacing, phase
	return true
end

function Pivot:request(action: string): (boolean, any, any?)
	local parent = self.parent
	local ok, accepted, result, proposed = pcall(function()
		return parent.remote[action](
			parent.remote,
			self.bodyId, self.bodyFeature, self.movingId, self.movingFeature,
			self.pinId, self.capA, self.capB, self.spacing, self.phase,
			parent.layout.revision
		)
	end)
	return ok and accepted == true, if ok then result else accepted, proposed
end

function Pivot:preview()
	local parent = self.parent
	if self.previewing or parent.pending then return end
	if not self.bodyFeature or not self.movingFeature
		or not self.pinId or not self.capA or not self.capB then
		return parent:_report("Select two bores, a pin and both retainers")
	end
	if not self:readParameters() then return end
	self.previewing = true
	parent.pending = true
	parent.manipulator.gizmo:setHidden(true)
	local valid, result, rejected = self:request("PreviewPivotPlacement")
	parent.pending = false
	self.previewing = false
	self.previewValid = valid
	local poses = if valid and type(result) == "table" then result.poses else rejected
	if type(poses) == "table" then
		for _, id in ipairs({self.movingId, self.pinId, self.capA, self.capB}) do
			local pose = poses[tostring(id)]
			local part = solid(parent, id)
			if part and typeof(pose) == "CFrame" then
				part.CFrame = pose
					* (part:GetAttribute("OWSourceLocalFrame") or CFrame.identity)
			end
		end
	else
		self:restore()
	end
	parent:clearHighlights()
	for _, id in ipairs({self.movingId, self.pinId, self.capA, self.capB}) do
		parent:highlight(id, if valid then
			Color3.fromRGB(55, 215, 145) else Color3.fromRGB(245, 85, 85))
	end
	self.resultLabel.Text = if valid
		then "Geometry and retention validated. Ready to finalize."
		else "Installation rejected: " .. tostring(result)
	parent:_report(self.resultLabel.Text)
end

function Pivot:finalize()
	if self.parent.pending or self.previewing or not self.previewValid
		or not self:readParameters() then
		return self.parent:_report("Preview a valid manufactured pivot before finalizing")
	end
	local parent = self.parent
	parent.pending = true
	local valid, result = self:request("FinalizePivotPlacement")
	parent.pending = false
	if not valid then
		self.previewValid = false
		return parent:_report("Pivot finalization rejected: " .. tostring(result))
	end
	local refreshed, issue = pcall(function() parent:reload() end)
	if not refreshed then
		return parent:_report("Pivot committed; layout refresh failed: " .. tostring(issue))
	end
	self:clear()
	parent:_report("Retained pin pivot installed and ready for Simulation")
end

return Pivot
