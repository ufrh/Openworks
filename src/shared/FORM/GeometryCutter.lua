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
		local center = Vector3.zero
		for _,p in ipairs(profile) do center += p end
		center = center / #profile + travel / 2
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

function GeometryCutter.file(edgeA:Vector3,edgeB:Vector3, outwardA:Vector3,outwardB:Vector3,width:number,interior:boolean?)
	local along=(edgeB-edgeA)
	if along.Magnitude<0.005 then error("Edge too short to file") end
	local n1,n2=outwardA.Unit,outwardB.Unit
	if math.abs(n1:Dot(n2))>0.95 then error("Edge faces are not a defined hard corner") end
	-- Plane intersections of the chamfer with both adjacent surfaces.
	-- For a convex edge, the two inward offset points are inside the
	-- solid along opposite faces; the exterior envelope cuts the corner.
	local margin=0.025
	local crossPoint = (n1+n2).Unit*(width+margin)
	local profile
	if interior then
		-- Re-entrant pocket/floor corners: enlarge the internal void by
		-- removing a wedge *behind* the two original surfaces. A normal
		-- outer-corner bevel would lie in the cavity and remove nothing.
		profile={
			edgeA+n1*(width+margin),
			edgeA+n2*(width+margin),
			edgeA-(n1+n2)*width,
		}
	else
		profile={
			edgeA-n1*width-n2*margin,
			edgeA+crossPoint,
			edgeA-n2*width-n1*margin,
		}
	end
	local axis=along.Unit
	local travel=along+axis*margin*2
	for i,p in ipairs(profile) do profile[i]=p-axis*margin end
	return GeometryCutter.prism(profile,travel)
end

return GeometryCutter
