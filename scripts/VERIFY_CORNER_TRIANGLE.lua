--!strict
-- Studio Command Bar regression: one EXACT diagonal seam shared by the
-- two real File cutters. No CornerTriangle.faces() / third cutter exists.
-- Runs pure geometry without GeometryService; visually test CSG separately.
local root=game:GetService("ReplicatedStorage"):WaitForChild("Openworks"):WaitForChild("FORM")
local Junction=require(root.CornerTriangle)
local Cutter=require(root.GeometryCutter)
local X,Y,Z=Vector3.xAxis,Vector3.yAxis,Vector3.zAxis
local p=Vector3.new(0,1,0)

local function spec(edgeB:Vector3,wall:Vector3,count:number,width:number)
	return {a=p,b=edgeB,n1=Y,n2=wall,segments=count,width=width}
end
local function near(a:Vector3,b:Vector3):boolean
	return (a-b).Magnitude<0.00001
end
for count=1,12 do
	local left=spec(p+Z*2,X,count,0.24)
	local right=spec(p+X*2,Z,count,0.24)
	local joint=Junction.between(left,right)
	assert(joint,"Concave 90-degree corner not paired")
	local leftEnd,rightEnd=Junction.miterEnds(joint,left,right)
	assert(leftEnd.atStart and rightEnd.atStart,"Expected matching start caps")
	assert(near(leftEnd.corner,rightEnd.corner))
	assert(near(leftEnd.normal,rightEnd.normal))
	local leftFaces,why=Cutter.fileSurfaceFaces(left.a,left.b,left.n1,left.n2,
		left.width,left.segments,leftEnd)
	assert(leftFaces,tostring(why))
	local rightFaces,reason=Cutter.fileSurfaceFaces(right.a,right.b,right.n1,right.n2,
		right.width,right.segments,rightEnd)
	assert(rightFaces,tostring(reason))
	assert(#leftFaces==count and #rightFaces==count,
		"Round segment strip count mismatch")
	-- Every matching strip uses the SAME miter seam vertices.
	for i=1,count do
		local leftStart=leftFaces[i].polygon
		local rightStart=rightFaces[i].polygon
		assert(near(leftStart[1],rightStart[1]) and near(leftStart[4],rightStart[4]),
			"Separate or doubled center seam at segment "..i)
		for _,v in ipairs({leftStart[1],leftStart[4]}) do
			assert(math.abs((v-p):Dot(leftEnd.normal))<0.00001,
				"Miter vertex is not on the common diagonal plane")
		end
		for _,surface in ipairs({leftFaces[i],rightFaces[i]}) do
			local v=surface.polygon
			local n=(v[2]-v[1]):Cross(v[3]-v[1])
			assert(n.Magnitude>0.000001,"Collapsed File facet")
			assert(math.abs((v[4]-v[1]):Dot(n.Unit))<0.00001,
				"File facet became twisted")
		end
	end
	-- Reversed source edge orientation uses the same END-cap miter.
	local reversedLeft={a=left.b,b=left.a,n1=left.n1,n2=left.n2,
		width=left.width,segments=count}
	local reversedRight={a=right.b,b=right.a,n1=right.n1,n2=right.n2,
		width=right.width,segments=count}
	local reversedJoint=Junction.between(reversedLeft,reversedRight)
	assert(reversedJoint,"Reversed source edges not paired")
	local la,rb=Junction.miterEnds(reversedJoint,reversedLeft,reversedRight)
	assert(la.atEnd and rb.atEnd,"Expected matching end caps")
	local lf=Cutter.fileSurfaceFaces(reversedLeft.a,reversedLeft.b,Y,X,0.24,count,la)
	local rf=Cutter.fileSurfaceFaces(reversedRight.a,reversedRight.b,Y,Z,0.24,count,rb)
	assert(lf and rf)
	for i=1,count do
		assert(near(lf[i].polygon[2],rf[i].polygon[2])
			and near(lf[i].polygon[3],rf[i].polygon[3]),
			"Reversed end-cap seam is not shared")
	end
end

assert(Junction.between(spec(p-Z*2,X,1,0.24),spec(p+X*2,Z,1,0.24))==nil,
	"Convex-facing edges must not miter")
assert(Junction.between(spec(p+Z*2,X,1,0.24),spec(p+X*2,Z,1,0.26))==nil,
	"Unequal widths must not miter")
assert(Junction.between(spec(p+Z*2,X,3,0.24),spec(p+X*2,Z,4,0.24))==nil,
	"Mismatched segments must not miter")
print("FORM: 1-12 segments have ONE shared diagonal seam (both edge orientations)")
