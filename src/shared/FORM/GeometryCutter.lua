--!strict
-- Build watertight CSG cutters from arbitrary plane loops. Face/edge tools
-- use current compiled geometry; an EditableMesh is never retained in history.
local AssetService = game:GetService("AssetService")
local BevelJunction = require(script.Parent.BevelJunction)
local GeometryCutter = {}

-- Ear-clips arbitrary simple planar cutter contours. This lets a face inset
-- follow a non-convex manufactured outline instead of fan-filling across it.
local function triangulate(profile:{Vector3},travel:Vector3):{{number}}
	local origin=profile[1]
	local u=(profile[2]-origin).Unit
	local v=travel.Unit:Cross(u).Unit
	local points={}
	for _,p in ipairs(profile) do
		local d=p-origin
		table.insert(points,Vector2.new(d:Dot(u),d:Dot(v)))
	end
	local remaining={}
	for i=1,#points do table.insert(remaining,i) end
	local function cross(a:Vector2,b:Vector2,c:Vector2):number
		local ab,ac=b-a,c-a
		return ab.X*ac.Y-ab.Y*ac.X
	end
	local function contains(p:Vector2,a:Vector2,b:Vector2,c:Vector2):boolean
		return cross(a,b,p)>=-1e-9 and cross(b,c,p)>=-1e-9
			and cross(c,a,p)>=-1e-9
	end
	local triangles={}
	while #remaining>3 do
		local found=false
		for slot=1,#remaining do
			local ai=remaining[(slot-2)%#remaining+1]
			local bi=remaining[slot]
			local ci=remaining[slot%#remaining+1]
			local a,b,c=points[ai],points[bi],points[ci]
			if cross(a,b,c)<=1e-9 then continue end
			local occupied=false
			for _,index in ipairs(remaining) do
				if index~=ai and index~=bi and index~=ci
					and contains(points[index],a,b,c) then
					occupied=true break
				end
			end
			if not occupied then
				table.insert(triangles,{ai,bi,ci})
				table.remove(remaining,slot)
				found=true
				break
			end
		end
		if not found then error("Inset cutter polygon cannot be triangulated") end
	end
	table.insert(triangles,{remaining[1],remaining[2],remaining[3]})
	return triangles
end

function GeometryCutter.prism(profile: {Vector3}, travel: Vector3): (MeshPart, () -> ())
	if #profile < 3 or #profile > 128 or travel.Magnitude < 0.0001 then
		error("Invalid geometry cutter profile", 0)
	end
	-- Ensure cap winding agrees with the extrusion direction.
	local winding = (profile[2]-profile[1]):Cross(profile[3]-profile[1]):Dot(travel)
	if math.abs(winding) < 1e-9 then error("Cutter profile is degenerate",0) end
	if winding < 0 then
		local reversed={}
		for i=#profile,1,-1 do table.insert(reversed,profile[i]) end
		profile=reversed
	end
	local capTriangles=triangulate(profile,travel)
	local editable: EditableMesh? = nil
	local part: MeshPart? = nil
	local ok, failure = pcall(function()
		editable = AssetService:CreateEditableMesh()
		if not editable then error("EditableMesh allocation unavailable") end
		-- MeshPart placement must use the actual AABB center, not the
		-- polygon's vertex centroid. Asymmetric triangles otherwise acquire
		-- offsets when converted to CSG mesh parts.
		local minBounds=Vector3.new(math.huge,math.huge,math.huge)
		local maxBounds=Vector3.new(-math.huge,-math.huge,-math.huge)
		for _,p in ipairs(profile) do
			for _,v in ipairs({p,p+travel}) do
				minBounds=Vector3.new(math.min(minBounds.X,v.X),
					math.min(minBounds.Y,v.Y),math.min(minBounds.Z,v.Z))
				maxBounds=Vector3.new(math.max(maxBounds.X,v.X),
					math.max(maxBounds.Y,v.Y),math.max(maxBounds.Z,v.Z))
			end
		end
		local center=(minBounds+maxBounds)/2
		local low, high = {}, {}
		for _,p in ipairs(profile) do
			table.insert(low, editable:AddVertex(p - center))
			table.insert(high, editable:AddVertex(p + travel - center))
		end
		local white = editable:AddColor(Color3.new(1, 1, 1),1)
		local function triangle(a:number,b:number,c:number)
			local face = editable:AddTriangle(a,b,c)
			local p,q,r = editable:GetPosition(a),editable:GetPosition(b),editable:GetPosition(c)
			local cross = (q-p):Cross(r-p)
			if cross.Magnitude>1e-9 then
				local normal = editable:AddNormal(cross.Unit)
				editable:SetFaceNormals(face,{normal,normal,normal})
			end
			editable:SetFaceColors(face,{white,white,white})
		end
		-- Contour-aware triangulation: no fan across a concave opening.
		for _,ids in ipairs(capTriangles) do
			local a,b,c=ids[1],ids[2],ids[3]
			triangle(low[a],low[c],low[b])
			triangle(high[a],high[b],high[c])
		end
		for i=1,#low do
			local j=i%#low+1
			triangle(low[i],high[j],high[i])
			triangle(low[i],low[j],high[j])
		end
		part=AssetService:CreateMeshPartAsync(Content.fromObject(editable),{
			CollisionFidelity=Enum.CollisionFidelity.Hull,
		})
		if not part then error("CSG cutter mesh creation returned nil") end
		part.Name="FORM_DisposableSurfaceCutter"
		part.CFrame=CFrame.new(center)
		part.Material=Enum.Material.SmoothPlastic
		part.Color=Color3.new(1,1,1)
		part.TextureID=""
		part.Anchored=true
		part.CanCollide=false
		part.CanTouch=false
		part.CanQuery=false
	end)
	if not ok or not part or not editable then
		if part then part:Destroy() end
		if editable then editable:Destroy() end
		error("Surface cutter creation failed: "..tostring(failure),0)
	end
	local done=false
	return part,function()
		if done then return end
		done=true
		part:Destroy()
		editable:Destroy()
	end
end

-- A chamfer is different on convex and re-entrant edges:
--   convex: SUBTRACT the outside corner of the existing body
--   concave: UNION a triangular bridge into the empty inside corner
-- Both operations make one flat bevel between two face points `width`
-- away from the edge. Subtracting a wedge from a concave corner instead
-- makes a hidden cavity / self-intersection, not an interior bevel.
--
-- This method expects an authored straight edge shared by exactly two
-- planar faces. It refuses inconsistent frames and extreme angles rather
-- than creating the huge malformed cutter triangles seen in the prototype.
local function bevelPlan(edgeA:Vector3,edgeB:Vector3,
	outwardA:Vector3,outwardB:Vector3,width:number,interior:boolean?)
	if typeof(edgeA)~="Vector3" or typeof(edgeB)~="Vector3"
		or typeof(outwardA)~="Vector3" or typeof(outwardB)~="Vector3"
		or typeof(width)~="number" or width~=width then
		return nil,"Invalid chamfer geometry"
	end
	local along=edgeB-edgeA
	if along.Magnitude<0.035 then return nil,"Edge is too short for a stable chamfer" end
	if width<0.018 or width>128 then
		return nil,"Chamfer width is outside safe fabrication limits"
	end
	-- Chamfer width is a distance ALONG the neighboring face planes,
	-- not along the selected edge axis. A short vertical edge on a thin
	-- plate can have a wide valid side bevel. Only *end-tapered* chamfers
	-- need an edge-length restriction, handled by taperedBevelPrism.
	if outwardA.Magnitude<0.9 or outwardB.Magnitude<0.9 then
		return nil,"Invalid neighboring face normals"
	end
	local axis=along.Unit
	local n1,n2=outwardA.Unit,outwardB.Unit
	local dot=n1:Dot(n2)
	if math.abs(dot)>0.84 then
		return nil,"Cannot file tangent or nearly parallel faces"
	end
	if math.abs(n1:Dot(axis))>0.015 or math.abs(n2:Dot(axis))>0.015 then
		return nil,"Edge axis does not match its adjacent face planes"
	end
	local intoFaceA=(n1*dot-n2).Unit
	local intoFaceB=(n2*dot-n1).Unit
	local bisector=(n1+n2).Unit
	local isInterior=interior==true
	local faceDir=if isInterior then -1 else 1
	local epsilon=math.clamp(width*0.07,0.002,0.006)
	local edgeExtension=math.min(epsilon,along.Magnitude*0.02)
	local a=edgeA-axis*edgeExtension
	local profile={
		a+intoFaceA*(width*faceDir),
		a+intoFaceB*(width*faceDir),
		a+bisector*(if isInterior then -epsilon else epsilon),
	}
	if isInterior then
		-- Add a wedge *inside the empty cavity*; overlap its two mounting
		-- planes by epsilon so UnionAsync connects it to the original solid.
		profile[1]-=n1*epsilon+n2*epsilon
		profile[2]-=n1*epsilon+n2*epsilon
	else
		-- Subtract an outer-corner chip; do not bury an enormous third
		-- vertex inside the part as the previous unstable cutter did.
		profile[1]+=bisector*epsilon
		profile[2]+=bisector*epsilon
	end
	return {profile=profile,travel=along+axis*edgeExtension*2},nil
end

-- Turn one convex clipped bevel solid into ONE watertight disposable
-- MeshPart. The exact same face polygons are consumed by HistoryTopology.
-- This is never CSG readback, so no CreateEditableMeshAsync is required.
function GeometryCutter.convexSolid(faces):(MeshPart,()->())
	local vertices={}
	local minB=Vector3.new(math.huge,math.huge,math.huge)
	local maxB=Vector3.new(-math.huge,-math.huge,-math.huge)
	for _,face in ipairs(faces) do
		for _,p in ipairs(face.polygon) do
			table.insert(vertices,p)
			minB=Vector3.new(math.min(minB.X,p.X),math.min(minB.Y,p.Y),math.min(minB.Z,p.Z))
			maxB=Vector3.new(math.max(maxB.X,p.X),math.max(maxB.Y,p.Y),math.max(maxB.Z,p.Z))
		end
	end
	if #faces<4 or #vertices<12 then error("Clipped bevel has no solid volume",0) end
	local center=(minB+maxB)*0.5
	local editable:EditableMesh?=nil
	local part:MeshPart?=nil
	local success,failure=pcall(function()
		editable=AssetService:CreateEditableMesh()
		if not editable then error("Cannot allocate bevel EditableMesh") end
		local ids={}
		local function vertexId(p:Vector3):number
			local key=string.format("%d:%d:%d",math.round(p.X*1e6),
				math.round(p.Y*1e6),math.round(p.Z*1e6))
			if not ids[key] then ids[key]=editable:AddVertex(p-center) end
			return ids[key]
		end
		local white=editable:AddColor(Color3.new(1,1,1),1)
		for _,face in ipairs(faces) do
			local loop=face.polygon
			if #loop<3 then continue end
			local normal=editable:AddNormal(face.normal.Unit)
			for i=2,#loop-1 do
				local p,q,r=loop[1],loop[i],loop[i+1]
				if (q-p):Cross(r-p).Magnitude>1e-8 then
					local f=editable:AddTriangle(vertexId(p),vertexId(q),vertexId(r))
					editable:SetFaceNormals(f,{normal,normal,normal})
					editable:SetFaceColors(f,{white,white,white})
				end
			end
		end
		part=AssetService:CreateMeshPartAsync(Content.fromObject(editable),{
			CollisionFidelity=Enum.CollisionFidelity.Hull,
		})
		if not part then error("Bevel mesh conversion returned no MeshPart") end
		part.Name="FORM_ClippedInsideBevel"
		part.CFrame=CFrame.new(center)
		part.Color=Color3.new(1,1,1)
		part.Material=Enum.Material.SmoothPlastic
		part.TextureID=""
		part.Anchored=true
		part.CanCollide=false
		part.CanTouch=false
		part.CanQuery=false
	end)
	if not success or not part or not editable then
		if part then part:Destroy() end
		if editable then editable:Destroy() end
		error("Clipped bevel creation failed: "..tostring(failure),0)
	end
	local disposed=false
	return part,function()
		if disposed then return end
		disposed=true
		part:Destroy()
		editable:Destroy()
	end
end

-- Segment count is an explicit fabrication feature, not display LOD.
-- 1 = the historical straight chamfer. 2..12 = quarter-circle profile
-- between the same face offsets, with one planar strip per segment.
local function roundedFileProfile(edgeA:Vector3,edgeB:Vector3,
	n1:Vector3,n2:Vector3,width:number,segments:number)
	local axis=(edgeB-edgeA).Unit
	local delta=n1:Dot(n2)
	if math.abs(delta)>0.12 then
		error("Rounded File currently supports perpendicular planar faces",0)
	end
	-- The rounded surface is a real circle of radius 'width' tangent
	-- to the two original planes. Its center is one radius inside both.
	local center=edgeA-(n1+n2)*width
	local epsilon=math.clamp(width*0.065,0.002,0.006)
	local length=(edgeB-edgeA).Magnitude
	local extension=math.min(epsilon,length*0.02)
	local start=edgeA-axis*extension
	local shift=start-edgeA
	local profile={start+(n1+n2).Unit*epsilon}
	-- Arc from wall 2 to wall 1, all contained in the original wedge.
	-- Both endpoint offsets have a tiny exterior overlap for CSG.
	for i=0,segments do
		local t=(i/segments)*math.pi*0.5
		local normal=n1*math.cos(t)+n2*math.sin(t)
		local p=center+normal*width+shift
		if i==0 or i==segments then
			p+=normal*epsilon
		end
		table.insert(profile,p)
	end
	return profile,(edgeB-edgeA)+axis*(extension*2)
end

-- Authoritative visible facet loops for a rounded exterior File.
-- Both HistoryTopology and the miter generator use the same quarter arc,
-- so the selectable geometry does not revert to a single flat chamfer.
function GeometryCutter.roundedSurfaces(edgeA:Vector3,edgeB:Vector3,
	n1:Vector3,n2:Vector3,width:number,segments:number)
	if segments<2 or segments>12 then return nil,"Invalid round segment count" end
	if math.abs(n1:Dot(n2))>0.12 then
		return nil,"Rounded File requires a right-angle edge"
	end
	local centerA=edgeA-(n1+n2)*width
	local centerB=edgeB-(n1+n2)*width
	local a,b={},{}
	for i=0,segments do
		local angle=i/segments*math.pi*0.5
		local normal=n1*math.cos(angle)+n2*math.sin(angle)
		table.insert(a,centerA+normal*width)
		table.insert(b,centerB+normal*width)
	end
	local faces={}
	for i=1,segments do
		local polygon={a[i],b[i],b[i+1],a[i+1]}
		local normal=(polygon[2]-polygon[1]):Cross(polygon[3]-polygon[1])
		if normal.Magnitude<1e-9 then
			return nil,"Degenerate rounded edge segment"
		end
		normal=normal.Unit
		if normal:Dot(n1+n2)<0 then
			polygon={a[i+1],b[i+1],b[i],a[i]}
			normal=-normal
		end
		table.insert(faces,{polygon=polygon,normal=normal})
	end
	return faces,nil
end

function GeometryCutter.validateFile(edgeA:Vector3,edgeB:Vector3,
	outwardA:Vector3,outwardB:Vector3,width:number,interior:boolean?):(boolean,string?)
	local plan,why=bevelPlan(edgeA,edgeB,outwardA,outwardB,width,interior)
	return plan~=nil,why
end

-- Shared, read-only bevel face geometry used for fabrication AND picking.
-- All neighboring exterior chamfer planes clip the inside wedge BEFORE
-- UnionAsync. This cannot refill already-cut top and bottom bevels.
function GeometryCutter.fileFaces(edgeA:Vector3,edgeB:Vector3,
	outwardA:Vector3,outwardB:Vector3,width:number,interior:boolean?,
	planes)
	local plan,why=bevelPlan(edgeA,edgeB,outwardA,outwardB,width,interior)
	if not plan then return nil,why end
	local base=BevelJunction.prismFaces(plan.profile,plan.travel)
	return BevelJunction.clipFaces(base,if interior then (planes or {}) else {})
end

function GeometryCutter.file(edgeA:Vector3,edgeB:Vector3,
	outwardA:Vector3,outwardB:Vector3,width:number,interior:boolean?,
	_taperA:boolean?,_taperB:boolean?,_planes,segments:number?)
	local count=segments or 1
	if count~=math.floor(count) or count<1 or count>12 then
		error("File segments must be between 1 and 12",0)
	end
	local plan,why=bevelPlan(edgeA,edgeB,outwardA,outwardB,width,interior)
	if not plan then error(why or "Invalid bevel geometry",0) end
	if interior then
		error("Interior edge filing remains paused",0)
	end
	if count==1 then return GeometryCutter.prism(plan.profile,plan.travel) end
	local profile,travel=roundedFileProfile(edgeA,edgeB,
		outwardA.Unit,outwardB.Unit,width,count)
	return GeometryCutter.prism(profile,travel)
end


return GeometryCutter
