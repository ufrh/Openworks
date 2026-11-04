--!strict
-- Pure, in-memory editable construction definitions. No CSG or UI dependencies.
local Quantize = require(script.Parent.Quantize)

local Document = {}
Document.__index = Document

local KINDS = { Block = true, Cylinder = true, Tube = true, HoleBlock = true }
local AXES = { X = true, Y = true, Z = true }

local function defaultSize(kind: string): Vector3
	if kind == "Cylinder" then return Vector3.new(2, 3, 2) end
	if kind == "Tube" then return Vector3.new(2, 3, 2) end
	return Vector3.new(4, 2, 4)
end

local function validNode(node)
	if node.kind == "Tube" then
		local diameter = node.size.X
		if diameter < Quantize.MinSize * 3 then
			return false, "Tube diameter must be at least 0.15 studs"
		end
		if node.wall < Quantize.MinSize or node.wall * 2 + Quantize.MinSize > diameter + 0.00001 then
			return false, "Tube wall leaves less than 0.05 studs of opening"
		end
	elseif node.kind == "HoleBlock" then
		local limit = math.min(node.size.X, node.size.Z)
		if node.bore < Quantize.MinSize or node.bore + Quantize.MinSize * 2 > limit + 0.00001 then
			return false, "Hole needs 0.05 studs of material on each side"
		end
	end
	return true, nil
end

function Document.new()
	return setmetatable({ components = {}, order = {}, nextComponent = 0, nextNode = 0 }, Document)
end

function Document:addNode(component, operation: string, kind: string, position: Vector3?)
	assert(KINDS[kind], "Unknown FORM primitive: " .. tostring(kind))
	assert(operation == "Add" or operation == "Subtract", "Unknown CSG operation")
	assert(operation == "Add" or #component.nodes > 0, "The first node must be additive")

	self.nextNode += 1
	local node = {
		id = self.nextNode,
		kind = kind,
		operation = operation,
		position = Quantize.vector(position or Vector3.new(0, 3, 0), Quantize.Grid),
		size = defaultSize(kind),
		rotation = Vector3.zero,
		bore = 1,
		wall = 0.25,
	}
	table.insert(component.nodes, node)
	component.revision += 1
	return node
end

function Document:create(kind: string, position: Vector3)
	self.nextComponent += 1
	local id = self.nextComponent
	local component = {
		id = id,
		name = kind .. " " .. id,
		nodes = {},
		revision = 0,
	}
	self.components[id] = component
	table.insert(self.order, id)
	self:addNode(component, "Add", kind, position)
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

function Document:deleteNode(component, index: number)
	if index <= 1 then return false, "Keep the first additive node; delete the component instead" end
	if not component.nodes[index] then return false, "No node at that index" end
	table.remove(component.nodes, index)
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
	local nodes = {}
	for _, node in ipairs(component.nodes) do
		table.insert(nodes, table.clone(node))
	end
	return { id = component.id, name = component.name, revision = component.revision, nodes = nodes }
end

return Document
