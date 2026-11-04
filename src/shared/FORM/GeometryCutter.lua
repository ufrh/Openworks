--!strict
-- Build watertight CSG cutters from arbitrary plane loops. Face/edge tools
-- use current compiled geometry; an EditableMesh is never retained in history.
local AssetService = game:GetService("AssetService")
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
	if width<0.018 or width>along.Magnitude*0.35 then
		return nil,"Chamfer width must fit within the selected edge"
	end
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

function GeometryCutter.validateFile(edgeA:Vector3,edgeB:Vector3,
	outwardA:Vector3,outwardB:Vector3,width:number,interior:boolean?):(boolean,string?)
	local plan,why=bevelPlan(edgeA,edgeB,outwardA,outwardB,width,interior)
	return plan~=nil,why
end

function GeometryCutter.file(edgeA:Vector3,edgeB:Vector3,
	outwardA:Vector3,outwardB:Vector3,width:number,interior:boolean?)
	local plan,why=bevelPlan(edgeA,edgeB,outwardA,outwardB,width,interior)
	if not plan then error(why or "Invalid bevel geometry",0) end
	return GeometryCutter.prism(plan.profile,plan.travel)
end



return GeometryCutter
