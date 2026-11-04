--!strict
-- Build watertight CSG cutters from arbitrary plane loops. Face/edge tools
-- use current compiled geometry; an EditableMesh is never retained in history.
local AssetService = game:GetService("AssetService")
local GeometryCutter = {}

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
		-- Fan triangulation is valid only for a convex profile. Concave
		-- faces must use polygon triangulation before this cutter is extended.
		for i=2,#low-1 do
			triangle(low[1],low[i+1],low[i])
			triangle(high[1],high[i],high[i+1])
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

function GeometryCutter.file(edgeA:Vector3,edgeB:Vector3, outwardA:Vector3,outwardB:Vector3,width:number)
	local along=(edgeB-edgeA)
	if along.Magnitude<0.005 then error("Edge too short to file") end
	local n1,n2=outwardA.Unit,outwardB.Unit
	if math.abs(n1:Dot(n2))>0.95 then error("Edge faces are not a defined hard corner") end
	-- Plane intersections of the chamfer with both adjacent surfaces.
	-- For a convex edge, the two inward offset points are inside the
	-- solid along opposite faces; the exterior envelope cuts the corner.
	local margin=0.025
	local crossPoint = (n1+n2).Unit*(width+margin)
	local profile={
		edgeA-n1*width-n2*margin,
		edgeA+crossPoint,
		edgeA-n2*width-n1*margin,
	}
	local axis=along.Unit
	local travel=along+axis*margin*2
	for i,p in ipairs(profile) do profile[i]=p-axis*margin end
	return GeometryCutter.prism(profile,travel)
end

return GeometryCutter
