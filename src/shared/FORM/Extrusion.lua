--!strict
-- Turns a closed planar sketch into one disposable, watertight extrusion mesh.
-- The sketch remains ordinary Vector2 data. EditableMesh only exists during CSG.
local AssetService = game:GetService("AssetService")
local SketchProfile = require(script.Parent.SketchProfile)

local Extrusion = {}

local function heightRange(node, operation): (number, number)
	local half = node.size.Y * 0.5
	local margin = 0.04
	if operation.mode == "Add" then
		return half - margin, half + operation.depth
	elseif operation.mode == "Remove" and not operation.through then
		return half - operation.depth, half + margin
	end
	-- Through cuts and intersect operations cover the whole source body.
	return -half - margin, half + margin
end

function Extrusion.create(node, operation): (MeshPart, () -> ())
	local points, triangles, errorMessage = SketchProfile.prepare(operation.points)
	if not points or not triangles then error(errorMessage or "Invalid sketch", 0) end
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, point in ipairs(points) do
		minX, maxX = math.min(minX, point.X), math.max(maxX, point.X)
		minZ, maxZ = math.min(minZ, point.Y), math.max(maxZ, point.Y)
	end
	local minY, maxY = heightRange(node, operation)
	-- SketchEditor:projectMouse() produces coordinates relative to the
	-- component's CENTER, as does SketchBodyProfile. The previous extra
	-- -node.size.X/2 and -node.size.Z/2 translation shifted every Boolean
	-- cutter toward a corner, corrupting the cut and its preview.
	local center = Vector3.new(
		(minX + maxX) / 2,
		(minY + maxY) / 2,
		(minZ + maxZ) / 2
	)
	local editable: EditableMesh? = nil
	local meshPart: MeshPart? = nil
	local ok, reason = pcall(function()
		editable = AssetService:CreateEditableMesh()
		if not editable then error("EditableMesh allocation unavailable (budget or permissions)") end
		local bottom = {}
		local top = {}
		for _, p in ipairs(points) do
			local x = p.X - (minX + maxX) / 2
			local z = p.Y - (minZ + maxZ) / 2
			table.insert(bottom, editable:AddVertex(Vector3.new(x, minY - center.Y, z)))
			table.insert(top, editable:AddVertex(Vector3.new(x, maxY - center.Y, z)))
		end
		-- Keep each face's appearance explicit. Roblox reuses corner normals and
		-- color IDs by default; shared cap/side normals produced dark, smoothed
		-- shading on the intentionally sharp edges of extruded sketches.
		local white = editable:AddColor(Color3.new(1, 1, 1), 1)
		local up = editable:AddNormal(Vector3.yAxis)
		local down = editable:AddNormal(-Vector3.yAxis)
		local function triangle(a: number, b: number, c: number, normalId: number)
			local faceId = editable:AddTriangle(a, b, c)
			editable:SetFaceNormals(faceId, { normalId, normalId, normalId })
			editable:SetFaceColors(faceId, { white, white, white })
		end
		-- Positive winding in X/Z has a -Y normal in Roblox world space.
		for _, indices in ipairs(triangles) do
			local a, b, c = indices[1], indices[2], indices[3]
			triangle(top[a], top[c], top[b], up)
			triangle(bottom[a], bottom[b], bottom[c], down)
		end
		for i = 1, #points do
			local nextIndex = i % #points + 1
			local direction = points[nextIndex] - points[i]
			local outward = Vector3.new(direction.Y, 0, -direction.X).Unit
			local sideNormal = editable:AddNormal(outward)
			-- Both triangles on each side share the same hard/flat normal.
			triangle(bottom[i], top[i], top[nextIndex], sideNormal)
			triangle(bottom[i], top[nextIndex], bottom[nextIndex], sideNormal)
		end
		meshPart = AssetService:CreateMeshPartAsync(Content.fromObject(editable), {
			CollisionFidelity = Enum.CollisionFidelity.Hull,
		})
		if not meshPart then error("EditableMesh conversion returned no MeshPart") end
		meshPart.Name = "FORM_DisposableProfileExtrusion"
		meshPart.Color = Color3.new(1, 1, 1)
		meshPart.Material = Enum.Material.SmoothPlastic
		meshPart.TextureID = ""
		meshPart.Transparency = 0
		meshPart.Reflectance = 0
		meshPart.Anchored = true
		meshPart.CanCollide = false
		meshPart.CanTouch = false
		meshPart.CanQuery = false
		meshPart.CFrame = CFrame.new(center)
	end)
	if not ok or not editable or not meshPart then
		if meshPart then meshPart:Destroy() end
		if editable then editable:Destroy() end
		error("Profile extrusion failed: " .. tostring(reason), 0)
	end
	local disposed = false
	return meshPart, function()
		if disposed then return end
		disposed = true
		meshPart:Destroy()
		editable:Destroy()
	end
end

return Extrusion
