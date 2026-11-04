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
	local meshPart: MeshPart? = nil
	local ok, failure = pcall(function()
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
		meshPart = AssetService:CreateMeshPartAsync(Content.fromObject(editable), {})
		local mesh = meshPart
		mesh.Name = "FORM_DisposableMeshSaw"
		mesh.CFrame = cf
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanTouch = false
		mesh.CanQuery = false
	end)
	if not ok or not meshPart then
		if meshPart then meshPart:Destroy() end
		editable:Destroy()
		error(tostring(failure or "No mesh returned"), 0)
	end
	return meshPart, editable
end

-- Returns the cutter and a release callback; release after CSG has finished.
-- Calling release is safe on success OR error, and frees EditableMesh budget.
function Cutters.create(node, operation, preferMesh: boolean?): (BasePart, () -> (), string)
	if operation.kind == "GrooveFace" then
		local a,b=operation.a,operation.b
		local outward=operation.normal.Unit
		local along=b-a
		if along.Magnitude<0.005 then error("Groove direction undefined") end
		local forward=along.Unit
		local right=outward:Cross(forward).Unit
		local back=right:Cross(outward).Unit
		local margin=0.04
		local height=if operation.through then node.size.Magnitude*2+margin*2
			else operation.depth+margin
		local center=(a+b)/2-outward*(height/2-margin)
		local part=nativeCut(operation.width/2,height,along.Magnitude+operation.width,
			CFrame.fromMatrix(center,right,outward,back))
		part.Name="FORM_PlanarGrooveCutter"
		return part,function() part:Destroy() end,"native"
	end
	if operation.kind == "DrillFace" then
		local outward=operation.normal.Unit
		local margin=0.04
		local through=operation.through~=false
		local depth=if through then node.size.Magnitude*2+margin*2
			else operation.depth+margin
		local center=operation.origin-outward*(depth/2-margin)
		local part=Instance.new("Part")
		part.Name="FORM_OrientedDrillCutter"
		part.Shape=Enum.PartType.Cylinder
		part.Size=Vector3.new(depth,operation.diameter,operation.diameter)
		part.CFrame=CFrame.lookAt(center,center-outward)*CFrame.Angles(0,math.pi/2,0)
		part.Color=Color3.new(1,1,1)
		part.Anchored=true
		part.CanCollide=false
		part.CanTouch=false
		part.CanQuery=false
		return part,function() part:Destroy() end,"native"
	end
	if operation.kind == "Drill" then
		local part = Instance.new("Part")
		part.Name = "FORM_DrillCutter"
		part.Shape = Enum.PartType.Cylinder
		local through = operation.through ~= false
		local margin = 0.04
		local depth = if through then node.size.Y + margin * 2
			else math.min(operation.depth or node.size.Y, node.size.Y) + margin
		local y = if through then 0 else node.size.Y / 2 - depth / 2 + margin
		part.Size = Vector3.new(depth, operation.diameter, operation.diameter)
		part.CFrame = CFrame.new(operation.x - node.size.X * 0.5, y, operation.z - node.size.Z * 0.5)
			* CFrame.Angles(0, 0, math.pi / 2)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		return part, function() part:Destroy() end, "native"
	end
	if operation.kind == "Inset" then
		local margin = operation.margin
		local width, length = node.size.X - 2 * margin, node.size.Z - 2 * margin
		local depth = math.min(node.size.Y, operation.depth)
		local top = node.size.Y / 2
		local part = nativeCut(width / 2, depth + 0.04, length,
			CFrame.new(0, top - depth / 2 + 0.02, 0))
		part.Name = "FORM_InsetPocketCutter"
		return part, function() part:Destroy() end, "native"
	end
	if operation.kind ~= "Saw" and operation.kind ~= "Groove" then
		error("Unknown cutter kind " .. tostring(operation.kind))
	end
	local a = Vector3.new(operation.x1 - node.size.X * 0.5, 0, operation.z1 - node.size.Z * 0.5)
	local b = Vector3.new(operation.x2 - node.size.X * 0.5, 0, operation.z2 - node.size.Z * 0.5)
	local delta = b - a
	local length = delta.Magnitude + operation.kerf
	local through = operation.kind == "Saw" or operation.through == true
	local margin = 0.04
	local height = if through then node.size.Y + margin * 2
		else math.min(operation.depth or node.size.Y, node.size.Y) + margin
	local centerY = if through then 0 else node.size.Y / 2 - height / 2 + margin
	local midpoint = (a + b) / 2 + Vector3.new(0, centerY, 0)
	local cf = CFrame.lookAt(midpoint, midpoint + delta)
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
