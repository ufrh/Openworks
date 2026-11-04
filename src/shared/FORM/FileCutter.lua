--!strict
-- Backward compatibility: older File history stored one of four stock
-- edge labels. Resolve it to the same validated chamfer implementation used
-- by geometry-selected FileMesh. There must be ONE bevel mesh generator.
local GeometryCutter=require(script.Parent.GeometryCutter)
local FileCutter={}

function FileCutter.create(node,operation):(MeshPart,()->())
	if node.kind~="Block" then error("Legacy File requires block stock",0) end
	local hx,hy,hz=node.size.X/2,node.size.Y/2,node.size.Z/2
	local a,b,n2
	if operation.edge=="X+" then
		a,b=Vector3.new(hx,hy,-hz),Vector3.new(hx,hy,hz)
		n2=Vector3.xAxis
	elseif operation.edge=="X-" then
		a,b=Vector3.new(-hx,hy,-hz),Vector3.new(-hx,hy,hz)
		n2=-Vector3.xAxis
	elseif operation.edge=="Z+" then
		a,b=Vector3.new(-hx,hy,hz),Vector3.new(hx,hy,hz)
		n2=Vector3.zAxis
	elseif operation.edge=="Z-" then
		a,b=Vector3.new(-hx,hy,-hz),Vector3.new(hx,hy,-hz)
		n2=-Vector3.zAxis
	else
		error("Unknown legacy filing edge",0)
	end
	return GeometryCutter.file(a,b,Vector3.yAxis,n2,operation.width,false)
end

return FileCutter
