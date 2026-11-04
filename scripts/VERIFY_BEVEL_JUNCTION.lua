--!strict
-- Studio Command Bar numeric check for FORM inside-bevel clipping.
-- Run after Rojo sync. This tests face construction and manifold closure,
-- NOT GeometryService Boolean runtime (which still needs a playtest).
local FORM=game:GetService("ReplicatedStorage"):WaitForChild("Openworks"):WaitForChild("FORM")
local BevelJunction=require(FORM.BevelJunction)
local GeometryCutter=require(FORM.GeometryCutter)

local X,Y,Z=Vector3.xAxis,Vector3.yAxis,Vector3.zAxis
local inner={
	a=Vector3.new(0,-1,0),b=Vector3.new(0,1,0),
	n1=X,n2=Z,width=0.20,interior=true,id=10,
}
local outside={
	{a=Vector3.new(0,1,0),b=Vector3.new(0,1,2),
		n1=Y,n2=X,width=0.12,interior=false,id=20},
	{a=Vector3.new(0,1,0),b=Vector3.new(2,1,0),
		n1=Y,n2=Z,width=0.12,interior=false,id=21},
	{a=Vector3.new(0,-1,0),b=Vector3.new(0,-1,2),
		n1=-Y,n2=X,width=0.12,interior=false,id=22},
	{a=Vector3.new(0,-1,0),b=Vector3.new(2,-1,0),
		n1=-Y,n2=Z,width=0.12,interior=false,id=23},
}
local planes=BevelJunction.planesFor(inner,outside)
assert(#planes==4,"Expected four top/bottom bevel-plane intersections")
local faces,reason=GeometryCutter.fileFaces(inner.a,inner.b,inner.n1,
	inner.n2,inner.width,true,planes)
assert(faces and #faces>=6,tostring(reason))
local edgeCounts={}
local function k(p:Vector3)
	return string.format("%d,%d,%d",math.round(p.X*100000),
		math.round(p.Y*100000),math.round(p.Z*100000))
end
for _,face in ipairs(faces) do
	assert(#face.polygon>=3)
	for i,p in ipairs(face.polygon) do
		for _,plane in ipairs(planes) do
			assert((p-plane.planePoint):Dot(plane.normal)<0.0001,
				"Clipped bevel refills an existing exterior chamfer")
		end
		local q=face.polygon[i%#face.polygon+1]
		local a,b=k(p),k(q)
		local key=if a<b then a.."|"..b else b.."|"..a
		edgeCounts[key]=(edgeCounts[key] or 0)+1
	end
end
for edge,count in pairs(edgeCounts) do
	assert(count==2,"Clipped bevel has an open or nonmanifold edge: "..edge)
end
local backwards={
	a=Vector3.new(0,1,0),b=Vector3.new(0,1,-2),
	n1=Y,n2=X,width=0.12,interior=false,id=99,
}
assert(BevelJunction.pair(inner,backwards)==nil,
	"An exterior edge pointing away from the notch cannot form a junction")
assert(BevelJunction.pair(outside[1],outside[2])==nil,
	"Two exterior bevels cannot be clipped as an inside junction")
local noPlanes=GeometryCutter.fileFaces(inner.a,inner.b,inner.n1,
	inner.n2,inner.width,true,{})
assert(noPlanes and #noPlanes==5,"Unconnected bevel should stay triangular prism")
print(string.format("FORM convex bevel: 4 clipping planes, %d watertight faces, %d edges",#faces,#edgeCounts))
