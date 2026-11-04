--!strict
-- Pure, in-memory editable construction definitions. No CSG or UI dependencies.
local Quantize = require(script.Parent.Quantize)

local Document = {}
Document.__index = Document

local KINDS = { Block = true, Cylinder = true, Tube = true, HoleBlock = true }
local AXES = { X = true, Y = true, Z = true }

local function defaultSize(kind: string): Vector3
	-- A drilled block must start with enough material for a visible, manufacturable bore.
	if kind == "HoleBlock" then
		return Vector3.new(1, 0.25, 1)
	end
	return Vector3.new(Quantize.MinSize, Quantize.MinSize, Quantize.MinSize)
end

local function validNode(node)
	if node.kind == "Tube" then
		local diameter = node.size.X
		-- Tiny primitives begin solid. Only validate bore clearance once it can exist.
		if node.wall < Quantize.MinSize then
			return false, "Tube wall must be at least 0.05 studs"
		end
		if diameter >= Quantize.MinSize * 3 and node.wall * 2 + Quantize.MinSize > diameter + 0.00001 then
			return false, "Tube wall leaves less than 0.05 studs of opening"
		end
	elseif node.kind == "HoleBlock" then
		local limit = math.min(node.size.X, node.size.Z)
		if node.bore < Quantize.MinSize then
			return false, "Hole diameter must be at least 0.05 studs"
		end
		if limit >= Quantize.MinSize * 3 and node.bore + Quantize.MinSize * 2 > limit + 0.00001 then
			return false, "Hole needs 0.05 studs of material on each side"
		end
	end
	return true, nil
end

function Document.new()
	return setmetatable({ components = {}, order = {}, nextComponent = 0, nextNode = 0 }, Document)
end

-- Components contain one editable, named parametric primitive, never a user
-- authored union/subtraction tree. CSG is an implementation detail of templates.
function Document:create(kind: string, position: Vector3)
	assert(KINDS[kind], "Unknown FORM primitive: " .. tostring(kind))
	self.nextComponent += 1
	self.nextNode += 1
	local id = self.nextComponent
	local node = {
		id = self.nextNode,
		kind = kind,
		position = Quantize.vector(position, Quantize.Grid),
		size = defaultSize(kind),
		rotation = Vector3.zero,
		bore = if kind == "HoleBlock" then 0.5 else Quantize.MinSize,
		wall = Quantize.MinSize,
	}
	local component = {
		id = id,
		name = kind .. " " .. id,
		nodes = { node }, -- retained as internal schema, not a Boolean editor
		revision = 1,
	}
	self.components[id] = component
	table.insert(self.order, id)
	return component
end

function Document:editNode(component, index: number, field: string, axis: string?, value: number)
	local node = component.nodes[index]
	if not node then return false, "No node selected" end
	if typeof(value) ~= "number" or not Quantize.isFinite(value) then
		return false, "Enter a finite number"
	end

	local before = table.clone(node)
	if field == "position" or field == "size" or field == "rotation" then
		if not axis or not AXES[axis] then return false, "Invalid axis" end
		local vec: Vector3 = node[field]
		local increment = if field == "rotation" then Quantize.Rotation else Quantize.Grid
		local snapped = Quantize.snap(value, increment)
		if field == "position" and math.abs(snapped) > Quantize.MaxPosition then
			return false, "Position must be within +/-512 studs"
		end
		if field == "size" then
			if snapped < Quantize.MinSize or snapped > Quantize.MaxSize then
				return false, "Size must be between 0.05 and 128 studs"
			end
		end
		if field == "rotation" then
			snapped = snapped % 360
		end
		local nextValues = { X = vec.X, Y = vec.Y, Z = vec.Z }
		nextValues[axis] = snapped
		if field == "size" and (node.kind == "Cylinder" or node.kind == "Tube") and axis ~= "Y" then
			nextValues.X = snapped
			nextValues.Z = snapped
		end
		node[field] = Vector3.new(nextValues.X, nextValues.Y, nextValues.Z)
	elseif field == "bore" or field == "wall" then
		local snapped = Quantize.snap(value, Quantize.Grid)
		if snapped < Quantize.MinSize or snapped > Quantize.MaxSize then
			return false, "Value must be between 0.05 and 128 studs"
		end
		if (field == "bore" and node.kind ~= "HoleBlock") or (field == "wall" and node.kind ~= "Tube") then
			return false, "This property does not apply to the selected primitive"
		end
		node[field] = snapped
	else
		return false, "Unknown FORM property"
	end

	local ok, reason = validNode(node)
	if not ok then
		for key, oldValue in pairs(before) do node[key] = oldValue end
		return false, reason
	end
	component.revision += 1
	return true, nil
end

-- Atomic transform editing for viewport manipulators. A single drag step is one
-- parametric revision; validation happens before any source definition is changed.
function Document:applyTransform(component, index: number, position: Vector3?, size: Vector3?, rotation: Vector3?, preserveFaceAnchor: boolean?)
	local node = component.nodes[index]
	if not node then return false, "No node selected" end

	-- A 0.05-stud face extension shifts its center only 0.025 studs.
	-- Rotated face normals likewise need exact world coordinates.
	local newPosition = if preserveFaceAnchor then (position or node.position)
		else Quantize.vector(position or node.position, Quantize.Grid)
	local newSize = Quantize.vector(size or node.size, Quantize.Grid)
	local inputRotation = rotation or node.rotation
	local newRotation = Vector3.new(
		Quantize.snap(inputRotation.X, Quantize.Rotation) % 360,
		Quantize.snap(inputRotation.Y, Quantize.Rotation) % 360,
		Quantize.snap(inputRotation.Z, Quantize.Rotation) % 360
	)
	for _, componentValue in ipairs({
		newPosition.X, newPosition.Y, newPosition.Z,
		newSize.X, newSize.Y, newSize.Z,
		newRotation.X, newRotation.Y, newRotation.Z,
	}) do
		if not Quantize.isFinite(componentValue) then
			return false, "Transform must contain finite numbers"
		end
	end
	if math.abs(newPosition.X) > Quantize.MaxPosition
		or math.abs(newPosition.Y) > Quantize.MaxPosition
		or math.abs(newPosition.Z) > Quantize.MaxPosition then
		return false, "Position must be within +/-512 studs"
	end
	if newSize.X < Quantize.MinSize or newSize.Y < Quantize.MinSize or newSize.Z < Quantize.MinSize
		or newSize.X > Quantize.MaxSize or newSize.Y > Quantize.MaxSize or newSize.Z > Quantize.MaxSize then
		return false, "Dimensions must be between 0.05 and 128 studs"
	end
	if node.kind == "Cylinder" or node.kind == "Tube" then
		-- The diameter is shared by X/Z; for handles, the larger edited radial
		-- dimension carries the resize, while Y continues independently.
		local xDifference = math.abs(newSize.X - node.size.X)
		local zDifference = math.abs(newSize.Z - node.size.Z)
		local diameter = if xDifference >= zDifference then newSize.X else newSize.Z
		newSize = Vector3.new(diameter, newSize.Y, diameter)
	end

	local previousPosition, previousSize, previousRotation = node.position, node.size, node.rotation
	node.position, node.size, node.rotation = newPosition, newSize, newRotation
	local ok, reason = validNode(node)
	if not ok then
		node.position, node.size, node.rotation = previousPosition, previousSize, previousRotation
		return false, reason
	end
	if previousPosition ~= newPosition or previousSize ~= newSize or previousRotation ~= newRotation then
		component.revision += 1
	end
	return true, nil
end

function Document:removeComponent(id: number)
	if not self.components[id] then return end
	self.components[id] = nil
	for i, value in ipairs(self.order) do
		if value == id then table.remove(self.order, i) break end
	end
end

function Document.snapshot(component)
	local nodes = {}
	for _, node in ipairs(component.nodes) do
		table.insert(nodes, table.clone(node))
	end
	return { id = component.id, name = component.name, revision = component.revision, nodes = nodes }
end

return Document
