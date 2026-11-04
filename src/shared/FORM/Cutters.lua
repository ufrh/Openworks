--!strict
-- Temporary manufacturing cutters. Native drilling is cheap; straight saw cuts
-- may use a disposable watertight EditableMesh with automatic native fallback.
local AssetService = game:GetService("AssetService")

local Cutters = {}

local function nativeCut(halfWidth: number, height: number, length: number, cf: CFrame): Part
	local part = Instance.new("Part")
	part.Name = "FORM_NativeSawCutter"
	part.Size = Vector3.new(halfWidth * 2, height, length)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CFrame = cf
	return part
end

local function generatedSaw(width: number, height: number, length: number, cf: CFrame): (MeshPart, EditableMesh)
	local editable = AssetService:CreateEditableMesh()
	if not editable then error("EditableMesh memory budget exhausted") end
	local ok, meshPart = pcall(function()
		local hx, hy, hz = width * 0.5, height * 0.5, length * 0.5
		local vertices = {}
		for _, v in ipairs({
			Vector3.new(-hx, -hy, -hz), Vector3.new(hx, -hy, -hz),
			Vector3.new(hx, hy, -hz), Vector3.new(-hx, hy, -hz),
			Vector3.new(-hx, -hy, hz), Vector3.new(hx, -hy, hz),
			Vector3.new(hx, hy, hz), Vector3.new(-hx, hy, hz),
		}) do
			table.insert(vertices, editable:AddVertex(v))
		end
		-- 12 outward-facing triangles forming a closed rectangular tool volume.
		for _, face in ipairs({
			{1,3,2}, {1,4,3}, {5,6,7}, {5,7,8},
			{1,5,8}, {1,8,4}, {2,3,7}, {2,7,6},
			{1,2,6}, {1,6,5}, {4,8,7}, {4,7,3},
		}) do
			editable:AddTriangle(vertices[face[1]], vertices[face[2]], vertices[face[3]])
		end
		return AssetService:CreateMeshPartAsync(Content.fromObject(editable), {})
	end)
	if not ok or not meshPart then
		editable:Destroy()
		error(tostring(meshPart), 0)
	end
	meshPart.Name = "FORM_DisposableMeshSaw"
	meshPart.CFrame = cf
	meshPart.Anchored = true
	meshPart.CanCollide = false
	meshPart.CanTouch = false
	meshPart.CanQuery = false
	return meshPart, editable
end

-- Returns the cutter and a release callback; release after CSG has finished.
-- Calling release is safe on success OR error, and frees EditableMesh budget.
function Cutters.create(node, operation, preferMesh: boolean?): (BasePart, () -> (), string)
	if operation.kind == "Drill" then
		local part = Instance.new("Part")
		part.Name = "FORM_DrillCutter"
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(node.size.Y + 1, operation.diameter, operation.diameter)
		part.CFrame = CFrame.new(operation.x - node.size.X * 0.5, 0, operation.z - node.size.Z * 0.5)
			* CFrame.Angles(0, 0, math.pi / 2)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		return part, function() part:Destroy() end, "native"
	end
	if operation.kind ~= "Saw" then error("Unknown cutter kind " .. tostring(operation.kind)) end
	local a = Vector3.new(operation.x1 - node.size.X * 0.5, 0, operation.z1 - node.size.Z * 0.5)
	local b = Vector3.new(operation.x2 - node.size.X * 0.5, 0, operation.z2 - node.size.Z * 0.5)
	local delta = b - a
	local length = delta.Magnitude + operation.kerf
	local height = node.size.Y + 1
	local cf = CFrame.lookAt((a + b) * 0.5, (a + b) * 0.5 + delta)
	if preferMesh then
		local ok, part, editable = pcall(generatedSaw, operation.kerf, height, length, cf)
		if ok and part and editable then
			return part, function()
				part:Destroy()
				editable:Destroy()
			end, "editable"
		end
		-- Failure due to budget, permissions, or mesh beta: a native box is
		-- geometrically equivalent for a straight saw kerf.
	end
	local part = nativeCut(operation.kerf * 0.5, height, length, cf)
	return part, function() part:Destroy() end, "native"
end

return Cutters
