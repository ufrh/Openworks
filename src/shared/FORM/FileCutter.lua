--!strict
-- Temporary CSG triangular-prism cutter for straight upper perimeter chamfers.
-- This deliberately supports only the four unambiguous stock-envelope edges;
-- arbitrary generated CSG edges need a proper edge reference system later.
local AssetService = game:GetService("AssetService")
local SketchProfile = require(script.Parent.SketchProfile)
local FileCutter = {}

function FileCutter.create(node, operation): (MeshPart, () -> ())
	if node.kind ~= "Block" then error("File only supports block stock") end
	local edge: string = operation.edge
	local w: number = operation.width
	local hx, hy, hz = node.size.X / 2, node.size.Y / 2, node.size.Z / 2
	local margin = 0.04
	local alongX = string.sub(edge, 1, 1) == "X"
	local sign = if string.sub(edge, 2, 2) == "+" then 1 else -1
	local origin = if alongX then Vector3.new(sign * hx, hy, 0)
		else Vector3.new(0, hy, sign * hz)
	local inward = if alongX then Vector3.new(-sign, 0, 0)
		else Vector3.new(0, 0, -sign)
	local downward = Vector3.new(0, -1, 0)
	local tangent = if alongX then Vector3.zAxis else Vector3.xAxis
	local halfLength = if alongX then hz + margin else hx + margin
	-- The exact diagonal u+v=w is the final chamfer surface. The rest
	-- extends slightly outside stock to avoid coplanar Boolean seams.
	local profile = {
		Vector2.new(-margin, -margin),
		Vector2.new(w + margin, -margin),
		Vector2.new(w, 0),
		Vector2.new(0, w),
		Vector2.new(-margin, w + margin),
	}
	local points, triangles, reason = SketchProfile.prepare(profile)
	if not points or not triangles then error(reason or "Invalid edge profile") end

	local positions = {}
	local function pointAt(p: Vector2, t: number): Vector3
		return origin + inward * p.X + downward * p.Y + tangent * t
	end
	for _, p in ipairs(points) do
		table.insert(positions, pointAt(p, -halfLength))
		table.insert(positions, pointAt(p, halfLength))
	end
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(positions) do
		low = Vector3.new(math.min(low.X, p.X), math.min(low.Y, p.Y), math.min(low.Z, p.Z))
		high = Vector3.new(math.max(high.X, p.X), math.max(high.Y, p.Y), math.max(high.Z, p.Z))
	end
	local center = (low + high) / 2
	local editable: EditableMesh? = nil
	local part: MeshPart? = nil
	local ok, failure = pcall(function()
		editable = AssetService:CreateEditableMesh()
		if not editable then error("EditableMesh allocation unavailable") end
		local white = editable:AddColor(Color3.new(1, 1, 1), 1)
		local verts = {}
		for _, p in ipairs(positions) do
			table.insert(verts, editable:AddVertex(p - center))
		end
		local function face(a: number, b: number, c: number)
			local av, bv, cv = positions[a], positions[b], positions[c]
			local cross = (bv-av):Cross(cv-av)
			if cross.Magnitude < 0.00000001 then return end
			local normal = editable:AddNormal(cross.Unit)
			local fid = editable:AddTriangle(verts[a], verts[b], verts[c])
			editable:SetFaceNormals(fid, { normal, normal, normal })
			editable:SetFaceColors(fid, { white, white, white })
		end
		-- Which cap winds outward depends on the signed orientation of the
		-- inward/down axes and the chosen tangent direction.
		local positive = inward:Cross(downward):Dot(tangent) > 0
		for _, tri in ipairs(triangles) do
			local a,b,c = tri[1],tri[2],tri[3]
			if positive then
				face(2*a, 2*b, 2*c)
				face(2*a-1, 2*c-1, 2*b-1)
			else
				face(2*a, 2*c, 2*b)
				face(2*a-1, 2*b-1, 2*c-1)
			end
		end
		for i=1,#points do
			local j = i % #points + 1
			if positive then
				face(2*i-1, 2*j-1, 2*j)
				face(2*i-1, 2*j, 2*i)
			else
				face(2*i-1, 2*j, 2*j-1)
				face(2*i-1, 2*i, 2*j)
			end
		end
		part = AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
			CollisionFidelity = Enum.CollisionFidelity.Hull,
		})
		if not part then error("Could not convert edge file to MeshPart") end
		part.Name = "FORM_DisposableEdgeFile"
		part.Color = Color3.new(1, 1, 1)
		part.Material = Enum.Material.SmoothPlastic
		part.TextureID = ""
		part.CFrame = CFrame.new(center)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end)
	if not ok or not part or not editable then
		if part then part:Destroy() end
		if editable then editable:Destroy() end
		error("Edge file cutter failed: " .. tostring(failure), 0)
	end
	local disposed = false
	return part, function()
		if disposed then return end
		disposed = true
		part:Destroy()
		editable:Destroy()
	end
end

return FileCutter
