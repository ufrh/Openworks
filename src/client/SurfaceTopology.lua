--!strict
-- Reconstruct selectable CAD faces/crease edges from the CURRENT compiled mesh,
-- never from its source stock envelope. Ephemeral EditableMesh is read once per
-- preview revision and destroyed; world points are resolved using part frame.
local AssetService = game:GetService("AssetService")
local SurfaceTopology = {}
local EPS = 0.0005
local COPLANAR = 0.993

local function rounded(p: Vector3): string
	return string.format("%d,%d,%d",
		math.round(p.X / EPS), math.round(p.Y / EPS), math.round(p.Z / EPS))
end
local function edgeKey(a: number, b: number): string
	return if a < b then tostring(a)..":"..tostring(b) else tostring(b)..":"..tostring(a)
end

function SurfaceTopology.extract(part: BasePart)
	local ok, mesh = pcall(function()
		return AssetService:CreateEditableMeshAsync(Content.fromObject(part), {FixedSize = true})
	end)
	if not ok or not mesh then return nil, tostring(mesh) end
	local success, topology = pcall(function()
		local size = mesh:GetSize()
		local scale = Vector3.new(
			if size.X > 1e-7 then part.Size.X / size.X else 1,
			if size.Y > 1e-7 then part.Size.Y / size.Y else 1,
			if size.Z > 1e-7 then part.Size.Z / size.Z else 1)
		local center = mesh:GetCenter()
		local welded, vertices, ids, triangles = {}, {}, {}, {}
		for _, faceId in ipairs(mesh:GetFaces()) do
			local indices = mesh:GetFaceVertices(faceId)
			if #indices ~= 3 then continue end
			local tri = {}
			for _, id in ipairs(indices) do
				if ids[id] == nil then
					local p = mesh:GetPosition(id)
					local localPoint = Vector3.new((p.X-center.X)*scale.X,
						(p.Y-center.Y)*scale.Y,(p.Z-center.Z)*scale.Z)
					local key = rounded(localPoint)
					if not welded[key] then
						table.insert(vertices, localPoint)
						welded[key] = #vertices
					end
					ids[id] = welded[key]
				end
				table.insert(tri, ids[id])
			end
			local a,b,c = vertices[tri[1]],vertices[tri[2]],vertices[tri[3]]
			local cross = (b-a):Cross(c-a)
			if cross.Magnitude > 1e-9 then
				table.insert(triangles, {v=tri, normal=cross.Unit})
			end
		end
		if #triangles == 0 then error("Compiled mesh has no readable triangles") end
		local incidences = {}
		for index, tri in ipairs(triangles) do
			local v = tri.v
			for i=1,3 do
				local a,b=v[i],v[i%3+1]
				local key=edgeKey(a,b)
				if not incidences[key] then incidences[key]={a=a,b=b,triangles={}} end
				table.insert(incidences[key].triangles,index)
			end
		end
		-- Connected triangle islands of the same supporting plane become a
		-- logical CAD face. Use geometric plane offset as well as normals.
		local adjacency = {}
		for i=1,#triangles do adjacency[i]={} end
		for _, edge in pairs(incidences) do
			if #edge.triangles == 2 then
				local i,j=edge.triangles[1],edge.triangles[2]
				local ta,tb=triangles[i],triangles[j]
				if ta.normal:Dot(tb.normal)>COPLANAR and
					math.abs((vertices[tb.v[1]]-vertices[ta.v[1]]):Dot(ta.normal))<0.002 then
					table.insert(adjacency[i],j)
					table.insert(adjacency[j],i)
				end
			end
		end
		local faceByTriangle, faces = {}, {}
		for i,tri in ipairs(triangles) do
			if faceByTriangle[i] then continue end
			local fid=#faces+1
			local face={id=fid,normal=tri.normal,triangles={},edges={},vertices={}}
			table.insert(faces,face)
			local queue={i}
			faceByTriangle[i]=fid
			local head=1
			while head<=#queue do
				local t=queue[head]
				head+=1
				table.insert(face.triangles,t)
				for _,n in ipairs(adjacency[t]) do
					if not faceByTriangle[n] then
						faceByTriangle[n]=fid
						table.insert(queue,n)
					end
				end
			end
		end
		local edges={}
		for _, e in pairs(incidences) do
			local adjacent={}
			for _,i in ipairs(e.triangles) do
				local f=faceByTriangle[i]
				if not table.find(adjacent,f) then table.insert(adjacent,f) end
			end
			if #adjacent == 1 and #e.triangles == 2 then continue end
			if #adjacent == 1 and #e.triangles == 1 then
				-- Open meshes are not suitable for Boolean-based fabrication.
				continue
			end
			if #adjacent < 2 then continue end
			local a,b=vertices[e.a],vertices[e.b]
			if (b-a).Magnitude<EPS then continue end
			local edge={a=a,b=b,faces=adjacent}
			table.insert(edges,edge)
			for _,f in ipairs(adjacent) do table.insert(faces[f].edges,edge) end
		end
		for _, face in ipairs(faces) do
			local boundary={}
			for _,edge in ipairs(face.edges) do
				boundary[rounded(edge.a)]=edge.a
				boundary[rounded(edge.b)]=edge.b
			end
			for _,p in pairs(boundary) do table.insert(face.vertices,p) end
		end
		return {vertices=vertices,triangles=triangles,faces=faces,edges=edges,
			part=part, revision=part}
	end)
	mesh:Destroy()
	if not success then return nil, tostring(topology) end
	return topology
end

local function closestOnSegment(p: Vector3,a: Vector3,b: Vector3): (number,Vector3)
	local d=b-a
	local t=math.clamp((p-a):Dot(d)/math.max(d:Dot(d),1e-12),0,1)
	local q=a+d*t
	return (p-q).Magnitude,q
end

function SurfaceTopology.closestEdge(topology, worldHit: Vector3, worldNormal: Vector3,
	camera: Camera, mouse: Vector2, maxPixels: number?)
	local candidate,bestPixels=nil,maxPixels or 18
	for _,edge in ipairs(topology.edges) do
		local a=topology.part.CFrame:PointToWorldSpace(edge.a)
		local b=topology.part.CFrame:PointToWorldSpace(edge.b)
		local ap,onScreenA=camera:WorldToViewportPoint(a)
		local bp,onScreenB=camera:WorldToViewportPoint(b)
		if onScreenA or onScreenB then
			local delta=Vector2.new(bp.X-ap.X,bp.Y-ap.Y)
			local t=math.clamp((mouse-Vector2.new(ap.X,ap.Y)):Dot(delta)/
				math.max(delta:Dot(delta),1e-8),0,1)
			local screenDistance=(mouse-(Vector2.new(ap.X,ap.Y)+delta*t)).Magnitude
			if screenDistance<bestPixels then
				local _,q=closestOnSegment(worldHit,a,b)
				-- Face-adjacency check avoids selecting edges behind
				-- unrelated surfaces.
				if (q-worldHit).Magnitude<0.25 then
					bestPixels=screenDistance
					candidate=edge
				end
			end
		end
	end
	return candidate
end

function SurfaceTopology.faceAt(topology, hitPoint: Vector3, hitNormal: Vector3)
	local localPoint=topology.part.CFrame:PointToObjectSpace(hitPoint)
	local localNormal=topology.part.CFrame:VectorToObjectSpace(hitNormal)
	local best,bestError=nil,math.huge
	for _,face in ipairs(topology.faces) do
		local first=topology.triangles[face.triangles[1]]
		local origin=topology.vertices[first.v[1]]
		local error=math.abs((localPoint-origin):Dot(face.normal))
		if face.normal:Dot(localNormal)>0.90 and error<bestError then
			best,bestError=face,error
		end
	end
	if bestError>0.035 then return nil end
	return best
end

return SurfaceTopology
