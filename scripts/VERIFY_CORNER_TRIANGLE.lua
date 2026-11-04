--!strict
-- Studio Command Bar: verify a 90-degree L-corner forms a proper shared
-- 45-degree miter seam for flat AND segmented rounded File profiles.
-- The source faces are checked here; Roblox CSG still needs visual testing.
local root=game:GetService("ReplicatedStorage"):WaitForChild("Openworks"):WaitForChild("FORM")
local Miter=require(root.CornerTriangle)
local Cutter=require(root.GeometryCutter)
local X,Y,Z=Vector3.xAxis,Vector3.yAxis,Vector3.zAxis
local p=Vector3.new(0,1,0)
local function file(last:Vector3,normal:Vector3,width:number,segments:number)
	return {a=p,b=last,n1=Y,n2=normal,width=width,segments=segments}
end
local function key(v:Vector3):string
	return string.format("%d:%d:%d",math.round(v.X*1e5),
		math.round(v.Y*1e5),math.round(v.Z*1e5))
end
local function check(segments:number)
	local left=file(p+Z*2,X,0.2,segments)
	local right=file(p+X*2,Z,0.2,segments)
	local miter=Miter.between(left,right)
	assert(miter,"Concave 90-degree corner not recognized")
	local faces,why=Miter.faces(miter)
	assert(faces,tostring(why))
	assert(#faces==4+2*segments,"Expected two triangular top faces, two side caps and two miter strips per segment")
	-- Top MUST be a triangle with the seam vertex at its midpoint:
	-- old implementation cut a square into the L corner.
	local top=faces[1].polygon
	local secondTop=faces[2].polygon
	assert(#top==3 and #secondTop==3,"Miter cap must be two triangles")
	local expected={
		p, p-X*0.2, p-Z*0.2, p-(X+Z)*0.1,
	}
	for _,point in ipairs(expected) do
		local found=false
		for _,face in ipairs({top,secondTop}) do
			for _,vertex in ipairs(face) do
				if (point-vertex).Magnitude<0.00002 then found=true break end
			end
		end
		assert(found,"Corner top is not the expected triangular miter cap")
	end
	local incidence={}
	local seamSegments=0
	for _,face in ipairs(faces) do
		-- Each rounded strip is an actual plane; a twisted quad can
		-- generate giant diagonal triangles after MeshPart conversion.
		local verts=face.polygon
		local base=verts[1]
		local normal=(verts[2]-base):Cross(verts[3]-base).Unit
		for _,v in ipairs(verts) do
			assert(math.abs((v-base):Dot(normal))<1e-5,
				"Rounded miter facet is twisted/nonplanar")
		end
		for i,a in ipairs(face.polygon) do
			local b=face.polygon[i%#face.polygon+1]
			local ka,kb=key(a),key(b)
			local k=if ka<kb then ka.."|"..kb else kb.."|"..ka
			if not incidence[k] then incidence[k]={} end
			table.insert(incidence[k],if ka<kb then 1 else -1)
		end
	end
	for _,edge in pairs(incidence) do
		assert(#edge==2 and edge[1]==-edge[2],
			"Miter has an exposed, nonmanifold or inverted edge")
	end
	local round,why=Cutter.roundedSurfaces(p,p+Z*2,Y,X,0.2,
		math.max(segments,2))
	assert(round and #round==math.max(segments,2),tostring(why))
	return #faces
end

for _,count in ipairs({1,2,3,4,6,8,12}) do
	print(string.format("FORM miter: %d segments -> %d watertight facets",count,check(count)))
end
assert(Miter.between(file(p-Z*2,X,0.2,1),file(p+X*2,Z,0.2,1))==nil,
	"Convex/outward-facing corner must not be mitered")
assert(Miter.between(file(p+Z*2,X,0.2,1),file(p+X*2,Z,0.3,1))==nil,
	"Unequal bevel widths cannot form this shared miter")
assert(Miter.between(file(p+Z*2,X,0.2,2),file(p+X*2,Z,0.2,4))==nil,
	"Mismatched rounding segments cannot form a shared miter")
print("FORM: straight/rounded 90-degree miter regression passed")
