--!strict
-- Paste into Roblox Studio Command Bar after syncing Openworks dev.
-- Checks ONLY the requested small triangle at two normal exterior File edges.
local root=game:GetService("ReplicatedStorage"):WaitForChild("Openworks"):WaitForChild("FORM")
local CornerTriangle=require(root.CornerTriangle)
local X,Y,Z=Vector3.xAxis,Vector3.yAxis,Vector3.zAxis

local function edge(a,b,wall,width)
	return {a=a,b=b,n1=Y,n2=wall,width=width}
end
local p=Vector3.new(0,1,0)
local first=edge(p,p+Z*2,X,0.14)
local second=edge(p,p+X*2,Z,0.18)
local triangle=CornerTriangle.between(first,second)
assert(triangle,"Two outside bevels at a concave L-notch should produce one triangle")
local faces=CornerTriangle.faces(triangle)
assert(faces and #faces==4,"Corner volume should have four triangle faces")
local points=triangle.points
assert((points[1]-p).Magnitude<1e-6)
assert((points[2]-(p-X*0.14)).Magnitude<1e-6)
assert((points[3]-(p-Z*0.18)).Magnitude<1e-6)
assert((points[4]-(p-Y*0.14)).Magnitude<1e-6)
local testConvex=edge(p,p-Z*2,X,0.14)
assert(CornerTriangle.between(testConvex,second)==nil,
	"A normal exterior block corner must NOT be modified")
assert(CornerTriangle.between(first,first)==nil,
	"A single edge cannot create a corner triangle")
local unrelated=edge(Vector3.new(0,1,0.3),Vector3.new(0,1,2),X,0.14)
assert(CornerTriangle.between(unrelated,second)==nil,
	"Nearby edges without shared vertex cannot form a corner triangle")
print("FORM small corner triangle: four targeted geometry checks passed")
