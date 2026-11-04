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

local function nativeBlock(part:Part)
	local h=part.Size/2
	local vertices={
		Vector3.new(-h.X,-h.Y,-h.Z),Vector3.new(h.X,-h.Y,-h.Z),
		Vector3.new(h.X,h.Y,-h.Z),Vector3.new(-h.X,h.Y,-h.Z),
		Vector3.new(-h.X,-h.Y,h.Z),Vector3.new(h.X,-h.Y,h.Z),
		Vector3.new(h.X,h.Y,h.Z),Vector3.new(-h.X,h.Y,h.Z),
	}
	-- These are the six actual planar faces of this uncut native Part.
	local specs={
		{normal=Vector3.yAxis,ring={4,3,7,8}},
		{normal=-Vector3.yAxis,ring={1,5,6,2}},
		{normal=Vector3.xAxis,ring={2,6,7,3}},
		{normal=-Vector3.xAxis,ring={1,4,8,5}},
		{normal=Vector3.zAxis,ring={5,8,7,6}},
		{normal=-Vector3.zAxis,ring={1,2,3,4}},
	}
	local faces,edges,triangles={}, {}, {}
	local shared={}
	for fi,spec in ipairs(specs) do
		local face={id=fi,normal=spec.normal,edges={},triangles={},vertices={}}
		table.insert(faces,face)
		for _,v in ipairs(spec.ring) do table.insert(face.vertices,vertices[v]) end
		for _,indices in ipairs({
			{spec.ring[1],spec.ring[2],spec.ring[3]},
			{spec.ring[1],spec.ring[3],spec.ring[4]},
		}) do
			table.insert(triangles,{v=indices,normal=spec.normal})
			table.insert(face.triangles,#triangles)
		end
		for i=1,4 do
			local a,b=spec.ring[i],spec.ring[i%4+1]
			local key=edgeKey(a,b)
			if not shared[key] then
				shared[key]={a=vertices[a],b=vertices[b],faces={}}
				table.insert(edges,shared[key])
			end
			table.insert(shared[key].faces,fi)
			table.insert(face.edges,shared[key])
		end
	end
	return setmetatable({vertices=vertices,triangles=triangles,faces=faces,edges=edges,part=part,revision=part}, {__index=SurfaceTopology})
end

function SurfaceTopology.extract(part: BasePart)
	if part:IsA("Part") and part.Shape==Enum.PartType.Block then
		return nativeBlock(part)
	end
	if not part:IsA("MeshPart") then return nil, "Surface selection requires a block or readable compiled MeshPart" end
	local okContent, contentOrError = pcall(function()
		return (part :: MeshPart).MeshContent
	end)
	if not okContent then
		return nil, "MeshContent inaccessible: " .. tostring(contentOrError)
	end
	local ok, mesh = pcall(function()
		return AssetService:CreateEditableMeshAsync(contentOrError, {FixedSize = true})
	end)
	if not ok or not mesh then
		return nil, "CreateEditableMeshAsync failed on " .. part.ClassName .. ": " ..
			tostring(mesh) .. " (CSG output may not support EditableMesh readback)"
	end
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
						-- Check against the seed plane, not just the
						-- preceding triangle: otherwise a curved surface
						-- can slowly chain into a fake planar CAD face.
						local neighbor=triangles[n]
						local seed=triangles[i]
						local seedOrigin=vertices[seed.v[1]]
						local neighborOrigin=vertices[neighbor.v[1]]
						if neighbor.normal:Dot(seed.normal)>COPLANAR
							and math.abs((neighborOrigin-seedOrigin):Dot(seed.normal))<0.002 then
							faceByTriangle[n]=fid
							table.insert(queue,n)
						end
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
		-- Collapse collinear tessellation fragments into full mechanical
		-- edges when they share exactly the same adjacent CAD faces.
		-- An edge from a CSG mesh can otherwise be only one tiny triangle
		-- side instead of the full shaft/housing perimeter.
		local changed=true
		while changed and #edges<=1500 do
			changed=false
			local endpoints={}
			for index,edge in ipairs(edges) do
				for _,p in ipairs({edge.a,edge.b}) do
					local key=rounded(p)
					if not endpoints[key] then endpoints[key]={} end
					table.insert(endpoints[key],index)
				end
			end
			for _,indices in pairs(endpoints) do
				if #indices~=2 then continue end
				local ai,bi=indices[1],indices[2]
				local a,b=edges[ai],edges[bi]
				if not a or not b or #a.faces~=2 or #b.faces~=2 then continue end
				if not (table.find(b.faces,a.faces[1]) and
					table.find(b.faces,a.faces[2])) then continue end
				local shared
				if (a.a-b.a).Magnitude<EPS or (a.a-b.b).Magnitude<EPS then shared=a.a
				elseif (a.b-b.a).Magnitude<EPS or (a.b-b.b).Magnitude<EPS then shared=a.b end
				if not shared then continue end
				local oa=if (a.a-shared).Magnitude<EPS then a.b else a.a
				local ob=if (b.a-shared).Magnitude<EPS then b.b else b.a
				local v1,v2=oa-shared,ob-shared
				if v1.Magnitude<EPS or v2.Magnitude<EPS or
					v1.Unit:Dot(v2.Unit)>-0.9995 then continue end
				local merged={a=oa,b=ob,faces=a.faces}
				local hi,lo=math.max(ai,bi),math.min(ai,bi)
				table.remove(edges,hi)
				table.remove(edges,lo)
				table.insert(edges,merged)
				changed=true
				break
			end
		end
		for _,face in ipairs(faces) do
			table.clear(face.edges)
			table.clear(face.vertices)
		end
		for _,edge in ipairs(edges) do
			for _,fid in ipairs(edge.faces) do
				table.insert(faces[fid].edges,edge)
			end
		end
		for _, face in ipairs(faces) do
			local boundary={}
			for _,edge in ipairs(face.edges) do
				boundary[rounded(edge.a)]=edge.a
				boundary[rounded(edge.b)]=edge.b
			end
			for _,p in pairs(boundary) do table.insert(face.vertices,p) end
		end
		return setmetatable({vertices=vertices,triangles=triangles,faces=faces,edges=edges,
			part=part, revision=part}, {__index=SurfaceTopology})
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

local function containsTriangle(p:Vector3,a:Vector3,b:Vector3,c:Vector3):boolean
	local u=b-a
	local v=c-a
	local w=p-a
	local uu,uv,vv=u:Dot(u),u:Dot(v),v:Dot(v)
	local wu,wv=w:Dot(u),w:Dot(v)
	local determinant=uu*vv-uv*uv
	if determinant<1e-12 then return false end
	local t=(wu*vv-wv*uv)/determinant
	local s=(wv*uu-wu*uv)/determinant
	return t>=-0.004 and s>=-0.004 and t+s<=1.004
end

function SurfaceTopology.faceAt(topology,hitPoint:Vector3,hitNormal:Vector3)
	local localPoint=topology.part.CFrame:PointToObjectSpace(hitPoint)
	local localNormal=topology.part.CFrame:VectorToObjectSpace(hitNormal)
	local best,bestError=nil,math.huge
	for _,face in ipairs(topology.faces) do
		if face.normal:Dot(localNormal)<0.90 then continue end
		local first=topology.triangles[face.triangles[1]]
		local origin=topology.vertices[first.v[1]]
		local error=math.abs((localPoint-origin):Dot(face.normal))
		if error>0.035 or error>=bestError then continue end
		local projected=localPoint-face.normal*((localPoint-origin):Dot(face.normal))
		for _,index in ipairs(face.triangles) do
			local tri=topology.triangles[index]
			local a,b,c=topology.vertices[tri.v[1]],
				topology.vertices[tri.v[2]],topology.vertices[tri.v[3]]
			if containsTriangle(projected,a,b,c) then
				best,bestError=face,error
				break
			end
		end
	end
	return best
end

return SurfaceTopology
