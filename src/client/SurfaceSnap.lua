--!strict
-- A common 3D construction-grid policy for all mouse-driven tools.
-- Quantize tangent coordinates, never the normal offset from the real
-- manufactured face. This keeps drill points, measurements and previews
-- exactly ON the selected surface (even after arbitrary rotation).
local Quantize=require(game:GetService("ReplicatedStorage")
	:WaitForChild("Openworks"):WaitForChild("FORM").Quantize)
local SurfaceSnap={}
SurfaceSnap.Increment=Quantize.Grid -- 0.05 stud / 14mm
function SurfaceSnap.pointOnPlane(point:Vector3,origin:Vector3,
	normal:Vector3,increment:number?):Vector3
	local n=normal.Unit
	local base=if math.abs(n:Dot(Vector3.yAxis))>0.95
		then Vector3.xAxis else Vector3.yAxis
	local x=(base-n*base:Dot(n)).Unit
	local y=n:Cross(x).Unit
	local offset=point-origin
	local size=increment or SurfaceSnap.Increment
	return origin+
		x*Quantize.snap(offset:Dot(x),size)+
		y*Quantize.snap(offset:Dot(y),size)
end
function SurfaceSnap.mm(studs:number):number
	return Quantize.snap(studs*280,1)/280
end
return SurfaceSnap
