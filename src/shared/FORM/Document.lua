--!strict
-- FORM source document: editable material envelopes plus ordered fabrication history.
-- A component's origin is the minimum local corner of its uncut envelope,
-- while BasePart positioning continues to use the calculated center.
local Quantize = require(script.Parent.Quantize)

local Document = {}
Document.__index = Document

local KINDS = { Block = true, Cylinder = true }
local AXES = { X = true, Y = true, Z = true }

local function orientation(rotation: Vector3): CFrame
	return CFrame.fromOrientation(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z))
end

local function halfOffset(size: Vector3, rotation: Vector3): Vector3
	return orientation(rotation):VectorToWorldSpace(size * 0.5)
end

local function withAxis(vec: Vector3, axis: string, value: number): Vector3
	if axis == "X" then return Vector3.new(value, vec.Y, vec.Z) end
	if axis == "Y" then return Vector3.new(vec.X, value, vec.Z) end
	return Vector3.new(vec.X, vec.Y, value)
end

function Document.minCorner(node): Vector3
	return node.position - halfOffset(node.size, node.rotation)
end

local function defaultSize(kind: string): Vector3
	if kind == "Cylinder" then return Vector3.new(0.5, 0.4, 0.5) end
	return Vector3.new(1, 0.4, 1)
end

function Document.new()
	return setmetatable({
		components = {}, order = {}, nextComponent = 0,
		nextNode = 0, nextOperation = 0,
	}, Document)
end

function Document:create(kind: string, minimumCorner: Vector3)
	assert(KINDS[kind], "Unknown FORM material: " .. tostring(kind))
	self.nextComponent += 1
	self.nextNode += 1
	local size = defaultSize(kind)
	local node = {
		id = self.nextNode,
		kind = kind,
		position = Quantize.vector(minimumCorner, Quantize.Grid) + size * 0.5,
		size = size,
		rotation = Vector3.zero,
	}
	local component = {
		id = self.nextComponent, name = kind .. " " .. self.nextComponent,
		nodes = { node }, operations = {}, revision = 1,
	}
	self.components[component.id] = component
	table.insert(self.order, component.id)
	return component
end

local function validateTransform(position: Vector3, size: Vector3, rotation: Vector3)
	for _, n in ipairs({
		position.X, position.Y, position.Z, size.X, size.Y, size.Z,
		rotation.X, rotation.Y, rotation.Z,
	}) do
		if not Quantize.isFinite(n) then return false, "Transform must contain finite numbers" end
	end
	if math.max(math.abs(position.X), math.abs(position.Y), math.abs(position.Z)) > Quantize.MaxPosition then
		return false, "Position must be within +/-512 studs"
	end
	if math.min(size.X, size.Y, size.Z) < Quantize.MinSize - 0.00001
		or math.max(size.X, size.Y, size.Z) > Quantize.MaxSize then
		return false, "Size must be between 0.05 and 128 studs"
	end
	return true, nil
end

function Document:editNode(component, index: number, field: string, axis: string?, value: number)
	local node = component.nodes[index]
	if not node then return false, "No node selected" end
	if typeof(value) ~= "number" or not Quantize.isFinite(value) then
		return false, "Enter a finite number"
	end
	if not axis or not AXES[axis] then return false, "Invalid axis" end
	local snapped = Quantize.snap(value, if field == "rotation" then Quantize.Rotation else Quantize.Grid)
	local position, size, rotation = node.position, node.size, node.rotation
	if field == "position" then
		-- Numeric MIN fields edit a boundary coordinate, not the part's center.
		local minimum = withAxis(Document.minCorner(node), axis, snapped)
		position = minimum + halfOffset(size, rotation)
	elseif field == "size" then
		local minimum = Document.minCorner(node)
		size = withAxis(size, axis, snapped)
		if node.kind == "Cylinder" and axis ~= "Y" then
			size = Vector3.new(snapped, size.Y, snapped)
		end
		position = minimum + halfOffset(size, rotation)
	elseif field == "rotation" then
		rotation = withAxis(rotation, axis, snapped % 360)
	else
		return false, "Unknown FORM property"
	end
	local ok, reason = validateTransform(position, size, rotation)
	if not ok then return false, reason end
	node.position, node.size, node.rotation = position, size, rotation
	component.revision += 1
	return true, nil
end

function Document:applyTransform(component, index: number, position: Vector3?, size: Vector3?, rotation: Vector3?, preserveFaceAnchor: boolean?)
	local node = component.nodes[index]
	if not node then return false, "No node selected" end
	local newSize = Quantize.vector(size or node.size, Quantize.Grid)
	local incoming = rotation or node.rotation
	local newRotation = Vector3.new(
		Quantize.snap(incoming.X, Quantize.Rotation) % 360,
		Quantize.snap(incoming.Y, Quantize.Rotation) % 360,
		Quantize.snap(incoming.Z, Quantize.Rotation) % 360
	)
	if node.kind == "Cylinder" then
		local dx = math.abs(newSize.X - node.size.X)
		local dz = math.abs(newSize.Z - node.size.Z)
		local diameter = if dx >= dz then newSize.X else newSize.Z
		newSize = Vector3.new(diameter, newSize.Y, diameter)
	end
	local newPosition = position or node.position
	if position and not preserveFaceAnchor then
		-- Move the *local minimum corner* onto 0.05-grid coordinates,
		-- accounting for half-cell centers of odd-sized envelopes.
		local half = halfOffset(newSize, node.rotation)
		newPosition = Quantize.vector(position - half, Quantize.Grid) + half
	end
	local ok, reason = validateTransform(newPosition, newSize, newRotation)
	if not ok then return false, reason end
	if newPosition ~= node.position or newSize ~= node.size or newRotation ~= node.rotation then
		node.position, node.size, node.rotation = newPosition, newSize, newRotation
		component.revision += 1
	end
	return true, nil
end

-- Fabrication locations are snapped offsets from minimum material edges, so
-- resizing from the opposite face does not unexpectedly move previous cuts.
function Document:addOperation(component, kind: string, data)
	local node = component.nodes[1]
	if node.kind ~= "Block" and node.kind ~= "Cylinder" then
		return false, "This workpiece does not support fabrication"
	end
	local operation
	if kind == "Drill" then
		local diameter = Quantize.snap(data.diameter, Quantize.Grid)
		if not Quantize.isFinite(diameter) or diameter < Quantize.MinSize
			or diameter > Quantize.MaxSize then
			return false, "Drill diameter must be between 0.05 and 128 studs"
		end
		operation = {
			kind = "Drill", diameter = diameter,
			-- Store offsets from the material's minimum X/Z edges.
			x = Quantize.snap(data.x + node.size.X * 0.5, Quantize.Grid),
			z = Quantize.snap(data.z + node.size.Z * 0.5, Quantize.Grid),
		}
	elseif kind == "Saw" then
		local kerf = Quantize.snap(data.kerf, Quantize.Grid)
		local x1, z1 = Quantize.snap(data.x1 + node.size.X * 0.5, Quantize.Grid),
			Quantize.snap(data.z1 + node.size.Z * 0.5, Quantize.Grid)
		local x2, z2 = Quantize.snap(data.x2 + node.size.X * 0.5, Quantize.Grid),
			Quantize.snap(data.z2 + node.size.Z * 0.5, Quantize.Grid)
		if not Quantize.isFinite(kerf) or kerf < Quantize.MinSize
			or kerf > Quantize.MaxSize then return false, "Invalid saw kerf" end
		if (Vector2.new(x2 - x1, z2 - z1)).Magnitude < Quantize.MinSize - 0.00001 then
			return false, "Saw cut must extend at least 0.05 studs"
		end
		operation = {
			kind = "Saw", x1 = x1, z1 = z1, x2 = x2, z2 = z2,
			kerf = kerf, useMesh = data.useMesh == true,
		}
	else
		return false, "Unknown fabrication tool"
	end
	for _, value in pairs(operation) do
		if typeof(value) == "number" and (not Quantize.isFinite(value) or math.abs(value) > 512) then
			return false, "Fabrication coordinate outside allowed bounds"
		end
	end
	self.nextOperation += 1
	operation.id = self.nextOperation
	table.insert(component.operations, operation)
	component.revision += 1
	return true, nil
end

function Document:undoOperation(component)
	if #component.operations == 0 then return false, "No cuts to undo" end
	table.remove(component.operations)
	component.revision += 1
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
	local nodes, operations = {}, {}
	for _, node in ipairs(component.nodes) do table.insert(nodes, table.clone(node)) end
	for _, operation in ipairs(component.operations) do
		table.insert(operations, table.clone(operation))
	end
	return {
		id = component.id, name = component.name,
		revision = component.revision, nodes = nodes, operations = operations,
	}
end

return Document
